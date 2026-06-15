import SwiftUI
import AppKit

// Maps model names/repos to their provider icon.

enum ProviderIcon {
    private static let providerMap: [(keyword: String, file: String)] = [
        ("qwen", "Qwen"),
        ("llama", "meta"),
        ("meta-llama", "meta"),
        ("codellama", "meta"),
        ("mistral", "Mistral"),
        ("mixtral", "Mistral"),
        ("deepseek", "Deepseek"),
        ("kimi", "Kimi"),
        ("moonshot", "Kimi"),
        ("gemma", "google"),
        ("gemini", "google"),
        ("google", "google"),
        ("gpt", "openai"),
        ("openai", "openai"),
        ("phi", "microsoft"),
        ("claude", "anthropic"),
        ("anthropic", "anthropic"),
    ]

    static func providerName(for modelName: String) -> String? {
        let lower = modelName.lowercased()
        return providerMap.first { lower.contains($0.keyword) }?.file
    }

    static func nsImage(for modelName: String) -> NSImage? {
        guard let provider = providerName(for: modelName) else { return nil }

        let bundle = Bundle.module
        let extensions = ["png", "webp", "svg"]

        for ext in extensions {
            if let url = bundle.url(forResource: provider, withExtension: ext,
                                    subdirectory: "ProviderIcons") {
                if let img = NSImage(contentsOf: url) {
                    // Render into a fixed-size bitmap to handle complex SVGs
                    return renderToSize(img, size: NSSize(width: 64, height: 64))
                }
            }
        }

        if let resURL = bundle.resourceURL {
            let dir = resURL.appendingPathComponent("ProviderIcons")
            for ext in extensions {
                let fileURL = dir.appendingPathComponent("\(provider).\(ext)")
                if FileManager.default.fileExists(atPath: fileURL.path),
                   let img = NSImage(contentsOf: fileURL) {
                    return renderToSize(img, size: NSSize(width: 64, height: 64))
                }
            }
        }

        return nil
    }

    private static func renderToSize(_ source: NSImage, size: NSSize) -> NSImage {
        let target = NSImage(size: size)
        target.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: size),
                    from: NSRect(origin: .zero, size: source.size),
                    operation: .copy, fraction: 1.0)
        target.unlockFocus()
        return target
    }
}

// MARK: - Reusable SwiftUI view

struct ProviderIconView: View {
    let modelName: String
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let nsImg = ProviderIcon.nsImage(for: modelName) {
                Image(nsImage: nsImg)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
            } else {
                Image(systemName: "cpu")
                    .font(.system(size: size * 0.7))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
