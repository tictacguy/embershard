import SwiftUI

struct HardwareScanView: View {
    @StateObject private var scanner = HardwareScanner.shared
    @State private var isScanning = false

    var body: some View {
        VStack(spacing: 0) {
            if let info = scanner.info {
                scannedView(info)
            } else {
                placeholderView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(24)
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "memorychip")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(.secondary)
            Text("Scan your hardware to get model recommendations")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                isScanning = true
                scanner.scan()
                isScanning = false
            } label: {
                Label(isScanning ? "Scanning…" : "Scan Hardware", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isScanning)
            Spacer()
        }
    }

    // MARK: - Scanned

    @ViewBuilder
    private func scannedView(_ info: HardwareInfo) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.chipName)
                        .font(.title3.weight(.semibold))
                    Text("Recommended: \(info.recommendedTier.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isScanning = true
                    scanner.scan()
                    isScanning = false
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }

            Divider()

            // Specs grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                SpecCard(label: "Total RAM",
                         value: "\(info.totalRAMGB) GB",
                         icon: "memorychip")
                SpecCard(label: "Available RAM",
                         value: "\(info.availableRAMGB) GB",
                         icon: "chart.bar")
                SpecCard(label: "CPU cores",
                         value: "\(info.cpuCores)",
                         icon: "cpu")
                SpecCard(label: "Metal GPU",
                         value: "Enabled",
                         icon: "bolt")
            }

            Divider()

            // Capability bar
            VStack(alignment: .leading, spacing: 8) {
                Text("Model size capacity")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    ForEach(tiers, id: \.label) { tier in
                        tierCell(tier, current: info.recommendedTier)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private struct Tier { let label: String; let tier: HardwareInfo.ModelTier; let color: Color }

    private var tiers: [Tier] {[
        Tier(label: "3B",  tier: .small,  color: .green),
        Tier(label: "7B",  tier: .mid,    color: .teal),
        Tier(label: "14B", tier: .large,  color: .blue),
        Tier(label: "32B", tier: .xlarge, color: .orange),
        Tier(label: "70B", tier: .xl,     color: .red),
    ]}

    @ViewBuilder
    private func tierCell(_ tier: Tier, current: HardwareInfo.ModelTier) -> some View {
        let isActive = tierIndex(current) >= tierIndex(tier.tier)
        VStack(spacing: 4) {
            Rectangle()
                .fill(isActive ? tier.color : Color(NSColor.separatorColor))
                .frame(height: 8)
            Text(tier.label)
                .font(.caption2)
                .foregroundStyle(isActive ? .primary : .tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func tierIndex(_ t: HardwareInfo.ModelTier) -> Int {
        switch t {
        case .none:   return -1
        case .small:  return 0
        case .mid:    return 1
        case .large:  return 2
        case .xlarge: return 3
        case .xl:     return 4
        }
    }
}

// MARK: - SpecCard

private struct SpecCard: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.headline)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor),
                     in: RoundedRectangle(cornerRadius: 10))
    }
}
