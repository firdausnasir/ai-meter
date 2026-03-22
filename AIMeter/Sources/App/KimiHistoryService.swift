import Foundation

@MainActor
final class KimiHistoryService: HistoryServiceBase<KimiHistory, KimiHistoryDataPoint> {
    private static let fileURL: URL = {
        try? FileManager.default.createDirectory(at: AppConstants.Paths.configDir, withIntermediateDirectories: true)
        return AppConstants.Paths.kimiHistoryFile
    }()

    override var historyFileURL: URL { Self.fileURL }

    override var dataPoints: [KimiHistoryDataPoint] {
        get { history.dataPoints }
        set { history.dataPoints = newValue }
    }

    override func timestamp(of point: KimiHistoryDataPoint) -> Date {
        point.timestamp
    }

    init() {
        super.init(emptyHistory: KimiHistory())
    }

    func recordDataPoint(totalBalance: Double) {
        let point = KimiHistoryDataPoint(totalBalance: totalBalance)
        history.dataPoints.append(point)
        markDirty()
    }
}
