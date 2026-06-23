import SwiftUI
import AppKit

// Fetches a HuggingFace org/user avatar (the logo you see on the model page) and
// caches it. Falls back to the bundled provider icon if there's no avatar or no
// network, so it never blocks or breaks the row.
@MainActor
final class HFAvatarStore: ObservableObject {
    static let shared = HFAvatarStore()
    @Published private var images: [String: NSImage] = [:]
    private var inFlight = Set<String>()
    private var failed = Set<String>()

    func image(for publisher: String) -> NSImage? { images[publisher.lowercased()] }

    func load(_ publisher: String) {
        let key = publisher.lowercased()
        guard !key.isEmpty, images[key] == nil, !inFlight.contains(key), !failed.contains(key) else { return }
        inFlight.insert(key)
        Task {
            let img = await Self.fetch(key)
            inFlight.remove(key)
            if let img { images[key] = img } else { failed.insert(key) }
        }
    }

    nonisolated private static func fetch(_ publisher: String) async -> NSImage? {
        for kind in ["organizations", "users"] {
            guard let url = URL(string: "https://huggingface.co/api/\(kind)/\(publisher)/avatar") else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            req.setValue("Embershard/1.0", forHTTPHeaderField: "User-Agent")
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { continue }
            // The endpoint returns either the image directly or JSON {avatarUrl}.
            if let img = NSImage(data: data) { return img }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let s = obj["avatarUrl"] as? String {
                let abs = s.hasPrefix("http") ? s : "https://huggingface.co\(s)"
                if let au = URL(string: abs),
                   let (idata, _) = try? await URLSession.shared.data(from: au),
                   let img = NSImage(data: idata) { return img }
            }
        }
        return nil
    }
}

struct HFAvatarView: View {
    let repoId: String          // "org/name"
    var size: CGFloat = 24
    @ObservedObject private var store = HFAvatarStore.shared

    private var publisher: String { repoId.split(separator: "/").first.map(String.init) ?? repoId }

    var body: some View {
        Group {
            if let img = store.image(for: publisher) {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                ProviderIconView(modelName: repoId, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear { store.load(publisher) }
    }
}
