import SwiftUI
import EmberShardBridge

struct ChatView: View {
    let chatId: UUID

    @EnvironmentObject var chatStore:  ChatStore
    @EnvironmentObject var appState:   AppState
    @EnvironmentObject var modelStore: LocalModelStore
    @EnvironmentObject var skillsStore: SkillsStore

    @State private var inputText = ""
    @State private var streamingMsgId: UUID?
    @State private var generationTask: Task<Void, Never>?
    @State private var isLoadingModel = false
    @State private var showScrollDown = false
    @AppStorage("es_agent_mode") private var agentMode = false

    private var chat: Chat? { chatStore.chat(id: chatId) }

    private var messages: [Message] {
        chat?.messages.sorted { $0.timestamp < $1.timestamp } ?? []
    }

    private static let warmupMessages = [
        "Warming up the engine...",
        "Loading model into Metal...",
        "Firing up the cores...",
        "Waking up the silicon...",
    ]

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(messages) { msg in
                                MessageBubble(
                                    message: msg,
                                    modelName: assistantModelName(for: msg),
                                    onRegenerate: msg.role == "assistant" && !msg.isStreaming
                                        ? { regenerateMessage(msg) } : nil
                                )
                                .id(msg.id)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                                .onAppear { showScrollDown = false }
                                .onDisappear { showScrollDown = true }
                        }
                        .padding(.vertical, 12)
                    }
                    .onAppear { scrollToBottom(proxy) }
                    .onChange(of: messages.count)    { _, _ in scrollToBottom(proxy) }
                    .onChange(of: streamingMsgId)    { _, _ in scrollToBottom(proxy) }
                    .onChange(of: isLoadingModel)    { _, _ in scrollToBottom(proxy) }
                    .overlay(alignment: .bottom) {
                        VStack(spacing: 8) {
                            if showScrollDown {
                                Button { scrollToBottom(proxy) } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .frame(width: 32, height: 32)
                                        .foregroundStyle(.secondary)
                                        .background(.regularMaterial, in: Circle())
                                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                                }
                                .buttonStyle(.plain)
                                .transition(.opacity)
                            }

                            LinearGradient(
                                colors: [Color(NSColor.windowBackgroundColor),
                                         Color(NSColor.windowBackgroundColor).opacity(0)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                            .frame(height: 32)
                            .allowsHitTesting(false)
                        }
                    }
                }
            }

            ChatInputView(
                text: $inputText,
                isGenerating: appState.isGenerating,
                models: modelStore.models,
                activeModelPath: modelStore.activeModelPath,
                agentMode: agentMode,
                skills: skillsStore.skills,
                activeSkillId: chat?.skillId,
                onModelChange: { model in modelStore.setActive(model) },
                onAgentToggle: { agentMode.toggle() },
                onSkillChange: { skillId in
                    guard var c = chat else { return }
                    c.skillId = skillId
                    chatStore.updateChat(c)
                },
                onSend: sendOrOrchestrate,
                onCancel: cancelGeneration
            )

            if messages.isEmpty {
                Spacer()
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Routing

    private func sendOrOrchestrate() {
        if agentMode && needsAgenticPipeline(inputText) {
            orchestrateMessage()
        } else {
            sendMessage()
        }
    }

    // Returns true only for queries complex enough to benefit from the
    // planner→executor→critic pipeline. Short/conversational messages bypass it.
    private func needsAgenticPipeline(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(separator: " ")
        guard words.count >= 8 else { return false }

        let lower = trimmed.lowercased()
        let complexTriggers = [
            "how", "why", "explain", "analyze", "analyse", "compare", "describe",
            "summarize", "summarise", "write", "create", "build", "design",
            "what is", "what are", "what does", "step by step",
            "come", "perché", "spiega", "analizza", "confronta", "scrivi",
            "crea", "descri", "riassumi", "progetta",
        ]
        return complexTriggers.contains { lower.contains($0) }
    }

    // MARK: - Chat (direct)

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !appState.isGenerating else { return }
        guard !modelStore.activeModelPath.isEmpty else { return }

        inputText = ""

        let userMsg = Message(role: "user", content: text)
        chatStore.addMessage(userMsg, toChatId: chatId)

        var assistantMsg = Message(role: "assistant", content: "", modelName: activeModelName)
        assistantMsg.isStreaming = true
        // Show loading text in the typing bubble while model loads
        if isLoadingModel {
            assistantMsg.agentStageName = Self.warmupMessages.randomElement()
        }
        chatStore.addMessage(assistantMsg, toChatId: chatId)
        streamingMsgId = assistantMsg.id

        appState.isGenerating = true
        let msgId = assistantMsg.id
        let isFirst = messages.filter { $0.role == "user" }.count == 1

        generationTask = Task {
            var tokenCount = 0
            do {
                let engine = EngineService.shared
                let systemPrompt = resolvedSystemPrompt()

                if await engine.needsReload(for: modelStore.activeModelPath) {
                    await MainActor.run {
                        isLoadingModel = true
                        chatStore.setAgentStage(msgId: msgId, inChatId: chatId,
                                                stageName: Self.warmupMessages.randomElement())
                    }
                    let config = buildEngineConfig()
                    try await engine.load(config: config) { _ in }
                    await MainActor.run {
                        isLoadingModel = false
                        chatStore.setAgentStage(msgId: msgId, inChatId: chatId, stageName: nil)
                    }
                }

                let maxTok = Int32(UserDefaults.standard.integer(forKey: "es_max_tokens").nonZeroOr(2048))
                let stream: AsyncThrowingStream<String, Error>
                if isFirst {
                    stream = await engine.generate(systemPrompt: systemPrompt, userText: text, maxTokens: maxTok)
                } else {
                    stream = await engine.continueConversation(userText: text, maxTokens: maxTok)
                }

                for try await piece in stream {
                    guard !Task.isCancelled else { break }
                    tokenCount += 1
                    await MainActor.run {
                        chatStore.appendToMessage(id: msgId, inChatId: chatId, piece: piece)
                    }
                }
            } catch is CancellationError {
                // intentional cancel
            } catch {
                await MainActor.run {
                    isLoadingModel = false
                    chatStore.appendToMessage(id: msgId, inChatId: chatId,
                                              piece: "\n_Error: \(error.localizedDescription)_")
                }
            }

            await MainActor.run {
                finishGeneration(msgId: msgId, tokenCount: tokenCount)
                // Generate title after first response
                if chat?.title == "New chat" {
                    generateTitle(for: chatId, from: text)
                }
            }
        }
    }

    // MARK: - Agent (Planner -> Executor -> Critic)

    private func orchestrateMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !appState.isGenerating else { return }
        guard !modelStore.activeModelPath.isEmpty else { return }

        inputText = ""

        let userMsg = Message(role: "user", content: text)
        chatStore.addMessage(userMsg, toChatId: chatId)

        var assistantMsg = Message(role: "assistant", content: "", modelName: activeModelName)
        assistantMsg.isStreaming = true
        assistantMsg.agentStageName = "Planning..."
        chatStore.addMessage(assistantMsg, toChatId: chatId)
        streamingMsgId = assistantMsg.id

        appState.isGenerating = true
        let msgId = assistantMsg.id
        let isFirst = messages.filter { $0.role == "user" }.count == 1

        generationTask = Task {
            do {
                let engine = EngineService.shared

                if await engine.needsReload(for: modelStore.activeModelPath) {
                    let config = buildEngineConfig()
                    try await engine.load(config: config) { _ in }
                }

                let maxTok = Int32(UserDefaults.standard.integer(forKey: "es_max_tokens").nonZeroOr(2048))
                let stream = await engine.orchestrate(userText: text, maxTokensPerStage: maxTok)

                for try await event in stream {
                    guard !Task.isCancelled else { break }
                    switch event {
                    case .stage(let stage):
                        let name = agentStageName(stage)
                        await MainActor.run {
                            chatStore.setAgentStage(msgId: msgId, inChatId: chatId, stageName: name)
                        }
                    case .token(let piece):
                        await MainActor.run {
                            chatStore.appendToMessage(id: msgId, inChatId: chatId, piece: piece)
                        }
                    }
                }
            } catch is CancellationError {
                // intentional cancel
            } catch {
                await MainActor.run {
                    chatStore.appendToMessage(id: msgId, inChatId: chatId,
                                              piece: "\n_Error: \(error.localizedDescription)_")
                }
            }

            await MainActor.run {
                finishGeneration(msgId: msgId)
                if chat?.title == "New chat" {
                    generateTitle(for: chatId, from: text)
                }
            }
        }
    }

    // MARK: - Title generation

    private func generateTitle(for chatId: UUID, from userMessage: String) {
        Task {
            let engine = EngineService.shared
            let stream = await engine.generate(
                systemPrompt: "Respond ONLY in this format, nothing else:\nICON: <sfSymbolName>\nTITLE: <short title max 6 words>\nChoose from: book, globe, chevron.left.forwardslash.chevron.right, music.note, heart, star, lightbulb, cart, airplane, camera, gamecontroller, film, pencil, doc.text, chart.bar, hammer, paintbrush, leaf, bolt, cpu, house, person, gift, bell, flag",
                userText: userMessage,
                maxTokens: 30
            )

            var result = ""
            do { for try await piece in stream { result += piece } } catch {}

            let lines = result.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)

            var icon = "bubble.left"
            var title = ""

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.lowercased().hasPrefix("icon:") {
                    let val = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if !val.isEmpty { icon = val }
                } else if trimmed.lowercased().hasPrefix("title:") {
                    title = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "\"", with: "")
                }
            }

            // Fallback if parsing failed
            if title.isEmpty {
                title = result.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "")
                    .prefix(60).description
            }

            if !title.isEmpty {
                await MainActor.run {
                    chatStore.setChatTitle(id: chatId, title: String(title.prefix(60)))
                    chatStore.setChatIcon(id: chatId, icon: icon)
                }
            }
        }
    }

    // MARK: - Helpers

    private func finishGeneration(msgId: UUID, tokenCount: Int = 0) {
        Task { @EngineActor in
            let engine = EngineService.shared
            let ctxUsed = engine.contextUsed
            let ctxMax  = engine.contextMax
            let frac = ctxMax > 0 ? Double(ctxUsed) / Double(ctxMax) : 0
            await MainActor.run {
                chatStore.finishMessage(id: msgId, inChatId: chatId,
                                        tokenCount: tokenCount, contextFraction: frac)
                streamingMsgId = nil
                appState.isGenerating = false
                isLoadingModel = false
            }
        }
    }

    private func resolvedSystemPrompt() -> String? {
        if let sid = chat?.skillId, let skill = skillsStore.skill(id: sid) {
            return skill.systemPrompt
        }
        return chat?.projectId.flatMap { pid in
            chatStore.projects.first { $0.id == pid }?.systemPrompt
        }
    }

    private func buildEngineConfig() -> EngineConfig {
        let ctxSize   = UserDefaults.standard.integer(forKey: "es_ctx_size").nonZeroOr(8192)
        let temp      = UserDefaults.standard.double(forKey: "es_temperature").nonZeroOr(0.7)
        let topP      = UserDefaults.standard.double(forKey: "es_top_p").nonZeroOr(0.95)
        let gpuLayers = UserDefaults.standard.integer(forKey: "es_gpu_layers")
        let threads   = UserDefaults.standard.integer(forKey: "es_threads")
        let kvRaw     = UserDefaults.standard.integer(forKey: "es_kv_quant")
        let kvQuant   = ESKVQuantType(rawValue: UInt32(kvRaw))
        return EngineConfig(
            modelPath: modelStore.activeModelPath,
            contextSize: Int32(ctxSize),
            temperature: Float(temp),
            topP: Float(topP),
            gpuLayers: Int32(gpuLayers == 0 ? -1 : gpuLayers),
            threads: Int32(threads),
            kvQuant: kvQuant
        )
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        Task { @EngineActor in EngineService.shared.cancel() }
        if let msgId = streamingMsgId {
            chatStore.finishMessage(id: msgId, inChatId: chatId)
        }
        streamingMsgId = nil
        appState.isGenerating = false
        isLoadingModel = false
    }

    private func regenerateMessage(_ msg: Message) {
        guard !appState.isGenerating else { return }
        chatStore.removeMessage(id: msg.id, fromChatId: chatId)
        let sorted = messages.sorted { $0.timestamp < $1.timestamp }
        guard let lastUser = sorted.last(where: { $0.role == "user" && $0.timestamp < msg.timestamp }) else { return }
        Task { @EngineActor in EngineService.shared.reset() }
        inputText = lastUser.content
        sendMessage()
    }

    private func assistantModelName(for msg: Message) -> String {
        if msg.role == "assistant" && !msg.modelName.isEmpty {
            return msg.modelName
        }
        return activeModelName
    }

    private var activeModelName: String {
        guard !modelStore.activeModelPath.isEmpty else { return "Model" }
        return URL(fileURLWithPath: modelStore.activeModelPath)
            .deletingPathExtension().lastPathComponent
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func agentStageName(_ stage: ESAgentStage) -> String {
        switch stage {
        case ES_STAGE_PLANNING:  return "Planning..."
        case ES_STAGE_EXECUTING: return "Executing..."
        case ES_STAGE_REVIEWING: return "Reviewing..."
        default:                 return "Working..."
        }
    }
}

// MARK: - Helpers

private extension Double {
    func nonZeroOr(_ fallback: Double) -> Double { self == 0 ? fallback : self }
}
private extension Int {
    func nonZeroOr(_ fallback: Int) -> Int { self == 0 ? fallback : self }
}
