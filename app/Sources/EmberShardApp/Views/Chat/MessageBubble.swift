import SwiftUI

struct MessageBubble: View {
    let message: Message

    var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Role label
                Text(isUser ? "You" : "Embershard")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                // Bubble
                BubbleContent(message: message, isUser: isUser)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

// MARK: - BubbleContent

private struct BubbleContent: View {
    let message: Message
    let isUser: Bool

    var body: some View {
        Group {
            if isUser {
                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if message.content.isEmpty && message.isStreaming {
                        // Typing indicator
                        TypingIndicator()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    } else {
                        MarkdownText(message.content)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                    }
                }
                .background(Color(NSColor.controlBackgroundColor),
                             in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
            }
        }
        .textSelection(.enabled)
    }
}

// MARK: - MarkdownText (simple markdown render)

private struct MarkdownText: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - TypingIndicator

private struct TypingIndicator: View {
    @State private var phase = 0

    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .frame(width: 6, height: 6)
                    .foregroundStyle(phase == i ? Color.primary : Color.secondary)
            }
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}
