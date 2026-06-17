import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var chatStore:  ChatStore
    @EnvironmentObject var appState:   AppState
    @EnvironmentObject var modelStore: LocalModelStore

    @State private var searchText = ""
    @State private var showNewProject = false
    @State private var showSettings = false
    @State private var renamingProject: Project? = nil
    @State private var renameText = ""
    @State private var editSystemPrompt = ""
    @State private var editIcon = "folder"
    @State private var selectMode = false
    @State private var picked: Set<UUID> = []
    @State private var confirmDelete = false

    private var noModel: Bool { modelStore.models.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // Search field (a plain field — `.searchable(.sidebar)` renders too
            // narrow on macOS before 26).
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
                TextField("Search", text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 4)

            // Chat list
            List(selection: Binding(
                get: { selectMode ? nil : appState.selectedChatId },
                set: { id in
                    // Ignore nil (project / empty-row taps) so the current tab stays put.
                    guard !selectMode, let id, let chat = chatStore.chat(id: id) else { return }
                    appState.selectedChatId = id
                    appState.selectedProjectId = chat.projectId
                }
            )) {
                let projects = chatStore.projects.sorted { $0.createdAt > $1.createdAt }
                if !projects.isEmpty {
                    Section("Projects") {
                        ForEach(projects) { project in
                            ProjectRow(project: project,
                                       selectMode: selectMode,
                                       picked: picked,
                                       onTogglePick: { togglePick($0) },
                                       onEnterSelect: { enterSelect($0) },
                                       onRequestDelete: { requestDelete($0) },
                                       onNewChat: { newChat(in: project) }) {
                                renameText = project.name
                                editSystemPrompt = project.systemPrompt
                                editIcon = project.icon
                                renamingProject = project
                            }
                        }
                    }
                }

                Section("Chats") {
                    ForEach(filteredChats) { chat in
                        ChatRow(chat: chat, projects: chatStore.projects,
                                selectMode: selectMode,
                                isPicked: picked.contains(chat.id),
                                onPick: { togglePick(chat.id) },
                                onEnterSelect: { enterSelect(chat.id) },
                                onOpen: {
                                    appState.selectedChatId = chat.id
                                    appState.selectedProjectId = chat.projectId
                                },
                                onMoveToProject: { projectId in
                            chatStore.moveChat(id: chat.id, toProject: projectId)
                        }, onRequestDelete: { requestDelete(chat.id) })
                        .tag(chat.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if chatStore.chats.isEmpty && chatStore.projects.isEmpty {
                    if noModel {
                        ContentUnavailableView {
                            Label("No model yet", systemImage: "arrow.down.circle")
                        } description: {
                            Text("Download a model to start chatting.")
                        } actions: {
                            Button("Open Settings") { showSettings = true }
                                .buttonStyle(.borderedProminent)
                        }
                    } else {
                        ContentUnavailableView {
                            Label("No chats yet", systemImage: "bubble.left.and.bubble.right")
                        } description: {
                            Text("Create a new chat to get started.")
                        } actions: {
                            Button("New Chat") { appState.selectedProjectId = nil; appState.requestNewChat() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }

            Divider()

            // Active download indicator
            ActiveDownloadView()
                .environmentObject(ModelDownloader.shared)

            // Bottom bar
            if selectMode {
                HStack(spacing: 8) {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete \(picked.count)", systemImage: "trash")
                    }
                    .disabled(picked.isEmpty)
                    Spacer()
                    Button("Done") { selectMode = false; picked = [] }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            } else {
                VStack(spacing: 2) {
                    SidebarButton(title: "New Chat", icon: "square.and.pencil") {
                        appState.selectedProjectId = nil
                        appState.requestNewChat()
                    }
                    .disabled(modelStore.activeModelPath.isEmpty)

                    SidebarButton(title: "New Project", icon: "folder.badge.plus") {
                        showNewProject = true
                    }

                    SidebarButton(title: "Settings", icon: "gearshape") {
                        showSettings = true
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .confirmationDialog("Delete \(picked.count) item(s)?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deletePicked() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the selected chats and projects. This can't be undone.")
        }
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet(isPresented: $showNewProject) { name, prompt, icon in
                let p = Project(name: name, systemPrompt: prompt, icon: icon)
                chatStore.addProject(p)
                appState.selectedProjectId = p.id
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(isPresented: $showSettings)
                .environmentObject(modelStore)
                .environmentObject(appState)
        }
        .sheet(item: $renamingProject) { project in
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit Project").font(.headline)
                HStack(spacing: 10) {
                    Image(systemName: editIcon).font(.title3).frame(width: 26)
                    TextField("Project name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                }
                ProjectIconPicker(selected: $editIcon)
                VStack(alignment: .leading, spacing: 4) {
                    Text("System prompt (applied to all chats in this project)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $editSystemPrompt)
                        .font(.body)
                        .frame(height: 100)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                }
                HStack {
                    Spacer()
                    Button("Cancel") { renamingProject = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        if !renameText.isEmpty {
                            chatStore.renameProject(id: project.id, name: renameText)
                            chatStore.updateProjectPrompt(id: project.id, prompt: editSystemPrompt)
                            chatStore.updateProjectIcon(id: project.id, icon: editIcon)
                        }
                        renamingProject = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameText.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 420)
        }
        .navigationTitle("Embershard")
    }

    private var filteredChats: [Chat] {
        let base = chatStore.standaloneChats
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private func togglePick(_ id: UUID) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    private func enterSelect(_ id: UUID) {
        selectMode = true
        picked = [id]
    }

    // Single-item delete (context menu) routes through the same confirmation.
    private func requestDelete(_ id: UUID) {
        picked = [id]
        confirmDelete = true
    }

    private func newChat(in project: Project) {
        appState.selectedProjectId = project.id
        appState.requestNewChat()
    }

    private func deletePicked() {
        for id in picked {
            if chatStore.projects.contains(where: { $0.id == id }) {
                if let p = chatStore.projects.first(where: { $0.id == id }) {
                    // Close tabs for that project's chats, then remove the project.
                    for c in chatStore.chats(for: p) { appState.closeTab(chatId: c.id) }
                    chatStore.removeProject(p)
                    if appState.selectedProjectId == id { appState.selectedProjectId = nil }
                }
            } else {
                appState.closeTab(chatId: id)
                chatStore.removeChat(id: id)
            }
        }
        picked = []
        selectMode = false
    }
}

// MARK: - SidebarButton

private struct SidebarButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                    .frame(width: 20)
                Text(title)
                    .font(.body)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                isHovered && isEnabled ? Color.primary.opacity(0.06) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? .primary : .tertiary)
        .onHover { isHovered = $0 }
    }
}

// MARK: - ChatRow

private struct ChatRow: View {
    let chat: Chat
    let projects: [Project]
    var selectMode: Bool = false
    var isPicked: Bool = false
    var onPick: () -> Void = {}
    var onEnterSelect: () -> Void = {}
    var onOpen: () -> Void = {}
    let onMoveToProject: (UUID) -> Void
    let onRequestDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if selectMode {
                Button(action: onPick) {
                    Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isPicked ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            Image(systemName: chat.icon).frame(width: 18)
            Text(chat.title).font(.body).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if selectMode { onPick() } else { onOpen() } }
        .contextMenu {
            Button("Select") { onEnterSelect() }
            if !projects.isEmpty {
                Menu("Move to project") {
                    ForEach(projects) { project in
                        Button(project.name) { onMoveToProject(project.id) }
                    }
                }
            }
            Divider()
            Button(role: .destructive) { onRequestDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - ProjectRow

private struct ProjectRow: View {
    let project: Project
    var selectMode: Bool = false
    var picked: Set<UUID> = []
    var onTogglePick: (UUID) -> Void = { _ in }
    var onEnterSelect: (UUID) -> Void = { _ in }
    var onRequestDelete: (UUID) -> Void = { _ in }
    var onNewChat: () -> Void = {}
    let onRename: () -> Void
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var appState:  AppState

    @State private var isExpanded = true
    @State private var hovering = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(chatStore.chats(for: project)) { chat in
                HStack(spacing: 6) {
                    if selectMode {
                        Button { onTogglePick(chat.id) } label: {
                            Image(systemName: picked.contains(chat.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(picked.contains(chat.id) ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Image(systemName: chat.icon).frame(width: 18)
                    Text(chat.title).font(.body).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .tag(chat.id)
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Select") { onEnterSelect(chat.id) }
                    Button("Remove from project") {
                        chatStore.moveChat(id: chat.id, toProject: nil)
                    }
                    Divider()
                    Button(role: .destructive) { onRequestDelete(chat.id) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .onTapGesture {
                    if selectMode { onTogglePick(chat.id) }
                    else {
                        appState.selectedChatId    = chat.id
                        appState.selectedProjectId = project.id
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if selectMode {
                    Button { onTogglePick(project.id) } label: {
                        Image(systemName: picked.contains(project.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(picked.contains(project.id) ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Image(systemName: project.icon).frame(width: 18)
                Text(project.name).font(.body.weight(.medium)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if !selectMode && hovering {
                    Button { onNewChat() } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("New chat in this project")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { if selectMode { onTogglePick(project.id) } }
            .contextMenu {
                Button("Select") { onEnterSelect(project.id) }
                Button("New chat here") { onNewChat() }
                Button("Edit") { onRename() }
                Divider()
                Button(role: .destructive) { onRequestDelete(project.id) } label: {
                    Label("Delete project", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - NewProjectSheet

private struct NewProjectSheet: View {
    @Binding var isPresented: Bool
    let onCreate: (String, String, String) -> Void

    @State private var name = ""
    @State private var systemPrompt = ""
    @State private var icon = "folder"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Project")
                .font(.title3.weight(.semibold))

            HStack(spacing: 10) {
                Image(systemName: icon).font(.title3).frame(width: 26)
                TextField("Project name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            ProjectIconPicker(selected: $icon)

            VStack(alignment: .leading, spacing: 4) {
                Text("System prompt (optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: $systemPrompt)
                    .font(.body)
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    guard !name.isEmpty else { return }
                    onCreate(name, systemPrompt, icon)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

// A compact grid of folder-ish SF Symbols to brand a project.
struct ProjectIconPicker: View {
    @Binding var selected: String
    private let icons = [
        "folder", "folder.fill", "tray.full", "doc.on.doc", "book", "graduationcap",
        "briefcase", "hammer", "paintbrush", "chart.bar", "lightbulb", "flask",
        "cart", "house", "gamecontroller", "music.note", "camera", "globe",
        "heart", "star", "flag", "bolt", "leaf", "terminal",
    ]
    private let cols = [GridItem(.adaptive(minimum: 40), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(icons, id: \.self) { name in
                Image(systemName: name)
                    .font(.system(size: 17))
                    .frame(width: 38, height: 38)
                    .background(selected == name ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(selected == name ? Color.accentColor : Color.clear, lineWidth: 1.5))
                    .foregroundStyle(selected == name ? Color.accentColor : .primary)
                    .contentShape(Rectangle())
                    .onTapGesture { selected = name }
            }
        }
        .padding(2)
    }
}

// MARK: - SettingsSheet

struct SettingsSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var modelStore: LocalModelStore
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            SettingsView()
                .environmentObject(modelStore)
                .environmentObject(appState)
        }
        .frame(width: 640, height: 520)
    }
}

// MARK: - Active Download Indicator

private struct ActiveDownloadView: View {
    @EnvironmentObject var downloader: ModelDownloader

    private var activeDownload: (name: String, progress: Double)? {
        for (id, state) in downloader.states {
            if case .downloading(let p) = state {
                let name = id.components(separatedBy: "/").last ?? id
                return (name, p)
            }
        }
        return nil
    }

    var body: some View {
        if let dl = activeDownload {
            HStack(spacing: 8) {
                ProviderIconView(modelName: dl.name, size: 14)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(dl.name)
                        .font(.caption)
                        .lineLimit(1)
                    ProgressView(value: dl.progress)
                        .progressViewStyle(.linear)
                }
                Text("\(Int(dl.progress * 100))%")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}
