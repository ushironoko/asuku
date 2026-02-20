# asuku

macOS menu bar app for managing [Claude Code](https://docs.anthropic.com/en/docs/claude-code) permission requests via native notifications.

Claude Code の hook 機能と連携し、ツール実行の許可リクエスト（Bash, Write, Edit 等）をmacOS通知として受け取り、Allow / Deny で応答できます。オプションで [ntfy](https://ntfy.sh) 連携を有効にすると、iPhoneからもリモートで応答可能です。

## Features

- **Menu bar UI** — 許可待ちリクエスト一覧、Allow/Deny ボタン、最近のアクティビティ表示
- **macOS notifications** — Alert スタイル通知で即座に Allow/Deny を選択
- **iPhone notifications (opt-in)** — ntfy.sh + Cloudflare Tunnel 経由で iPhone から応答
- **Auto-deny timeout** — 280秒で自動Deny（Claude Code の 300秒タイムアウト前に）
- **Sensitive data masking** — トークンやAPIキーを自動マスク
- **One-click hook install** — Claude Code の `settings.json` にフックを自動登録
- **Launch at login** — SMAppService によるログイン時自動起動

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

App bundle は `.build/asuku.app` に生成されます。`AsukuApp`（メニューバーアプリ）と `asuku-hook`（CLI フック）の両方がバンドルに含まれます。

## Setup

### 1. Hook のインストール

アプリ起動後、以下のいずれかでフックを登録:

- **メニューバー** → "Install Hook..." ボタン
- **Settings** → "Install Hook to Claude Code" ボタン

これにより `~/.claude/settings.json` に `PermissionRequest`（同期、300秒タイムアウト）と `Notification`（非同期）のフックが追加されます。

### 2. 通知の許可

初回起動時にmacOS通知の許可を求められます。**Alert スタイル**で通知されるように、システム設定 → 通知 → asuku で「通知スタイル」を「通知パネル」に設定してください。

## iPhone Notifications (ntfy)

ntfy.sh と Cloudflare Tunnel を組み合わせて、iPhone からも Allow/Deny を応答できます。デフォルトは無効です。

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

macOS通知と ntfy のどちらが先に応答しても、`PendingRequestManager.resolve()` は二重解決を防ぎます（先着勝ち）。

### Setup: Docker (recommended)

```bash
# ntfy.sh 公開サーバーを使う場合
./docker/start.sh

# セルフホスト ntfy も含める場合
./docker/start.sh --selfhosted
```

スクリプトが表示する URL を Settings の対応フィールドに貼り付けてください。

### Setup: Manual

1. iPhone に [ntfy アプリ](https://apps.apple.com/app/ntfy/id1625396347)をインストール
2. Settings → "iPhone Notifications (ntfy)" を有効化
3. 表示された Topic を iPhone の ntfy アプリで購読
4. cloudflared をインストール:
   ```bash
   brew install cloudflare/cloudflare/cloudflared
   ```
5. トンネルを起動:
   ```bash
   cloudflared tunnel --url http://localhost:8945
   ```
6. 表示されたトンネル URL を Settings の "Webhook URL" に貼り付け

> **Note:** Quick Tunnel の URL は起動ごとに変わります。恒久的な URL が必要な場合は [Named Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) を使用してください。

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
