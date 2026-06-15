import SwiftUI

struct MessageBubble: View {
    let message: Message
    var modelName: String = "Model"
    var onRegenerate: (() -> Void)? = nil
    @AppStorage("es_show_token_info") private var showTokenInfo: Bool = false
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

    var body: some View {
        Group {
            if isUser {
                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(bubbleColor, in: RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(.white)
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

// MARK: - MarkdownText

private struct MarkdownText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let content):
                    if let attributed = try? AttributedString(markdown: content,
                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(attributed)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(content)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .code(let lang, let content):
                    CodeBlockView(language: lang, code: content)
                }
            }
        }
    }

    private enum Block {
        case text(String)
        case code(String, String) // language, content
    }

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var currentText = ""

        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("```") {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.trimmingCharacters(in: .newlines)))
                    currentText = ""
                }
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.code(lang, codeLines.joined(separator: "\n")))
                i += 1 // skip closing ```
            } else {
                currentText += (currentText.isEmpty ? "" : "\n") + line
                i += 1
            }
        }
        if !currentText.isEmpty {
            blocks.append(.text(currentText.trimmingCharacters(in: .newlines)))
        }
        return blocks
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
                if !language.isEmpty {
                    Text(language)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
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

// MARK: - TypingIndicator

private struct TypingIndicator: View {
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
