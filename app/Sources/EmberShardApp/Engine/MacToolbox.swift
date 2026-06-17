import Foundation
import AppKit
import CryptoKit

// ─────────────────────────────────────────────────────────────────────────────
// macOS Helper tools — everything here runs app-side (Swift), never the engine.
// Read-only tools return results directly. Mutating tools return a *plan* the UI
// previews and the user must approve (accept / decline / modify) before it runs.
// Deletes always go to the Trash (reversible) — never an unlink. Emptying the
// Trash is intentionally NOT offered.
// ─────────────────────────────────────────────────────────────────────────────

enum MacToolID: String, CaseIterable, Codable {
    case findFiles, largestFiles, largestOnMac, folderSizes, recentFiles, scanThreats, heaviestApps   // read-only
    case tidyDesktop, tidyFolder, organizeByDate, findDuplicates, cleanOldDownloads,
         moveItem, createFolder, quitApp                                                // mutating
}

struct MacTool: Identifiable {
    let id: MacToolID
    let title: String
    let icon: String
    let blurb: String       // shown in the capabilities list
    let modelDesc: String   // shown to the model for routing (when + args)
    let destructive: Bool

    static let all: [MacTool] = [
        .init(id: .findFiles, title: "Find files", icon: "magnifyingglass",
              blurb: "Search for files anywhere you've granted access.",
              modelDesc: "Find files whose name contains some text. Use when the user looks for a file. args: query (required), path (optional folder).",
              destructive: false),
        .init(id: .largestFiles, title: "Largest files", icon: "scalemass",
              blurb: "Find the biggest files in a folder.",
              modelDesc: "List the biggest files in ONE folder. args: path (optional, default home).",
              destructive: false),
        .init(id: .largestOnMac, title: "Biggest files on Mac", icon: "externaldrive.badge.exclamationmark",
              blurb: "Find the biggest files across your whole Mac.",
              modelDesc: "List the biggest files across the WHOLE Mac (home, Applications, shared). Use for 'what's taking space on my computer'. no args.",
              destructive: false),
        .init(id: .folderSizes, title: "Where's my space", icon: "chart.pie",
              blurb: "See which subfolders use the most disk space.",
              modelDesc: "Break a folder down by the size of its subfolders. Use for 'where is my space going'. args: path (optional, default home).",
              destructive: false),
        .init(id: .recentFiles, title: "Recent files", icon: "clock",
              blurb: "List files changed in the last few days.",
              modelDesc: "List recently modified files. Use for 'what did I work on'. args: path (optional), days (optional, default 7).",
              destructive: false),
        .init(id: .scanThreats, title: "Scan for threats", icon: "shield.lefthalf.filled",
              blurb: "Heuristic check for suspicious files.",
              modelDesc: "Heuristically flag suspicious files: quarantined executables, unsigned apps, launch agents. Use for security worries. no args.",
              destructive: false),
        .init(id: .heaviestApps, title: "Heaviest apps", icon: "gauge.with.dots.needle.67percent",
              blurb: "Show the apps using the most memory and CPU.",
              modelDesc: "List running apps by memory and CPU. Use for 'what's slowing my Mac'. no args.",
              destructive: false),
        .init(id: .tidyDesktop, title: "Tidy Desktop", icon: "menubar.dock.rectangle",
              blurb: "Group loose Desktop files into folders by type.",
              modelDesc: "Sort the Desktop's loose files into subfolders by kind. Use for 'clean my desktop'. no args.",
              destructive: true),
        .init(id: .tidyFolder, title: "Tidy a folder", icon: "folder.badge.gearshape",
              blurb: "Group a folder's files into subfolders by type.",
              modelDesc: "Sort a folder's files into subfolders by kind. args: path (required).",
              destructive: true),
        .init(id: .organizeByDate, title: "Organize by date", icon: "calendar",
              blurb: "Sort a folder's files into Year/Month folders.",
              modelDesc: "Move a folder's files into Year/Month subfolders by modified date. args: path (required).",
              destructive: true),
        .init(id: .findDuplicates, title: "Find duplicates", icon: "doc.on.doc",
              blurb: "Find identical files; extras can go to the Trash.",
              modelDesc: "Find duplicate (identical) files; extra copies can be trashed. args: path (optional, default home).",
              destructive: true),
        .init(id: .cleanOldDownloads, title: "Clean old Downloads", icon: "arrow.down.circle",
              blurb: "Trash items in Downloads older than a while.",
              modelDesc: "Trash files in ~/Downloads older than N days. args: days (optional, default 30).",
              destructive: true),
        .init(id: .moveItem, title: "Move / rename", icon: "arrow.right.doc.on.clipboard",
              blurb: "Move or rename a specific file or folder.",
              modelDesc: "Move or rename one file/folder. Use for 'move X to Y' or 'rename X to Y'. args: source (required path), destination (required path or folder).",
              destructive: true),
        .init(id: .createFolder, title: "Create folder", icon: "folder.badge.plus",
              blurb: "Make a new folder with a specific name.",
              modelDesc: "Create a new folder. args: path (required, the folder to create).",
              destructive: true),
        .init(id: .quitApp, title: "Quit an app", icon: "xmark.app",
              blurb: "Quit a running app or process by name.",
              modelDesc: "Quit a running application by name. Use after 'heaviest apps' or 'close X'. args: name (required app name).",
              destructive: true),
    ]

    static func by(_ id: MacToolID) -> MacTool { all.first { $0.id == id }! }
}

struct MacFileItem: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let detail: String
    var name: String { (path as NSString).lastPathComponent }
}

// A pending mutating change the UI must confirm (accept / decline / modify).
struct MacActionPlan {
    enum Kind { case move, trash, mkdir, quitApp }
    let kind: Kind
    var moves: [(from: String, to: String)] = []
    var trashPaths: [String] = []
    var mkdirPath: String = ""
    var appName: String = ""
    let confirmText: String
    var count: Int {
        switch kind {
        case .move: return moves.count
        case .trash: return trashPaths.count
        case .mkdir, .quitApp: return 1
        }
    }
}

struct MacToolResult {
    var summary: String
    var files: [MacFileItem] = []
    var plan: MacActionPlan? = nil
}

enum MacToolError: Error, LocalizedError {
    case cancelled
    case message(String)
    var errorDescription: String? {
        switch self {
        case .cancelled: return "Cancelled"
        case .message(let m): return m
        }
    }
}

enum MacToolbox {
    static let fm = FileManager.default
    static var home: URL { fm.homeDirectoryForCurrentUser }

    static func expand(_ p: String) -> URL {
        URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
    }
    static func fmtBytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
    private static func checkCancel() throws { if Task.isCancelled { throw MacToolError.cancelled } }

    // Category buckets for tidy operations.
    private static let buckets: [(String, Set<String>)] = [
        ("Images",   ["jpg","jpeg","png","gif","heic","webp","tiff","bmp","svg"]),
        ("Documents",["pdf","doc","docx","pages","txt","rtf","md","key","ppt","pptx","xls","xlsx","numbers","csv"]),
        ("Archives", ["zip","tar","gz","tgz","rar","7z","dmg","pkg"]),
        ("Audio",    ["mp3","wav","aac","flac","m4a","aiff"]),
        ("Video",    ["mp4","mov","avi","mkv","m4v","webm"]),
        ("Code",     ["swift","c","h","cpp","py","js","ts","json","sh","rb","go","rs","java","html","css"]),
    ]
    private static func bucket(for ext: String) -> String {
        let e = ext.lowercased()
        for (name, set) in buckets where set.contains(e) { return name }
        return "Other"
    }

    // ── Tidy (by type) ──────────────────────────────────────────────────────
    static func tidy(folder: URL, progress: @escaping (String) -> Void) throws -> MacToolResult {
        progress("Scanning \(folder.lastPathComponent)…")
        let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [.skipsHiddenFiles])) ?? []
        var moves: [(from: String, to: String)] = []
        var perBucket: [String: Int] = [:]
        for url in items {
            try checkCancel()
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { continue }
            let b = bucket(for: url.pathExtension)
            moves.append((from: url.path, to: folder.appendingPathComponent(b).appendingPathComponent(url.lastPathComponent).path))
            perBucket[b, default: 0] += 1
        }
        if moves.isEmpty { return MacToolResult(summary: "\(folder.lastPathComponent) is already tidy.") }
        let breakdown = perBucket.sorted { $0.value > $1.value }.map { "\($0.value) → \($0.key)" }.joined(separator: ", ")
        return MacToolResult(summary: "Ready to tidy \(folder.lastPathComponent): \(breakdown).",
                             plan: MacActionPlan(kind: .move, moves: moves,
                                 confirmText: "Move \(moves.count) files in \(folder.lastPathComponent) into type folders (\(breakdown))."))
    }

    // ── Organize by modified date ──────────────────────────────────────────────
    static func organizeByDate(folder: URL, progress: @escaping (String) -> Void) throws -> MacToolResult {
        progress("Reading \(folder.lastPathComponent)…")
        let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                                                 options: [.skipsHiddenFiles])) ?? []
        let cal = Calendar.current
        var moves: [(from: String, to: String)] = []
        for url in items {
            try checkCancel()
            let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            if vals?.isDirectory == true { continue }
            let date = vals?.contentModificationDate ?? Date(timeIntervalSince1970: 0)
            let c = cal.dateComponents([.year, .month], from: date)
            let sub = String(format: "%04d/%02d", c.year ?? 0, c.month ?? 0)
            moves.append((from: url.path, to: folder.appendingPathComponent(sub).appendingPathComponent(url.lastPathComponent).path))
        }
        if moves.isEmpty { return MacToolResult(summary: "Nothing to organize in \(folder.lastPathComponent).") }
        return MacToolResult(summary: "Ready to file \(moves.count) items by date.",
                             plan: MacActionPlan(kind: .move, moves: moves,
                                 confirmText: "Move \(moves.count) files in \(folder.lastPathComponent) into Year/Month folders."))
    }

    // ── Find files by name ─────────────────────────────────────────────────────
    static func find(query: String, roots: [URL], limit: Int = 300,
                     progress: @escaping (String) -> Void) throws -> MacToolResult {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw MacToolError.message("Tell me what to search for.") }
        var hits: [MacFileItem] = []
        var scanned = 0
        for root in roots {
            try checkCancel()
            progress("Searching \(root.lastPathComponent)…")
            let en = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                                   options: [.skipsHiddenFiles], errorHandler: { _, _ in true })
            while let u = en?.nextObject() as? URL {
                try checkCancel()
                scanned += 1
                if scanned % 2000 == 0 { progress("Searched \(scanned) items, \(hits.count) matches…") }
                if u.lastPathComponent.localizedCaseInsensitiveContains(q) {
                    let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                    hits.append(MacFileItem(path: u.path, detail: v?.isDirectory == true ? "folder" : fmtBytes(Int64(v?.fileSize ?? 0))))
                    if hits.count >= limit { break }
                }
            }
            if hits.count >= limit { break }
        }
        let cap = hits.count >= limit ? " (first \(limit))" : ""
        return MacToolResult(summary: "Found \(hits.count) item(s) matching “\(q)”\(cap).", files: hits)
    }

    // ── Largest files ──────────────────────────────────────────────────────────
    static func largest(root: URL, top: Int = 25, progress: @escaping (String) -> Void) throws -> MacToolResult {
        progress("Measuring files under \(root.lastPathComponent)…")
        var all: [(String, Int64)] = []
        var scanned = 0
        let en = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                               options: [.skipsHiddenFiles], errorHandler: { _, _ in true })
        while let u = en?.nextObject() as? URL {
            try checkCancel()
            scanned += 1
            if scanned % 3000 == 0 { progress("Scanned \(scanned) files…") }
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if v?.isDirectory == true { continue }
            if let s = v?.fileSize { all.append((u.path, Int64(s))) }
        }
        let topN = all.sorted { $0.1 > $1.1 }.prefix(top)
        let files = topN.map { MacFileItem(path: $0.0, detail: fmtBytes($0.1)) }
        let total = topN.reduce(Int64(0)) { $0 + $1.1 }
        return MacToolResult(summary: "Top \(files.count) files under \(root.lastPathComponent) total \(fmtBytes(total)).", files: Array(files))
    }

    // ── Largest files across the whole Mac ──────────────────────────────────────
    static func largestEverywhere(top: Int = 30, progress: @escaping (String) -> Void) throws -> MacToolResult {
        let roots = [home,
                     URL(fileURLWithPath: "/Applications"),
                     URL(fileURLWithPath: "/Users/Shared")]
        var all: [(String, Int64)] = []
        var scanned = 0
        for root in roots {
            try checkCancel()
            progress("Scanning \(root.path)…")
            let en = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                                   options: [.skipsHiddenFiles], errorHandler: { _, _ in true })
            while let u = en?.nextObject() as? URL {
                try checkCancel()
                scanned += 1
                if scanned % 4000 == 0 { progress("Scanned \(scanned) files…") }
                let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                if v?.isDirectory == true { continue }
                if let s = v?.fileSize, s > 1_000_000 { all.append((u.path, Int64(s))) }
            }
        }
        let topN = all.sorted { $0.1 > $1.1 }.prefix(top)
        let files = topN.map { MacFileItem(path: $0.0, detail: fmtBytes($0.1)) }
        let total = topN.reduce(Int64(0)) { $0 + $1.1 }
        return MacToolResult(summary: "Biggest \(files.count) files on this Mac total \(fmtBytes(total)).", files: Array(files))
    }

    // ── Folder size breakdown ───────────────────────────────────────────────────
    static func folderSizes(root: URL, progress: @escaping (String) -> Void) throws -> MacToolResult {
        let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                    options: [.skipsHiddenFiles])) ?? []
        var sized: [(String, Int64)] = []
        var reused = 0
        for c in children {
            try checkCancel()
            let isDir = (try? c.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                // Reuse the cached size unless this folder's direct contents changed.
                if let cached = MacSizeCache.shared.cached(c) { sized.append((c.path, cached)); reused += 1 }
                else {
                    progress("Sizing \(c.lastPathComponent)…")
                    let s = dirSize(c)
                    MacSizeCache.shared.store(c, size: s)
                    sized.append((c.path, s))
                }
            } else {
                sized.append((c.path, Int64((try? c.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)))
            }
        }
        MacSizeCache.shared.flush()
        let sorted = sized.sorted { $0.1 > $1.1 }
        let files = sorted.map { MacFileItem(path: $0.0, detail: fmtBytes($0.1)) }
        let total = sorted.reduce(Int64(0)) { $0 + $1.1 }
        let note = reused > 0 ? " (\(reused) reused from cache)" : ""
        return MacToolResult(summary: "\(root.lastPathComponent) holds \(fmtBytes(total)) across \(files.count) items\(note).", files: files)
    }

    // Persistent folder-size cache: compute once, reuse until a folder's direct
    // contents change (its modification date moves). Deep-only changes won't
    // invalidate it — good enough for a "where's my space" overview, and fast.
    final class MacSizeCache: @unchecked Sendable {
        static let shared = MacSizeCache()
        private struct Entry: Codable { let size: Int64; let mtime: Date }
        private var map: [String: Entry] = [:]
        private var dirty = false
        private let lock = NSLock()
        private let url: URL

        init() {
            let base = (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true))
                ?? FileManager.default.temporaryDirectory
            url = base.appendingPathComponent("embershard-foldersizes.json")
            if let data = try? Data(contentsOf: url),
               let m = try? JSONDecoder().decode([String: Entry].self, from: data) { map = m }
        }

        private func mtime(_ dir: URL) -> Date {
            (try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        func cached(_ dir: URL) -> Int64? {
            lock.lock(); defer { lock.unlock() }
            guard let e = map[dir.path], e.mtime == mtime(dir) else { return nil }
            return e.size
        }
        func store(_ dir: URL, size: Int64) {
            lock.lock(); map[dir.path] = Entry(size: size, mtime: mtime(dir)); dirty = true; lock.unlock()
        }
        func flush() {
            lock.lock(); defer { lock.unlock() }
            guard dirty, let data = try? JSONEncoder().encode(map) else { return }
            try? data.write(to: url, options: .atomic); dirty = false
        }
    }

    private static func dirSize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        let en = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                               options: [.skipsHiddenFiles], errorHandler: { _, _ in true })
        while let u = en?.nextObject() as? URL {
            if Task.isCancelled { break }
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if v?.isDirectory == true { continue }
            total += Int64(v?.fileSize ?? 0)
        }
        return total
    }

    // ── Recently modified files ─────────────────────────────────────────────────
    static func recent(root: URL, days: Int = 7, top: Int = 60, progress: @escaping (String) -> Void) throws -> MacToolResult {
        progress("Looking for files changed in the last \(days) days…")
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        var hits: [(String, Date)] = []
        let en = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                               options: [.skipsHiddenFiles], errorHandler: { _, _ in true })
        while let u = en?.nextObject() as? URL {
            try checkCancel()
            let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            if v?.isDirectory == true { continue }
            if let d = v?.contentModificationDate, d >= cutoff { hits.append((u.path, d)) }
        }
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        let sorted = hits.sorted { $0.1 > $1.1 }.prefix(top)
        let files = sorted.map { MacFileItem(path: $0.0, detail: df.string(from: $0.1)) }
        return MacToolResult(summary: "\(files.count) file(s) changed under \(root.lastPathComponent) in the last \(days) days.", files: files)
    }

    // ── Heuristic threat scan ────────────────────────────────────────────────
    static func scanThreats(progress: @escaping (String) -> Void) throws -> MacToolResult {
        var flags: [MacFileItem] = []
        for dir in ["Downloads", "Desktop"] {
            try checkCancel()
            progress("Inspecting \(dir)…")
            let base = home.appendingPathComponent(dir)
            for u in (try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [] {
                try checkCancel()
                if u.pathExtension == "app" {
                    if !codesignValid(u.path) { flags.append(MacFileItem(path: u.path, detail: "app fails signature check")) }
                    else if hasQuarantine(u.path) { flags.append(MacFileItem(path: u.path, detail: "downloaded app (quarantined)")) }
                } else if hasQuarantine(u.path) && fm.isExecutableFile(atPath: u.path) {
                    flags.append(MacFileItem(path: u.path, detail: "quarantined executable"))
                }
            }
        }
        let launchDirs = [home.appendingPathComponent("Library/LaunchAgents"),
                          URL(fileURLWithPath: "/Library/LaunchAgents"),
                          URL(fileURLWithPath: "/Library/LaunchDaemons")]
        for d in launchDirs {
            try checkCancel()
            progress("Reviewing \(d.path)…")
            for u in (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [] where u.pathExtension == "plist" {
                flags.append(MacFileItem(path: u.path, detail: "launch item — review what it runs"))
            }
        }
        let summary = flags.isEmpty
            ? "No obvious red flags. (Heuristic scan — not a substitute for antivirus.)"
            : "Flagged \(flags.count) item(s) worth a look. Heuristic only — review before acting."
        return MacToolResult(summary: summary, files: flags)
    }

    private static func hasQuarantine(_ path: String) -> Bool { run("/usr/bin/xattr", ["-p", "com.apple.quarantine", path]).status == 0 }
    private static func codesignValid(_ path: String) -> Bool { run("/usr/bin/codesign", ["--verify", "--deep", "--strict", path]).status == 0 }

    // ── Duplicate files ──────────────────────────────────────────────────────
    static func duplicates(root: URL, maxFileSize: Int64 = 800_000_000, progress: @escaping (String) -> Void) throws -> MacToolResult {
        progress("Indexing \(root.lastPathComponent) by size…")
        var bySize: [Int64: [URL]] = [:]
        let en = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                               options: [.skipsHiddenFiles], errorHandler: { _, _ in true })
        while let u = en?.nextObject() as? URL {
            try checkCancel()
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if v?.isDirectory == true { continue }
            guard let s = v?.fileSize, s > 4096, Int64(s) <= maxFileSize else { continue }
            bySize[Int64(s), default: []].append(u)
        }
        var byHash: [String: [URL]] = [:]
        var hashed = 0
        for (_, group) in bySize where group.count > 1 {
            for u in group {
                try checkCancel()
                hashed += 1
                if hashed % 200 == 0 { progress("Hashed \(hashed) candidates…") }
                if let h = sha256(u) { byHash[h, default: []].append(u) }
            }
        }
        var files: [MacFileItem] = []; var trash: [String] = []; var reclaim: Int64 = 0; var groups = 0
        for (_, dups) in byHash where dups.count > 1 {
            groups += 1
            let sorted = dups.sorted { $0.path < $1.path }
            let size = Int64((try? sorted[0].resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            for (i, u) in sorted.enumerated() {
                let keep = i == 0
                files.append(MacFileItem(path: u.path, detail: keep ? "keep · \(fmtBytes(size))" : "duplicate · \(fmtBytes(size))"))
                if !keep { trash.append(u.path); reclaim += size }
            }
        }
        if trash.isEmpty { return MacToolResult(summary: "No duplicate files under \(root.lastPathComponent).") }
        return MacToolResult(summary: "Found \(groups) duplicate set(s); \(trash.count) extra copies (~\(fmtBytes(reclaim))) can be trashed.",
                             files: files,
                             plan: MacActionPlan(kind: .trash, trashPaths: trash,
                                 confirmText: "Move \(trash.count) duplicate copies to the Trash (~\(fmtBytes(reclaim)) freed). One copy of each is kept."))
    }

    private static func sha256(_ url: URL) -> String? { try? fileSHA256(url) }
    private static func fileSHA256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: { () -> Bool in
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk); return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // ── Clean old Downloads ─────────────────────────────────────────────────────
    static func cleanOldDownloads(days: Int = 30, progress: @escaping (String) -> Void) throws -> MacToolResult {
        let dl = home.appendingPathComponent("Downloads")
        progress("Checking Downloads for items older than \(days) days…")
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let items = (try? fm.contentsOfDirectory(at: dl, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        var old: [MacFileItem] = []; var paths: [String] = []; var reclaim: Int64 = 0
        for u in items {
            try checkCancel()
            let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            if let d = v?.contentModificationDate, d < cutoff {
                let s = Int64(v?.fileSize ?? 0)
                old.append(MacFileItem(path: u.path, detail: fmtBytes(s))); paths.append(u.path); reclaim += s
            }
        }
        if paths.isEmpty { return MacToolResult(summary: "Nothing in Downloads older than \(days) days.") }
        return MacToolResult(summary: "\(paths.count) item(s) in Downloads are older than \(days) days (~\(fmtBytes(reclaim))).",
                             files: old,
                             plan: MacActionPlan(kind: .trash, trashPaths: paths,
                                 confirmText: "Move \(paths.count) old Downloads to the Trash (~\(fmtBytes(reclaim)) freed)."))
    }

    // ── Move / rename a single item ──────────────────────────────────────────────
    static func moveItem(source: String, destination: String) throws -> MacToolResult {
        let src = expand(source)
        guard fm.fileExists(atPath: src.path) else { throw MacToolError.message("Couldn't find \(src.path).") }
        var dst = expand(destination)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: dst.path, isDirectory: &isDir), isDir.boolValue {
            dst = dst.appendingPathComponent(src.lastPathComponent)   // into the folder
        }
        let plan = MacActionPlan(kind: .move, moves: [(from: src.path, to: dst.path)],
                                 confirmText: "Move “\(src.lastPathComponent)” → \(dst.path)")
        return MacToolResult(summary: "Ready to move “\(src.lastPathComponent)”.", plan: plan)
    }

    // ── Create a folder ──────────────────────────────────────────────────────────
    static func createFolder(path: String) throws -> MacToolResult {
        let url = expand(path)
        if fm.fileExists(atPath: url.path) { throw MacToolError.message("\(url.path) already exists.") }
        return MacToolResult(summary: "Ready to create \(url.path).",
                             plan: MacActionPlan(kind: .mkdir, mkdirPath: url.path,
                                 confirmText: "Create folder \(url.path)"))
    }

    // ── Quit an app ────────────────────────────────────────────────────────────
    @MainActor
    static func quitApp(name: String) throws -> MacToolResult {
        let q = name.trimmingCharacters(in: .whitespaces).lowercased()
        let match = NSWorkspace.shared.runningApplications.first {
            ($0.localizedName ?? "").lowercased().contains(q) && $0.activationPolicy == .regular
        }
        guard let app = match, let appName = app.localizedName else {
            throw MacToolError.message("No running app named “\(name)”.")
        }
        return MacToolResult(summary: "Ready to quit \(appName).",
                             plan: MacActionPlan(kind: .quitApp, appName: appName,
                                 confirmText: "Quit \(appName)? Unsaved work could be lost."))
    }

    // ── Applying confirmed plans ─────────────────────────────────────────────
    static func applyMoves(_ moves: [(from: String, to: String)], progress: @escaping (String) -> Void) -> Int {
        var done = 0
        for (i, m) in moves.enumerated() {
            let dst = URL(fileURLWithPath: m.to)
            try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dst.path) { continue }
            do { try fm.moveItem(atPath: m.from, toPath: m.to); done += 1 } catch {}
            if i % 20 == 0 { progress("Moved \(done)/\(moves.count)…") }
        }
        progress("Moved \(done) item(s).")
        return done
    }

    static func trash(_ paths: [String], progress: @escaping (String) -> Void) -> Int {
        var done = 0
        for (i, p) in paths.enumerated() {
            do { try fm.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: nil); done += 1 } catch {}
            if i % 20 == 0 { progress("Trashed \(done)/\(paths.count)…") }
        }
        progress("Moved \(done) item(s) to the Trash.")
        return done
    }

    static func mkdir(_ path: String) -> Bool {
        (try? fm.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true)) != nil
    }

    @MainActor
    static func quitRunning(named appName: String) -> Bool {
        let app = NSWorkspace.shared.runningApplications.first { ($0.localizedName ?? "") == appName }
        return app?.terminate() ?? false
    }

    // ── Heaviest running apps ──────────────────────────────────────────────────
    static func heaviestApps(top: Int = 12, progress: @escaping (String) -> Void) throws -> MacToolResult {
        progress("Sampling running processes…")
        let out = run("/bin/ps", ["-A", "-o", "rss=,pcpu=,comm="]).stdout
        struct P { var rss: Int64; var cpu: Double }
        var agg: [String: P] = [:]
        for line in out.split(separator: "\n") {
            let parts = line.split(maxSplits: 2, whereSeparator: { $0 == " " }).filter { !$0.isEmpty }
            guard parts.count >= 3 else { continue }
            let rss = Int64(parts[0]) ?? 0, cpu = Double(parts[1]) ?? 0
            let comm = String(parts[2])
            var name = (comm as NSString).lastPathComponent
            if let r = comm.range(of: ".app/") {
                name = ((String(comm[..<r.lowerBound]) + ".app") as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            }
            var p = agg[name] ?? P(rss: 0, cpu: 0); p.rss += rss * 1024; p.cpu += cpu; agg[name] = p
        }
        let topMem = agg.sorted { $0.value.rss > $1.value.rss }.prefix(top)
        let files = topMem.map { MacFileItem(path: $0.key, detail: "\(fmtBytes($0.value.rss)) RAM · \(String(format: "%.1f", $0.value.cpu))% CPU") }
        let lines = files.map { "• \($0.path) — \($0.detail)" }.joined(separator: "\n")
        return MacToolResult(summary: "Top \(files.count) apps by memory:\n\(lines)")
    }

    // ── Process helper / Finder ─────────────────────────────────────────────────
    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) -> (status: Int32, stdout: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
