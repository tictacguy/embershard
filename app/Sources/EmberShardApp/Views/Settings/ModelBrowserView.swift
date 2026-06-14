import SwiftUI

struct ModelBrowserView: View {
    @EnvironmentObject var modelStore: LocalModelStore
    @StateObject private var downloader  = ModelDownloader.shared
    @StateObject private var hf          = HuggingFaceService.shared
    @StateObject private var scanner     = HardwareScanner.shared

    @State private var filterByRAM = true
    @State private var showFilePicker = false

    private var visibleModels: [HFModelEntry] {
        guard filterByRAM, let info = scanner.info else { return hf.models }
        return hf.models(forRAMGB: info.totalRAMGB)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Toggle("Show compatible only", isOn: $filterByRAM)
                    .toggleStyle(.checkbox)
                    .font(.subheadline)
                Spacer()
                Button {
                    showFilePicker = true
                } label: {
                    Label("Add local file…", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Installed models
            if !modelStore.models.isEmpty {
                installedSection
                Divider()
            }

            // Catalog
            ScrollView {
                LazyVStack(spacing: 8, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(visibleModels) { model in
                            ModelRow(model: model)
                                .environmentObject(downloader)
                                .environmentObject(modelStore)
                        }
                    } header: {
                        Text("Available models")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(.bar)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .onAppear { if scanner.info == nil { scanner.scan() } }
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.init(filenameExtension: "gguf")!]) { result in
            if case .success(let url) = result {
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attrs?[.size] as? Int64) ?? 0
                let lm = LocalModel(
                    name: url.deletingPathExtension().lastPathComponent,
                    path: url.path,
                    sizeBytes: size,
                    quantization: ModelDownloader.parseQuantization(from: url.lastPathComponent)
                )
                modelStore.add(lm)
                if modelStore.activeModelPath.isEmpty { modelStore.setActive(lm) }
            }
        }
    }

    // MARK: - Installed section

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Installed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)

            ForEach(modelStore.models) { model in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.name).font(.subheadline.weight(.medium))
                        Text("\(model.quantization)  ·  \(model.sizeString)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if modelStore.activeModelPath == model.path {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        Button("Set active") { modelStore.setActive(model) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Button(role: .destructive) { modelStore.remove(model) } label: {
                        Image(systemName: "trash").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - ModelRow

private struct ModelRow: View {
    let model: HFModelEntry
    @EnvironmentObject var downloader: ModelDownloader
    @EnvironmentObject var modelStore: LocalModelStore

    private var state: DownloadState { downloader.states[model.id] ?? .idle }
    private var isInstalled: Bool { downloader.localPath(for: model) != nil }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            Image(systemName: "brain")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color(NSColor.controlBackgroundColor),
                             in: RoundedRectangle(cornerRadius: 8))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.name).font(.subheadline.weight(.semibold))
                    Text(model.quantization)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1),
                                     in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(Color.accentColor)
                }
                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Label("\(model.sizeGB, specifier: "%.1f") GB", systemImage: "internaldrive")
                    Label("\(model.minRAMGB) GB RAM min", systemImage: "memorychip")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            // Action
            actionButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5),
                     in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch state {
        case .idle:
            if isInstalled {
                Button("Active") {}
                    .buttonStyle(.bordered)
                    .disabled(true)
                    .controlSize(.small)
            } else {
                Button {
                    downloader.download(model)
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

        case .downloading(let p):
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: p)
                    .progressViewStyle(.linear)
                    .frame(width: 80)
                HStack(spacing: 6) {
                    Text("\(Int(p * 100))%")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("Cancel") { downloader.cancel(model) }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

        case .done:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)

        case .failed:
            VStack(alignment: .trailing, spacing: 4) {
                Label("Failed", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.red)
                Button("Retry") { downloader.download(model) }
                    .font(.caption2).buttonStyle(.borderless)
            }
        }
    }
}

