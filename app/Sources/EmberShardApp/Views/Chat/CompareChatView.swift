import SwiftUI
import EmberShardBridge

// Arena mode: ask one question to up to 4 models and see the answers side by
// side. Each model has its own resident es_gx instance and they all generate
// CONCURRENTLY (separate Metal backends + KV caches). Markdown is rendered.
// Memory-bound: keep the picked models small enough to fit together.
struct CompareChatView: View {
    let chatId: UUID

    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var modelStore: LocalModelStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var skillsStore: SkillsStore

    @AppStorage("es_show_token_info") private var showTokenInfo: Bool = false

    @State private var input = ""
    @State private var turns: [CompareTurn] = []
    @State private var busy = false
    @State private var loadingModels = false
    @State private var warmupPhrase = ""
    @State private var task: Task<Void, Never>?
    @State private var runner = CompareRunner()

    private var chat: Chat? { chatStore.chat(id: chatId) }
    private var modelPaths: [String] { chat?.compareModels ?? [] }
    private func name(_ path: String) -> String {
        modelStore.models.first { $0.path == path }?.name
            ?? (path as NSString).lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            if turns.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.split.3x1.fill")
                        .font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
                    Text("Arena · \(modelPaths.count) models")
                        .font(.title3.weight(.regular)).foregroundStyle(.secondary)
                    Text(modelPaths.map(name).joined(separator: "  ·  "))
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        ForEach(turns) { turn in turnView(turn) }
                    }
                    .padding(.vertical, 14).padding(.horizontal, 12)
                }
            }
            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { if turns.isEmpty { turns = chat?.compareTurns ?? [] } }
        .onDisappear { task?.cancel(); runner.cancelAll(); runner.freeAll() }
    }

    private func turnView(_ turn: CompareTurn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer(minLength: 60)
                Text(turn.prompt)
                    .font(.body).padding(.horizontal, 14).padding(.vertical, 9)
                    .background(appState.accentColor, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
            }
            HStack(alignment: .top, spacing: 10) {
                ForEach(turn.answers) { ans in columnView(ans) }
            }
        }
    }

    private func columnView(_ ans: CompareAnswer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ProviderIconView(modelName: ans.modelName, size: 14)
                Text(ans.modelName).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer()
            }
            if ans.text.isEmpty && !ans.done {
                HStack(spacing: 8) {
                    EngineDots()
                    if loadingModels {
                        Text(warmupPhrase).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            } else {
                MarkdownText(ans.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if ans.done && showTokenInfo && ans.tokenCount > 0 {
                ContextUsageBadge(tokenCount: ans.tokenCount, contextFraction: ans.contextFraction)
                    .padding(.top, 2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
    }

    private var inputBar: some View {
        ChatInputView(
            text: $input,
            isGenerating: busy,
            models: [],
            activeModelPath: "",
            skills: skillsStore.skills,
            activeSkillId: chat?.skillId,
            onModelChange: { _ in },
            onSkillChange: { skillId in
                guard var c = chat else { return }
                c.skillId = skillId
                chatStore.updateChat(c)
            },
            onSend: { if canSend { send() } },
            onCancel: cancel,
            showModelPicker: false,
            toggleActive: chat?.agentMode ?? false,
            toggleLabel: "Agent",
            toggleIcon: "wand.and.stars",
            onToggle: {
                guard var c = chat else { return }
                c.agentMode.toggle()
                chatStore.updateChat(c)
            }
        )
    }

    private static let agentSystem =
        "Work like an agent: briefly outline a plan as numbered steps, then carry it "
      + "out and give the final answer. Be concise."

    private var canSend: Bool { busy || !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func cancel() {
        task?.cancel()
        runner.cancelAll()
        busy = false
    }

    private func send() {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !busy, !modelPaths.isEmpty else { return }
        input = ""

        let paths = modelPaths
        let priorTurns = turns
        let answers = paths.map { CompareAnswer(modelPath: $0, modelName: name($0), text: "", done: false) }
        turns.append(CompareTurn(prompt: prompt, answers: answers))
        let turnIdx = turns.count - 1
        busy = true

        if turnIdx == 0, chat?.title == "New chat" {
            chatStore.setChatTitle(id: chatId, title: "Arena: " + String(prompt.prefix(28)))
            chatStore.setChatIcon(id: chatId, icon: "rectangle.split.3x1.fill")
        }

        let ctxSize = Int32(UserDefaults.standard.integer(forKey: "es_ctx_size").nonZeroOr(8192))
        let kvQuant = Int32(UserDefaults.standard.integer(forKey: "es_kv_quant"))
        let maxTokens = Int32(UserDefaults.standard.integer(forKey: "es_max_tokens").nonZeroOr(2048))
        let samp = nativeSamplingFromSettings()
        let runner = self.runner
        // Optional skill + agent mode form the system prompt applied to every model.
        let skillSys = chat?.skillId.flatMap { skillsStore.skill(id: $0)?.systemPrompt }
        let parts = [(chat?.agentMode ?? false) ? Self.agentSystem : nil, skillSys].compactMap { $0 }
        let system: String? = parts.isEmpty ? nil : parts.joined(separator: "\n\n")

        loadingModels = true
        warmupPhrase = EngineUI.warmupMessages.randomElement() ?? "Warming up the engine..."

        task = Task {
            // Free the standard chat's resident model so the arena models have room.
            await NativeEngine.shared.unload()

            let ok = await runner.ensureLoaded(paths: paths, nCtx: ctxSize, kvQuant: kvQuant)
            await MainActor.run { loadingModels = false }
            for (col, path) in paths.enumerated() where !ok.contains(path) {
                await MainActor.run { setAnswer(turnIdx, col, append: "_(failed to load model)_", done: true) }
            }
            if Task.isCancelled { await MainActor.run { busy = false }; return }

            await withTaskGroup(of: Void.self) { group in
                for (col, path) in paths.enumerated() where ok.contains(path) {
                    // Per-model conversation history from prior turns.
                    var history: [NativeTurn] = []
                    for t in priorTurns {
                        history.append(NativeTurn(role: "user", content: t.prompt))
                        if let a = t.answers.first(where: { $0.modelPath == path }) {
                            history.append(NativeTurn(role: "assistant", content: a.text))
                        }
                    }
                    group.addTask {
                        let stats = await runner.generate(path: path, prompt: prompt, history: history,
                                                          system: system, sampling: samp, maxTokens: maxTokens) { piece in
                            DispatchQueue.main.async { setAnswer(turnIdx, col, append: piece, done: false) }
                        }
                        await MainActor.run {
                            setAnswer(turnIdx, col, append: "", done: true,
                                      tokens: stats.tokens, fraction: stats.contextFraction)
                        }
                    }
                }
            }
            await MainActor.run {
                busy = false
                chatStore.setCompareTurns(id: chatId, turns: turns)
            }
        }
    }

    private func setAnswer(_ turn: Int, _ col: Int, append: String, done: Bool,
                           tokens: Int = 0, fraction: Double = 0) {
        guard turn < turns.count, col < turns[turn].answers.count else { return }
        turns[turn].answers[col].text += append
        if done {
            turns[turn].answers[col].done = true
            if tokens > 0 { turns[turn].answers[col].tokenCount = tokens }
            if fraction > 0 { turns[turn].answers[col].contextFraction = fraction }
        }
    }
}

struct CompareTurn: Identifiable, Codable {
    var id = UUID()
    let prompt: String
    var answers: [CompareAnswer]
}
struct CompareAnswer: Identifiable, Codable {
    var id = UUID()
    let modelPath: String
    let modelName: String
    var text: String
    var done: Bool
    var tokenCount: Int = 0
    var contextFraction: Double = 0
}

// Holds one resident es_gx model per path. Models are loaded sequentially
// (Metal residency-set mutation is serialized) but generate concurrently on
// independent backends + KV caches.
final class CompareRunner: @unchecked Sendable {
    private var models: [String: OpaquePointer] = [:]
    private let lock = NSLock()
    private let loadQueue = DispatchQueue(label: "embershard.arena.load")

    func ensureLoaded(paths: [String], nCtx: Int32, kvQuant: Int32) async -> Set<String> {
        await withCheckedContinuation { cont in
            loadQueue.async {
                var ok = Set<String>()
                for p in paths {
                    self.lock.lock(); let existing = self.models[p]; self.lock.unlock()
                    if existing != nil { ok.insert(p); continue }
                    if let m = p.withCString({ es_gx_load($0, nCtx, kvQuant) }) {
                        self.lock.lock(); self.models[p] = m; self.lock.unlock()
                        ok.insert(p)
                    }
                }
                cont.resume(returning: ok)
            }
        }
    }

    func generate(path: String, prompt: String, history: [NativeTurn], system: String?,
                  sampling: es_gx_sampling, maxTokens: Int32,
                  onPiece: @escaping @Sendable (String) -> Void) async -> (tokens: Int, contextFraction: Double) {
        lock.lock(); let model = models[path]; lock.unlock()
        guard let m = model else { return (0, 0) }
        return await withCheckedContinuation { (cont: CheckedContinuation<(Int, Double), Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                es_gx_set_sampling(m, sampling)
                let isSPM = es_gx_is_spm(m)
                let isQwen = es_gx_get_arch(m) == ES_GX_ARCH_QWEN2
                let p = gxChatPrompt(isSPM: isSPM, isQwen: isQwen, system: system,
                                     history: history, user: prompt, continuation: false)
                es_gx_reset(m)
                let ingested = p.withCString { es_gx_ingest(m, $0, false, true) == 0 }
                if !ingested { cont.resume(returning: (0, 0)); return }

                let box = PieceBox(onPiece)
                let ud = Unmanaged.passRetained(box).toOpaque()
                let cb: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { piece, ud in
                    guard let piece, let ud else { return }
                    Unmanaged<PieceBox>.fromOpaque(ud).takeUnretainedValue().fn(String(cString: piece))
                }
                let produced = Int(es_gx_generate_stream(m, maxTokens, cb, ud))
                Unmanaged<PieceBox>.fromOpaque(ud).release()
                let past = Int(es_gx_n_past(m)), cap = Int(es_gx_n_ctx(m))
                let frac = cap > 0 ? Double(past) / Double(cap) : 0
                cont.resume(returning: (produced, frac))
            }
        }
    }

    func cancelAll() {
        lock.lock(); let ms = Array(models.values); lock.unlock()
        for m in ms { es_gx_cancel(m) }
    }

    func freeAll() {
        lock.lock(); let ms = Array(models.values); models.removeAll(); lock.unlock()
        for m in ms { es_gx_free(m) }
    }
}

private final class PieceBox {
    let fn: (String) -> Void
    init(_ f: @escaping (String) -> Void) { fn = f }
}
