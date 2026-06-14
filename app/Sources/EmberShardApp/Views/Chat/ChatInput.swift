import SwiftUI

struct ChatInputView: View {
    @Binding var text: String
    let isGenerating: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Text field
            ZStack(alignment: .bottomLeading) {
                if text.isEmpty {
                    Text("Message Embershard…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .font(.body)
                    .focused($focused)
                    .frame(minHeight: 36, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .onKeyPress(.return) {
                        if NSEvent.modifierFlags.contains(.shift) { return .ignored }
                        onSend()
                        return .handled
                    }
            }
            .background(Color(NSColor.controlBackgroundColor),
                         in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(focused ? Color.accentColor.opacity(0.5) : Color(NSColor.separatorColor),
                            lineWidth: focused ? 1.5 : 0.5)
            )
            .animation(.easeInOut(duration: 0.15), value: focused)

            // Send / Cancel button
            Button {
                if isGenerating { onCancel() } else { onSend() }
            } label: {
                Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(canSend ? .white : .secondary)
                    .background(
                        canSend ? Color.accentColor : Color(NSColor.controlColor),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: [.command])
            .animation(.easeInOut(duration: 0.15), value: isGenerating)
        }
        .onAppear { focused = true }
    }

    private var canSend: Bool {
        isGenerating || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
