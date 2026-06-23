import SwiftUI
import AppKit

struct ModelBrowserView: View {
    @EnvironmentObject var modelStore: LocalModelStore
    @StateObject private var downloader = ModelDownloader.shared
    @StateObject private var hf         = HuggingFaceService.shared
    @StateObject private var scanner    = HardwareScanner.shared

    @State private var searchText = ""
    @State private var showFilePicker = false
    @State private var installedExpanded = false

    private var maxModelSizeGB: Double {
        guard let info = scanner.info else { return 8.0 }
        return max(2.0, Double(info.totalRAMGB) * 0.7)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                    TextField("Search HuggingFace models...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .onSubmit {
                            Task { await hf.search(query: searchText, maxSizeGB: maxModelSizeGB) }
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                Button { showFilePicker = true } label: {
                    Label("Add file", systemImage: "plus")
                        .font(.body)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.bordered)
                .help("Add a local .gguf model file from disk")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Installed models
            if !modelStore.models.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.none) {
                            installedExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .rotationEffect(.degrees(installedExpanded ? 90 : 0))
                            Text("Installed")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if installedExpanded {
                        installedContent
                            .padding(.horizontal, 16)
                    }
                }

                Divider()
            }

            // Available models
            ScrollView {
                LazyVStack(spacing: 8) {
                    if let info = scanner.info {
                        HStack(spacing: 6) {
                            Image(systemName: "memorychip")
                                .foregroundStyle(.secondary)
                            Text("\(info.chipName) \u{00b7} \(info.totalRAMGB) GB — recommended up to \(info.recommendedTier.rawValue)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }

                    if hf.isFetching {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Searching HuggingFace...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 24)
                    } else {
                        let ram = scanner.info?.totalRAMGB ?? 999
                        // Show everything found; sort runnable-here first, then too-big,
                        // then unsupported. Nothing is hidden — just flagged.
                        let sorted = hf.models.sorted { a, b in
                            func rank(_ m: HFModelEntry) -> Int {
                                switch m.availability(ramGB: ram) {
                                case .available: return 0; case .tooBig: return 1
                                case .unsupported: return 2; case .noBuild: return 3
                                }
                            }
                            return rank(a) == rank(b) ? a.downloads > b.downloads : rank(a) < rank(b)
                        }
                        if sorted.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 28, weight: .light))
                                    .foregroundStyle(.tertiary)
                                Text(searchText.isEmpty
                                     ? "Search HuggingFace for a model."
                                     : "No GGUF found for “\(searchText)”.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("The engine runs GGUF builds of llama / qwen2 models. Paste a repo id or a name (e.g. “qwen”, “llama”, “VibeThinker”).")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                        } else {
                            ForEach(sorted) { model in
                                ModelRow(model: model, ramGB: ram)
                                    .environmentObject(downloader)
                                    .environmentObject(modelStore)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
        }
        .onAppear {
            if scanner.info == nil { scanner.scan() }
            // Reset search when settings reopen
            searchText = ""
            hf.resetToCurated()
        }
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

    // MARK: - Installed

    private var installedContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(modelStore.models) { model in
                let archOK = modelStore.isCompatible(model.path)
                let complete = modelStore.shardsComplete(model.path)
                let usable = archOK && complete
                HStack(spacing: 10) {
                    ProviderIconView(modelName: model.name, size: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.name).font(.body)
                        HStack(spacing: 6) {
                            Text("\(model.quantization)  \u{00b7}  \(model.sizeString)")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(modelStore.arch(for: model.path))
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background((usable ? Color.green : Color.orange).opacity(0.15),
                                             in: Capsule())
                                .foregroundStyle(usable ? Color.green : Color.orange)
                            if !archOK {
                                Text("not supported").font(.caption2).foregroundStyle(.orange)
                            } else if !complete {
                                Text("incomplete shards").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                    }
                    Spacer()
                    Button { modelStore.remove(model) } label: {
                        Image(systemName: "trash")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
                .opacity(usable ? 1 : 0.6)
            }
        }
    }
}

// MARK: - ModelRow

private struct ModelRow: View {
    let model: HFModelEntry
    var ramGB: Int = 999
    @EnvironmentObject var downloader: ModelDownloader
    @EnvironmentObject var modelStore: LocalModelStore

    private var state: DownloadState { downloader.states[model.id] ?? .idle }
    private var isInstalled: Bool { downloader.localPath(for: model) != nil }
    private var availability: HFModelEntry.Availability { model.availability(ramGB: ramGB) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HFAvatarView(repoId: model.repoId, size: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // Full HuggingFace repo id (org/name), as shown on the site.
                    Text(model.repoId)
                        .font(.body)
                        .lineLimit(1).truncationMode(.middle)
                    Text(model.quantization)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1),
                                     in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(Color.accentColor)
                }
                // Official / community badge
                HStack(spacing: 4) {
                    Image(systemName: model.isOfficial ? "checkmark.seal.fill" : "person.crop.circle")
                        .font(.caption2)
                        .foregroundStyle(model.isOfficial ? Color.blue : Color.secondary)
                    Text(model.isOfficial ? "official" : "community")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 12) {
                    Label("\(model.sizeGB, specifier: "%.1f") GB", systemImage: "internaldrive")
                    Label("\(model.downloads.abbreviated)", systemImage: "arrow.down.circle")
                    Label("\(model.likes.abbreviated)", systemImage: "heart")
                    availabilityBadge
                }
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            actionButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5),
                     in: RoundedRectangle(cornerRadius: 10))
        .opacity(availability == .available || isInstalled ? 1 : 0.6)
    }

    @ViewBuilder
    private var availabilityBadge: some View {
        switch availability {
        case .available: EmptyView()
        case .tooBig(let need):
            Text("Needs \(need) GB").font(.caption2.weight(.medium))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color.orange.opacity(0.15), in: Capsule()).foregroundStyle(.orange)
        case .unsupported:
            Text("Unsupported").font(.caption2.weight(.medium))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color.red.opacity(0.15), in: Capsule()).foregroundStyle(.red)
        case .noBuild:
            Text("No GGUF").font(.caption2.weight(.medium))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15), in: Capsule()).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch state {
        case .idle:
            if model.isPlaceholder {
                // No GGUF to download — link out to the model page instead.
                Button { NSWorkspace.shared.open(model.pageURL) } label: {
                    Image(systemName: "arrow.up.right.square").font(.title3)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("No GGUF build — open on HuggingFace")
            } else if isInstalled {
                Text("Installed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if availability != .available {
                // Too big for this Mac, or an architecture the engine can't run.
                Image(systemName: "nosign")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .help(availability == .unsupported
                          ? "This architecture isn't supported by the engine."
                          : "This model needs more memory than this Mac has.")
            } else {
                Button { downloader.download(model) } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

        case .downloading(let p):
            VStack(spacing: 3) {
                ProgressView(value: p)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                Text("\(Int(p * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .onTapGesture { downloader.cancel(model) }

        case .done:
            Text("Installed")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .failed:
            Button { downloader.download(model) } label: {
                Image(systemName: "exclamationmark.circle")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Number formatting

private extension Int {
    var abbreviated: String {
        if self >= 1_000_000 { return "\(self / 1_000_000)M" }
        if self >= 1_000 { return "\(self / 1_000)K" }
        return "\(self)"
    }
}
