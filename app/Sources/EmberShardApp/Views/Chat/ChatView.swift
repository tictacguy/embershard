import SwiftUI

struct ChatView: View {
    let chatId: UUID

    @EnvironmentObject var chatStore:  ChatStore
    @EnvironmentObject var appState:   AppState
    @EnvironmentObject var modelStore: LocalModelStore

    @State private var inputText = ""
    @State private var streamingMsgId: UUID?
    @State private var generationTask: Task<Void, Never>?

    private var chat: Chat? { chatStore.chat(id: chatId) }

    private var messages: [Message] {
        chat?.messages.sorted { $0.timestamp < $1.timestamp } ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chat?.title ?? "Chat")
                        .font(.headline)
                    if !modelStore.activeModelPath.isEmpty {
                        Text(URL(fileURLWithPath: modelStore.activeModelPath)
                            .deletingPathExtension().lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical, 12)
                }
                .onAppear { scrollToBottom(proxy) }
                .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: streamingMsgId) { _, _ in scrollToBottom(proxy) }
            }

            Divider()

            // Input
            ChatInputView(
                text: $inputText,
                isGenerating: appState.isGenerating,
                onSend: sendMessage,
                onCancel: cancelGeneration
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle(chat?.title ?? "Chat")
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !appState.isGenerating else { return }
        guard !modelStore.activeModelPath.isEmpty else { return }

        inputText = ""

        let userMsg = Message(role: "user", content: text)
        chatStore.addMessage(userMsg, toChatId: chatId)

        var assistantMsg = Message(role: "assistant", content: "")
        assistantMsg.isStreaming = true
        chatStore.addMessage(assistantMsg, toChatId: chatId)
        streamingMsgId = assistantMsg.id

        appState.isGenerating = true
        let msgId = assistantMsg.id
        let isFirstUserMessage = messages.filter { $0.role == "user" }.count == 1

        generationTask = Task {
            do {
                let engine = EngineService.shared
                let systemPrompt = chat?.projectId.flatMap { pid in
                    chatStore.projects.first { $0.id == pid }?.systemPrompt
                }

                let engineLoaded = await engine.isLoaded
                let enginePath = await engine.currentModelPath
                if !engineLoaded || enginePath != modelStore.activeModelPath {
                    let config = EngineConfig(
                        modelPath: modelStore.activeModelPath,
                        contextSize: Int32(UserDefaults.standard.integer(forKey: "es_ctx_size").nonZeroOr(4096)),
                        temperature: Float(UserDefaults.standard.double(forKey: "es_temperature").nonZeroOr(0.7))
                    )
                    try await engine.load(config: config) { _ in }
                }

                let stream: AsyncThrowingStream<String, Error>
                if isFirstUserMessage {
                    stream = await engine.generate(systemPrompt: systemPrompt, userText: text)
                } else {
                    stream = await engine.continueConversation(userText: text)
                }

                for try await piece in stream {
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        chatStore.appendToMessage(id: msgId, inChatId: chatId, piece: piece)
                    }
                }
            } catch is CancellationError {
                // User cancelled — keep whatever was generated
            } catch {
                await MainActor.run {
                    chatStore.appendToMessage(id: msgId, inChatId: chatId,
                                              piece: "\n_Error: \(error.localizedDescription)_")
                }
            }

            await MainActor.run {
                chatStore.finishMessage(id: msgId, inChatId: chatId)
                streamingMsgId = nil
                appState.isGenerating = false
            }
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        Task { @EngineActor in EngineService.shared.cancel() }
        if let msgId = streamingMsgId {
            chatStore.finishMessage(id: msgId, inChatId: chatId)
        }
        streamingMsgId = nil
        appState.isGenerating = false
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("bottom", anchor: .bottom)
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
