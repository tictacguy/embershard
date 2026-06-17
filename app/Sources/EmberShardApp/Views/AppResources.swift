import Foundation

// Non-crashing replacement for SwiftPM's `Bundle.module`.
//
// `Bundle.module` calls `fatalError` when the generated resource bundle can't be
// located, which takes the whole app down at launch — exactly the SIGTRAP we hit
// when the packaged .app didn't ship the bundle. This searches the likely
// locations and returns nil instead, so callers degrade gracefully (the logo and
// provider icons just fall back) rather than crashing.
enum AppResources {
    private final class Token {}

    static let bundle: Bundle? = {
        let name = "Embershard_EmberShardApp"
        let token = Bundle(for: Token.self)
        let candidates: [URL?] = [
            Bundle.main.resourceURL,                              // App.app/Contents/Resources
            Bundle.main.bundleURL,                                // App.app
            token.resourceURL,
            token.bundleURL,
            Bundle.main.executableURL?.deletingLastPathComponent(), // next to the binary (dev/CLI)
        ]
        for case let dir? in candidates {
            let url = dir.appendingPathComponent(name + ".bundle")
            if let b = Bundle(url: url) { return b }
        }
        // Resources may also have been copied loose into the main bundle.
        return Bundle.main
    }()
}
