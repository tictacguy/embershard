import Foundation

// MARK: - Message

struct Message: Codable, Identifiable {
    var id: UUID = UUID()
    var role: String        // "user" | "assistant" | "system"
    var content: String
    var timestamp: Date = Date()
    var isStreaming: Bool = false   // transient — reset to false on load

    // Exclude isStreaming from persistence so it never stays true across launches.
    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp
    }

    init(role: String, content: String = "") {
        self.role = role
        self.content = content
    }
}

// MARK: - Chat

struct Chat: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String = "New chat"
    var createdAt: Date = Date()
    var modelPath: String = ""
    var projectId: UUID? = nil   // nil = standalone chat
    var messages: [Message] = []

    init(modelPath: String = "", projectId: UUID? = nil) {
        self.modelPath = modelPath
        self.projectId = projectId
    }

    mutating func autoTitle() {
        guard title == "New chat" || title.isEmpty else { return }
        if let first = messages.first(where: { $0.role == "user" }) {
            title = String(first.content.prefix(50))
        }
    }
}

// MARK: - Project

struct Project: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var systemPrompt: String = ""

    init(name: String, systemPrompt: String = "") {
        self.name = name
        self.systemPrompt = systemPrompt
    }
}

// MARK: - ChatStore

final class ChatStore: ObservableObject {
    static let shared = ChatStore()

    @Published private(set) var projects: [Project] = []
    @Published private(set) var chats: [Chat] = []

    private init() { load() }

    // MARK: Lookups

    var standaloneChats: [Chat] {
        chats.filter { $0.projectId == nil }.sorted { $0.createdAt > $1.createdAt }
    }

    func chats(for project: Project) -> [Chat] {
        chats.filter { $0.projectId == project.id }.sorted { $0.createdAt > $1.createdAt }
    }

    func project(for chat: Chat) -> Project? {
        guard let pid = chat.projectId else { return nil }
        return projects.first { $0.id == pid }
    }

    func chat(id: UUID) -> Chat? {
        chats.first { $0.id == id }
    }

    // MARK: Project CRUD

    func addProject(_ project: Project) {
        projects.append(project)
        save()
    }

    func removeProject(_ project: Project) {
        chats.removeAll { $0.projectId == project.id }
        projects.removeAll { $0.id == project.id }
        save()
    }

    // MARK: Chat CRUD

    func addChat(_ chat: Chat) {
        chats.append(chat)
        save()
    }

    func removeChat(id: UUID) {
        chats.removeAll { $0.id == id }
        save()
    }

    func updateChat(_ chat: Chat) {
        if let idx = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[idx] = chat
        }
    }

    // MARK: Message mutations (used during streaming)

    func addMessage(_ msg: Message, toChatId chatId: UUID) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[idx].messages.append(msg)
    }

    func appendToMessage(id msgId: UUID, inChatId chatId: UUID, piece: String) {
        guard let cidx = chats.firstIndex(where: { $0.id == chatId }),
              let midx = chats[cidx].messages.firstIndex(where: { $0.id == msgId }) else { return }
        chats[cidx].messages[midx].content += piece
    }

    func finishMessage(id msgId: UUID, inChatId chatId: UUID) {
        guard let cidx = chats.firstIndex(where: { $0.id == chatId }),
              let midx = chats[cidx].messages.firstIndex(where: { $0.id == msgId }) else { return }
        chats[cidx].messages[midx].isStreaming = false
        chats[cidx].autoTitle()
        save()
    }

    // MARK: Persistence

    func save() {
        struct Snapshot: Codable {
            var projects: [Project]
            var chats: [Chat]
        }
        guard let data = try? JSONEncoder().encode(Snapshot(projects: projects, chats: chats)) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func load() {
        struct Snapshot: Codable {
            var projects: [Project]
            var chats: [Chat]
        }
        guard let data = try? Data(contentsOf: storeURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        projects = snap.projects
        // Clear any stale isStreaming flags left by a previous crash.
        chats = snap.chats.map { chat in
            var c = chat
            for i in c.messages.indices { c.messages[i].isStreaming = false }
            return c
        }
    }

    private var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir  = base.appendingPathComponent("Embershard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("chats.json")
    }
}

// MARK: - LocalModel

struct LocalModel: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var path: String
    var sizeBytes: Int64
    var quantization: String

    var sizeString: String {
        let gb = Double(sizeBytes) / 1_073_741_824
        return gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", Double(sizeBytes) / 1_048_576)
    }
}

// MARK: - LocalModelStore

final class LocalModelStore: ObservableObject {
    static let shared = LocalModelStore()

    private let modelsKey = "es_local_models"
    private let activeKey = "es_active_model"

    @Published private(set) var models: [LocalModel] = []
    @Published private(set) var activeModelPath: String = ""

    private init() {
        if let data    = UserDefaults.standard.data(forKey: modelsKey),
           let decoded = try? JSONDecoder().decode([LocalModel].self, from: data) {
            models = decoded
        }
        activeModelPath = UserDefaults.standard.string(forKey: activeKey) ?? ""
    }

    func add(_ model: LocalModel) {
        guard !models.contains(where: { $0.path == model.path }) else { return }
        models.append(model)
        persist()
    }

    func remove(_ model: LocalModel) {
        models.removeAll { $0.id == model.id }
        if activeModelPath == model.path { activeModelPath = ""; persistActive() }
        persist()
    }

    func setActive(_ model: LocalModel) {
        activeModelPath = model.path
        persistActive()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(models) {
            UserDefaults.standard.set(data, forKey: modelsKey)
        }
    }

    private func persistActive() {
        UserDefaults.standard.set(activeModelPath, forKey: activeKey)
    }
}
