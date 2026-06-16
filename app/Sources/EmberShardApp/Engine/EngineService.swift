import Foundation
import EmberShardBridge

// MARK: - Configuration

struct EngineConfig {
    var modelPath: String
    var contextSize: Int32 = 4096
    var temperature: Float = 0.7
    var topP: Float = 0.95
    var gpuLayers: Int32 = -1
    var threads: Int32 = 0
    var batchSize: Int32 = 512
    var kvQuant: ESKVQuantType = ES_KV_QUANT_F16
    var flashAttn: Bool = true
    var useMmap: Bool = true
}

// MARK: - Events

enum AgentEvent: Sendable {
    case stage(ESAgentStage)
    case token(String)
}

// MARK: - Engine errors

enum EngineError: LocalizedError {
    case modelLoadFailed
    case contextInitFailed
    case generationFailed
    case contextFull
    case notLoaded

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed:   return "Failed to load model"
        case .contextInitFailed: return "Failed to initialize context"
        case .generationFailed:  return "Generation failed — context may be full. Start a new chat."
        case .contextFull:       return "Context full — start a new chat to continue."
        case .notLoaded:         return "Engine not loaded"
        }
    }
}

// MARK: - EngineService

/// Serializes all C engine calls through a dedicated global actor.
@globalActor actor EngineActor {
    static let shared = EngineActor()
}

@EngineActor
final class EngineService: ObservableObject {
    static let shared = EngineService()

    private var engine: ESEngineRef?

    private(set) var isLoaded = false
    private(set) var isGenerating = false
    private(set) var loadProgress: Double = 0
    private(set) var currentModelPath: String = ""

    nonisolated private init() {}

    // MARK: - Lifecycle

    func load(config: EngineConfig, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        if let existing = engine {
            es_destroy(existing)
            engine = nil
            isLoaded = false
        }

        var cConfig = ESConfig()
        cConfig.model_path   = nil
        cConfig.n_ctx        = config.contextSize
        cConfig.n_gpu_layers = config.gpuLayers
        cConfig.n_threads    = config.threads
        cConfig.n_batch      = config.batchSize
        cConfig.temperature  = config.temperature
        cConfig.top_p        = config.topP
        cConfig.kv_quant     = config.kvQuant
        cConfig.flash_attn   = config.flashAttn
        cConfig.use_mmap     = config.useMmap

        let box = ProgressBox(callback: onProgress)
        let boxPtr = Unmanaged.passRetained(box).toOpaque()
        cConfig.progress_ud = boxPtr
        cConfig.on_progress = { progress, ud in
            guard let ud else { return true }
            let b = Unmanaged<ProgressBox>.fromOpaque(ud).takeUnretainedValue()
            b.callback(Double(progress))
            return true
        }

        var ref: ESEngineRef?
        let status: ESStatus = config.modelPath.withCString { path in
            var cfg = cConfig
            cfg.model_path = path
            return es_create(&cfg, &ref)
        }

        Unmanaged<ProgressBox>.fromOpaque(boxPtr).release()

        guard status == ES_STATUS_OK, let ref else {
            throw EngineError.modelLoadFailed
        }

        engine = ref
        isLoaded = true
        currentModelPath = config.modelPath
    }

    func unload() {
        guard let e = engine else { return }
        es_destroy(e)
        engine = nil
        isLoaded = false
        currentModelPath = ""
    }

    // MARK: - Generation

    func generate(systemPrompt: String?, userText: String, maxTokens: Int32 = 2048) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @EngineActor in
                guard let eng = self.engine else {
                    continuation.finish(throwing: EngineError.notLoaded)
                    return
                }
                self.isGenerating = true
                defer { self.isGenerating = false }

                let ctx = ContinuationBox(continuation: continuation)
                let boxPtr = Unmanaged.passRetained(ctx).toOpaque()

                let onToken: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { piece, ud in
                    guard let piece, let ud else { return }
                    let b = Unmanaged<ContinuationBox>.fromOpaque(ud).takeUnretainedValue()
                    b.continuation.yield(String(cString: piece))
                }

                let onDone: @convention(c) (ESStatus, UnsafeMutableRawPointer?) -> Void = { status, ud in
                    guard let ud else { return }
                    let b = Unmanaged<ContinuationBox>.fromOpaque(ud).takeRetainedValue()
                    if status == ES_STATUS_CANCELLED {
                        b.continuation.finish(throwing: CancellationError())
                    } else if status == ES_STATUS_ERR_GEN {
                        b.continuation.finish(throwing: EngineError.generationFailed)
                    } else {
                        b.continuation.finish()
                    }
                }

                let sysCStr = systemPrompt.map { ($0 as NSString).utf8String }
                let userCStr = (userText as NSString).utf8String!
                _ = es_generate(eng, sysCStr ?? nil, userCStr, maxTokens, onToken, onDone, boxPtr)
            }
        }
    }

    func continueConversation(userText: String, maxTokens: Int32 = 2048) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @EngineActor in
                guard let eng = self.engine else {
                    continuation.finish(throwing: EngineError.notLoaded)
                    return
                }
                self.isGenerating = true
                defer { self.isGenerating = false }

                let ctx = ContinuationBox(continuation: continuation)
                let boxPtr = Unmanaged.passRetained(ctx).toOpaque()

                let onToken: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { piece, ud in
                    guard let piece, let ud else { return }
                    let b = Unmanaged<ContinuationBox>.fromOpaque(ud).takeUnretainedValue()
                    b.continuation.yield(String(cString: piece))
                }

                let onDone: @convention(c) (ESStatus, UnsafeMutableRawPointer?) -> Void = { status, ud in
                    guard let ud else { return }
                    let b = Unmanaged<ContinuationBox>.fromOpaque(ud).takeRetainedValue()
                    if status == ES_STATUS_CANCELLED {
                        b.continuation.finish(throwing: CancellationError())
                    } else if status == ES_STATUS_ERR_GEN {
                        b.continuation.finish(throwing: EngineError.generationFailed)
                    } else {
                        b.continuation.finish()
                    }
                }

                let userCStr = (userText as NSString).utf8String!
                _ = es_continue(eng, userCStr, maxTokens, onToken, onDone, boxPtr)
            }
        }
    }

    // MARK: - Agentic Pipeline

    func orchestrate(systemPrompt: String?, userText: String,
                     maxTokensPerStage: Int32 = 1024) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { @EngineActor in
                guard let eng = self.engine else {
                    continuation.finish(throwing: EngineError.notLoaded)
                    return
                }
                self.isGenerating = true
                defer { self.isGenerating = false }

                let box = AgentEventBox(continuation: continuation)
                let boxPtr = Unmanaged.passRetained(box).toOpaque()

                let onStage: @convention(c) (ESAgentStage, UnsafeMutableRawPointer?) -> Void = { stage, ud in
                    guard let ud else { return }
                    let b = Unmanaged<AgentEventBox>.fromOpaque(ud).takeUnretainedValue()
                    b.continuation.yield(.stage(stage))
                }

                let onToken: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { piece, ud in
                    guard let piece, let ud else { return }
                    let b = Unmanaged<AgentEventBox>.fromOpaque(ud).takeUnretainedValue()
                    b.continuation.yield(.token(String(cString: piece)))
                }

                let onDone: @convention(c) (ESStatus, UnsafeMutableRawPointer?) -> Void = { status, ud in
                    guard let ud else { return }
                    let b = Unmanaged<AgentEventBox>.fromOpaque(ud).takeRetainedValue()
                    if status == ES_STATUS_CANCELLED {
                        b.continuation.finish(throwing: CancellationError())
                    } else if status != ES_STATUS_OK {
                        b.continuation.finish(throwing: EngineError.generationFailed)
                    } else {
                        b.continuation.finish()
                    }
                }

                let sysCStr = systemPrompt.flatMap { $0.isEmpty ? nil : ($0 as NSString).utf8String }
                let queryCStr = (userText as NSString).utf8String!
                _ = es_orchestrate(eng, sysCStr ?? nil, queryCStr, maxTokensPerStage,
                                   onStage, onToken, onDone, boxPtr)
            }
        }
    }

    // MARK: - Control

    func cancel() {
        guard let e = engine else { return }
        es_cancel(e)
    }

    func reset() {
        guard let e = engine else { return }
        es_reset(e)
    }

    var contextUsed: Int32 { engine.map { es_ctx_used($0) } ?? 0 }
    var contextMax:  Int32 { engine.map { es_ctx_max($0)  } ?? 0 }
    var lastNTokens: Int32 { engine.map { es_last_n_tokens($0) } ?? 0 }

    func needsReload(for path: String) -> Bool {
        !isLoaded || currentModelPath != path
    }
}

// MARK: - Private helpers

private final class ProgressBox: @unchecked Sendable {
    let callback: (Double) -> Void
    init(callback: @escaping (Double) -> Void) { self.callback = callback }
}

private final class ContinuationBox: @unchecked Sendable {
    let continuation: AsyncThrowingStream<String, Error>.Continuation
    init(continuation: AsyncThrowingStream<String, Error>.Continuation) {
        self.continuation = continuation
    }
}

private final class AgentEventBox: @unchecked Sendable {
    let continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    init(continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation) {
        self.continuation = continuation
    }
}
