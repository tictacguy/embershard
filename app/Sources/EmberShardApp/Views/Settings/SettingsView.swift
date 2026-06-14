import SwiftUI

struct SettingsView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case general  = "General"
        case models   = "Models"
        case hardware = "Hardware"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general:  "gearshape"
            case .models:   "square.and.arrow.down"
            case .hardware: "memorychip"
            }
        }
    }

    @State private var tab: Tab = .general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsView()
                .tabItem { Label(Tab.general.rawValue, systemImage: Tab.general.icon) }
                .tag(Tab.general)

            ModelBrowserView()
                .tabItem { Label(Tab.models.rawValue, systemImage: Tab.models.icon) }
                .tag(Tab.models)

            HardwareScanView()
                .tabItem { Label(Tab.hardware.rawValue, systemImage: Tab.hardware.icon) }
                .tag(Tab.hardware)
        }
        .frame(width: 600, height: 480)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @EnvironmentObject var modelStore: LocalModelStore
    @State private var temperature: Double = 0.7
    @State private var contextSize: Int = 4096

    var body: some View {
        Form {
            Section("Inference") {
                LabeledContent("Temperature") {
                    HStack {
                        Slider(value: $temperature, in: 0...1, step: 0.05)
                            .frame(width: 160)
                        Text(String(format: "%.2f", temperature))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                LabeledContent("Context size") {
                    Picker("", selection: $contextSize) {
                        Text("2048").tag(2048)
                        Text("4096").tag(4096)
                        Text("8192").tag(8192)
                        Text("16384").tag(16384)
                    }
                    .frame(width: 100)
                    .pickerStyle(.menu)
                }
            }

            Section("Active model") {
                if modelStore.models.isEmpty {
                    Text("No models installed. Go to the Models tab.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Model", selection: Binding(
                        get: { modelStore.activeModelPath },
                        set: { path in
                            if let m = modelStore.models.first(where: { $0.path == path }) {
                                modelStore.setActive(m)
                            }
                        }
                    )) {
                        ForEach(modelStore.models) { m in
                            Text(m.name).tag(m.path)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            temperature = UserDefaults.standard.double(forKey: "es_temperature").nonZero ?? 0.7
            contextSize = UserDefaults.standard.integer(forKey: "es_ctx_size").nonZero ?? 4096
        }
        .onChange(of: temperature) { _, v in UserDefaults.standard.set(v, forKey: "es_temperature") }
        .onChange(of: contextSize) { _, v in UserDefaults.standard.set(v, forKey: "es_ctx_size") }
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
