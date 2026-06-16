import AppKit

/// Curated set of SF Symbols offered to the title-naming model, plus validation.
///
/// The model is given this full list so it always picks a symbol that exists.
/// Whatever it returns is still validated against the system symbol table
/// (`NSImage(systemSymbolName:)`) and falls back to a safe default if the symbol
/// is unknown — so a hallucinated or off-list name can never produce a blank icon.
enum IconCatalog {
    static let fallback = "bubble.left"

    /// Broad, category-spanning set. Every entry is a real SF Symbol on macOS 14+.
    static let titleIcons: [String] = [
        // General / conversation
        "bubble.left", "text.bubble", "quote.bubble", "bell", "flag", "tag",
        // Code / tech
        "chevron.left.forwardslash.chevron.right", "curlybraces", "terminal",
        "cpu", "memorychip", "server.rack", "network", "gearshape", "wrench.and.screwdriver",
        "ant", "ladybug", "function",
        // Knowledge / writing
        "book", "books.vertical", "doc.text", "newspaper", "pencil", "highlighter",
        "graduationcap", "brain", "lightbulb", "magnifyingglass",
        // Data / business
        "chart.bar", "chart.pie", "chart.line.uptrend.xyaxis", "tablecells",
        "dollarsign.circle", "cart", "briefcase", "creditcard", "calendar", "clock",
        // Media / creative
        "music.note", "film", "camera", "photo", "paintbrush", "paintpalette",
        "gamecontroller", "mic", "headphones",
        // World / life
        "globe", "map", "airplane", "car", "house", "leaf", "flame", "drop",
        "bolt", "sun.max", "moon.stars", "cloud", "heart", "star", "gift",
        "person", "person.2", "hand.raised", "figure.walk",
        // Food / health
        "fork.knife", "cup.and.saucer", "cross.case", "pills", "dumbbell",
        // Science / math
        "atom", "testtube.2", "ruler", "compass.drawing", "scalemass",
    ]

    /// Comma-separated list to embed in the model prompt.
    static let promptList = titleIcons.joined(separator: ", ")

    private static let lowerSet = Set(titleIcons.map { $0.lowercased() })

    /// Resolve the model's raw icon pick into a guaranteed-renderable SF Symbol.
    ///
    /// Order: clean the string → match the curated list (case-insensitive) →
    /// accept any real system symbol → keyword-guess from the title → default.
    static func resolve(rawIcon: String, title: String) -> String {
        let cleaned = clean(rawIcon)
        if !cleaned.isEmpty {
            if lowerSet.contains(cleaned.lowercased()),
               let exact = titleIcons.first(where: { $0.lowercased() == cleaned.lowercased() }) {
                return exact
            }
            if NSImage(systemSymbolName: cleaned, accessibilityDescription: nil) != nil {
                return cleaned
            }
        }
        return keywordIcon(for: title) ?? fallback
    }

    /// Strip markdown/quotes/punctuation and keep the first symbol-like token.
    private static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "`", with: "")
             .replacingOccurrences(of: "\"", with: "")
             .replacingOccurrences(of: "'", with: "")
        // Keep only the first whitespace-separated token (drop trailing prose).
        if let first = s.split(whereSeparator: { $0 == " " || $0 == "\n" }).first {
            s = String(first)
        }
        // SF Symbol names are [a-z0-9.] — trim anything else from the ends.
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.")
        while let f = s.unicodeScalars.first, !allowed.contains(f) { s.removeFirst() }
        while let l = s.unicodeScalars.last,  !allowed.contains(l) { s.removeLast() }
        return s
    }

    private static let keywordMap: [(String, String)] = [
        ("code", "chevron.left.forwardslash.chevron.right"), ("program", "curlybraces"),
        ("bug", "ant"), ("debug", "ant"), ("function", "function"), ("math", "function"),
        ("translat", "globe"), ("language", "globe"), ("write", "pencil"), ("essay", "doc.text"),
        ("story", "book"), ("book", "book"), ("research", "magnifyingglass"), ("idea", "lightbulb"),
        ("brainstorm", "lightbulb"), ("music", "music.note"), ("movie", "film"), ("film", "film"),
        ("game", "gamecontroller"), ("photo", "photo"), ("image", "photo"), ("money", "dollarsign.circle"),
        ("budget", "dollarsign.circle"), ("buy", "cart"), ("shop", "cart"), ("travel", "airplane"),
        ("trip", "airplane"), ("car", "car"), ("home", "house"), ("house", "house"),
        ("health", "cross.case"), ("food", "fork.knife"), ("recipe", "fork.knife"), ("workout", "dumbbell"),
        ("science", "atom"), ("data", "chart.bar"), ("chart", "chart.bar"), ("plan", "calendar"),
        ("schedule", "calendar"), ("time", "clock"), ("weather", "cloud"), ("plant", "leaf"),
    ]

    /// Best-effort icon guess from words in the title.
    static func keywordIcon(for title: String) -> String? {
        let lower = title.lowercased()
        for (kw, icon) in keywordMap where lower.contains(kw) { return icon }
        return nil
    }
}
