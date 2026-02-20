import Foundation
@preconcurrency import ServiceManagement

@MainActor
enum LaunchAtLogin {
    private static let service = SMAppService.mainApp

    static var isEnabled: Bool {
        service.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            print("[LaunchAtLogin] Failed to \(enabled ? "register" : "unregister"): \(error)")
        }
    }
}
