import Foundation

@MainActor
final class CodexHistoryService: HistoryServiceBase<CodexHistory, CodexHistoryDataPoint> {
    private static let fileURL: URL = {
        try? FileManager.default.createDirectory(at: AppConstants.Paths.configDir, withIntermediateDirectories: true)
        return AppConstants.Paths.codexHistoryFile
    }()

    override var historyFileURL: URL { Self.fileURL }

    override var dataPoints: [CodexHistoryDataPoint] {
        get { history.dataPoints }
        set { history.dataPoints = newValue }
    }

    override func timestamp(of point: CodexHistoryDataPoint) -> Date {
        point.timestamp
    }

    init() {
        super.init(emptyHistory: CodexHistory())
    }

    func recordDataPoint(primaryPercent: Int, secondaryPercent: Int) {
        let point = CodexHistoryDataPoint(primaryPercent: primaryPercent, secondaryPercent: secondaryPercent)
        history.dataPoints.append(point)
        markDirty()
    }
}
