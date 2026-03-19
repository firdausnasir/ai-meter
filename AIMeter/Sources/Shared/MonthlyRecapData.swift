import Foundation

struct MonthlyRecapData: Codable, Equatable {
    let month: Date              // first day of the recap month
    let generatedAt: Date
    let claude: ClaudeRecapStats?
    let copilot: CopilotRecapStats?
}

struct ClaudeRecapStats: Codable, Equatable {
    let avgSessionUtilization: Double    // average 5h window %
    let avgWeeklyUtilization: Double     // average 7d window %
    let peakSessionUtilization: Double   // highest 5h spike
    let peakWeeklyUtilization: Double    // highest 7d spike
    let peakDate: Date                   // when peak occurred
    let dataPointCount: Int              // total snapshots recorded
    let planName: String?
}

struct CopilotRecapStats: Codable, Equatable {
    let avgChatUtilization: Double
    let avgCompletionsUtilization: Double
    let avgPremiumUtilization: Double
    let peakChatUtilization: Double
    let peakCompletionsUtilization: Double
    let peakPremiumUtilization: Double
    let peakDate: Date
    let dataPointCount: Int
    let plan: String?
}
