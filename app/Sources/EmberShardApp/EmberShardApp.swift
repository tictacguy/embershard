import SwiftUI

@main
struct EmberShardApp: App {
    @StateObject private var chatStore   = ChatStore.shared
    @StateObject private var modelStore  = LocalModelStore.shared
    @StateObject private var appState    = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(chatStore)
                .environmentObject(modelStore)
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") { appState.requestNewChat() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(modelStore)
                .environmentObject(appState)
        }
    }
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var selectedChatId: UUID?
    @Published var selectedProjectId: UUID?
    @Published var isGenerating = false
    @Published var loadProgress: Double = 0
    @Published var engineLoaded = false
    @Published var newChatRequested = false

    private init() {}

    func requestNewChat() {
        newChatRequested = true
    }
}
