import Foundation
import AppKit

@MainActor
enum ExportService {
    /// Export quota history as CSV to a user-chosen location
    static func exportQuotaHistory(from service: QuotaHistoryService) {
        let points = service.history.dataPoints
        guard !points.isEmpty else { return }

        let csv = buildCSV(
            headers: ["Timestamp", "Session %", "Weekly %"],
            rows: points.map { point in
                [
                    ISO8601DateFormatter().string(from: point.timestamp),
                    String(format: "%.1f", point.session * 100),
                    String(format: "%.1f", point.weekly * 100)
                ]
            }
        )
        saveCSV(csv, suggestedName: "claude-quota-history.csv")
    }

    /// Export copilot history as CSV
    static func exportCopilotHistory(from service: CopilotHistoryService) {
        let points = service.history.dataPoints
        guard !points.isEmpty else { return }

        let csv = buildCSV(
            headers: ["Timestamp", "Chat %", "Completions %", "Premium %"],
            rows: points.map { point in
                [
                    ISO8601DateFormatter().string(from: point.timestamp),
                    point.chatUtilization.map { String($0) } ?? "",
                    point.completionsUtilization.map { String($0) } ?? "",
                    point.premiumUtilization.map { String($0) } ?? ""
                ]
            }
        )
        saveCSV(csv, suggestedName: "copilot-quota-history.csv")
    }

    private static func buildCSV(headers: [String], rows: [[String]]) -> String {
        var lines = [headers.joined(separator: ",")]
        for row in rows {
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func saveCSV(_ content: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
