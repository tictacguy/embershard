import Foundation
import EmberShardBridge

// MARK: - HardwareInfo

struct HardwareInfo {
    let chipName: String
    let totalRAMGB: Int
    let availableRAMGB: Int
    let cpuCores: Int
    let recommendedTier: ModelTier

    enum ModelTier: String {
        case none   = "Not supported"
        case small  = "3B models"
        case mid    = "7B models"
        case large  = "14B models"
        case xlarge = "32B models"
        case xl     = "70B models"
    }
}

// MARK: - HardwareScanner

@MainActor
final class HardwareScanner: ObservableObject {
    static let shared = HardwareScanner()

    @Published private(set) var info: HardwareInfo?

    private init() {}

    func scan() {
        let raw = es_get_hw_info()

        let totalGB = Int(raw.total_ram / 1_073_741_824)
        let availGB = Int(raw.available_ram / 1_073_741_824)
        let cores   = Int(raw.cpu_cores)

        let chipRaw = withUnsafeBytes(of: raw.chip) { bytes -> String in
            let ptr = bytes.bindMemory(to: CChar.self).baseAddress!
            return String(cString: ptr)
        }
        let chip = chipRaw.isEmpty ? "Unknown chip" : chipRaw

        let tier: HardwareInfo.ModelTier
        switch totalGB {
        case ..<8:   tier = .none
        case 8..<16: tier = .small
        case 16..<32: tier = .large   // M4 16GB can run 14B Q4
        case 32..<48: tier = .xlarge
        case 48..<64: tier = .xlarge
        default:     tier = .xl
        }

        info = HardwareInfo(
            chipName: chip,
            totalRAMGB: totalGB,
            availableRAMGB: availGB,
            cpuCores: cores,
            recommendedTier: tier
        )
    }
}
