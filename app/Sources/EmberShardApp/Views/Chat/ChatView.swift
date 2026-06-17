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
    @State private var nativeNeedsReplay = false   // force full KV replay next turn

    private var chat: Chat? { chatStore.chat(id: chatId) }

    private var messages: [Message] {
        chat?.messages.sorted { $0.timestamp < $1.timestamp } ?? []
    }

    private static let warmupMessages = EngineUI.warmupMessages

    private var logoImage: NSImage? {
        guard let url = Bundle.module.url(forResource: "logo", withExtension: "svg"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        return img
    }

    private var emptyTitle: some View {
        HStack(spacing: 10) {
            if let img = logoImage {
                Image(nsImage: img).resizable().renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 26, height: 26)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.secondary)
            }
            Text("Embershard")
                .font(.title2.weight(.regular))
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        switch chat?.kind {
        case .compare: CompareChatView(chatId: chatId)
        case .macos:   MacHelperChatView(chatId: chatId)
        default:       standardBody
        }
    }

    private var standardBody: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    emptyTitle
                    chatInputView.frame(maxWidth: 620)
                }
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
                chatInputView   // full width once the conversation has started
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // fill so the bg is uniform
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var chatInputView: some View {
        ChatInputView(
            text: $inputText,
            isGenerating: appState.isGenerating,
            models: modelStore.compatibleModels,
            activeModelPath: modelStore.activeModelPath,
            skills: skillsStore.skills,
            activeSkillId: chat?.skillId,
            onModelChange: { model in modelStore.setActive(model) },
            onSkillChange: { skillId in
                guard var c = chat else { return }
                c.skillId = skillId
                chatStore.updateChat(c)
            },
            onSend: sendOrOrchestrate,
            onCancel: cancelGeneration,
            toggleActive: chat?.agentMode ?? false,
            toggleLabel: "Agent",
            toggleIcon: "wand.and.stars",
            onToggle: {
                guard var c = chat else { return }
                c.agentMode.toggle()
                chatStore.updateChat(c)
            }
        )
    }

    // MARK: - Routing

    private func sendOrOrchestrate() {
        // Agent toggle runs the planner→executor pipeline (trivial greetings stay
        // a quick direct reply).
        if (chat?.agentMode ?? false) && !isTrivialGreeting(inputText) {
            orchestrateMessage()
        } else {
            sendMessageNative()
        }
    }

    // True for short greetings / small-talk that should never trigger the
    // agentic pipeline even when agent mode is on.
    private func isTrivialGreeting(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let words = trimmed.split { $0 == " " || $0 == "\n" }
        // Anything longer than a few words is a real request → use the pipeline.
        guard words.count <= 3 else { return false }

        let greetings: Set<String> = [
            "ciao", "salve", "hey", "hi", "hello", "yo", "buongiorno", "buonasera",
            "hola", "ehi", "ok", "okay", "grazie", "thanks", "thank you", "test",
            "come stai", "how are you", "what's up", "whats up", "sup",
        ]
        if greetings.contains(trimmed) { return true }
        // Single short word with no question mark → treat as small-talk.
        return words.count == 1 && !trimmed.contains("?")
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
                // Set title and icon for new chats
                if chat?.title == "New chat" {
                    generateTitleNative(from: text)
                }
            }
        }
    }

    // MARK: - Native engine (es_gx: own forward pass + KV cache + tokenizer)

    private func sendMessageNative() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !appState.isGenerating else { return }
        guard !modelStore.activeModelPath.isEmpty else { return }

        inputText = ""
        // Completed prior turns become the replay history (used only on chat switch).
        let history = nativeHistory()
        chatStore.addMessage(Message(role: "user", content: text), toChatId: chatId)
        let force = nativeNeedsReplay; nativeNeedsReplay = false
        runNativeTurn(userText: text, history: history, forceFull: force)
    }

    // Prior completed user/assistant turns of this chat, in order.
    private func nativeHistory() -> [NativeTurn] {
        messages.filter { ($0.role == "user" || $0.role == "assistant") && !$0.content.isEmpty }
                .map { NativeTurn(role: $0.role, content: $0.content) }
    }

    private func runNativeTurn(userText: String, history: [NativeTurn], forceFull: Bool = false) {
        var assistantMsg = Message(role: "assistant", content: "", modelName: activeModelName)
        assistantMsg.isStreaming = true
        chatStore.addMessage(assistantMsg, toChatId: chatId)
        streamingMsgId = assistantMsg.id
        appState.isGenerating = true
        let msgId = assistantMsg.id

        let path    = modelStore.activeModelPath
        let system  = resolvedSystemPrompt()
        let ctxSize = Int32(UserDefaults.standard.integer(forKey: "es_ctx_size").nonZeroOr(8192))
        let maxTok  = Int32(UserDefaults.standard.integer(forKey: "es_max_tokens").nonZeroOr(2048))
        let kvQuant = Int32(UserDefaults.standard.integer(forKey: "es_kv_quant"))   // 0=F16 1=Q8_0 2=Q4_0
        let samp    = nativeSampling()
        let cid     = chatId

        generationTask = Task {
            var tokenCount = 0
            do {
                // One model resident at a time: drop the agent (llama.cpp) engine.
                await EngineService.shared.unload()
                let willLoad = await NativeEngine.shared.needsReload(for: path)
                if willLoad {
                    await MainActor.run {
                        isLoadingModel = true
                        chatStore.setAgentStage(msgId: msgId, inChatId: chatId,
                                                stageName: Self.warmupMessages.randomElement())
                    }
                }
                let ok = await NativeEngine.shared.ensureLoaded(path: path, nCtx: ctxSize, kvQuant: kvQuant)
                if willLoad {
                    await MainActor.run {
                        isLoadingModel = false
                        chatStore.setAgentStage(msgId: msgId, inChatId: chatId, stageName: nil)
                    }
                }
                guard ok else { throw EngineError.modelLoadFailed }
                let stream = await NativeEngine.shared.send(chat: cid, system: system,
                                                            history: history, user: userText,
                                                            maxTokens: maxTok, sampling: samp,
                                                            forceFull: forceFull)
                for try await piece in stream {
                    guard !Task.isCancelled else { break }
                    tokenCount += 1
                    await MainActor.run { chatStore.appendToMessage(id: msgId, inChatId: chatId, piece: piece) }
                }
            } catch is CancellationError {
                // partial turn -> stale KV; cancelGeneration sets nativeNeedsReplay
            } catch {
                await MainActor.run {
                    chatStore.appendToMessage(id: msgId, inChatId: chatId,
                                              piece: "\n_Error: \(error.localizedDescription)_")
                }
            }
            await MainActor.run {
                finishGeneration(msgId: msgId, tokenCount: tokenCount)
                if chat?.title == "New chat" { generateTitleNative(from: userText) }
            }
        }
    }

    // Build the native sampler config from the user's Inference settings.
    private func nativeSampling() -> es_gx_sampling {
        let d = UserDefaults.standard
        func f(_ k: String, _ def: Double) -> Float { Float(d.object(forKey: k) as? Double ?? def) }
        func i(_ k: String, _ def: Int) -> Int32 { Int32(d.object(forKey: k) as? Int ?? def) }
        return es_gx_sampling(
            temp:           f("es_temperature", 0.7),
            top_p:          f("es_top_p", 0.95),
            top_k:          i("es_top_k", 40),
            min_p:          f("es_min_p", 0.05),
            repeat_penalty: f("es_repeat_penalty", 1.1),
            repeat_last_n:  i("es_repeat_last_n", 64),
            seed:           UInt32(truncatingIfNeeded: d.object(forKey: "es_seed") as? Int ?? 0)
        )
    }

    // Topic-based title + icon from the first user message. Uses the model once
    // (which clobbers the chat KV → next turn re-prefills automatically). Falls
    // back to a keyword heuristic if parsing fails.
    private func generateTitleNative(from userMessage: String) {
        let cid = chatId
        let sys = """
        Respond ONLY in this exact format, nothing else:
        ICON: <name>
        TITLE: <short title, max 6 words>

        Pick ICON verbatim from this list:
        \(IconCatalog.promptList)
        """
        Task {
            let out = await NativeEngine.shared.complete(system: sys, user: userMessage, maxTokens: 28)
            var rawIcon = "", title = ""
            for line in out.components(separatedBy: .newlines) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.lowercased().hasPrefix("icon:") {
                    rawIcon = String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                } else if t.lowercased().hasPrefix("title:") {
                    title = String(t.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "\"", with: "")
                }
            }
            if title.isEmpty {
                title = userMessage.split(whereSeparator: { $0 == " " || $0 == "\n" })
                    .prefix(6).joined(separator: " ")
            }
            let finalTitle = String(title.prefix(60))
            guard !finalTitle.isEmpty else { return }
            await MainActor.run {
                let icon = IconCatalog.resolve(rawIcon: rawIcon, title: finalTitle)
                chatStore.setChatTitle(id: cid, title: finalTitle)
                chatStore.setChatIcon(id: cid, icon: icon)
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

        let systemPrompt = resolvedSystemPrompt()

        generationTask = Task {
            // Pipeline = Planner → Executor. Planner steps stream into a collapsible
            // "Planning" card; the executor's answer streams into the message body
            // as the final response.
            var currentStage: ESAgentStage = ES_STAGE_PLANNING
            var answerTokens = 0
            let ctxSize = Int32(UserDefaults.standard.integer(forKey: "es_ctx_size").nonZeroOr(8192))
            let kvQuant = Int32(UserDefaults.standard.integer(forKey: "es_kv_quant"))
            let maxTok  = Int32(UserDefaults.standard.integer(forKey: "es_max_tokens").nonZeroOr(2048))
            let samp    = nativeSampling()
            _ = systemPrompt   // skill prompt not applied to the agent pipeline yet
            do {
                // Agent pipeline runs on our native engine too (no llama.cpp).
                await EngineService.shared.unload()
                let ok = await NativeEngine.shared.ensureLoaded(path: modelStore.activeModelPath,
                                                                nCtx: ctxSize, kvQuant: kvQuant)
                guard ok else { throw EngineError.modelLoadFailed }
                let stream = await NativeEngine.shared.orchestrate(user: text, maxTokens: maxTok, sampling: samp)

                for try await event in stream {
                    guard !Task.isCancelled else { break }
                    switch event {
                    case .stage(let stage):
                        currentStage = stage
                        await MainActor.run {
                            if stage == ES_STAGE_PLANNING {
                                chatStore.setAgentStage(msgId: msgId, inChatId: chatId, stageName: "Planning")
                                chatStore.beginAgentStep(msgId: msgId, inChatId: chatId,
                                                         title: "Planning", icon: "list.bullet.rectangle")
                            } else {
                                // Executor is the final answer — clear the stage label
                                // so the message body shows the streaming response.
                                chatStore.setAgentStage(msgId: msgId, inChatId: chatId, stageName: nil)
                            }
                        }
                    case .token(let piece):
                        let stage = currentStage
                        if stage != ES_STAGE_PLANNING { answerTokens += 1 }
                        await MainActor.run {
                            if stage == ES_STAGE_PLANNING {
                                chatStore.appendToAgentStep(msgId: msgId, inChatId: chatId, piece: piece)
                            } else {
                                chatStore.appendToMessage(id: msgId, inChatId: chatId, piece: piece)
                            }
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
                finishGeneration(msgId: msgId, tokenCount: answerTokens)
                if chat?.title == "New chat" { generateTitleNative(from: text) }
            }
        }
    }

    // MARK: - Title generation

    private func generateTitle(for chatId: UUID, from userMessage: String) {
        Task {
            let engine = EngineService.shared
            let stream = await engine.generate(
                systemPrompt: "You generate short chat titles. Reply with ONLY the title (3-5 words, no quotes, no explanation).",
                userText: userMessage,
                maxTokens: 15
            )

            var result = ""
            do { for try await piece in stream { result += piece } } catch {}

            var title = result.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .components(separatedBy: .newlines).first ?? ""

            // Remove common prefixes the model might add
            for prefix in ["Title:", "title:", "TITLE:", "Sure!", "Here"] {
                if title.hasPrefix(prefix) {
                    title = String(title.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                }
            }

            if title.isEmpty || title.count < 2 {
                title = String(userMessage.prefix(40))
            }

            let finalTitle = String(title.prefix(50))

            await MainActor.run {
                chatStore.setChatTitle(id: chatId, title: finalTitle)
                // Infer icon from title keywords
                let icon = IconCatalog.resolve(rawIcon: "", title: finalTitle)
                chatStore.setChatIcon(id: chatId, icon: icon)
            }
        }
    }

    // MARK: - Helpers

    private func finishGeneration(msgId: UUID, tokenCount: Int = 0) {
        Task { @NativeEngineActor in
            let used = NativeEngine.shared.contextUsed
            let cap  = NativeEngine.shared.contextMax
            let frac = cap > 0 ? Double(used) / Double(cap) : 0
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
        let d = UserDefaults.standard
        let ctxSize   = d.integer(forKey: "es_ctx_size").nonZeroOr(8192)
        let temp      = d.double(forKey: "es_temperature").nonZeroOr(0.7)
        let topP      = d.double(forKey: "es_top_p").nonZeroOr(0.95)
        let gpuLayers = d.integer(forKey: "es_gpu_layers")
        let threads   = d.integer(forKey: "es_threads")
        let batchSize = d.integer(forKey: "es_batch_size").nonZeroOr(512)
        let kvRaw     = d.integer(forKey: "es_kv_quant")
        let kvQuant   = ESKVQuantType(rawValue: UInt32(kvRaw))
        // Booleans: AppStorage defaults aren't written to UserDefaults until the
        // user toggles them, so fall back to the recommended default when unset.
        let flashAttn = d.object(forKey: "es_flash_attn") as? Bool ?? true
        let useMmap   = d.object(forKey: "es_use_mmap")   as? Bool ?? true
        return EngineConfig(
            modelPath: modelStore.activeModelPath,
            contextSize: Int32(ctxSize),
            temperature: Float(temp),
            topP: Float(topP),
            gpuLayers: Int32(gpuLayers == 0 ? -1 : gpuLayers),
            threads: Int32(threads),
            batchSize: Int32(batchSize),
            kvQuant: kvQuant,
            flashAttn: flashAttn,
            useMmap: useMmap
        )
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        Task { @EngineActor in EngineService.shared.cancel() }
        NativeEngine.shared.requestCancel()   // stop the C decode loop now
        nativeNeedsReplay = true   // partial KV -> replay next turn
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
        // KV no longer matches the message list — force a full replay, then
        // regenerate for the existing last user turn (no new user message).
        let history = sorted.filter { $0.timestamp < lastUser.timestamp
                                      && ($0.role == "user" || $0.role == "assistant") && !$0.content.isEmpty }
                            .map { NativeTurn(role: $0.role, content: $0.content) }
        runNativeTurn(userText: lastUser.content, history: history, forceFull: true)
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

}

// MARK: - Helpers

extension Double {
    func nonZeroOr(_ fallback: Double) -> Double { self == 0 ? fallback : self }
}
extension Int {
    func nonZeroOr(_ fallback: Int) -> Int { self == 0 ? fallback : self }
}
