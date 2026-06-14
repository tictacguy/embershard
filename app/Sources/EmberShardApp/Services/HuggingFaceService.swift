import Foundation

// MARK: - HF model catalog

struct HFModelEntry: Identifiable, Hashable {
    var id: String { repoId }
    let repoId: String          // e.g. "bartowski/Llama-3.2-3B-Instruct-GGUF"
    let name: String            // display name
    let filename: String        // specific .gguf file to download
    let sizeGB: Double
    let quantization: String
    let minRAMGB: Int
    let description: String
    let downloadURL: URL

    static func == (lhs: HFModelEntry, rhs: HFModelEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Curated catalog

extension HFModelEntry {
    static let catalog: [HFModelEntry] = [
        // 3B tier (8 GB RAM)
        make("bartowski/Llama-3.2-3B-Instruct-GGUF",
             name: "Llama 3.2 3B Instruct",
             file: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
             size: 2.0, quant: "Q4_K_M", minRAM: 8,
             desc: "Meta's compact Llama 3.2. Great for quick tasks."),

        make("Qwen/Qwen2.5-3B-Instruct-GGUF",
             name: "Qwen 2.5 3B Instruct",
             file: "qwen2.5-3b-instruct-q4_k_m.gguf",
             size: 2.0, quant: "Q4_K_M", minRAM: 8,
             desc: "Alibaba's Qwen 2.5 3B, excellent multilingual support."),

        // 7B tier (16 GB RAM)
        make("bartowski/Meta-Llama-3.1-8B-Instruct-GGUF",
             name: "Llama 3.1 8B Instruct",
             file: "Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf",
             size: 4.9, quant: "Q4_K_M", minRAM: 16,
             desc: "Meta's flagship 8B model, best in class for its size."),

        make("bartowski/Mistral-7B-Instruct-v0.3-GGUF",
             name: "Mistral 7B Instruct v0.3",
             file: "Mistral-7B-Instruct-v0.3-Q4_K_M.gguf",
             size: 4.4, quant: "Q4_K_M", minRAM: 16,
             desc: "Mistral 7B, strong reasoning and coding."),

        make("Qwen/Qwen2.5-7B-Instruct-GGUF",
             name: "Qwen 2.5 7B Instruct",
             file: "qwen2.5-7b-instruct-q4_k_m.gguf",
             size: 4.7, quant: "Q4_K_M", minRAM: 16,
             desc: "Alibaba's Qwen 2.5 7B, exceptional coding and math."),

        // 14B tier (32 GB RAM)
        make("bartowski/Qwen2.5-14B-Instruct-GGUF",
             name: "Qwen 2.5 14B Instruct",
             file: "Qwen2.5-14B-Instruct-Q4_K_M.gguf",
             size: 8.9, quant: "Q4_K_M", minRAM: 32,
             desc: "Qwen 2.5 14B — near-frontier quality on Apple Silicon."),

        make("bartowski/Phi-4-GGUF",
             name: "Microsoft Phi-4 14B",
             file: "Phi-4-Q4_K_M.gguf",
             size: 8.4, quant: "Q4_K_M", minRAM: 32,
             desc: "Microsoft Phi-4, exceptional reasoning despite compact size."),

        // 70B tier (64 GB RAM)
        make("bartowski/Meta-Llama-3.1-70B-Instruct-GGUF",
             name: "Llama 3.1 70B Instruct",
             file: "Meta-Llama-3.1-70B-Instruct-Q4_K_M.gguf",
             size: 42.5, quant: "Q4_K_M", minRAM: 64,
             desc: "Meta's 70B flagship. Requires 64 GB unified memory."),
    ]

    private static func make(
        _ repo: String, name: String, file: String,
        size: Double, quant: String, minRAM: Int, desc: String
    ) -> HFModelEntry {
        let urlStr = "https://huggingface.co/\(repo)/resolve/main/\(file)"
        return HFModelEntry(
            repoId: repo, name: name, filename: file,
            sizeGB: size, quantization: quant, minRAMGB: minRAM,
            description: desc,
            downloadURL: URL(string: urlStr)!
        )
    }
}

// MARK: - HuggingFaceService

@MainActor
final class HuggingFaceService: ObservableObject {
    static let shared = HuggingFaceService()

    @Published private(set) var models: [HFModelEntry] = HFModelEntry.catalog
    @Published private(set) var isFetching = false

    private init() {}

    /// Filter catalog by minimum RAM requirement.
    func models(forRAMGB ram: Int) -> [HFModelEntry] {
        models.filter { $0.minRAMGB <= ram }
    }

    /// Try fetching updated model info from HuggingFace API.
    /// Falls back to catalog if unavailable.
    func refresh() async {
        // The catalog is curated and reliable; network fetch is a bonus.
        // For now, the catalog is the source of truth.
        // Future: query HF API for updated file sizes / new models.
    }
}
