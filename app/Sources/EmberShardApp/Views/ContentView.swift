import SwiftUI

struct ContentView: View {
    @EnvironmentObject var chatStore:  ChatStore
    @EnvironmentObject var modelStore: LocalModelStore
    @EnvironmentObject var appState:   AppState

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if !appState.openTabs.isEmpty {
                    ChromeTabBar()
                }

                if let chatId = appState.selectedChatId,
                   chatStore.chat(id: chatId) != nil {
                    ChatView(chatId: chatId)
                        .id(chatId)
                } else {
                    WelcomeView()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 560)
        .onChange(of: appState.newChatRequested) { _, requested in
            if requested { createNewChat(); appState.newChatRequested = false }
        }
        .onChange(of: appState.selectedChatId) { _, newId in
            if let id = newId, !appState.openTabs.contains(id) {
                appState.openTabs.append(id)
            }
        }
    }

    private func createNewChat() {
        let chat = Chat(modelPath: modelStore.activeModelPath,
                        projectId: appState.selectedProjectId)
        chatStore.addChat(chat)
        appState.openTab(chatId: chat.id)
    }
}

// MARK: - Chrome Tab Bar

private struct ChromeTabBar: View {
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: -1) {
                ForEach(appState.openTabs, id: \.self) { tabId in
                    ChromeTab(
                        title: chatStore.chat(id: tabId)?.title ?? "New chat",
                        icon: chatStore.chat(id: tabId)?.icon ?? "bubble.left",
                        isSelected: appState.selectedChatId == tabId,
                        onSelect: { appState.selectedChatId = tabId },
                        onClose: { appState.closeTab(chatId: tabId) },
                        onCloseOthers: {
                            let others = appState.openTabs.filter { $0 != tabId }
                            for id in others { appState.closeTab(chatId: id) }
                        }
                    )
                }
                Spacer()
            }
            .padding(.leading, 8)
            .padding(.top, 4)
        }
        .frame(height: 36)
        .background(Color.primary.opacity(0.04))
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - Chrome Tab (linguetta)

private struct ChromeTab: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onCloseOthers: () -> Void

    @State private var isHovered = false
    @State private var closeHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: 130, alignment: .leading)
                .foregroundStyle(isSelected ? .primary : .secondary)

            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 14, height: 14)
                    .foregroundStyle(closeHovered ? .primary : .tertiary)
                    .background(closeHovered ? Color.primary.opacity(0.1) : Color.clear, in: Circle())
            }
            .buttonStyle(.plain)
            .onHover { closeHovered = $0 }
            .opacity(isHovered || isSelected ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            isSelected
                ? Color(NSColor.windowBackgroundColor)
                : (isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color.clear),
            in: UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 0,
                                        bottomTrailingRadius: 0, topTrailingRadius: 8)
        )
        .shadow(color: isSelected ? .black.opacity(0.05) : .clear, radius: 1, y: -1)
        .zIndex(isSelected ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Close tab") { onClose() }
            Button("Close other tabs") { onCloseOthers() }
        }
    }
}

// MARK: - WelcomeView (VSCode-style)

private struct WelcomeView: View {
    @EnvironmentObject var modelStore: LocalModelStore
    @EnvironmentObject var appState: AppState

    private var logoImage: NSImage? {
        guard let url = Bundle.module.url(forResource: "logo", withExtension: "svg"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        return img
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                if let img = logoImage {
                    Image(nsImage: img)
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                        .foregroundStyle(.quaternary)
                } else {
                    Image(systemName: "flame")
                        .font(.system(size: 56, weight: .ultraLight))
                        .foregroundStyle(.quaternary)
                }
                Text("Embershard")
                    .font(.title.weight(.light))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                WelcomeAction(icon: "square.and.pencil", title: "New Chat", shortcut: "Cmd+N") {
                    appState.requestNewChat()
                }
                .disabled(modelStore.activeModelPath.isEmpty)

                WelcomeAction(icon: "folder.badge.plus", title: "New Project", shortcut: "Cmd+Shift+N") {
                    // Triggered from sidebar
                }

                WelcomeAction(icon: "gearshape", title: "Open Settings", shortcut: "Cmd+,") {
                    // Triggered from sidebar
                }
            }
            .frame(maxWidth: 280)

            if modelStore.activeModelPath.isEmpty {
                Text("No model loaded. Open Settings to download one.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct WelcomeAction: View {
    let icon: String
    let title: String
    let shortcut: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.body)
                Spacer()
                Text(shortcut)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isHovered ? Color.primary.opacity(0.04) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
