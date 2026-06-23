import SwiftUI

struct MessageBubble: View {
    let message: Message
    var modelName: String = "Model"
    var onRegenerate: (() -> Void)? = nil
    @AppStorage("es_show_token_info") private var showTokenInfo: Bool = true
    @EnvironmentObject var appState: AppState

    var isUser: Bool { message.role == "user" }

    private func contextColor(_ fraction: Double) -> Color {
        if fraction < 0.5 { return .green }
        if fraction < 0.8 { return .orange }
        return .red
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 80) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                // Role label with provider icon
                HStack(spacing: 5) {
                    if !isUser {
                        ProviderIconView(modelName: modelName, size: 16)
                    }
                    Text(isUser ? "You" : modelName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                // Agentic pipeline steps (planner / executor), collapsed by default
                if !isUser && !message.agentSteps.isEmpty {
                    AgentStepsView(steps: message.agentSteps,
                                   activeStage: message.isStreaming ? message.agentStageName : nil)
                }

                // Reasoning (<think>) — collapsible; auto-open while still thinking.
                if !isUser && !message.reasoning.isEmpty {
                    ReasoningView(text: message.reasoning,
                                  thinking: message.isStreaming && message.content.isEmpty)
                }

                // Bubble content
                BubbleContent(message: message, isUser: isUser, bubbleColor: appState.accentColor)

                // Action buttons for completed assistant messages
                if !isUser && !message.isStreaming && !message.content.isEmpty {
                    HStack(spacing: 12) {
                        MessageActionButton(title: "Copy", icon: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)
                        }

                        if let onRegenerate {
                            MessageActionButton(title: "Regenerate", icon: "arrow.counterclockwise") {
                                onRegenerate()
                            }
                        }

                        // Token info (configurable)
                        if showTokenInfo && message.tokenCount > 0 {
                            HStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                                    Circle()
                                        .trim(from: 0, to: message.contextFraction)
                                        .stroke(contextColor(message.contextFraction), lineWidth: 2)
                                        .rotationEffect(.degrees(-90))
                                }
                                .frame(width: 14, height: 14)

                                Text("\(message.tokenCount) tokens")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            if !isUser { Spacer(minLength: 80) }
        }
    }
}

// MARK: - MessageActionButton

private struct MessageActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(isHovered ? .primary : .tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isHovered ? Color.primary.opacity(0.06) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - BubbleContent

private struct BubbleContent: View {
    let message: Message
    let isUser: Bool
    var bubbleColor: Color = .accentColor

    // While the planner is running (answer not yet started), the prominent
    // Planning card stands in for the loader, so suppress the empty answer bubble.
    private var showPlanningCardOnly: Bool {
        !isUser && message.isStreaming && message.content.isEmpty
            && message.agentStageName == "Planning" && !message.agentSteps.isEmpty
    }

    var body: some View {
        Group {
            if isUser {
                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(bubbleColor, in: RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(.white)
            } else if showPlanningCardOnly {
                // The prominent Planning card (rendered above) is the sole visible
                // element while the planner works — no empty answer bubble.
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if message.content.isEmpty && message.isStreaming {
                        HStack(spacing: 8) {
                            TypingIndicator()
                            if let stage = message.agentStageName {
                                Text(stage)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    } else {
                        MarkdownText(message.content)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                }
                .background(Color(NSColor.controlBackgroundColor),
                             in: RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
                )
            }
        }
        .textSelection(.enabled)
    }
}

// MARK: - ReasoningView

private struct ReasoningView: View {
    let text: String
    let thinking: Bool
    @State private var expanded = false

    var body: some View {
        let open = expanded || thinking
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } label: {
                HStack(spacing: 7) {
                    Image(systemName: "brain")
                        .font(.subheadline).foregroundStyle(.secondary).frame(width: 18)
                    Text(thinking ? "Thinking…" : "Reasoning")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    if thinking { ProgressView().controlSize(.small).padding(.leading, 2) }
                    Spacer(minLength: 8)
                    if !thinking {
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                            .rotationEffect(.degrees(open ? 90 : 0)).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 9)

            if open {
                Divider().opacity(0.4)
                ScrollView {
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 240)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - MarkdownText

struct MarkdownText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let content):
                    inline(content)
                        .font(headingFont(level))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, level <= 2 ? 4 : 2)
                case .paragraph(let content):
                    inline(content)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                case .bullet(let content):
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").font(.body).foregroundStyle(.secondary)
                        inline(content).font(.body).fixedSize(horizontal: false, vertical: true)
                    }
                case .numbered(let marker, let content):
                    HStack(alignment: .top, spacing: 8) {
                        Text(marker).font(.body.monospacedDigit()).foregroundStyle(.secondary)
                        inline(content).font(.body).fixedSize(horizontal: false, vertical: true)
                    }
                case .rule:
                    Divider()
                case .code(let lang, let content):
                    CodeBlockView(language: lang, code: content)
                }
            }
        }
    }

    // Render inline markdown (**bold**, *italic*, `code`, [links]) within one line.
    private func inline(_ content: String) -> Text {
        if let attributed = try? AttributedString(markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(content)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:  return .title2.weight(.bold)
        case 2:  return .title3.weight(.bold)
        case 3:  return .headline
        default: return .subheadline.weight(.semibold)
        }
    }

    private enum Block {
        case heading(Int, String)
        case paragraph(String)
        case bullet(String)
        case numbered(String, String)
        case rule
        case code(String, String) // language, content
    }

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var para: [String] = []

        func flushPara() {
            if !para.isEmpty {
                blocks.append(.paragraph(para.joined(separator: "\n")))
                para = []
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block
            if trimmed.hasPrefix("```") {
                flushPara()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i]); i += 1
                }
                blocks.append(.code(lang, codeLines.joined(separator: "\n")))
                i += 1
                continue
            }

            // ATX heading: #, ##, ### …
            if let h = headingMatch(trimmed) {
                flushPara()
                blocks.append(.heading(h.level, h.text))
                i += 1; continue
            }

            // Setext underline (==== under a heading) — the text above already
            // carries the emphasis, so drop the underline to avoid literal noise.
            if trimmed.count >= 2 && trimmed.allSatisfy({ $0 == "=" }) {
                i += 1; continue
            }
            // Horizontal rule: a line of only -, *, or _ (3+)
            if trimmed.count >= 3 &&
               (trimmed.allSatisfy { $0 == "-" } ||
                trimmed.allSatisfy { $0 == "*" } ||
                trimmed.allSatisfy { $0 == "_" }) {
                flushPara()
                blocks.append(.rule)
                i += 1; continue
            }

            // Bullet list: -, *, +
            if let b = bulletMatch(trimmed) {
                flushPara()
                blocks.append(.bullet(b))
                i += 1; continue
            }

            // Numbered list: "1. ", "2) " …
            if let n = numberedMatch(trimmed) {
                flushPara()
                blocks.append(.numbered(n.marker, n.text))
                i += 1; continue
            }

            // Blank line ends a paragraph
            if trimmed.isEmpty {
                flushPara()
                i += 1; continue
            }

            para.append(line)
            i += 1
        }
        flushPara()
        return blocks
    }

    private func headingMatch(_ s: String) -> (level: Int, text: String)? {
        guard s.hasPrefix("#") else { return nil }
        var level = 0
        for ch in s { if ch == "#" { level += 1 } else { break } }
        guard level >= 1 && level <= 6 else { return nil }
        let rest = s.dropFirst(level)
        guard rest.first == " " else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private func bulletMatch(_ s: String) -> String? {
        for p in ["- ", "* ", "+ "] where s.hasPrefix(p) {
            return String(s.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func numberedMatch(_ s: String) -> (marker: String, text: String)? {
        var digits = ""
        for ch in s { if ch.isNumber { digits.append(ch) } else { break } }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let after = s.dropFirst(digits.count)
        guard after.first == "." || after.first == ")" else { return nil }
        let rest = after.dropFirst()
        guard rest.first == " " else { return nil }
        return ("\(digits).", rest.trimmingCharacters(in: .whitespaces))
    }
}

// MARK: - Code Block

private struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language and copy button
            HStack {
                Text(language.isEmpty ? "bash" : language)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.03))

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .padding(12)
            }
        }
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Agent pipeline steps

struct AgentStepsView: View {
    let steps: [AgentStep]
    var activeStage: String? = nil   // e.g. "Executing..." while that stage streams

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                // Only the last step is "active" while a stage is streaming, so
                // repeated titles don't all expand at once.
                AgentStepRow(step: step, isActive: activeStage != nil && idx == steps.count - 1)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }
}

private struct AgentStepRow: View {
    let step: AgentStep
    let isActive: Bool
    @State private var expanded = false

    // While the step is generating it shows prominently (large icon/font, the
    // plan streaming live); once done it collapses to a compact, expandable card.
    private var showContent: Bool { isActive || expanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: isActive ? 9 : 8) {
                    Image(systemName: step.icon)
                        .font(isActive ? .title3 : .subheadline)
                        .frame(width: isActive ? 24 : 20)
                    Text(isActive ? "\(step.title)…" : step.title)
                        .font(isActive ? .headline : .subheadline.weight(.semibold))
                    if isActive {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 2)
                    }
                    Spacer(minLength: 8)
                    if !isActive {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                }
                .foregroundStyle(isActive ? .primary : .secondary)
                .padding(.horizontal, isActive ? 14 : 12)
                .padding(.vertical, isActive ? 11 : 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isActive)

            if showContent && !(step.content.isEmpty && !isActive) {
                Text(step.content.isEmpty ? "…" : step.content)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, isActive ? 14 : 10)
                    .padding(.bottom, isActive ? 12 : 8)
            }
        }
        .background(Color.primary.opacity(isActive ? 0.05 : 0.03),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08),
                        lineWidth: 1)
        )
        .frame(maxWidth: isActive ? .infinity : nil, alignment: .leading)
    }
}

// MARK: - TypingIndicator

struct TypingIndicator: View {
    @State private var phase = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .frame(width: 7, height: 7)
                    .foregroundStyle(phase == i ? Color.primary : Color.secondary.opacity(0.4))
                    .animation(.easeInOut(duration: 0.3), value: phase)
            }
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}
