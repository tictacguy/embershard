import SwiftUI

struct SkillsSettingsView: View {
    @StateObject private var store = SkillsStore.shared
    @State private var showNewSkill = false
    @State private var editingSkill: Skill?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Skills define the system prompt and behavior for a chat.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { showNewSkill = true } label: {
                    Label("New Skill", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Skills list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.skills) { skill in
                        SkillRow(skill: skill) {
                            editingSkill = skill
                        } onDelete: {
                            store.remove(id: skill.id)
                        }
                    }
                }
                .padding(12)
            }
        }
        .sheet(isPresented: $showNewSkill) {
            SkillEditorSheet(skill: nil) { newSkill in
                store.add(newSkill)
            }
        }
        .sheet(item: $editingSkill) { skill in
            SkillEditorSheet(skill: skill) { updated in
                store.update(updated)
            }
        }
    }
}

// MARK: - SkillRow

private struct SkillRow: View {
    let skill: Skill
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: skill.icon)
                .font(.title3)
                .foregroundStyle(skill.isBuiltIn ? .blue : .orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(skill.name).font(.body.weight(.medium))
                    if skill.isBuiltIn {
                        Text("Built-in")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.blue)
                    }
                }
                Text(skill.systemPrompt.prefix(80) + (skill.systemPrompt.count > 80 ? "..." : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if !skill.isBuiltIn {
                Button { onEdit() } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button { onDelete() } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5),
                     in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - SkillEditorSheet

private struct SkillEditorSheet: View {
    let skill: Skill?
    let onSave: (Skill) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = "brain"
    @State private var systemPrompt = ""

    private let iconOptions = [
        "brain", "chevron.left.forwardslash.chevron.right", "magnifyingglass",
        "pencil", "book", "lightbulb", "hammer", "paintbrush", "doc.text",
        "globe", "music.note", "chart.bar"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(skill == nil ? "New Skill" : "Edit Skill")
                .font(.title3.weight(.semibold))

            TextField("Skill name", text: $name)
                .textFieldStyle(.roundedBorder)

            // Icon picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Icon").font(.subheadline).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 8), spacing: 8) {
                    ForEach(iconOptions, id: \.self) { ic in
                        Button {
                            icon = ic
                        } label: {
                            Image(systemName: ic)
                                .font(.body)
                                .frame(width: 32, height: 32)
                                .background(icon == ic ? Color.accentColor.opacity(0.15) : Color.clear,
                                             in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(icon == ic ? Color.accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("System Prompt").font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $systemPrompt)
                    .font(.body)
                    .frame(height: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var s = skill ?? Skill(name: name, systemPrompt: systemPrompt)
                    s.name = name
                    s.icon = icon
                    s.systemPrompt = systemPrompt
                    onSave(s)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || systemPrompt.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            if let s = skill {
                name = s.name
                icon = s.icon
                systemPrompt = s.systemPrompt
            }
        }
    }
}
