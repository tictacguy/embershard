import SwiftUI
import AppKit

// Pomme — a macOS assistant (Beta). Deliberately simple and predictable: the
// model does ONE thing per turn — pick the right tool for your request — and
// everything else is plain Swift. Any change to your files is shown as a preview
// you accept, decline, or adjust. One tool per message keeps it stable: for a
// follow-up, just ask again. Deletes go to the Trash.
struct MacHelperChatView: View {
    let chatId: UUID

    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var modelStore: LocalModelStore
    @EnvironmentObject var appState: AppState

    @State private var input = ""
    @State private var busy = false
    @State private var loadingModel = false
    @State private var warmup = ""
    @State private var task: Task<Void, Never>?
    @State private var preview: PreviewInfo?
    @State private var decisionCont: CheckedContinuation<Decision, Never>?
    @State private var showTools = false
    @State private var attachments: [URL] = []
    @AppStorage("es_show_token_info") private var showTokenInfo: Bool = false

    enum Decision { case accept, decline }
    struct PreviewInfo: Identifiable { let id = UUID(); let plan: MacActionPlan }

    static let appIcon = "apple.logo"

    private var chat: Chat? { chatStore.chat(id: chatId) }
    private var messages: [Message] { chat?.messages ?? [] }
    private var modelPath: String {
        let p = chat?.modelPath ?? ""; return p.isEmpty ? modelStore.activeModelPath : p
    }
    private var modelName: String { modelStore.models.first { $0.path == modelPath }?.name ?? "Model" }

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                capabilities
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(messages) { msg in messageView(msg) }
                        }
                        .padding(.vertical, 16).padding(.horizontal, 14)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                }
            }
            if !attachments.isEmpty { attachmentBar }
            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showTools) { toolsSheet }
        .onDisappear { cancel() }
    }

    // ── Empty state ──────────────────────────────────────────────────────────
    private var capabilities: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: Self.appIcon).font(.title2)
                        Text("Pomme").font(.title2.weight(.semibold))
                        Text("BETA").font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18), in: Capsule()).foregroundStyle(.orange)
                    }
                    Text("Describe one thing you want done on your Mac. I'll pick the right tool and, for anything that changes files, show you a preview to approve first. Deletes go to the Trash.")
                        .font(.callout).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                        ForEach(MacTool.all) { tool in
                            HStack(spacing: 11) {
                                Image(systemName: tool.icon).font(.system(size: 18))
                                    .foregroundStyle(tool.destructive ? .orange : appState.accentColor).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tool.title).font(.body.weight(.medium))
                                    Text(tool.blurb).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    Text("Try: “tidy my desktop”, “find files called invoice”, “what's taking space on my Mac?”, “move report.pdf to ~/Documents”.")
                        .font(.footnote).foregroundStyle(.tertiary).padding(.top, 2)
                }
                .padding(24).frame(maxWidth: 760)
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .center)
            }
        }
    }

    // ── Messages ───────────────────────────────────────────────────────────────
    @ViewBuilder
    private func messageView(_ msg: Message) -> some View {
        if msg.role == "user" {
            HStack {
                Spacer(minLength: 60)
                VStack(alignment: .trailing, spacing: 6) {
                    if !msg.fileResults.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(msg.fileResults, id: \.self) { path in
                                HStack(spacing: 5) {
                                    FileIconView(path: path, size: 15)
                                    Text((path as NSString).lastPathComponent).font(.caption).lineLimit(1)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(Color(NSColor.controlBackgroundColor), in: Capsule())
                                .overlay(Capsule().stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
                            }
                        }
                    }
                    if !msg.content.isEmpty {
                        Text(msg.content).font(.body)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(appState.accentColor, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.white)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    ProviderIconView(modelName: msg.modelName, size: 16)
                    Text(msg.modelName.isEmpty ? "Model" : msg.modelName)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
                if msg.content.isEmpty && msg.isStreaming && preview == nil {
                    HStack(spacing: 8) {
                        TypingIndicator()
                        Text(loadingModel ? warmup : "Thinking…").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                if !msg.agentSteps.isEmpty {
                    AgentStepsView(steps: msg.agentSteps, activeStage: msg.isStreaming ? msg.agentStageName : nil)
                }
                if !msg.content.isEmpty { MarkdownText(msg.content).textSelection(.enabled) }
                if !msg.fileResults.isEmpty { FileResults(paths: msg.fileResults, accent: appState.accentColor) }
                if msg.isStreaming, let p = preview { confirmCard(p) }
                if !msg.isStreaming && showTokenInfo && msg.tokenCount > 0 {
                    ContextUsageBadge(tokenCount: msg.tokenCount, contextFraction: msg.contextFraction)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // ── Preview card ─────────────────────────────────────────────────────────
    private func confirmCard(_ p: PreviewInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "hand.raised.fill").font(.title3).foregroundStyle(appState.accentColor)
                Text("Proposed action").font(.headline)
            }
            Text(p.plan.confirmText).font(.body).foregroundStyle(.primary)
            planItems(p.plan)
            HStack {
                Spacer()
                Button("Decline") { resolve(.decline) }.buttonStyle(.bordered).controlSize(.large)
                Button("Accept") { resolve(.accept) }.buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
        .padding(16)
        .background(appState.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(appState.accentColor.opacity(0.4), lineWidth: 1.5))
    }

    @ViewBuilder
    private func planItems(_ plan: MacActionPlan) -> some View {
        let rows = previewRows(plan)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.prefix(40).enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 9) {
                        FileIconView(path: r.iconPath, size: 22)
                        Text(r.name).font(.subheadline.weight(.medium)).lineLimit(1)
                        if let dest = r.dest {
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                            if dest == "Trash" {
                                Image(systemName: "trash").font(.subheadline).foregroundStyle(.secondary)
                            } else { FileIconView(path: dest, size: 16) }
                            Text(dest).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if FileManager.default.fileExists(atPath: r.iconPath) { RevealInFinderButton(path: r.iconPath) }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                }
                if rows.count > 40 {
                    Text("+ \(rows.count - 40) more").font(.caption).foregroundStyle(.tertiary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                }
            }
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private struct PreviewRow { let iconPath: String; let name: String; let dest: String? }
    private func previewRows(_ plan: MacActionPlan) -> [PreviewRow] {
        switch plan.kind {
        case .move:  return plan.moves.map { PreviewRow(iconPath: $0.from, name: ($0.from as NSString).lastPathComponent, dest: ($0.to as NSString).deletingLastPathComponent) }
        case .trash: return plan.trashPaths.map { PreviewRow(iconPath: $0, name: ($0 as NSString).lastPathComponent, dest: "Trash") }
        case .mkdir: return [PreviewRow(iconPath: plan.mkdirPath, name: (plan.mkdirPath as NSString).lastPathComponent, dest: (plan.mkdirPath as NSString).deletingLastPathComponent)]
        case .quitApp: return []
        }
    }

    private func resolve(_ d: Decision) {
        preview = nil
        let c = decisionCont; decisionCont = nil
        c?.resume(returning: d)
    }

    // ── Attachments ──────────────────────────────────────────────────────────
    private var attachmentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments, id: \.self) { url in
                    HStack(spacing: 6) {
                        FileIconView(path: url.path, size: 16)
                        Text(url.lastPathComponent).font(.caption).lineLimit(1)
                        Button { attachments.removeAll { $0 == url } } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
            .padding(.horizontal, 16).padding(.top, 6)
        }
    }

    private func attachPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Link a file or folder for Pomme"
        guard panel.runModal() == .OK else { return }
        for u in panel.urls where !attachments.contains(u) { attachments.append(u) }
    }

    // ── Input ──────────────────────────────────────────────────────────────────
    private var inputBar: some View {
        ChatInputView(
            text: $input,
            isGenerating: busy,
            models: modelStore.compatibleModels,
            activeModelPath: modelPath,
            skills: [],
            activeSkillId: nil,
            onModelChange: { m in
                modelStore.setActive(m)
                if var c = chat { c.modelPath = m.path; chatStore.updateChat(c) }
            },
            onSkillChange: { _ in },
            onSend: { if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { send() } },
            onCancel: cancel,
            showSkillPicker: false,
            onShowTools: messages.isEmpty ? nil : { showTools = true },
            onAttach: { attachPath() }
        )
    }

    // ── Turn: route → run one tool → preview/apply (deterministic) ──────────────
    private func send() {
        guard !busy else { return }
        let request = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        let attached = attachments
        input = ""; attachments = []

        var um = Message(role: "user", content: request)
        um.fileResults = attached.map(\.path)
        chatStore.addMessage(um, toChatId: chatId)
        if chat?.title == "New chat" { chatStore.setChatTitle(id: chatId, title: String(request.prefix(40))) }
        let msgId = startAssistant()
        busy = true; loadingModel = true
        warmup = EngineUI.warmupMessages.randomElement() ?? "Warming up the engine..."

        let path = modelPath
        let nCtx = Int32(UserDefaults.standard.integer(forKey: "es_ctx_size").nonZeroOr(8192))
        let kvQuant = Int32(UserDefaults.standard.integer(forKey: "es_kv_quant"))
        let attachCtx = attached.isEmpty ? "" : "Attached: " + attached.map(\.path).joined(separator: ", ") + "\n"

        task = Task { @MainActor in
            let loaded = await NativeEngine.shared.ensureLoaded(path: path, nCtx: nCtx, kvQuant: kvQuant)
            loadingModel = false
            guard loaded else { finishNote(msgId, "Couldn't load the model."); busy = false; return }

            // ONE model call: which tool?
            let raw = await NativeEngine.shared.complete(system: MacAgent.resolveSystem(),
                                                         user: attachCtx + "Request: \(request)", maxTokens: 110)
            if Task.isCancelled { endTurn(msgId); return }

            switch MacAgent.parse(raw) {
            case .action(let toolId, var args):
                fillFromAttachment(&args, toolId: toolId, attached: attached)
                await runOneTool(toolId, args, msgId: msgId)
            case .final:
                // No tool needed → a short conversational reply (only place the model writes prose).
                _ = await streamReply(into: msgId, user: "User: \(request)")
            }
            endTurn(msgId)
        }
    }

    private func runOneTool(_ toolId: MacToolID, _ args: MacAgent.Args, msgId: UUID) async {
        let tool = MacTool.by(toolId)
        chatStore.beginAgentStep(msgId: msgId, inChatId: chatId, title: tool.title, icon: tool.icon)
        chatStore.setAgentStage(msgId: msgId, inChatId: chatId, stageName: tool.title)

        let result: MacToolResult
        do { result = try await compute(toolId, args, msgId: msgId) }
        catch {
            chatStore.setAgentStepContent(msgId: msgId, inChatId: chatId, content: "⚠️ \(error.localizedDescription)")
            chatStore.setAgentStage(msgId: msgId, inChatId: chatId, stageName: nil)
            chatStore.appendToMessage(id: msgId, inChatId: chatId, piece: error.localizedDescription)
            return
        }
        chatStore.setAgentStepContent(msgId: msgId, inChatId: chatId, content: result.summary)
        chatStore.setAgentStage(msgId: msgId, inChatId: chatId, stageName: nil)

        guard let plan = result.plan else {
            // Read-only: deterministic summary + collapsible results. No model prose.
            chatStore.appendToMessage(id: msgId, inChatId: chatId, piece: result.summary)
            chatStore.setMessageFileResults(msgId: msgId, inChatId: chatId, paths: result.files.map(\.path))
            return
        }

        switch await askDecision(plan) {
        case .accept:
            chatStore.beginAgentStep(msgId: msgId, inChatId: chatId,
                                     title: plan.kind == .trash ? "Moving to Trash" : "Applying",
                                     icon: plan.kind == .trash ? "trash" : "folder")
            chatStore.setAgentStage(msgId: msgId, inChatId: chatId, stageName: plan.kind == .trash ? "Moving to Trash" : "Applying")
            let n = await apply(plan, msgId: msgId)
            chatStore.setAgentStage(msgId: msgId, inChatId: chatId, stageName: nil)
            chatStore.appendToMessage(id: msgId, inChatId: chatId, piece: "✓ \(applied(plan, n))")
        case .decline:
            chatStore.appendToMessage(id: msgId, inChatId: chatId, piece: "Okay — I won't make that change.")
        }
    }

    // If the tool needs a path/source and the model left it empty, use an attachment.
    private func fillFromAttachment(_ a: inout MacAgent.Args, toolId: MacToolID, attached: [URL]) {
        guard let first = attached.first?.path else { return }
        switch toolId {
        case .tidyFolder, .organizeByDate, .largestFiles, .folderSizes, .findDuplicates, .recentFiles:
            if a.path.isEmpty { a.path = first }
        case .moveItem:
            if a.source.isEmpty { a.source = first }
        case .createFolder:
            if a.path.isEmpty { a.path = first }
        default: break
        }
    }

    private func endTurn(_ msgId: UUID) {
        Task { @MainActor in
            let used = await NativeEngine.shared.contextUsed
            let cap = await NativeEngine.shared.contextMax
            chatStore.finishMessage(id: msgId, inChatId: chatId,
                                    tokenCount: used, contextFraction: cap > 0 ? Double(used) / Double(cap) : 0)
            busy = false
        }
    }

    // Stream a short conversational reply into the message body.
    @discardableResult
    private func streamReply(into msgId: UUID, user: String) async -> String {
        var acc = ""
        do {
            for try await piece in await NativeEngine.shared.completeStream(system: MacAgent.chatSystem(), user: user, maxTokens: 220) {
                if Task.isCancelled { break }
                acc += piece
                chatStore.appendToMessage(id: msgId, inChatId: chatId, piece: piece)
            }
        } catch {}
        return acc
    }

    // ── Tool execution (off the main actor, cancellable) ────────────────────────
    private func compute(_ id: MacToolID, _ a: MacAgent.Args, msgId: UUID) async throws -> MacToolResult {
        let prog: @Sendable (String) -> Void = { line in
            DispatchQueue.main.async { chatStore.setAgentStepContent(msgId: msgId, inChatId: chatId, content: line) }
        }
        if id == .quitApp { return try MacToolbox.quitApp(name: a.name) }
        let home = MacToolbox.home
        let worker = Task.detached(priority: .userInitiated) { () throws -> MacToolResult in
            switch id {
            case .findFiles:
                let roots = a.path.isEmpty ? [home] : [MacToolbox.expand(a.path)]
                return try MacToolbox.find(query: a.query.isEmpty ? a.name : a.query, roots: roots, progress: prog)
            case .largestFiles:    return try MacToolbox.largest(root: a.path.isEmpty ? home : MacToolbox.expand(a.path), progress: prog)
            case .largestOnMac:    return try MacToolbox.largestEverywhere(progress: prog)
            case .folderSizes:     return try MacToolbox.folderSizes(root: a.path.isEmpty ? home : MacToolbox.expand(a.path), progress: prog)
            case .recentFiles:     return try MacToolbox.recent(root: a.path.isEmpty ? home : MacToolbox.expand(a.path), days: a.days ?? 7, progress: prog)
            case .scanThreats:     return try MacToolbox.scanThreats(progress: prog)
            case .heaviestApps:    return try MacToolbox.heaviestApps(progress: prog)
            case .tidyDesktop:     return try MacToolbox.tidy(folder: home.appendingPathComponent("Desktop"), progress: prog)
            case .tidyFolder:      return try MacToolbox.tidy(folder: MacToolbox.expand(a.path), progress: prog)
            case .organizeByDate:  return try MacToolbox.organizeByDate(folder: MacToolbox.expand(a.path), progress: prog)
            case .findDuplicates:  return try MacToolbox.duplicates(root: a.path.isEmpty ? home : MacToolbox.expand(a.path), progress: prog)
            case .cleanOldDownloads: return try MacToolbox.cleanOldDownloads(days: a.days ?? 30, progress: prog)
            case .moveItem:        return try MacToolbox.moveItem(source: a.source, destination: a.destination)
            case .createFolder:    return try MacToolbox.createFolder(path: a.path)
            case .quitApp:         return MacToolResult(summary: "")
            }
        }
        // Propagate cancellation so a long scan stops when the user hits Stop.
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    private func apply(_ plan: MacActionPlan, msgId: UUID) async -> Int {
        let prog: @Sendable (String) -> Void = { line in
            DispatchQueue.main.async { chatStore.setAgentStepContent(msgId: msgId, inChatId: chatId, content: line) }
        }
        switch plan.kind {
        case .quitApp: return await MacToolbox.quitRunning(named: plan.appName) ? 1 : 0
        case .mkdir:   return MacToolbox.mkdir(plan.mkdirPath) ? 1 : 0
        case .move:    return await Task.detached(priority: .userInitiated) { MacToolbox.applyMoves(plan.moves, progress: prog) }.value
        case .trash:   return await Task.detached(priority: .userInitiated) { MacToolbox.trash(plan.trashPaths, progress: prog) }.value
        }
    }

    private func applied(_ plan: MacActionPlan, _ n: Int) -> String {
        switch plan.kind {
        case .trash:   return "Moved \(n) item(s) to the Trash."
        case .mkdir:   return "Created the folder."
        case .quitApp: return "Quit \(plan.appName)."
        case .move:    return "Moved \(n) file(s)."
        }
    }

    private func askDecision(_ plan: MacActionPlan) async -> Decision {
        await withCheckedContinuation { cont in decisionCont = cont; preview = PreviewInfo(plan: plan) }
    }

    // ── Tools sheet ──────────────────────────────────────────────────────────
    private var toolsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("What Pomme can do").font(.headline)
                Spacer()
                Button("Done") { showTools = false }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(MacTool.all) { tool in
                        HStack(spacing: 11) {
                            Image(systemName: tool.icon).font(.system(size: 17))
                                .foregroundStyle(tool.destructive ? .orange : appState.accentColor).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tool.title).font(.body.weight(.medium))
                                Text(tool.blurb).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if tool.destructive { Text("asks first").font(.caption2).foregroundStyle(.orange) }
                        }
                        .padding(10).background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 460, height: 520)
    }

    // ── Helpers ──────────────────────────────────────────────────────────────
    private func addMessage(role: String, content: String) {
        chatStore.addMessage(Message(role: role, content: content), toChatId: chatId)
        if chat?.title == "New chat", role == "user" {
            chatStore.setChatTitle(id: chatId, title: String(content.prefix(40)))
        }
    }
    private func startAssistant() -> UUID {
        var m = Message(role: "assistant", modelName: modelName); m.isStreaming = true
        chatStore.addMessage(m, toChatId: chatId)
        return m.id
    }
    private func finishNote(_ msgId: UUID, _ text: String) {
        chatStore.appendToMessage(id: msgId, inChatId: chatId, piece: text)
        chatStore.finishMessage(id: msgId, inChatId: chatId)
    }
    private func cancel() {
        task?.cancel()
        decisionCont?.resume(returning: .decline); decisionCont = nil; preview = nil
        NativeEngine.shared.requestCancel()
        busy = false; loadingModel = false
    }
}

// Collapsed-by-default list of read-only file results (so it never feels bulky).
private struct FileResults: View {
    let paths: [String]
    let accent: Color
    @State private var expanded = false

    // Size · created · kind, read live from disk (so it survives reloads).
    static func info(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let v = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .isDirectoryKey, .totalFileAllocatedSizeKey])
        var parts: [String] = []
        if v?.isDirectory == true {
            parts.append("Folder")
        } else if let s = v?.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(s), countStyle: .file))
        }
        if let created = v?.creationDate {
            let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
            parts.append("created \(df.string(from: created))")
        }
        let ext = (path as NSString).pathExtension
        if !ext.isEmpty { parts.append(ext.uppercased()) }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("\(paths.count) result\(paths.count == 1 ? "" : "s")").font(.subheadline.weight(.medium))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 8)
            if expanded {
                ForEach(Array(paths.prefix(80)), id: \.self) { path in
                    HStack(spacing: 8) {
                        FileIconView(path: path, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text((path as NSString).lastPathComponent).font(.subheadline).lineLimit(1)
                            Text(Self.info(for: path)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        RevealInFinderButton(path: path)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    Divider().opacity(0.3)
                }
                if paths.count > 80 {
                    Text("+ \(paths.count - 80) more").font(.caption).foregroundStyle(.tertiary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
    }
}
