# asuku

macOS menu bar app for managing [Claude Code](https://docs.anthropic.com/en/docs/claude-code) permission requests via native notifications.

Integrates with Claude Code's hook system to receive tool execution permission requests (Bash, Write, Edit, etc.) as macOS notifications and respond with Allow / Deny. Optionally enable [ntfy](https://ntfy.sh) integration to respond from your iPhone remotely.

[Japanese / 日本語](README-jp.md)

## Features

- **Menu bar UI** — Pending request list, Allow/Deny buttons, recent activity
- **macOS notifications** — Alert-style notifications with instant Allow/Deny actions
- **iPhone notifications (opt-in)** — Respond remotely via ntfy.sh + Cloudflare Tunnel
- **Auto-deny timeout** — Auto-denies after 280s (before Claude Code's 300s hook timeout)
- **Sensitive data masking** — Automatically masks tokens and API keys
- **One-click hook install** — Auto-registers hooks in Claude Code's `settings.json`
- **Launch at login** — Via SMAppService

## Requirements

- macOS 14.0 (Sonoma) or later
- Swift 6.0+
- Claude Code installed

## Build

```bash
# Build
swift build

# Build app bundle (.app with code signing)
scripts/build-app.sh

# Run
open .build/asuku.app
```

The app bundle is generated at `.build/asuku.app`, containing both `AsukuApp` (menu bar app) and `asuku-hook` (CLI hook binary).

## Setup

### 1. Install Hook

After launching the app, register hooks using either:

- **Menu bar** → "Install Hook..." button
- **Settings** → "Install Hook to Claude Code" button

This adds `PermissionRequest` (sync, 300s timeout) and `Notification` (async) hooks to `~/.claude/settings.json`.

### 2. Grant Notification Permission

On first launch, macOS will prompt for notification permission. For best results, go to System Settings → Notifications → asuku and set the notification style to **Alerts**.

## iPhone Notifications (ntfy)

Combine ntfy.sh with Cloudflare Tunnel to respond to permission requests from your iPhone. Disabled by default.

### Architecture

```
[Permission Request]
        |
[AppState] ── macOS notification (always)
        |
        └── ntfy HTTP POST (opt-in)
                |
        [ntfy.sh or self-hosted]
                |
        [iPhone: ntfy app]
        User taps Allow/Deny
                |
        [Cloudflare Tunnel]
                |
        [WebhookServer on 127.0.0.1:8945]
                |
        [AppState.resolveRequest] ← first-response-wins
```

Whichever responds first (macOS notification or iPhone ntfy) wins. `PendingRequestManager.resolve()` prevents duplicate resolution.

### Setup: Docker (recommended)

```bash
# Using ntfy.sh public server
./docker/start.sh

# With self-hosted ntfy server
./docker/start.sh --selfhosted
```

Paste the URLs printed by the script into the corresponding fields in Settings.

### Setup: Manual

1. Install the [ntfy app](https://apps.apple.com/app/ntfy/id1625396347) on your iPhone
2. Enable "iPhone Notifications (ntfy)" in Settings
3. Subscribe to the displayed topic in the iPhone ntfy app
4. Install cloudflared:
   ```bash
   brew install cloudflare/cloudflare/cloudflared
   ```
5. Start the tunnel:
   ```bash
   cloudflared tunnel --url http://localhost:8945
   ```
6. Paste the tunnel URL into "Webhook URL" in Settings

> **Note:** Quick Tunnel URLs change on each restart. For permanent URLs, use [Named Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/).

## Architecture

```
Sources/
├── AsukuShared/            Shared library
│   ├── IPCProtocol.swift     Wire format, message types, sanitizer
│   └── SocketPath.swift      UDS socket path resolution
├── AsukuApp/               Menu bar app (macOS)
│   ├── AsukuApp.swift        @main entry, MenuBarExtra + Settings window
│   ├── AppState.swift        Central @Observable state, orchestrates all components
│   ├── IPCServer.swift       Unix Domain Socket server (Network.framework)
│   ├── PendingRequestManager.swift  Actor managing pending requests + timeouts
│   ├── NotificationManager.swift    macOS UNUserNotification with Allow/Deny actions
│   ├── NtfyConfig.swift      UserDefaults-backed ntfy configuration
│   ├── NtfyNotifier.swift    HTTP POST to ntfy.sh with action buttons
│   ├── WebhookServer.swift   TCP HTTP server for ntfy webhook callbacks
│   ├── MenuBarView.swift     Menu bar popover UI
│   ├── SettingsView.swift    Settings window UI
│   ├── MenuBarIcon.swift     Terminal icon with badge
│   ├── HookInstaller.swift   Auto-installs hooks into Claude Code settings
│   └── LaunchAtLogin.swift   SMAppService wrapper
└── AsukuHook/              CLI hook binary
    ├── AsukuHook.swift       Entry point, subcommand dispatch
    ├── PermissionRequestHandler.swift  Sync hook: send request, wait for response
    ├── NotificationHandler.swift       Async hook: fire-and-forget notification
    └── IPCClient.swift       UDS client with retry

docker/
├── docker-compose.yml      cloudflared + optional self-hosted ntfy
└── start.sh                Helper script to start services and extract tunnel URLs
```

### Data Flow

1. **Claude Code** → `asuku-hook permission-request` (stdin: JSON)
2. **asuku-hook** → IPC message over Unix Domain Socket
3. **AsukuApp IPCServer** → `AppState.handlePermissionRequest`
4. **AppState** → macOS notification + ntfy notification (if enabled)
5. **User responds** via macOS notification, menu bar UI, or iPhone ntfy
6. **AppState.resolveRequest** → IPC response → **asuku-hook** → stdout JSON → **Claude Code**

## Tests

```bash
swift test
```

## License

MIT
