import SwiftUI

struct ContentView: View {
    @EnvironmentObject var chatStore:  ChatStore
    @EnvironmentObject var modelStore: LocalModelStore
    @EnvironmentObject var appState:   AppState

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
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
            if requested { showNewChatPicker = true; appState.newChatRequested = false }
        }
        .onChange(of: appState.selectedChatId) { _, newId in
            if let id = newId, !appState.openTabs.contains(id) {
                appState.openTabs.append(id)
            }
        }
        .sheet(isPresented: $showNewChatPicker) {
            NewChatSheet(models: modelStore.compatibleModels,
                         activeModel: modelStore.activeModelPath) { kind, compareModels in
                createNewChat(kind: kind, compareModels: compareModels)
                showNewChatPicker = false
            } onCancel: { showNewChatPicker = false }
        }
    }

    @State private var showNewChatPicker = false

    private func createNewChat(kind: ChatKind = .standard, compareModels: [String] = []) {
        var chat = Chat(modelPath: modelStore.activeModelPath,
                        projectId: appState.selectedProjectId,
                        kind: kind, compareModels: compareModels)
        // Give helper/arena chats their recognizable icon up front (sidebar + tabs).
        switch kind {
        case .macos:   chat.icon = "apple.logo"; chat.agentMode = true
        case .compare: chat.icon = "rectangle.split.3x1.fill"
        case .standard: break
        }
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

    @EnvironmentObject var appState: AppState
    @State private var isHovered = false
    @State private var closeHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? appState.accentColor : Color.secondary)

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

// MARK: - New Chat type picker

struct NewChatSheet: View {
    let models: [LocalModel]
    let activeModel: String
    let onCreate: (ChatKind, [String]) -> Void
    let onCancel: () -> Void

    @EnvironmentObject var appState: AppState
    @State private var kind: ChatKind = .standard
    @State private var selected: [String] = []

    // Arena fits 2 models on 16 GB; 4 once you have 32 GB+.
    private var maxArena: Int {
        ProcessInfo.processInfo.physicalMemory >= 32 * 1024 * 1024 * 1024 ? 4 : 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New chat").font(.title2.weight(.semibold))

            HStack(spacing: 12) {
                typeCard(.standard, "Standard", "bubble.left.fill",
                         "Chat with one model. Toggle Agent for multi-step tasks.")
                typeCard(.macos, "Pomme", "apple.logo",
                         "A macOS assistant that is hable to handle tasks on your Mac.", beta: true)
                typeCard(.compare, "Arena", "rectangle.split.3x1.fill",
                         "Ask up to 4 models at once.")
            }

            if kind == .compare {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pick up to \(maxArena) models (\(selected.count)/\(maxArena))")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if maxArena < 4 {
                        Label("Your GPU has under 32 GB, so Arena runs 2 models at once here. 32 GB+ unlocks 4.",
                              systemImage: "info.circle")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(models) { m in modelRow(m) }
                        }
                    }
                    .frame(maxHeight: 200)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Create") { onCreate(kind, kind == .compare ? selected : []) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(createDisabled)
            }
        }
        .padding(20)
        .frame(width: 540)
        .onAppear { if selected.isEmpty, !activeModel.isEmpty { selected = [activeModel] } }
    }

    private var createDisabled: Bool {
        if models.isEmpty { return true }
        if kind == .compare { return selected.count < 2 }
        return false
    }

    private func toggleModel(_ m: LocalModel) {
        if selected.contains(m.path) { selected.removeAll { $0 == m.path } }
        else if selected.count < maxArena { selected.append(m.path) }
    }

    private func typeCard(_ k: ChatKind, _ title: String, _ icon: String, _ desc: String,
                          beta: Bool = false) -> some View {
        let on = kind == k
        return Button { kind = k } label: {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 22))
                    .foregroundStyle(on ? appState.accentColor : .secondary)
                HStack(spacing: 5) {
                    Text(title).font(.subheadline.weight(.medium))
                    if beta {
                        Text("BETA").font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                Text(desc).font(.caption2).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(.vertical, 10)
            .background(on ? appState.accentColor.opacity(0.1) : Color.primary.opacity(0.03),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(on ? appState.accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func modelRow(_ m: LocalModel) -> some View {
        let on = selected.contains(m.path)
        return Button { toggleModel(m) } label: {
            HStack(spacing: 8) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? appState.accentColor : Color.secondary)
                Text(m.name).font(.subheadline).lineLimit(1)
                Spacer()
                Text(m.sizeString).font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!on && selected.count >= maxArena)
    }
}
