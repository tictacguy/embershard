import SwiftUI

struct ChatInputView: View {
    @Binding var text: String
    let isGenerating: Bool
    let models: [LocalModel]
    let activeModelPath: String
    let agentMode: Bool
    let skills: [Skill]
    let activeSkillId: UUID?
    let onModelChange: (LocalModel) -> Void
    let onAgentToggle: () -> Void
    let onSkillChange: (UUID?) -> Void
    let onSend: () -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool

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
                // Text area (min 2 lines)
                TextField("Message...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($focused)
                    .lineLimit(2...8)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .onSubmit {
                        if !NSEvent.modifierFlags.contains(.shift) {
                            onSend()
                        }
                    }

                // Bottom toolbar
                HStack(spacing: 8) {
                    // Model selector
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

                    // Skill selector
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

                    // Agent toggle
                    Button { onAgentToggle() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "brain")
                                .font(.caption)
                            Text("Agent")
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            agentMode ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03),
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                        .foregroundStyle(agentMode ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Multi-agent pipeline")

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
                                canSend ? Color.accentColor : Color.secondary.opacity(0.1),
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
                    .stroke(focused ? Color.accentColor.opacity(0.4) : Color(NSColor.separatorColor).opacity(0.5),
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
        .onAppear { focused = true }
    }

    private var canSend: Bool {
        isGenerating || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
