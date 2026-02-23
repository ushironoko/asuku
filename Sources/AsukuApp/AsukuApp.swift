import SwiftUI

@main
struct AsukuApp: App {
    @State private var appState: AppState
    @State private var coordinator: AppCoordinator

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState, dispatch: coordinator.dispatch)
        } label: {
            MenuBarIcon(hasPending: !appState.pendingRequests.isEmpty)
        }
        .menuBarExtraStyle(.window)

        Window("asuku Settings", id: "settings") {
            SettingsView(appState: appState, dispatch: coordinator.dispatch)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    init() {
        let state = AppState()
        _appState = State(initialValue: state)
        _coordinator = State(initialValue: AppCoordinator(appState: state))
    }
}
