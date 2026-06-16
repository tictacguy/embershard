import SwiftUI
import EmberShardBridge

@main
struct EmberShardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var chatStore   = ChatStore.shared
    @StateObject private var modelStore  = LocalModelStore.shared
    @StateObject private var appState    = AppState.shared
    @StateObject private var skillsStore = SkillsStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(chatStore)
                .environmentObject(modelStore)
                .environmentObject(appState)
                .environmentObject(skillsStore)
                .tint(appState.accentColor)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") { appState.requestNewChat() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

// MARK: - AppDelegate (fixes Metal cleanup crash on quit)

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // Free ALL Metal resources before the ggml-metal static destructor runs at
        // process exit — otherwise its residency-set teardown asserts (SIGABRT).
        // The native engine (es_gx) is the active one and holds the model + KV
        // buffers, so it must be freed too. Cancel first so any in-flight decode
        // returns immediately, then wait (briefly) for each unload to complete.
        NativeEngine.shared.requestCancel()

        let g1 = DispatchSemaphore(value: 0)
        Task { @NativeEngineActor in NativeEngine.shared.unload(); g1.signal() }
        _ = g1.wait(timeout: .now() + 3)

        let g2 = DispatchSemaphore(value: 0)
        Task { @EngineActor in EngineService.shared.unload(); g2.signal() }
        _ = g2.wait(timeout: .now() + 3)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply saved appearance immediately on launch
        let mode = UserDefaults.standard.string(forKey: "es_appearance") ?? "system"
        switch mode {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil
        }
    }
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var selectedChatId: UUID?
    @Published var selectedProjectId: UUID?
    @Published var openTabs: [UUID] = []  // ordered list of open chat tabs
    @Published var isGenerating = false
    @Published var loadProgress: Double = 0
    @Published var engineLoaded = false
    @Published var newChatRequested = false
    @Published var accentColor: Color = .blue {
        didSet { saveAccentColor() }
    }

    private init() { loadAccentColor() }

    func requestNewChat() {
        newChatRequested = true
    }

    func openTab(chatId: UUID) {
        if !openTabs.contains(chatId) {
            openTabs.append(chatId)
        }
        selectedChatId = chatId
    }

    func closeTab(chatId: UUID) {
        openTabs.removeAll { $0 == chatId }
        if selectedChatId == chatId {
            selectedChatId = openTabs.last
        }
    }

    private func saveAccentColor() {
        let c = NSColor(accentColor)
        let r = c.redComponent
        let g = c.greenComponent
        let b = c.blueComponent
        UserDefaults.standard.set("\(r),\(g),\(b)", forKey: "es_accent_rgb")
    }

    private func loadAccentColor() {
        guard let str = UserDefaults.standard.string(forKey: "es_accent_rgb") else { return }
        let parts = str.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 3 else { return }
        accentColor = Color(red: parts[0], green: parts[1], blue: parts[2])
    }
}
