import Foundation

enum HookInstallResult {
    case success(hookPath: String, settingsPath: String)
    case failure(String)
}

enum HookInstaller {
    /// Shell-escape a path by wrapping in single quotes
    private static func shellEscape(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    /// Path to Claude Code settings
    private static var settingsPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return (home as NSString).appendingPathComponent(".claude/settings.json")
    }

    /// Path to the asuku-hook binary
    private static var hookBinaryPath: String? {
        // Check if running from app bundle
        if let bundlePath = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("asuku-hook").path
        {
            if FileManager.default.fileExists(atPath: bundlePath) {
                return bundlePath
            }
        }

        // Fallback: check common install locations
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/usr/local/bin/asuku-hook",
            "/opt/homebrew/bin/asuku-hook",
            (home as NSString).appendingPathComponent(".local/bin/asuku-hook"),
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    /// Check if hook is already installed in Claude Code settings
    static func isInstalled() -> Bool {
        guard let data = FileManager.default.contents(atPath: settingsPath),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let hooks = json["hooks"] as? [String: Any],
            let permissionHooks = hooks["PermissionRequest"] as? [[String: Any]]
        else {
            return false
        }

        return permissionHooks.contains { entry in
            guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
            return hookList.contains { hook in
                guard let command = hook["command"] as? String else { return false }
                return command.contains("asuku-hook")
            }
        }
    }

    /// Install hook configuration into Claude Code settings
    @MainActor
    static func install() async -> HookInstallResult {
        let fm = FileManager.default

        guard let hookPath = hookBinaryPath else {
            return .failure(
                "asuku-hook binary not found.\nExpected in app bundle or /usr/local/bin/asuku-hook"
            )
        }

        // Read existing settings or create new
        var settings: [String: Any] = [:]
        if let data = fm.contents(atPath: settingsPath),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            settings = json
            // Backup existing settings
            let backupPath = settingsPath + ".backup.\(Int(Date().timeIntervalSince1970))"
            try? fm.copyItem(atPath: settingsPath, toPath: backupPath)
        }

        // Build hook configuration
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        let permissionRequestHook: [String: Any] = [
            "matcher": ".*",
            "hooks": [
                [
                    "type": "command",
                    "command": "\(hookPath) permission-request",
                    "timeout": 300,
                ] as [String: Any]
            ],
        ]

        let notificationHook: [String: Any] = [
            "matcher": ".*",
            "hooks": [
                [
                    "type": "command",
                    "command": "\(hookPath) notification",
                    "async": true,
                ] as [String: Any]
            ],
        ]

        // Merge with existing hooks
        var permissionHooks = hooks["PermissionRequest"] as? [[String: Any]] ?? []
        permissionHooks.removeAll { entry in
            guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
            return hookList.contains { hook in
                (hook["command"] as? String)?.contains("asuku-hook") == true
            }
        }
        permissionHooks.append(permissionRequestHook)
        hooks["PermissionRequest"] = permissionHooks

        var notificationHooks = hooks["Notification"] as? [[String: Any]] ?? []
        notificationHooks.removeAll { entry in
            guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
            return hookList.contains { hook in
                (hook["command"] as? String)?.contains("asuku-hook") == true
            }
        }
        notificationHooks.append(notificationHook)
        hooks["Notification"] = notificationHooks

        // Statusline configuration
        let escapedHookPath = shellEscape(hookPath)
        let statuslineCommand: String
        let existingCommand = (settings["statusLine"] as? [String: Any])?["command"] as? String
        if let existing = existingCommand, !existing.contains("asuku-hook") {
            // Existing non-asuku statusline: pipe chain
            statuslineCommand = "\(escapedHookPath) statusline | \(existing)"
        } else if existingCommand == nil {
            // No existing statusline: passthrough only
            statuslineCommand = "\(escapedHookPath) statusline"
        } else {
            // Already contains asuku-hook: keep as-is
            statuslineCommand = existingCommand!
        }

        var statusLine = settings["statusLine"] as? [String: Any] ?? [:]
        statusLine["command"] = statuslineCommand
        if statusLine["type"] == nil {
            statusLine["type"] = "command"
        }
        settings["statusLine"] = statusLine

        settings["hooks"] = hooks

        do {
            let jsonData = try JSONSerialization.data(
                withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])

            let dir = (settingsPath as NSString).deletingLastPathComponent
            try fm.createDirectory(
                atPath: dir, withIntermediateDirectories: true, attributes: nil)

            try jsonData.write(to: URL(fileURLWithPath: settingsPath))
            return .success(hookPath: hookPath, settingsPath: settingsPath)
        } catch {
            return .failure("Failed to write settings: \(error.localizedDescription)")
        }
    }
}
