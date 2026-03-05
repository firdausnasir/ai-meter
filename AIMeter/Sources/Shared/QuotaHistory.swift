import Foundation

struct QuotaDataPoint: Codable, Identifiable {
    var id: UUID
    let timestamp: Date
    let session: Double
    let weekly: Double

    init(timestamp: Date = Date(), session: Double, weekly: Double) {
        self.id = UUID()
        self.timestamp = timestamp
        self.session = session
        self.weekly = weekly
    }
}

struct QuotaHistory: Codable {
    var dataPoints: [QuotaDataPoint] = []
}

enum QuotaTimeRange: String, CaseIterable, Identifiable {
    case hour1 = "1h"
    case hour6 = "6h"
    case day1 = "1d"
    case day7 = "7d"

    var id: String { rawValue }

    var interval: TimeInterval {
        switch self {
        case .hour1: return 3600
        case .hour6: return 6 * 3600
        case .day1: return 86400
        case .day7: return 7 * 86400
        }
    }

    var targetPointCount: Int {
        switch self {
        case .hour1: return 60
        case .hour6: return 120
        case .day1: return 144
        case .day7: return 168
        }
    }
}
