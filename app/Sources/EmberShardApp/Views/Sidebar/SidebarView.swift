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

    var body: some View {
        VStack(spacing: 0) {
            // Chat list
            List(selection: Binding(
                get: { appState.selectedChatId },
                set: { id in
                    appState.selectedChatId = id
                    if let id, let chat = chatStore.chat(id: id) {
                        appState.selectedProjectId = chat.projectId
                    }
                }
            )) {
                let projects = chatStore.projects.sorted { $0.createdAt > $1.createdAt }
                if !projects.isEmpty {
                    Section("Projects") {
                        ForEach(projects) { project in
                            ProjectRow(project: project) {
                                renameText = project.name
                                editSystemPrompt = project.systemPrompt
                                renamingProject = project
                            }
                        }
                    }
                }

                Section("Chats") {
                    ForEach(filteredChats) { chat in
                        ChatRow(chat: chat, projects: chatStore.projects) { projectId in
                            chatStore.moveChat(id: chat.id, toProject: projectId)
                        } onDelete: {
                            appState.closeTab(chatId: chat.id)
                            chatStore.removeChat(id: chat.id)
                        }
                        .tag(chat.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search")

            Divider()

            // Active download indicator
            ActiveDownloadView()
                .environmentObject(ModelDownloader.shared)

            // Bottom bar: uniform buttons
            VStack(spacing: 2) {
                SidebarButton(title: "New Chat", icon: "square.and.pencil") {
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
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet(isPresented: $showNewProject) { name, prompt in
                let p = Project(name: name, systemPrompt: prompt)
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
                TextField("Project name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
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
                        }
                        renamingProject = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameText.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 400)
        }
        .navigationTitle("Embershard")
    }

    private var filteredChats: [Chat] {
        let base = chatStore.standaloneChats
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
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
    let onMoveToProject: (UUID) -> Void
    let onDelete: () -> Void

    var body: some View {
        Label(chat.title, systemImage: chat.icon)
            .font(.body)
            .lineLimit(1)
            .contextMenu {
                if !projects.isEmpty {
                    Menu("Move to project") {
                        ForEach(projects) { project in
                            Button(project.name) { onMoveToProject(project.id) }
                        }
                    }
                }
                Divider()
                Button(role: .destructive) { onDelete() } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}

// MARK: - ProjectRow

private struct ProjectRow: View {
    let project: Project
    let onRename: () -> Void
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var appState:  AppState

    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(chatStore.chats(for: project)) { chat in
                Label(chat.title, systemImage: chat.icon)
                    .font(.body)
                    .lineLimit(1)
                    .tag(chat.id)
                    .contextMenu {
                        Button("Remove from project") {
                            chatStore.moveChat(id: chat.id, toProject: nil)
                        }
                        Divider()
                        Button(role: .destructive) {
                            appState.closeTab(chatId: chat.id)
                            chatStore.removeChat(id: chat.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .onTapGesture {
                        appState.selectedChatId    = chat.id
                        appState.selectedProjectId = project.id
                    }
            }
        } label: {
            Label(project.name, systemImage: chatStore.chats(for: project).isEmpty ? "folder" : "folder.fill")
                .font(.body.weight(.medium))
                .contextMenu {
                    Button("Edit") { onRename() }
                    Divider()
                    Button(role: .destructive) {
                        chatStore.removeProject(project)
                        if appState.selectedProjectId == project.id {
                            appState.selectedProjectId = nil
                        }
                    } label: {
                        Label("Delete project", systemImage: "trash")
                    }
                }
        }
    }
}

// MARK: - NewProjectSheet

private struct NewProjectSheet: View {
    @Binding var isPresented: Bool
    let onCreate: (String, String) -> Void

    @State private var name = ""
    @State private var systemPrompt = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Project")
                .font(.title3.weight(.semibold))

            TextField("Project name", text: $name)
                .textFieldStyle(.roundedBorder)

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
                    onCreate(name, systemPrompt)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
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
