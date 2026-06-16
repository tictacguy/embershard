import SwiftUI

// Shared bits of engine UI reused across Standard chat and Arena.
enum EngineUI {
    static let warmupMessages = [
        "Warming up the engine...",
        "Loading model into Metal...",
        "Firing up the cores...",
        "Waking up the silicon...",
    ]

    static func contextColor(_ fraction: Double) -> Color {
        if fraction < 0.5 { return .green }
        if fraction < 0.8 { return .orange }
        return .red
    }
}

// Three pulsing dots — the engine "thinking" indicator.
struct EngineDots: View {
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(0.3 + 0.7 * abs(sin(phase + Double(i) * 0.6)))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                phase = .pi
            }
        }
    }
}

// Small ring + "N tokens" footer (context usage), matching the chat bubble.
struct ContextUsageBadge: View {
    let tokenCount: Int
    let contextFraction: Double
    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: contextFraction)
                    .stroke(EngineUI.contextColor(contextFraction), lineWidth: 2)
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)
            Text("\(tokenCount) tokens")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
