import Foundation

// MARK: - DownloadState

enum DownloadState: Equatable {
    case idle
    case downloading(progress: Double)  // 0.0 → 1.0
    case done(path: String)
    case failed(String)
}

// MARK: - ModelDownloader

@MainActor
final class ModelDownloader: NSObject, ObservableObject {
    static let shared = ModelDownloader()

    @Published var states: [String: DownloadState] = [:]  // keyed by HFModelEntry.id

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForResource = 3600
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    nonisolated static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Embershard/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private override init() {}

    func download(_ model: HFModelEntry) {
        guard states[model.id] != .downloading(progress: 0) else { return }

        let destURL = Self.modelsDirectory.appendingPathComponent(model.filename)
        if FileManager.default.fileExists(atPath: destURL.path) {
            states[model.id] = .done(path: destURL.path)
            return
        }

        states[model.id] = .downloading(progress: 0)
        var request = URLRequest(url: model.downloadURL)
        request.setValue("Embershard/1.0", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        task.taskDescription = model.id
        tasks[model.id] = task
        task.resume()
    }

    func cancel(_ model: HFModelEntry) {
        tasks[model.id]?.cancel()
        tasks[model.id] = nil
        states[model.id] = .idle
    }

    func localPath(for model: HFModelEntry) -> String? {
        let url = Self.modelsDirectory.appendingPathComponent(model.filename)
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }
}

// MARK: - URLSessionDownloadDelegate

extension ModelDownloader: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let modelId = downloadTask.taskDescription else { return }
        let dest = Self.modelsDirectory.appendingPathComponent(
            downloadTask.response?.suggestedFilename
            ?? location.lastPathComponent
        )
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            Task { @MainActor in
                self.states[modelId] = .done(path: dest.path)
                self.tasks.removeValue(forKey: modelId)
                // Auto-register in LocalModelStore
                let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
                let size = (attrs?[.size] as? Int64) ?? 0
                let quant = Self.parseQuantization(from: dest.lastPathComponent)
                let lm = LocalModel(
                    name: dest.deletingPathExtension().lastPathComponent,
                    path: dest.path,
                    sizeBytes: size,
                    quantization: quant
                )
                LocalModelStore.shared.add(lm)
                if LocalModelStore.shared.activeModelPath.isEmpty {
                    LocalModelStore.shared.setActive(lm)
                }
            }
        } catch {
            Task { @MainActor in
                self.states[modelId] = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didWriteData _: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard let modelId = downloadTask.taskDescription,
              totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            self.states[modelId] = .downloading(progress: progress)
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let error, let modelId = task.taskDescription else { return }
        Task { @MainActor in
            self.states[modelId] = .failed(error.localizedDescription)
            self.tasks.removeValue(forKey: modelId)
        }
    }

    static func parseQuantization(from filename: String) -> String {
        let patterns = ["Q8_0","Q6_K","Q5_K_M","Q5_K_S","Q5_0","Q4_K_M","Q4_K_S","Q4_0","Q3_K_M","Q2_K"]
        let upper = filename.uppercased()
        return patterns.first { upper.contains($0) } ?? "unknown"
    }
}
