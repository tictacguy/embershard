import SwiftUI

struct ChatInputView: View {
    @Binding var text: String
    let isGenerating: Bool
    let models: [LocalModel]
    let activeModelPath: String
    let skills: [Skill]
    let activeSkillId: UUID?
    let onModelChange: (LocalModel) -> Void
    let onSkillChange: (UUID?) -> Void
    let onSend: () -> Void
    let onCancel: () -> Void
    var kindBadge: String? = nil   // "Agentic" chip shown for agent chats
    var showModelPicker: Bool = true   // hidden in Arena (each column is its own model)
    var showSkillPicker: Bool = true   // hidden in the macOS Helper
    // Optional toggle button (planner→executor "Agent", or the helper's "Auto" mode).
    var toggleActive: Bool = false
    var toggleLabel: String = "Agent"
    var toggleIcon: String = "wand.and.stars"
    var onToggle: (() -> Void)? = nil
    var onShowTools: (() -> Void)? = nil   // macOS Helper: list available tools
    var onAttach: (() -> Void)? = nil      // macOS Helper: link a file/folder

    @EnvironmentObject var appState: AppState
    @State private var focused: Bool = false
    @State private var editorHeight: CGFloat = 38

    private var activeModelName: String {
        models.first { $0.path == activeModelPath }?.name ?? "No model"
    }

    private var activeSkillName: String {
        if let id = activeSkillId, let skill = skills.first(where: { $0.id == id }) {
            return skill.name
        }
        return "No skill"
    }

    private var activeSkillIcon: String {
        if let id = activeSkillId, let skill = skills.first(where: { $0.id == id }) {
            return skill.icon
        }
        return "sparkles"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                // Text area (Enter = send, Shift+Enter = newline)
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Message...")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                    ChatTextEditor(text: $text, height: $editorHeight, isFocused: $focused,
                                   onSubmit: { if canSend { onSend() } },
                                   minHeight: 38, maxHeight: 170)
                        .frame(height: editorHeight)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }

                // Bottom toolbar
                HStack(spacing: 8) {
                    // Model selector
                    if showModelPicker {
                        Menu {
                            ForEach(models) { model in
                                Button(model.name) { onModelChange(model) }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                ProviderIconView(modelName: activeModelName, size: 14)
                                Text(activeModelName)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                    }

                    // Skill selector
                    if showSkillPicker {
                        Menu {
                            Button("No skill") { onSkillChange(nil) }
                            Divider()
                            ForEach(skills) { skill in
                                Button { onSkillChange(skill.id) } label: {
                                    Label(skill.name, systemImage: skill.icon)
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: activeSkillIcon)
                                    .font(.caption)
                                    .foregroundStyle(activeSkillId != nil ? .orange : .secondary)
                                Text(activeSkillName)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .foregroundStyle(activeSkillId != nil ? .orange : .primary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                    }

                    // Static chat-kind chip (agentic chats)
                    if let badge = kindBadge {
                        HStack(spacing: 5) {
                            Image(systemName: "wand.and.stars").font(.caption)
                            Text(badge).font(.subheadline)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(appState.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(appState.accentColor)
                    }

                    // Toggle button (Agent pipeline, or helper Auto-mode)
                    if let onToggle {
                        Button(action: onToggle) {
                            HStack(spacing: 5) {
                                Image(systemName: toggleIcon).font(.caption)
                                Text(toggleLabel).font(.subheadline)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(toggleActive ? appState.accentColor.opacity(0.15) : Color.primary.opacity(0.03),
                                        in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(toggleActive ? appState.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    // Attach a file/folder (macOS Helper)
                    if let onAttach {
                        Button(action: onAttach) {
                            HStack(spacing: 5) {
                                Image(systemName: "paperclip").font(.caption)
                                Text("Attach").font(.subheadline)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Link a file or folder")
                    }

                    // Tools list (macOS Helper)
                    if let onShowTools {
                        Button(action: onShowTools) {
                            HStack(spacing: 5) {
                                Image(systemName: "wrench.and.screwdriver").font(.caption)
                                Text("Tools").font(.subheadline)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Send / Stop
                    Button {
                        if isGenerating { onCancel() } else { onSend() }
                    } label: {
                        Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(canSend ? Color.white : Color.secondary)
                            .background(
                                canSend ? appState.accentColor : Color.secondary.opacity(0.1),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
            .background(Color(NSColor.controlBackgroundColor),
                         in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(focused ? appState.accentColor.opacity(0.4) : Color(NSColor.separatorColor).opacity(0.5),
                            lineWidth: focused ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.03), radius: 3, y: 1)

            Text("AI can make mistakes. Verify important information.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var canSend: Bool {
        isGenerating || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// AppKit-backed multiline editor: Enter sends, Shift+Enter inserts a newline.
// Auto-grows between minHeight and maxHeight, then scrolls.
struct ChatTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var isFocused: Bool
    var onSubmit: () -> Void
    let minHeight: CGFloat
    let maxHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = .systemFont(ofSize: NSFont.systemFontSize + 1)
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 0, height: 4)
        tv.textContainer?.lineFragmentPadding = 0
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.textContainer?.widthTracksTextView = true
        context.coordinator.textView = tv
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        context.coordinator.recomputeHeight()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatTextEditor
        weak var textView: NSTextView?
        init(_ p: ChatTextEditor) { parent = p }

        func recomputeHeight() {
            guard let tv = textView, let lm = tv.layoutManager,
                  let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let used = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2
            let clamped = min(max(used, parent.minHeight), parent.maxHeight)
            if abs(clamped - parent.height) > 0.5 {
                DispatchQueue.main.async { self.parent.height = clamped }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            recomputeHeight()
        }

        func textDidBeginEditing(_ notification: Notification) {
            DispatchQueue.main.async { self.parent.isFocused = true }
        }
        func textDidEndEditing(_ notification: Notification) {
            DispatchQueue.main.async { self.parent.isFocused = false }
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    tv.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.onSubmit()
                }
                return true
            }
            return false
        }
    }
}
