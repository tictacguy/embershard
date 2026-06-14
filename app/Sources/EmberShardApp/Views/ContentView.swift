import SwiftUI

struct ContentView: View {
    @EnvironmentObject var chatStore:  ChatStore
    @EnvironmentObject var modelStore: LocalModelStore
    @EnvironmentObject var appState:   AppState

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SidebarView()
        } detail: {
            if let chatId = appState.selectedChatId,
               chatStore.chat(id: chatId) != nil {
                ChatView(chatId: chatId)
            } else {
                WelcomeView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 560)
        .onChange(of: appState.newChatRequested) { _, requested in
            if requested { createNewChat(); appState.newChatRequested = false }
        }
    }

    private func createNewChat() {
        let chat = Chat(modelPath: modelStore.activeModelPath,
                        projectId: appState.selectedProjectId)
        chatStore.addChat(chat)
        appState.selectedChatId = chat.id
    }
}

// MARK: - WelcomeView

private struct WelcomeView: View {
    @EnvironmentObject var modelStore: LocalModelStore
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "flame")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.secondary)

            Text("Embershard")
                .font(.largeTitle.weight(.light))
                .foregroundStyle(.primary)

            if modelStore.activeModelPath.isEmpty {
                VStack(spacing: 8) {
                    Text("No model selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Open Settings → Models to download or add a model.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text(URL(fileURLWithPath: modelStore.activeModelPath).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
            }

            Button("New Chat") { appState.requestNewChat() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(modelStore.activeModelPath.isEmpty)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
