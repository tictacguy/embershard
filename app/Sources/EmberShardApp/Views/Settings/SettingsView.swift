import SwiftUI
import EmberShardBridge

struct SettingsView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case display   = "Display"
        case inference = "Inference"
        case models    = "Models"
        case skills    = "Skills"
        case hardware  = "Hardware"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .display:   return "paintbrush"
            case .inference: return "bolt"
            case .models:    return "square.and.arrow.down"
            case .skills:    return "brain"
            case .hardware:  return "memorychip"
            }
        }
    }

    @State private var tab: Tab = .display

    var body: some View {
        TabView(selection: $tab) {
            DisplaySettingsView()
                .tabItem { Label(Tab.display.rawValue, systemImage: Tab.display.icon) }
                .tag(Tab.display)

            ModelBrowserView()
                .tabItem { Label(Tab.models.rawValue, systemImage: Tab.models.icon) }
                .tag(Tab.models)

            InferenceSettingsView()
                .tabItem { Label(Tab.inference.rawValue, systemImage: Tab.inference.icon) }
                .tag(Tab.inference)

            SkillsSettingsView()
                .tabItem { Label(Tab.skills.rawValue, systemImage: Tab.skills.icon) }
                .tag(Tab.skills)

            HardwareScanView()
                .tabItem { Label(Tab.hardware.rawValue, systemImage: Tab.hardware.icon) }
                .tag(Tab.hardware)
        }
    }
}

// MARK: - Display

private struct DisplaySettingsView: View {
    @AppStorage("es_appearance") private var appearance: String = "system"
    @AppStorage("es_show_token_info") private var showTokenInfo: Bool = false
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Appearance") {
                Picker(selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                } label: {
                    Label("Theme", systemImage: "paintbrush")
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { _, value in applyAppearance(value) }

                HStack {
                    Label("Accent color", systemImage: "paintpalette")
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { appState.accentColor },
                        set: { appState.accentColor = $0 }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44)
                }
            }

            Section("Chat") {
                Toggle(isOn: $showTokenInfo) {
                    Label("Show token count and context usage", systemImage: "number")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { applyAppearance(appearance) }
    }

    private func applyAppearance(_ mode: String) {
        switch mode {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil
        }
    }
}

// MARK: - Inference

private struct InferenceSettingsView: View {
    @AppStorage("es_temperature") private var temperature: Double = 0.7
    @AppStorage("es_top_p") private var topP: Double = 0.95
    @AppStorage("es_ctx_size") private var contextSize: Int = 8192
    @AppStorage("es_max_tokens") private var maxTokens: Int = 2048
    @AppStorage("es_gpu_layers") private var gpuLayers: Int = -1
    @AppStorage("es_threads") private var threads: Int = 0
    @AppStorage("es_batch_size") private var batchSize: Int = 512
    @AppStorage("es_kv_quant") private var kvQuant: Int = 0
    @AppStorage("es_flash_attn") private var flashAttn: Bool = true
    @AppStorage("es_use_mmap") private var useMmap: Bool = true

    var body: some View {
        Form {
            Section("Sampling") {
                HStack {
                    Label("Temperature", systemImage: "thermometer.medium")
                    Spacer()
                    Slider(value: $temperature, in: 0...2, step: 0.05)
                        .frame(width: 160)
                    Text(String(format: "%.2f", temperature))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

                HStack {
                    Label("Top-P", systemImage: "chart.bar")
                    Spacer()
                    Slider(value: $topP, in: 0...1, step: 0.05)
                        .frame(width: 160)
                    Text(String(format: "%.2f", topP))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }

            Section("Context") {
                Picker(selection: $contextSize) {
                    Text("2048").tag(2048)
                    Text("4096").tag(4096)
                    Text("8192").tag(8192)
                    Text("16384").tag(16384)
                    Text("32768").tag(32768)
                    Text("65536").tag(65536)
                } label: {
                    Label("Context size", systemImage: "text.alignleft")
                }
                .pickerStyle(.menu)

                Picker(selection: $maxTokens) {
                    Text("256").tag(256)
                    Text("512").tag(512)
                    Text("1024").tag(1024)
                    Text("2048").tag(2048)
                    Text("4096").tag(4096)
                } label: {
                    Label("Max tokens per response", systemImage: "text.word.spacing")
                }
                .pickerStyle(.menu)
            }

            Section("Compute") {
                HStack {
                    Label("GPU layers", systemImage: "rectangle.3.group.fill")
                    Spacer()
                    TextField("", value: $gpuLayers, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Text("-1 = all")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HStack {
                    Label("CPU threads", systemImage: "cpu")
                    Spacer()
                    TextField("", value: $threads, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Text("0 = auto")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HStack {
                    Label("Batch size", systemImage: "square.grid.3x3")
                    Spacer()
                    Picker("", selection: $batchSize) {
                        Text("128").tag(128)
                        Text("256").tag(256)
                        Text("512").tag(512)
                        Text("1024").tag(1024)
                        Text("2048").tag(2048)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
            }

            Section("Memory") {
                Picker(selection: $kvQuant) {
                    Text("F16 (full)").tag(0)
                    Text("Q8_0 (~50% savings)").tag(1)
                    Text("Q4_0 (~75% savings)").tag(2)
                } label: {
                    Label("KV cache quantization", systemImage: "memorychip")
                }
                .pickerStyle(.menu)

                Toggle(isOn: $flashAttn) {
                    Label("Flash attention", systemImage: "bolt.circle")
                }

                Toggle(isOn: $useMmap) {
                    Label("Memory-mapped loading (mmap)", systemImage: "doc.on.doc")
                }
            }

            Section {
                Text("Changes take effect on next model load.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
