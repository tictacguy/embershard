import Foundation
import AppKit

// Checks GitHub Releases for a newer version and surfaces a banner. We can't do a
// fully silent install without an Apple Developer ID (a downloaded, un-notarized
// build is quarantined by Gatekeeper and needs a one-time approval), so "Update"
// fetches the .dmg and opens it for the usual drag-to-Applications step.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    struct Update: Equatable { let version: String; let url: URL }
    @Published var available: Update?
    @Published var downloading = false

    private let repo = "tictacguy/embershard"
    private var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func check() async {
        guard let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var req = URLRequest(url: api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 8
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String else { return }

        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard Self.isNewer(latest, than: current) else { return }

        var dmg: URL?
        if let assets = obj["assets"] as? [[String: Any]] {
            for a in assets where (a["name"] as? String)?.hasSuffix(".dmg") == true {
                if let s = a["browser_download_url"] as? String { dmg = URL(string: s); break }
            }
        }
        let page = URL(string: "https://github.com/\(repo)/releases/latest")!
        available = Update(version: latest, url: dmg ?? page)
    }

    // Download the .dmg to ~/Downloads and open it (or just open the page).
    func update() {
        guard let upd = available else { return }
        guard upd.url.pathExtension == "dmg" else { NSWorkspace.shared.open(upd.url); return }
        downloading = true
        Task {
            defer { downloading = false }
            let dest = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads")
                .appendingPathComponent(upd.url.lastPathComponent)
            if let (tmp, _) = try? await URLSession.shared.download(from: upd.url) {
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.moveItem(at: tmp, to: dest)
                NSWorkspace.shared.open(dest)            // mount the .dmg
            } else {
                NSWorkspace.shared.open(upd.url)          // fall back to the browser
            }
            available = nil
        }
    }

    func dismiss() { available = nil }

    // Numeric semver compare: "0.2.0" > "0.1.9".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
