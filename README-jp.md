# asuku

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) の許可リクエストをmacOS通知で管理するメニューバーアプリ。

Claude Code の hook 機能と連携し、ツール実行の許可リクエスト（Bash, Write, Edit 等）をmacOS通知として受け取り、Allow / Deny で応答できます。オプションで [ntfy](https://ntfy.sh) 連携を有効にすると、iPhoneからもリモートで応答可能です。

[English](README.md)

## 機能

- **メニューバーUI** — 許可待ちリクエスト一覧、Allow/Deny ボタン、最近のアクティビティ表示
- **macOS通知** — Alert スタイル通知で即座に Allow/Deny を選択
- **iPhone通知 (opt-in)** — ntfy.sh + Cloudflare Tunnel 経由で iPhone から応答
- **自動Denyタイムアウト** — 280秒で自動Deny（Claude Code の 300秒タイムアウト前に）
- **機密データマスク** — トークンやAPIキーを自動マスク
- **ワンクリックhookインストール** — Claude Code の `settings.json` にフックを自動登録
- **ログイン時起動** — SMAppService によるログイン時自動起動

## 動作要件

- macOS 14.0 (Sonoma) 以降
- Swift 6.0+
- Claude Code インストール済み

## ビルド

```bash
# ビルド
swift build

# App bundle 生成（コード署名付き .app）
scripts/build-app.sh

# 起動
open .build/asuku.app
```

App bundle は `.build/asuku.app` に生成されます。`AsukuApp`（メニューバーアプリ）と `asuku-hook`（CLI フック）の両方がバンドルに含まれます。

## セットアップ

### 1. Hook のインストール

アプリ起動後、以下のいずれかでフックを登録:

- **メニューバー** → "Install Hook..." ボタン
- **Settings** → "Install Hook to Claude Code" ボタン

これにより `~/.claude/settings.json` に `PermissionRequest`（同期、300秒タイムアウト）と `Notification`（非同期）のフックが追加されます。

### 2. 通知の許可

初回起動時にmacOS通知の許可を求められます。**Alert スタイル**で通知されるように、システム設定 → 通知 → asuku で「通知スタイル」を「通知パネル」に設定してください。

## iPhone通知 (ntfy)

ntfy.sh と Cloudflare Tunnel を組み合わせて、iPhone からも Allow/Deny を応答できます。デフォルトは無効です。

### アーキテクチャ

```
[許可リクエスト受信]
        |
[AppState] ── macOS通知（常に送信）
        |
        └── ntfy HTTP POST（有効時のみ）
                |
        [ntfy.sh or セルフホスト]
                |
        [iPhone: ntfyアプリ]
        ユーザーが Allow/Deny タップ
                |
        [Cloudflare Tunnel]
                |
        [WebhookServer on 127.0.0.1:8945]
                |
        [AppState.resolveRequest] ← 先着勝ち
```

macOS通知と ntfy のどちらが先に応答しても、`PendingRequestManager.resolve()` が二重解決を防ぎます（先着勝ち）。

### セットアップ: Docker（推奨）

```bash
# ntfy.sh 公開サーバーを使う場合
./docker/start.sh

# セルフホスト ntfy も含める場合
./docker/start.sh --selfhosted
```

スクリプトが表示する URL を Settings の対応フィールドに貼り付けてください。

### セットアップ: 手動

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

## アーキテクチャ

```
Sources/
├── AsukuShared/            共有ライブラリ
│   ├── IPCProtocol.swift     ワイヤーフォーマット、メッセージ型、サニタイザー
│   └── SocketPath.swift      UDS ソケットパス解決
├── AsukuApp/               メニューバーアプリ (macOS)
│   ├── AsukuApp.swift        @main エントリ、MenuBarExtra + Settings ウィンドウ
│   ├── AppState.swift        中央 @Observable 状態、全コンポーネントを統合
│   ├── IPCServer.swift       Unix Domain Socket サーバー (Network.framework)
│   ├── PendingRequestManager.swift  許可待ちリクエスト管理 Actor + タイムアウト
│   ├── NotificationManager.swift    macOS UNUserNotification、Allow/Deny アクション付き
│   ├── NtfyConfig.swift      UserDefaults ベースの ntfy 設定
│   ├── NtfyNotifier.swift    ntfy.sh への HTTP POST、アクションボタン付き
│   ├── WebhookServer.swift   ntfy webhook コールバック用 TCP HTTP サーバー
│   ├── MenuBarView.swift     メニューバーポップオーバー UI
│   ├── SettingsView.swift    設定ウィンドウ UI
│   ├── MenuBarIcon.swift     ターミナルアイコン + バッジ
│   ├── HookInstaller.swift   Claude Code 設定への hook 自動登録
│   └── LaunchAtLogin.swift   SMAppService ラッパー
└── AsukuHook/              CLI フックバイナリ
    ├── AsukuHook.swift       エントリポイント、サブコマンド振り分け
    ├── PermissionRequestHandler.swift  同期 hook: リクエスト送信、レスポンス待ち
    ├── NotificationHandler.swift       非同期 hook: fire-and-forget 通知
    └── IPCClient.swift       UDS クライアント（リトライ付き）

docker/
├── docker-compose.yml      cloudflared + オプションのセルフホスト ntfy
└── start.sh                サービス起動 + トンネルURL取得ヘルパー
```

### データフロー

1. **Claude Code** → `asuku-hook permission-request`（stdin: JSON）
2. **asuku-hook** → Unix Domain Socket 経由で IPC メッセージ送信
3. **AsukuApp IPCServer** → `AppState.handlePermissionRequest`
4. **AppState** → macOS通知 + ntfy通知（有効時）
5. **ユーザー応答** — macOS通知、メニューバーUI、または iPhone ntfy
6. **AppState.resolveRequest** → IPC レスポンス → **asuku-hook** → stdout JSON → **Claude Code**

## テスト

```bash
swift test
```

## ライセンス

MIT
