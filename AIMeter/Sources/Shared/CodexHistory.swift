import Foundation

struct CodexHistoryDataPoint: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let primaryPercent: Int
    let secondaryPercent: Int

    init(primaryPercent: Int, secondaryPercent: Int) {
        self.id = UUID()
        self.timestamp = Date()
        self.primaryPercent = primaryPercent
        self.secondaryPercent = secondaryPercent
    }
}

struct CodexHistory: Codable {
    var dataPoints: [CodexHistoryDataPoint] = []
}
