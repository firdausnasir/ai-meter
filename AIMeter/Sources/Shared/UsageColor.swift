import SwiftUI

enum UsageColor {
    /// Read thresholds from UserDefaults, with sensible defaults
    private static var elevatedThreshold: Int {
        UserDefaults.standard.object(forKey: "colorThresholdElevated") as? Int ?? 50
    }

    private static var highThreshold: Int {
        UserDefaults.standard.object(forKey: "colorThresholdHigh") as? Int ?? 80
    }

    private static var criticalThreshold: Int {
        UserDefaults.standard.object(forKey: "colorThresholdCritical") as? Int ?? 95
    }

    static func forUtilization(_ value: Int) -> Color {
        switch value {
        case ..<elevatedThreshold: return .green
        case ..<highThreshold: return .yellow
        case ..<criticalThreshold: return .orange
        default: return .red
        }
    }

    static func levelDescription(_ value: Int) -> String {
        switch value {
        case ..<elevatedThreshold: "Normal"
        case ..<highThreshold: "Elevated"
        case ..<criticalThreshold: "High"
        default: "Critical"
        }
    }
}
