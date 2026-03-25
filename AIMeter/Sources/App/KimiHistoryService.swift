import Foundation

@MainActor
final class KimiHistoryService: ObservableObject {
    @Published var history: KimiHistory = KimiHistory()

    private static let historyFileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/aimeter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("kimi-history.json")
    }()

    private var saveTask: Task<Void, Never>?

    init() {
        loadHistory()
    }

    func recordDataPoint(utilization: Int) {
        let point = KimiHistoryDataPoint(utilization: utilization)
        history.dataPoints.append(point)

        // Keep only last 7 days of data
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        history.dataPoints.removeAll { $0.timestamp < cutoff }

        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            await self.saveHistory()
        }
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: Self.historyFileURL),
              let decoded = try? JSONDecoder().decode(KimiHistory.self, from: data) else {
            return
        }
        history = decoded
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: Self.historyFileURL, options: .atomic)
    }
}
