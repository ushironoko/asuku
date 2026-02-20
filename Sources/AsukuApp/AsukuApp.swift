import SwiftUI

@main
struct AsukuApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            MenuBarIcon(hasPending: !appState.pendingRequests.isEmpty)
        }
        .menuBarExtraStyle(.window)

        Window("asuku Settings", id: "settings") {
            SettingsView(appState: appState)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
