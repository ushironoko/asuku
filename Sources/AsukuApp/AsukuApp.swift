import SwiftUI

@main
struct AsukuApp: App {
    @State private var appState: AppState
    @State private var coordinator: AppCoordinator

    private var contextPressure: Bool {
        guard let percent = appState.activeSessions.first?.contextUsedPercent else {
            return false
        }
        return percent >= 80
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState, dispatch: coordinator.dispatch)
        } label: {
            MenuBarIcon(
                hasPending: !appState.pendingRequests.isEmpty,
                contextPressure: contextPressure
            )
        }
        .menuBarExtraStyle(.window)

        Window("asuku Settings", id: "settings") {
            SettingsView(appState: appState, dispatch: coordinator.dispatch)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("asuku Dashboard", id: "dashboard") {
            DashboardView(appState: appState)
        }
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
        .defaultSize(width: 600, height: 450)
    }

    init() {
        let state = AppState()
        _appState = State(initialValue: state)
        _coordinator = State(initialValue: AppCoordinator(appState: state))
    }
}
