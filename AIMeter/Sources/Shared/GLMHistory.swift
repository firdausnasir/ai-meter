import Foundation

struct GLMHistoryDataPoint: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let tokensPercent: Int

    init(tokensPercent: Int) {
        self.id = UUID()
        self.timestamp = Date()
        self.tokensPercent = tokensPercent
    }
}

struct GLMHistory: Codable {
    var dataPoints: [GLMHistoryDataPoint] = []
}
