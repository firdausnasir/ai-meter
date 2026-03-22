import Foundation

struct KimiHistoryDataPoint: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let totalBalance: Double

    init(totalBalance: Double) {
        self.id = UUID()
        self.timestamp = Date()
        self.totalBalance = totalBalance
    }
}

struct KimiHistory: Codable {
    var dataPoints: [KimiHistoryDataPoint] = []
}
