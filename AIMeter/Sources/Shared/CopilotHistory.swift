import Foundation

struct CopilotHistoryDataPoint: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let chatUtilization: Int?
    let chatRemaining: Int?
    let completionsUtilization: Int?
    let completionsRemaining: Int?
    let premiumUtilization: Int?
    let premiumRemaining: Int?

    init(timestamp: Date = Date(), from data: CopilotUsageData) {
        self.id = UUID()
        self.timestamp = timestamp
        self.chatUtilization = data.chat.unlimited ? nil : data.chat.utilization
        self.chatRemaining = data.chat.unlimited ? nil : data.chat.remaining
        self.completionsUtilization = data.completions.unlimited ? nil : data.completions.utilization
        self.completionsRemaining = data.completions.unlimited ? nil : data.completions.remaining
        self.premiumUtilization = data.premiumInteractions.unlimited ? nil : data.premiumInteractions.utilization
        self.premiumRemaining = data.premiumInteractions.unlimited ? nil : data.premiumInteractions.remaining
    }

    init(
        timestamp: Date,
        chatUtilization: Int?,
        chatRemaining: Int?,
        completionsUtilization: Int?,
        completionsRemaining: Int?,
        premiumUtilization: Int?,
        premiumRemaining: Int?
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.chatUtilization = chatUtilization
        self.chatRemaining = chatRemaining
        self.completionsUtilization = completionsUtilization
        self.completionsRemaining = completionsRemaining
        self.premiumUtilization = premiumUtilization
        self.premiumRemaining = premiumRemaining
    }
}

struct CopilotHistory: Codable {
    var dataPoints: [CopilotHistoryDataPoint] = []
}

enum CopilotChartMetric: String, CaseIterable, Identifiable {
    case utilization = "Usage %"
    case remaining = "Remaining"

    var id: String { rawValue }
}
