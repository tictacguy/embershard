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

    // HuggingFace org that published the repo (the part before "/").
    var publisher: String { repoId.split(separator: "/").first.map(String.init) ?? repoId }
    var isOfficial: Bool { HFModelEntry.officialOrgs.contains(publisher.lowercased()) }

    static let officialOrgs: Set<String> = [
        "qwen", "meta-llama", "meta", "mistralai", "microsoft", "google",
        "deepseek-ai", "nvidia", "ibm-granite", "tiiuae", "huggingfacetb",
    ]

    // Compatible == an architecture our native engine (es_gx) implements: the
    // llama family (Llama, Mistral, TinyLlama…) and qwen2 (Qwen2/2.5,
    // DeepSeek-R1-Distill-Qwen). Excludes MoE and unsupported architectures.
    static func inferCompatible(_ s: String) -> Bool {
        let l = s.lowercased()
        let bad = ["phi", "gemma", "gpt-oss", "gpt-neox", "falcon", "mpt", "bloom",
                   "mamba", "rwkv", "mixtral", "-moe", "deepseek-v2", "deepseek-v3",
                   "deepseek-coder-v2", "command-r", "stablelm", "starcoder", "vl", "vision"]
        if bad.contains(where: { l.contains($0) }) { return false }
        let good = ["llama", "qwen", "mistral", "tinyllama"]
        return good.contains(where: { l.contains($0) })
    }
    var compatible: Bool { HFModelEntry.inferCompatible(repoId + " " + name) }

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

    // Curated OFFICIAL GGUF from the original providers, compatible with our
    // native engine (llama / qwen2 architectures only). Among supported archs,
    // first-party GGUF are published mainly by Qwen and HuggingFaceTB (SmolLM2,
    // a llama-architecture model); Meta/Mistral ship original weights, not GGUF.
    static let curatedModels: [HFModelEntry] = [
        // ── ≤8 GB RAM ────────────────────────────────────────────────────────
        entry("HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF", name: "SmolLM2 1.7B Instruct",
              file: "smollm2-1.7b-instruct-q4_k_m.gguf", size: 1.1, quant: "Q4_K_M", ram: 8, dl: 30000, likes: 150),
        entry("Qwen/Qwen2.5-1.5B-Instruct-GGUF", name: "Qwen 2.5 1.5B Instruct",
              file: "qwen2.5-1.5b-instruct-q4_k_m.gguf", size: 1.1, quant: "Q4_K_M", ram: 8, dl: 45000, likes: 220),
        // Meta does not publish GGUF; bartowski is the canonical repack for Llama.
        entry("bartowski/Llama-3.2-1B-Instruct-GGUF", name: "Llama 3.2 1B Instruct",
              file: "Llama-3.2-1B-Instruct-Q4_K_M.gguf", size: 0.8, quant: "Q4_K_M", ram: 8, dl: 90000, likes: 350),
        entry("bartowski/Llama-3.2-3B-Instruct-GGUF", name: "Llama 3.2 3B Instruct",
              file: "Llama-3.2-3B-Instruct-Q4_K_M.gguf", size: 2.0, quant: "Q4_K_M", ram: 8, dl: 120000, likes: 600),
        entry("Qwen/Qwen2.5-3B-Instruct-GGUF", name: "Qwen 2.5 3B Instruct",
              file: "qwen2.5-3b-instruct-q4_k_m.gguf", size: 2.0, quant: "Q4_K_M", ram: 8, dl: 50000, likes: 260),

        // ── 16 GB RAM ────────────────────────────────────────────────────────
        entry("bartowski/Meta-Llama-3.1-8B-Instruct-GGUF", name: "Llama 3.1 8B Instruct",
              file: "Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf", size: 4.9, quant: "Q4_K_M", ram: 16, dl: 200000, likes: 800),
        entry("Qwen/Qwen2.5-7B-Instruct-GGUF", name: "Qwen 2.5 7B Instruct",
              file: "qwen2.5-7b-instruct-q4_k_m.gguf", size: 4.7, quant: "Q4_K_M", ram: 16, dl: 60000, likes: 320),
        entry("Qwen/Qwen2.5-Coder-7B-Instruct-GGUF", name: "Qwen 2.5 Coder 7B",
              file: "qwen2.5-coder-7b-instruct-q4_k_m.gguf", size: 4.7, quant: "Q4_K_M", ram: 16, dl: 48000, likes: 280),
        // SentencePiece (SPM) models — exercise the SPM tokenizer + [INST] template.
        entry("bartowski/Mistral-7B-Instruct-v0.2-GGUF", name: "Mistral 7B Instruct v0.2",
              file: "Mistral-7B-Instruct-v0.2-Q4_K_M.gguf", size: 4.4, quant: "Q4_K_M", ram: 16, dl: 80000, likes: 300),
        entry("bartowski/Llama-2-7b-chat-hf-GGUF", name: "Llama 2 7B Chat",
              file: "Llama-2-7b-chat-hf-Q4_K_M.gguf", size: 4.1, quant: "Q4_K_M", ram: 16, dl: 60000, likes: 250),
        entry("bartowski/Qwen2.5-14B-Instruct-GGUF", name: "Qwen 2.5 14B Instruct",
              file: "Qwen2.5-14B-Instruct-Q4_K_M.gguf", size: 9.0, quant: "Q4_K_M", ram: 16, dl: 70000, likes: 300),

        // ── 32 GB+ RAM ───────────────────────────────────────────────────────
        entry("bartowski/Qwen2.5-32B-Instruct-GGUF", name: "Qwen 2.5 32B Instruct",
              file: "Qwen2.5-32B-Instruct-Q4_K_M.gguf", size: 19.8, quant: "Q4_K_M", ram: 32, dl: 30000, likes: 200),
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
                // Skip all sharded files (any part marker)
                let shardPattern = try? NSRegularExpression(pattern: "-\\d{5}-of-\\d{5}")
                if let _ = shardPattern?.firstMatch(in: f.filename, range: NSRange(f.filename.startIndex..., in: f.filename)) {
                    return false
                }
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
