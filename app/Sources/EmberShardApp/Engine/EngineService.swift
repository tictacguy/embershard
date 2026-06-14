import Foundation
import EmberShardBridge

// MARK: - Configuration

struct EngineConfig {
    var modelPath: String
    var contextSize: Int32 = 4096
    var temperature: Float = 0.7
    var topP: Float = 0.95
    var gpuLayers: Int32 = -1   // -1 = all on Metal
    var threads: Int32 = 0      // 0 = auto
}

// MARK: - Engine errors

enum EngineError: LocalizedError {
    case modelLoadFailed
    case contextInitFailed
    case generationFailed
    case notLoaded

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed:   return "Failed to load model"
        case .contextInitFailed: return "Failed to initialize context"
        case .generationFailed:  return "Generation failed"
        case .notLoaded:         return "Engine not loaded"
        }
    }
}

// MARK: - EngineService

/// Thread-safe actor that owns the C engine instance.
/// All engine calls are serialized through this actor.
@globalActor actor EngineActor {
    static let shared = EngineActor()
}

@EngineActor
final class EngineService: ObservableObject {
    static let shared = EngineService()

    private var engine: ESEngineRef?

    // Published state (projected to MainActor for UI updates)
    private(set) var isLoaded = false
    private(set) var isGenerating = false
    private(set) var loadProgress: Double = 0
    private(set) var currentModelPath: String = ""

    private init() {}

    // MARK: - Lifecycle

    func load(config: EngineConfig, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        if let existing = engine {
            es_destroy(existing)
            engine = nil
            isLoaded = false
        }

        var cConfig = ESConfig()
        cConfig.model_path   = nil // set below
        cConfig.n_ctx        = config.contextSize
        cConfig.n_gpu_layers = config.gpuLayers
        cConfig.n_threads    = config.threads
        cConfig.temperature  = config.temperature
        cConfig.top_p        = config.topP

        // Bridge progress callback via a box
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

        // Release the box
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

    /// Starts a new conversation and generates a response.
    /// Returns an AsyncStream of token pieces.
    func generate(systemPrompt: String?, userText: String, maxTokens: Int32 = 512) -> AsyncThrowingStream<String, Error> {
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
                    } else {
                        b.continuation.finish()
                    }
                }

                if systemPrompt != nil || true {
                    let sysCStr = systemPrompt.map { ($0 as NSString).utf8String }
                    let userCStr = (userText as NSString).utf8String!
                    _ = es_generate(eng, sysCStr ?? nil, userCStr, maxTokens,
                                    onToken, onDone, boxPtr)
                }
            }
        }
    }

    /// Continues an existing conversation.
    func continueConversation(userText: String, maxTokens: Int32 = 512) -> AsyncThrowingStream<String, Error> {
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

                let onDone: @convention(c) (ESStatus, UnsafeMutableRawPointer?) -> Void = { _, ud in
                    guard let ud else { return }
                    Unmanaged<ContinuationBox>.fromOpaque(ud).takeRetainedValue().continuation.finish()
                }

                let userCStr = (userText as NSString).utf8String!
                _ = es_continue(eng, userCStr, maxTokens, onToken, onDone, boxPtr)
            }
        }
    }

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
