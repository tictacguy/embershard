import Foundation

// MARK: - HFModelEntry

struct HFModelEntry: Identifiable, Hashable {
    var id: String { "\(repoId)/\(filename)" }
    let repoId: String
    let name: String
    let filename: String
    let sizeGB: Double
    let quantization: String
    let minRAMGB: Int
    let description: String
    let downloadURL: URL
    let downloads: Int
    let likes: Int

    static func == (lhs: HFModelEntry, rhs: HFModelEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - HuggingFaceService

@MainActor
final class HuggingFaceService: ObservableObject {
    static let shared = HuggingFaceService()

    @Published private(set) var models: [HFModelEntry] = []
    @Published private(set) var isFetching = false

    private init() {
        models = Self.curatedModels
    }

    func models(forRAMGB ram: Int) -> [HFModelEntry] {
        models.filter { $0.minRAMGB <= ram }
    }

    func resetToCurated() {
        models = Self.curatedModels
    }

    // Curated official models from top providers
    static let curatedModels: [HFModelEntry] = [
        // 3B tier (8 GB RAM)
        entry("Qwen/Qwen2.5-3B-Instruct-GGUF", name: "Qwen 2.5 3B Instruct",
              file: "qwen2.5-3b-instruct-q4_k_m.gguf", size: 2.0, quant: "Q4_K_M", ram: 8, dl: 50000, likes: 200),
        entry("bartowski/Llama-3.2-3B-Instruct-GGUF", name: "Llama 3.2 3B Instruct",
              file: "Llama-3.2-3B-Instruct-Q4_K_M.gguf", size: 2.0, quant: "Q4_K_M", ram: 8, dl: 80000, likes: 400),

        // 7-8B tier (16 GB RAM)
        entry("Qwen/Qwen2.5-7B-Instruct-GGUF", name: "Qwen 2.5 7B Instruct",
              file: "qwen2.5-7b-instruct-q4_k_m.gguf", size: 4.7, quant: "Q4_K_M", ram: 16, dl: 60000, likes: 300),
        entry("bartowski/Meta-Llama-3.1-8B-Instruct-GGUF", name: "Llama 3.1 8B Instruct",
              file: "Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf", size: 4.9, quant: "Q4_K_M", ram: 16, dl: 120000, likes: 500),
        entry("bartowski/Mistral-7B-Instruct-v0.3-GGUF", name: "Mistral 7B Instruct v0.3",
              file: "Mistral-7B-Instruct-v0.3-Q4_K_M.gguf", size: 4.4, quant: "Q4_K_M", ram: 16, dl: 70000, likes: 250),

        // 14B tier (16 GB RAM - fits on M4 16GB)
        entry("bartowski/Qwen2.5-14B-Instruct-GGUF", name: "Qwen 2.5 14B Instruct",
              file: "Qwen2.5-14B-Instruct-Q4_K_M.gguf", size: 8.9, quant: "Q4_K_M", ram: 16, dl: 90000, likes: 350),
        entry("bartowski/Phi-4-GGUF", name: "Phi-4 14B (Microsoft)",
              file: "Phi-4-Q4_K_M.gguf", size: 8.4, quant: "Q4_K_M", ram: 16, dl: 40000, likes: 180),
        entry("bartowski/DeepSeek-R1-Distill-Qwen-14B-GGUF", name: "DeepSeek R1 Distill 14B",
              file: "DeepSeek-R1-Distill-Qwen-14B-Q4_K_M.gguf", size: 8.9, quant: "Q4_K_M", ram: 16, dl: 55000, likes: 220),

        // 32B tier (32 GB RAM)
        entry("bartowski/Qwen2.5-32B-Instruct-GGUF", name: "Qwen 2.5 32B Instruct",
              file: "Qwen2.5-32B-Instruct-Q4_K_M.gguf", size: 19.8, quant: "Q4_K_M", ram: 32, dl: 30000, likes: 150),

        // 70B tier (64 GB RAM)
        entry("bartowski/Meta-Llama-3.1-70B-Instruct-GGUF", name: "Llama 3.1 70B Instruct",
              file: "Meta-Llama-3.1-70B-Instruct-Q4_K_M.gguf", size: 42.5, quant: "Q4_K_M", ram: 64, dl: 25000, likes: 100),
    ]

    private static func entry(_ repo: String, name: String, file: String,
                              size: Double, quant: String, ram: Int, dl: Int, likes: Int) -> HFModelEntry {
        HFModelEntry(
            repoId: repo, name: name, filename: file,
            sizeGB: size, quantization: quant, minRAMGB: ram,
            description: repo,
            downloadURL: URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file)")!,
            downloads: dl, likes: likes
        )
    }

    /// Search HF API (only when user explicitly searches)
    func search(query: String, maxSizeGB: Double) async {
        guard !query.isEmpty else {
            models = Self.curatedModels.filter { $0.sizeGB <= maxSizeGB }
            return
        }

        isFetching = true
        defer { isFetching = false }

        if let results = await searchHF(query: "\(query) GGUF", maxSizeGB: maxSizeGB) {
            var seen = Set<String>()
            models = results
                .sorted { $0.downloads > $1.downloads }
                .filter { seen.insert($0.filename.lowercased()).inserted }
        }
    }

    // MARK: - HF API

    private func searchHF(query: String, maxSizeGB: Double) async -> [HFModelEntry]? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlStr = "https://huggingface.co/api/models?search=\(encoded)&filter=gguf&sort=downloads&direction=-1&limit=20"
        guard let url = URL(string: urlStr) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Embershard/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        guard let repos = try? JSONDecoder().decode([HFRepoResponse].self, from: data) else { return nil }

        var entries: [HFModelEntry] = []

        for repo in repos.prefix(15) {
            // Skip embedding models
            let lower = repo.id.lowercased()
            if lower.contains("embed") || lower.contains("bge-") || lower.contains("e5-") || lower.contains("gte-") {
                continue
            }
            guard let files = await fetchRepoFiles(repo: repo.id) else { continue }

            let preferredQuants = ["Q4_K_M", "Q5_K_M", "Q4_K_S", "Q8_0"]
            let ggufFiles = files.filter { f in
                guard f.filename.hasSuffix(".gguf") else { return false }
                // Skip split files
                guard !f.filename.contains("-00001-of-") && !f.filename.contains("-00002-of-") else { return false }
                let upper = f.filename.uppercased()
                return preferredQuants.contains { upper.contains($0) }
            }

            for file in ggufFiles {
                let sizeGB = Double(file.size) / 1_073_741_824.0
                guard sizeGB > 0.5 && sizeGB <= maxSizeGB else { continue }

                let quant = parseQuantization(from: file.filename)
                guard !quant.isEmpty else { continue }

                let minRAM = estimateMinRAM(sizeGB: sizeGB)
                let downloadURL = URL(string: "https://huggingface.co/\(repo.id)/resolve/main/\(file.filename)")!

                entries.append(HFModelEntry(
                    repoId: repo.id,
                    name: repo.id.components(separatedBy: "/").last ?? repo.id,
                    filename: file.filename,
                    sizeGB: sizeGB,
                    quantization: quant,
                    minRAMGB: minRAM,
                    description: repo.id,
                    downloadURL: downloadURL,
                    downloads: repo.downloads ?? 0,
                    likes: repo.likes ?? 0
                ))
            }
        }

        return entries
    }

    private func fetchRepoFiles(repo: String) async -> [HFFileInfo]? {
        let encoded = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repo
        let urlStr = "https://huggingface.co/api/models/\(encoded)?blobs=true"
        guard let url = URL(string: urlStr) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Embershard/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        guard let detail = try? JSONDecoder().decode(HFModelDetail.self, from: data) else { return nil }
        return detail.siblings
    }

    private func parseQuantization(from filename: String) -> String {
        let patterns = ["Q8_0","Q6_K","Q5_K_M","Q5_K_S","Q5_0","Q4_K_M","Q4_K_S","Q4_0","Q3_K_M","Q3_K_S","Q2_K"]
        let upper = filename.uppercased()
        return patterns.first { upper.contains($0) } ?? ""
    }

    private func estimateMinRAM(sizeGB: Double) -> Int {
        let needed = sizeGB + 2.0
        if needed <= 6 { return 8 }
        if needed <= 12 { return 16 }
        if needed <= 24 { return 32 }
        return 64
    }
}

// MARK: - HF API Response Models

private struct HFRepoResponse: Decodable {
    let id: String
    let downloads: Int?
    let likes: Int?
}

private struct HFModelDetail: Decodable {
    let siblings: [HFFileInfo]?
}

private struct HFFileInfo: Decodable {
    let rfilename: String?
    let size: Int

    var filename: String { rfilename ?? "" }

    enum CodingKeys: String, CodingKey {
        case rfilename, size
    }
}
