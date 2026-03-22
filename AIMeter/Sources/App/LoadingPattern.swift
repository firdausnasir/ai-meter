import Foundation

enum LoadingPattern: String, CaseIterable {
    case fade = "fade"           // Smooth sinusoidal fade
    case knightRider = "knight"  // Ping-pong brightness sweep
    case pulse = "pulse"         // Gentle pulse between 40-100% opacity
    case blink = "blink"         // Quick blink every 2 seconds
    case none = "none"           // No animation, static dim

    var displayName: String {
        switch self {
        case .fade: "Fade"
        case .knightRider: "Knight Rider"
        case .pulse: "Pulse"
        case .blink: "Blink"
        case .none: "None"
        }
    }

    /// Calculate opacity for a given time phase (0.0 to 1.0 cycling)
    func opacity(at phase: Double) -> Double {
        switch self {
        case .fade:
            // Smooth sinusoidal fade: 0.3 to 1.0
            return 0.3 + 0.7 * (0.5 + 0.5 * sin(phase * .pi * 2))
        case .knightRider:
            // Triangle wave sweep: 0.2 to 1.0
            let saw = abs(phase * 2 - 1)
            return 0.2 + 0.8 * saw
        case .pulse:
            // Gentle pulse: 0.4 to 1.0
            return 0.4 + 0.6 * (0.5 + 0.5 * cos(phase * .pi * 2))
        case .blink:
            // Sharp blink: full opacity except brief dip at start of cycle
            return phase < 0.15 ? 0.2 : 1.0
        case .none:
            return 0.5
        }
    }
}
