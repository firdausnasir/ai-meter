import SwiftUI

@main
struct AIMeterApp: App {
    @StateObject private var service = UsageService()
    @StateObject private var copilotService = CopilotService()
    @StateObject private var glmService = GLMService()
    @StateObject private var updaterManager = UpdaterManager()
    @StateObject private var authManager = SessionAuthManager()
    @StateObject private var historyService = QuotaHistoryService()
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60

    var body: some Scene {
        MenuBarExtra {
            PopoverView(service: service, copilotService: copilotService, glmService: glmService, updaterManager: updaterManager, authManager: authManager, historyService: historyService)
                .task {
                    service.start(interval: refreshInterval, authManager: authManager, historyService: historyService)
                    copilotService.start(interval: refreshInterval)
                    glmService.start(interval: refreshInterval)
                }
                .onChange(of: refreshInterval) { _, newValue in
                    service.stop()
                    service.start(interval: newValue, authManager: authManager, historyService: historyService)
                    copilotService.stop()
                    copilotService.start(interval: newValue)
                    glmService.stop()
                    glmService.start(interval: newValue)
                }
                .onChange(of: authManager.isAuthenticated) { _, isAuth in
                    if isAuth {
                        Task { await service.fetch() }
                    }
                }
        } label: {
            MenuBarLabel(utilization: max(
                service.usageData.highestUtilization,
                copilotService.copilotData.highestUtilization,
                glmService.glmData.tokensPercent
            ))
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let utilization: Int

    var body: some View {
        Image(systemName: "sparkles")
            .foregroundStyle(UsageColor.forUtilization(utilization))
    }
}
