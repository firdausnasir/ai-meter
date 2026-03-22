import Foundation

@MainActor
final class GLMHistoryService: HistoryServiceBase<GLMHistory, GLMHistoryDataPoint> {
    private static let fileURL: URL = {
        try? FileManager.default.createDirectory(at: AppConstants.Paths.configDir, withIntermediateDirectories: true)
        return AppConstants.Paths.glmHistoryFile
    }()

    override var historyFileURL: URL { Self.fileURL }

    override var dataPoints: [GLMHistoryDataPoint] {
        get { history.dataPoints }
        set { history.dataPoints = newValue }
    }

    override func timestamp(of point: GLMHistoryDataPoint) -> Date {
        point.timestamp
    }

    init() {
        super.init(emptyHistory: GLMHistory())
    }

    func recordDataPoint(tokensPercent: Int) {
        let point = GLMHistoryDataPoint(tokensPercent: tokensPercent)
        history.dataPoints.append(point)
        markDirty()
    }
}
