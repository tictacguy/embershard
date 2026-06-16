import Foundation
import EmberShardBridge

// Swift wrapper around the native ggml engine (es_gx): own forward pass, resident
// KV cache, native tokenizer — the app's only inference engine for chat.
//
// Multi-turn: the KV cache is kept live for one chat at a time. Continuing the
// same chat appends only the new turn (cheap); switching chats resets and
// replays that chat's history once.

struct NativeTurn { let role: String; let content: String }

@globalActor actor NativeEngineActor {
    static let shared = NativeEngineActor()
}

@NativeEngineActor
final class NativeEngine {
    static let shared = NativeEngine()

    private var model: OpaquePointer?      // es_gx_model *
    private var loadedPath = ""
    private var liveChat: UUID?            // chat whose KV is currently resident
    private var isQwen = false
    private var isSPM = false              // SentencePiece model (Llama 2 / Mistral)

    // Mirror of `model` reachable without actor isolation, so cancellation can
    // set the C atomic flag while the actor is busy inside generate_stream.
    nonisolated(unsafe) private var cancelPtr: OpaquePointer?

    nonisolated private init() {}

    nonisolated func requestCancel() {
        if let p = cancelPtr { es_gx_cancel(p) }
    }

    var archName: String {
        guard let m = model, let c = es_gx_arch_name(m) else { return "?" }
        return String(cString: c)
    }

    func ensureLoaded(path: String, nCtx: Int32, kvQuant: Int32) -> Bool {
        if model != nil && loadedPath == path { return true }
        if let m = model { es_gx_free(m); model = nil; loadedPath = ""; liveChat = nil }
        guard let m = es_gx_load(path, nCtx, kvQuant) else { return false }
        model = m
        cancelPtr = m
        loadedPath = path
        liveChat = nil
        isQwen = (es_gx_get_arch(m) == ES_GX_ARCH_QWEN2)
        isSPM  = es_gx_is_spm(m)
        return true
    }

    func unload() {
        cancelPtr = nil
        if let m = model { es_gx_free(m); model = nil; loadedPath = ""; liveChat = nil }
    }

    // Force the next turn to do a full history replay (after edits/regenerate).
    func invalidate() { liveChat = nil }

    // Stream one assistant turn. `history` are the completed prior turns of `chat`.
    // forceFull = re-prefill the whole history (after cancel/regenerate/switch).
    func send(chat: UUID, system: String?, history: [NativeTurn], user: String,
              maxTokens: Int32, sampling: es_gx_sampling,
              forceFull: Bool) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @NativeEngineActor in
                guard let m = self.model else {
                    continuation.finish(throwing: EngineError.notLoaded); return
                }
                es_gx_set_sampling(m, sampling)
                let continuationTurn = (!forceFull && self.liveChat == chat)
                let text = self.buildPrompt(system: system, history: history, user: user,
                                            continuation: continuationTurn)
                if !continuationTurn { es_gx_reset(m) }

                let ok = text.withCString { es_gx_ingest(m, $0, false, true) == 0 }
                if !ok { continuation.finish(throwing: EngineError.generationFailed); return }

                let box = NativeBox(continuation: continuation)
                let ud = Unmanaged.passRetained(box).toOpaque()
                let cb: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { piece, ud in
                    guard let piece, let ud else { return }
                    Unmanaged<NativeBox>.fromOpaque(ud).takeUnretainedValue()
                        .continuation.yield(String(cString: piece))
                }
                _ = es_gx_generate_stream(m, maxTokens, cb, ud)
                Unmanaged<NativeBox>.fromOpaque(ud).release()

                self.liveChat = chat
                continuation.finish()
            }
        }
    }

    // Agentic pipeline on es_gx (no llama.cpp): planner → executor, run
    // sequentially over the single KV cache. Mirrors the previous orchestrator.
    private static let plannerSys =
        "You are a planning agent. Break the user's request into clear, numbered "
      + "steps (1., 2., 3., ...). Be concise. List only the steps, no preamble."
    private static let executorSys =
        "You are an execution agent. You receive the user's request and a plan. "
      + "Write the complete, well-structured final answer addressed to the user. "
      + "Use Markdown where helpful. Do not mention the plan or that you are an agent."

    func orchestrate(user: String, maxTokens: Int32,
                     sampling: es_gx_sampling) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { @NativeEngineActor in
                guard let m = self.model else {
                    continuation.finish(throwing: EngineError.notLoaded); return
                }
                self.liveChat = nil                 // pipeline clobbers the chat KV

                // Planning (greedy for structured output) — streamed to the card.
                continuation.yield(.stage(ES_STAGE_PLANNING))
                var planSamp = sampling; planSamp.temp = 0.0; planSamp.top_p = 1.0
                var plan = ""
                self.runStage(m, system: Self.plannerSys, user: user,
                              sampling: planSamp, maxTokens: min(maxTokens, 512)) {
                    plan += $0; continuation.yield(.token($0))
                }

                // Executing — the final answer, streamed to the message body.
                continuation.yield(.stage(ES_STAGE_EXECUTING))
                let execUser = "User request:\n\(user)\n\nPlan:\n\(plan)\n\nNow write the final answer."
                self.runStage(m, system: Self.executorSys, user: execUser,
                              sampling: sampling, maxTokens: maxTokens) {
                    continuation.yield(.token($0))
                }
                continuation.finish()
            }
        }
    }

    // One pipeline stage: model-correct chat template (llama3 / qwen2 / SPM),
    // fresh KV, streamed via a per-piece callback.
    private func runStage(_ m: OpaquePointer, system: String, user: String,
                          sampling: es_gx_sampling, maxTokens: Int32,
                          onPiece: @escaping (String) -> Void) {
        es_gx_set_sampling(m, sampling)
        let prompt = buildPrompt(system: system, history: [], user: user, continuation: false)
        es_gx_reset(m)
        let ok = prompt.withCString { es_gx_ingest(m, $0, false, true) == 0 }
        guard ok else { return }
        let box = CBBox(onPiece)
        let ud = Unmanaged.passRetained(box).toOpaque()
        let cb: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { p, ud in
            guard let p, let ud else { return }
            Unmanaged<CBBox>.fromOpaque(ud).takeUnretainedValue().f(String(cString: p))
        }
        _ = es_gx_generate_stream(m, maxTokens, cb, ud)
        Unmanaged<CBBox>.fromOpaque(ud).release()
    }

    // One-shot completion that does NOT touch the live chat KV (used sparingly).
    func oneShot(prompt: String, maxTokens: Int32, temp: Float) -> String {
        guard let m = model else { return "" }
        liveChat = nil   // we are about to clobber the KV
        final class Acc: @unchecked Sendable { var s = "" }
        let acc = Acc()
        let ud = Unmanaged.passRetained(acc).toOpaque()
        let cb: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { p, ud in
            guard let p, let ud else { return }
            Unmanaged<Acc>.fromOpaque(ud).takeUnretainedValue().s += String(cString: p)
        }
        _ = es_gx_generate(m, prompt, maxTokens, temp, 0.95, false, true, cb, ud)
        Unmanaged<Acc>.fromOpaque(ud).release()
        return acc.s
    }

    // ── chat templating (llama3 / qwen2) ─────────────────────────────────────
    private func buildPrompt(system: String?, history: [NativeTurn], user: String,
                             continuation: Bool) -> String {
        let sys = (system?.isEmpty == false) ? system! : nil
        if isSPM {
            // Llama 2 / Mistral style: <s>[INST] ... [/INST] answer </s> …
            if continuation {
                return " </s><s>[INST] \(user) [/INST]"
            }
            var p = "<s>[INST] "
            if let sys { p += "<<SYS>>\n\(sys)\n<</SYS>>\n\n" }
            for t in history where t.role == "user" || t.role == "assistant" {
                if t.role == "user" { p += "\(t.content) [/INST]" }
                else                { p += " \(t.content) </s><s>[INST] " }
            }
            p += "\(user) [/INST]"
            return p
        }
        if isQwen {
            if continuation {
                return "<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
            }
            var p = ""
            if let sys { p += "<|im_start|>system\n\(sys)<|im_end|>\n" }
            for t in history where t.role == "user" || t.role == "assistant" {
                p += "<|im_start|>\(t.role)\n\(t.content)<|im_end|>\n"
            }
            p += "<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
            return p
        } else { // llama3
            if continuation {
                return "<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n\(user)<|eot_id|>"
                     + "<|start_header_id|>assistant<|end_header_id|>\n\n"
            }
            var p = "<|begin_of_text|>"
            if let sys { p += "<|start_header_id|>system<|end_header_id|>\n\n\(sys)<|eot_id|>" }
            for t in history where t.role == "user" || t.role == "assistant" {
                p += "<|start_header_id|>\(t.role)<|end_header_id|>\n\n\(t.content)<|eot_id|>"
            }
            p += "<|start_header_id|>user<|end_header_id|>\n\n\(user)<|eot_id|>"
            p += "<|start_header_id|>assistant<|end_header_id|>\n\n"
            return p
        }
    }
}

private final class NativeBox: @unchecked Sendable {
    let continuation: AsyncThrowingStream<String, Error>.Continuation
    init(continuation: AsyncThrowingStream<String, Error>.Continuation) {
        self.continuation = continuation
    }
}

private final class CBBox: @unchecked Sendable {
    let f: (String) -> Void
    init(_ f: @escaping (String) -> Void) { self.f = f }
}
