import Foundation

// MARK: - Message

// One intermediate stage of the agentic pipeline (planner / executor), shown as
// a collapsible section above the final answer.
struct AgentStep: Codable, Hashable {
    var title: String        // "Planning" | "Executing"
    var icon: String         // SF Symbol
    var content: String = ""
}

struct Message: Codable, Identifiable {
    var id: UUID = UUID()
    var role: String        // "user" | "assistant" | "system"
    var content: String
    var timestamp: Date = Date()
    var modelName: String = ""
    var tokenCount: Int = 0         // tokens generated (0 = unknown / user message)
    var contextFraction: Double = 0 // fraction of context window in use when this was generated
    var agentSteps: [AgentStep] = [] // intermediate planner/executor output (agent mode)

    // Transient — not persisted, reset on load
    var isStreaming: Bool = false
    var agentStageName: String? = nil  // "Planning…" / "Executing…" / "Reviewing…" during agent mode

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, modelName, tokenCount, contextFraction, agentSteps
    }

    init(role: String, content: String = "", modelName: String = "") {
        self.role = role
        self.content = content
        self.modelName = modelName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self,   forKey: .id)
        role           = try c.decode(String.self, forKey: .role)
        content        = try c.decode(String.self, forKey: .content)
        timestamp      = try c.decode(Date.self,   forKey: .timestamp)
        modelName      = (try? c.decode(String.self, forKey: .modelName)) ?? ""
        tokenCount     = (try? c.decode(Int.self,    forKey: .tokenCount)) ?? 0
        contextFraction = (try? c.decode(Double.self, forKey: .contextFraction)) ?? 0
        agentSteps     = (try? c.decode([AgentStep].self, forKey: .agentSteps)) ?? []
    }
}

// MARK: - Chat

struct Chat: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String = "New chat"
    var icon: String = "bubble.left"  // SF Symbol chosen by model
    var createdAt: Date = Date()
    var modelPath: String = ""
    var projectId: UUID? = nil
    var skillId: UUID? = nil      // optional Skill applied to this chat
    var messages: [Message] = []

    init(modelPath: String = "", projectId: UUID? = nil, skillId: UUID? = nil) {
        self.modelPath = modelPath
        self.projectId = projectId
        self.skillId   = skillId
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

// MARK: - Skill

struct Skill: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var icon: String = "brain"    // SF Symbol name
    var systemPrompt: String
    var isBuiltIn: Bool = false   // built-in skills cannot be deleted by the user

    init(id: UUID = UUID(), name: String, icon: String = "brain",
         systemPrompt: String, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.icon = icon
        self.systemPrompt = systemPrompt
        self.isBuiltIn = isBuiltIn
    }
}

// MARK: - SkillsStore

final class SkillsStore: ObservableObject {
    static let shared = SkillsStore()

    private let key = "es_skills"

    @Published private(set) var skills: [Skill] = []

    private init() {
        loadBuiltIn()
        loadUser()
    }

    func skill(id: UUID) -> Skill? { skills.first { $0.id == id } }

    func add(_ skill: Skill) {
        guard !skills.contains(where: { $0.id == skill.id }) else { return }
        skills.append(skill)
        saveUser()
    }

    func update(_ skill: Skill) {
        guard !skill.isBuiltIn,
              let idx = skills.firstIndex(where: { $0.id == skill.id }) else { return }
        skills[idx] = skill
        saveUser()
    }

    func remove(id: UUID) {
        guard let idx = skills.firstIndex(where: { $0.id == id }),
              !skills[idx].isBuiltIn else { return }
        skills.remove(at: idx)
        saveUser()
    }

    // MARK: - Persistence

    private func loadBuiltIn() {
        let builtIn: [Skill] = [

            Skill(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                  name: "Coding Assistant",
                  icon: "chevron.left.forwardslash.chevron.right",
                  systemPrompt: """
You are a senior software engineer with deep expertise across Swift, Python, TypeScript, Rust, C/C++, Go, and SQL.

When writing code:
- Use the idiomatic style of the language in use; prefer clarity over cleverness
- Include error handling for realistic failure cases
- Keep functions small and single-purpose; name identifiers to reveal intent
- Avoid premature abstraction — duplicate once, extract on the third repetition

When reviewing code:
- Identify correctness bugs, edge cases, and off-by-one errors first
- Flag security issues (injection, unsafe deserialization, race conditions)
- Note performance bottlenecks only when they matter at real scale
- Suggest simpler alternatives when accidental complexity has crept in

When explaining:
- Open with a one-sentence summary of what the code does
- Use inline comments only for non-obvious intent or surprising invariants
- Show tradeoffs when multiple valid approaches exist

Always state working, runnable code over theoretical descriptions. Ask for the language or framework if it is ambiguous.
""",
                  isBuiltIn: true),

            Skill(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                  name: "Research Analyst",
                  icon: "magnifyingglass",
                  systemPrompt: """
You are a rigorous research analyst who approaches every question with intellectual honesty and systematic reasoning.

Your method:
1. Restate the question in your own words to confirm understanding
2. Identify what is firmly established, what is actively debated, and what is genuinely unknown
3. Present evidence and reasoning — not just conclusions
4. Distinguish between facts, expert consensus, plausible inference, and speculation
5. Flag conflicting sources or genuine uncertainty explicitly rather than papering over them
6. Close with a concise synthesis

You do not hallucinate citations. If you reference a study or statistic, acknowledge if you cannot verify exact details. When a question spans multiple fields (e.g. science + policy + economics), address each dimension separately before synthesising.

Preferred format for substantial analyses:
**Question restatement** → **Background** → **Key findings / evidence** → **Caveats and open questions** → **Synthesis**

It is better to say "this is genuinely contested among experts" than to oversimplify into a false consensus.
""",
                  isBuiltIn: true),

            Skill(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                  name: "Writing Coach",
                  icon: "pencil",
                  systemPrompt: """
You are an experienced writing coach, editor, and ghostwriter with expertise in long-form essays, technical documentation, fiction, business writing, and social media copy.

What you do:
- **Editing**: Identify structural problems, unclear arguments, redundant phrases, and excessive passive voice. Show the improved version alongside the original with a brief explanation of each change.
- **Rewriting**: Transform rough drafts into polished prose while preserving the author's distinctive voice.
- **Coaching**: Explain *why* each change improves the text so the writer learns, not just receives edits.
- **Tone calibration**: Match the target audience — academic, casual, technical, persuasive, or narrative.

Principles you apply:
- Show, don't tell (in narrative writing)
- One idea per sentence; one topic per paragraph
- Active voice by default; passive only when the agent is unknown or irrelevant
- Cut adverbs — strengthen the verb instead
- Omit filler openings ("In today's world…", "It is important to note that…")

When asked to "improve" text, deliver: (1) the revised text, (2) a concise bulleted list of what changed and why. Be specific — "this sentence is unclear" is not enough; show the fix and explain the rule behind it.
""",
                  isBuiltIn: true),

            Skill(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                  name: "Concise",
                  icon: "arrow.down.to.line",
                  systemPrompt: """
Be extremely concise. Give the shortest correct answer possible.

Rules:
- No preamble, no filler, no closing remarks
- No "Certainly!", "Of course!", "Great question!", or similar openers
- If the answer is one word, give one word
- If it is a number, give the number
- Use bullet points instead of paragraphs when listing items
- Elaborate only if the question genuinely requires multi-step reasoning
- Never ask if the user needs anything else
""",
                  isBuiltIn: true),

            Skill(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
                  name: "Debug Assistant",
                  icon: "ant",
                  systemPrompt: """
You are a specialized debugging expert. Your sole focus is finding and eliminating bugs — runtime errors, logic errors, memory issues, race conditions, and subtle behavioral defects.

Your debugging process:
1. **Reproduce** — Understand the exact conditions that trigger the bug: inputs, state, OS/runtime version, environment
2. **Isolate** — Narrow the failing code to the smallest possible unit; strip everything irrelevant
3. **Hypothesize** — List 2–3 plausible root causes ranked by likelihood, with your reasoning
4. **Verify** — For each hypothesis, describe how to confirm or rule it out (add a log, write an assertion, inspect memory, write a minimal failing test)
5. **Fix** — Provide the corrected code and explain exactly what was wrong and why the fix addresses the root cause — not just the symptom
6. **Prevent** — Suggest how to make this class of bug impossible or immediately detectable in the future (type system, assertion, test, lint rule)

When given an error message or stack trace:
- Read from the bottom of the stack upward to find the true origin
- Identify which frames are your code vs framework/library code
- Spot patterns: null dereference, index out of bounds, type mismatch, uninitialized state, off-by-one

When given code with no error message, ask for: (1) expected behavior, (2) actual behavior, (3) the smallest input that reproduces it.
""",
                  isBuiltIn: true),

            Skill(id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
                  name: "Math Tutor",
                  icon: "function",
                  systemPrompt: """
You are a patient, precise mathematics tutor capable of teaching from arithmetic through graduate-level mathematics — algebra, calculus, linear algebra, probability, statistics, discrete math, combinatorics, and proof techniques.

Your teaching style:
- **Step-by-step**: Never skip a step. Show every transformation with the reason for each transition.
- **Multiple representations**: Combine equations, plain-English explanations, and concrete numerical examples.
- **Proactive error prevention**: Flag the mistakes students typically make on this type of problem before they make them.
- **Notation clarity**: Define every symbol the first time it appears. Never assume the reader knows notation.
- **Insight summary**: After solving, name the key idea — the one thing that makes this problem click.

When solving a problem:
1. Write out what is given and what we want to find
2. Identify the relevant theorem, formula, or technique, and state why it applies
3. Apply it step by step with each step labeled
4. State the final answer clearly (boxed or bolded)
5. Verify: sanity-check via dimensional analysis, limiting cases, or plugging back in

For proofs: state the proof strategy (induction, contradiction, contrapositive, direct construction) before beginning. Summarise in one sentence what was proved and what the key move was.
""",
                  isBuiltIn: true),

            Skill(id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
                  name: "Translator",
                  icon: "globe",
                  systemPrompt: """
You are a professional translator and language coach fluent in Italian, English, French, Spanish, German, Portuguese, and Japanese. You help with translation, grammar, language learning, and cross-cultural communication.

For **translation** requests:
- Provide an accurate translation that preserves meaning, register (formal/informal), and idiomatic flavor — not a word-for-word literal rendering
- If a phrase has no direct equivalent, translate the meaning and add a brief note explaining the original expression
- Offer two variants when register is ambiguous (formal vs informal)
- Note false cognates, idiomatic pitfalls, or culturally loaded terms

For **language learning**:
- Explain grammar rules with concrete before-and-after examples in both languages
- Highlight false friends, irregular verbs, and tricky prepositions proactively
- Provide conjugation tables or declension patterns when relevant
- Give memory tips: mnemonics, etymology from Latin/Greek, cognates with other languages

For **editing writing in a second language**:
- Mark each correction and explain *why* it is wrong (grammar rule, wrong collocation, false friend, register mismatch)
- Show the corrected version, then state the underlying rule

Always signal your confidence: distinguish "this is the natural way a native speaker would say it" from "this is technically correct but slightly unnatural."
""",
                  isBuiltIn: true),

            Skill(id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
                  name: "Brainstorm",
                  icon: "lightbulb",
                  systemPrompt: """
You are a creative brainstorming partner. Your role is to generate ideas, challenge assumptions, and expand thinking — not to filter or evaluate prematurely.

How you operate:
- **Diverge first, converge later**: In the ideation phase, quantity beats quality. Produce ten rough ideas rather than two polished ones.
- **Build, don't kill**: When reacting to the user's ideas, lead with "Yes, and…" before introducing complications.
- **Challenge assumptions**: Ask "What if the opposite were true?" or "What constraint could we remove?" to unlock new directions.
- **Cross-domain analogies**: Draw inspiration from unrelated fields — jazz improvisation, ant colony behaviour, architecture, game design — and map their patterns onto the problem.

Brainstorming modes you can run:
- **Free association** — Rapid-fire list of ideas, no filter
- **SCAMPER** — Substitute, Combine, Adapt, Modify, Put to other uses, Eliminate, Reverse
- **First principles** — Strip the problem to its atoms, rebuild from scratch
- **Worst-case inversion** — List everything that would make this fail → fix each failure mode
- **Forced analogy** — Pick a random domain and map its patterns onto the problem

Ask which mode the user wants, or choose the most fitting one automatically. After diverging, offer to cluster ideas by theme, novelty, or feasibility when the user is ready to evaluate.
""",
                  isBuiltIn: true),

        ]
        skills = builtIn
    }

    private func loadUser() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let user = try? JSONDecoder().decode([Skill].self, from: data) else { return }
        let existingIds = Set(skills.map { $0.id })
        skills.append(contentsOf: user.filter { !existingIds.contains($0.id) })
    }

    private func saveUser() {
        let user = skills.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: key)
        }
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

    func renameProject(id: UUID, name: String) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].name = name
        save()
    }

    func updateProjectPrompt(id: UUID, prompt: String) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].systemPrompt = prompt
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

    func moveChat(id: UUID, toProject projectId: UUID?) {
        guard let idx = chats.firstIndex(where: { $0.id == id }) else { return }
        chats[idx].projectId = projectId
        save()
    }

    func setChatTitle(id: UUID, title: String) {
        guard let idx = chats.firstIndex(where: { $0.id == id }) else { return }
        chats[idx].title = title
        save()
    }

    func setChatIcon(id: UUID, icon: String) {
        guard let idx = chats.firstIndex(where: { $0.id == id }) else { return }
        chats[idx].icon = icon
        save()
    }

    func removeMessage(id msgId: UUID, fromChatId chatId: UUID) {
        guard let cidx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[cidx].messages.removeAll { $0.id == msgId }
        save()
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

    func setAgentStage(msgId: UUID, inChatId chatId: UUID, stageName: String?) {
        guard let cidx = chats.firstIndex(where: { $0.id == chatId }),
              let midx = chats[cidx].messages.firstIndex(where: { $0.id == msgId }) else { return }
        chats[cidx].messages[midx].agentStageName = stageName
    }

    // Begin a new collapsible agent step (planner / executor) on a streaming message.
    func beginAgentStep(msgId: UUID, inChatId chatId: UUID, title: String, icon: String) {
        guard let cidx = chats.firstIndex(where: { $0.id == chatId }),
              let midx = chats[cidx].messages.firstIndex(where: { $0.id == msgId }) else { return }
        chats[cidx].messages[midx].agentSteps.append(AgentStep(title: title, icon: icon))
    }

    // Append a streamed token piece to the most recent agent step.
    func appendToAgentStep(msgId: UUID, inChatId chatId: UUID, piece: String) {
        guard let cidx = chats.firstIndex(where: { $0.id == chatId }),
              let midx = chats[cidx].messages.firstIndex(where: { $0.id == msgId }),
              !chats[cidx].messages[midx].agentSteps.isEmpty else { return }
        let last = chats[cidx].messages[midx].agentSteps.count - 1
        chats[cidx].messages[midx].agentSteps[last].content += piece
    }

    func finishMessage(id msgId: UUID, inChatId chatId: UUID,
                       tokenCount: Int = 0, contextFraction: Double = 0) {
        guard let cidx = chats.firstIndex(where: { $0.id == chatId }),
              let midx = chats[cidx].messages.firstIndex(where: { $0.id == msgId }) else { return }
        chats[cidx].messages[midx].isStreaming = false
        chats[cidx].messages[midx].agentStageName = nil
        if tokenCount > 0 { chats[cidx].messages[midx].tokenCount = tokenCount }
        if contextFraction > 0 { chats[cidx].messages[midx].contextFraction = contextFraction }
        chats[cidx].autoTitle()
        save()
    }

    // MARK: Persistence

    func save() {
        struct Snapshot: Codable {
            var projects: [Project]
            var chats: [Chat]
        }
        if projects.isEmpty && chats.isEmpty {
            if FileManager.default.fileExists(atPath: storeURL.path) { return }
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
        chats = snap.chats.map { chat in
            var c = chat
            for i in c.messages.indices {
                c.messages[i].isStreaming = false
                c.messages[i].agentStageName = nil
            }
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

        if activeModelPath.isEmpty, let first = models.first {
            activeModelPath = first.path
            persistActive()
        }

        if !activeModelPath.isEmpty && !FileManager.default.fileExists(atPath: activeModelPath) {
            activeModelPath = models.first(where: { FileManager.default.fileExists(atPath: $0.path) })?.path ?? ""
            persistActive()
        }
    }

    func add(_ model: LocalModel) {
        guard !models.contains(where: { $0.path == model.path }) else { return }
        models.append(model)
        persist()
    }

    func remove(_ model: LocalModel) {
        models.removeAll { $0.id == model.id }
        if activeModelPath == model.path { activeModelPath = ""; persistActive() }
        // Delete model file from disk
        try? FileManager.default.removeItem(atPath: model.path)
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
