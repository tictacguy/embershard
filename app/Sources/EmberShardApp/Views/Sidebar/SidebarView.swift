import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var chatStore:  ChatStore
    @EnvironmentObject var appState:   AppState
    @EnvironmentObject var modelStore: LocalModelStore

    @State private var searchText = ""
    @State private var showNewProject = false

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedChatId },
            set: { id in
                appState.selectedChatId = id
                if let id, let chat = chatStore.chat(id: id) {
                    appState.selectedProjectId = chat.projectId
                }
            }
        )) {
            // Projects section
            let projects = chatStore.projects.sorted { $0.createdAt > $1.createdAt }
            if !projects.isEmpty {
                Section {
                    ForEach(projects) { project in
                        ProjectRow(project: project)
                    }
                } header: {
                    Label("Projects", systemImage: "folder")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            // Standalone chats
            Section {
                ForEach(filteredChats) { chat in
                    ChatRow(chat: chat)
                        .tag(chat.id)
                }
                .onDelete(perform: deleteChats)
            } header: {
                Label("Chats", systemImage: "bubble.left.and.bubble.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search chats")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { appState.requestNewChat() } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("New Chat (⌘N)")
                .disabled(modelStore.activeModelPath.isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { showNewProject = true } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("New Project")
            }
        }
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet(isPresented: $showNewProject) { name, prompt in
                let p = Project(name: name, systemPrompt: prompt)
                chatStore.addProject(p)
                appState.selectedProjectId = p.id
            }
        }
        .navigationTitle("Embershard")
    }

    private var filteredChats: [Chat] {
        let base = chatStore.standaloneChats
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private func deleteChats(at offsets: IndexSet) {
        for idx in offsets {
            let chat = filteredChats[idx]
            if appState.selectedChatId == chat.id { appState.selectedChatId = nil }
            chatStore.removeChat(id: chat.id)
        }
    }
}

// MARK: - ChatRow

private struct ChatRow: View {
    let chat: Chat

    var body: some View {
        Label(chat.title, systemImage: "bubble.left")
            .lineLimit(1)
    }
}

// MARK: - ProjectRow

private struct ProjectRow: View {
    let project: Project
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var appState:  AppState

    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(chatStore.chats(for: project)) { chat in
                Label(chat.title, systemImage: "bubble.left")
                    .lineLimit(1)
                    .tag(chat.id)
                    .onTapGesture {
                        appState.selectedChatId    = chat.id
                        appState.selectedProjectId = project.id
                    }
            }
        } label: {
            Label(project.name, systemImage: "folder")
                .fontWeight(.medium)
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
            Text("New Project").font(.headline)

            TextField("Project name", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("System prompt (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $systemPrompt)
                    .font(.body)
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Create") {
                    guard !name.isEmpty else { return }
                    onCreate(name, systemPrompt)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
