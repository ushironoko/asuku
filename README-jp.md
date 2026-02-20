# asuku

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) の許可リクエストをmacOS通知で管理するメニューバーアプリ。

Claude Code がツール（Bash, Write, Edit 等）の実行許可を求めると、macOS通知で Allow / Deny ボタン付きで届きます。オプションで [ntfy](https://ntfy.sh) を有効にすれば、iPhoneからもリモートで応答できます。

[English](README.md)

## 機能

- **macOS通知** — Allow / Deny アクション付きの Alert スタイル通知
- **メニューバーUI** — 許可待ちリクエスト一覧、クイックアクション、最近のアクティビティ
- **iPhone通知** — ntfy + Cloudflare Tunnel 経由でリモート応答（opt-in）
- **自動Denyタイムアウト** — 280秒で自動的に Deny
- **機密データマスク** — トークンやAPIキーは通知上でマスクされる
- **ワンクリックhookインストール** — Claude Code の設定にフックを自動登録
- **ログイン時起動**

## 動作要件

- macOS 14.0 (Sonoma) 以降
- Swift 6.0+
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) インストール済み

## はじめ方

### 1. ビルドして起動

```bash
scripts/build-app.sh
open .build/asuku.app
```

### 2. Hook をインストール

メニューバーのドロップダウンで **"Install Hook..."** をクリック、または **Settings → Install Hook to Claude Code** をクリック。

`~/.claude/settings.json` に [Claude Code hook](https://docs.anthropic.com/en/docs/claude-code/hooks) として asuku が登録されます。

### 3. 通知を設定

初回起動時に通知の許可を求められるので許可してください。その後 **システム設定 → 通知 → asuku** で通知スタイルを **「通知パネル」（Alerts）** に設定します。バナーだと Allow / Deny ボタンが表示されません。

### 4. 使う

Claude Code をいつも通り起動するだけです。ツール実行の許可が必要になると：

- **macOS通知** に Allow / Deny ボタン付きで表示
- **メニューバーのドロップダウン** にも Allow / Deny ボタン付きで表示

どちらからでも応答できます。280秒以内に応答がなければ自動的に Deny されます。

## iPhone通知 (ntfy)

許可リクエストを iPhone でも受信し、リモートで応答できます。Mac から離れているときに便利です。デフォルトは無効です。

### 仕組み

1. 許可リクエストが届く → asuku が [ntfy.sh](https://ntfy.sh) 経由でプッシュ通知を送信
2. iPhone に **Allow** / **Deny** ボタン付き通知が届く
3. ボタンをタップすると [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) 経由で Mac に webhook が届く
4. Mac と iPhone のどちらが先に応答しても、もう一方は無視される（先着勝ち）

### 前提

1. iPhone に [ntfy アプリ](https://apps.apple.com/app/ntfy/id1625396347)をインストール
2. asuku の **Settings** で **"iPhone Notifications (ntfy)"** を有効化
3. iPhone の ntfy アプリで Settings に表示されたトピック（例: `asuku-xxxxxxxx-...`）を購読

以下の Docker または手動セットアップで Cloudflare Tunnel を設定してください。

### Docker で簡単セットアップ

```bash
# ntfy.sh 公開サーバーを使う場合（最も簡単）
./docker/start.sh

# セルフホスト ntfy を使う場合（よりプライベート）
./docker/start.sh --selfhosted
```

スクリプトが cloudflared（とオプションで ntfy）を Docker で起動し、トンネル URL を表示します。表示された URL を **Settings → iPhone Notifications (ntfy)** に貼り付けてください。

### 手動セットアップ

1. cloudflared をインストール：
   ```bash
   brew install cloudflare/cloudflare/cloudflared
   ```
2. トンネルを起動：
   ```bash
   cloudflared tunnel --url http://localhost:8945
   ```
3. 表示される `https://xxxxx.trycloudflare.com` の URL をコピーし、Settings の **Webhook URL** に貼り付け

これで次の許可リクエストから Mac と iPhone の両方に通知が届きます。

> **Note:** Quick Tunnel の URL は cloudflared を再起動するたびに変わります。恒久的な URL が必要な場合は `--token` で Named Tunnel を使用：
> ```bash
> ./docker/start.sh --token <CLOUDFLARE_TUNNEL_TOKEN>
> ```
> トークンは [Cloudflare Zero Trust ダッシュボード](https://one.dash.cloudflare.com/)で取得できます。

### 停止

```bash
# Docker の場合
docker compose -f docker/docker-compose.yml down

# 手動の場合
# cloudflared プロセスを停止するだけ (Ctrl+C)
```

## トラブルシューティング

**通知が表示されない**
- システム設定 → 通知 → asuku が有効で、スタイルが **通知パネル（Alerts）** になっているか確認
- Hook がインストール済みか確認: `~/.claude/settings.json` に `asuku-hook` のエントリがあるか

**iPhone通知が届かない**
- Settings で Webhook Server に緑のインジケーターが表示されているか確認
- Webhook を手動テスト: `curl -X POST http://localhost:8945/webhook/allow/test-id`（403 が返れば正常 — サーバーは動いている）
- cloudflared トンネルが起動中で、Webhook URL が設定されているか確認

**ポート競合**
- ポート 8945 が使用中の場合、Settings で **Webhook Port** を変更し、Webhook Server を再起動

## 開発

```bash
# ビルド
swift build

# テスト
swift test

# .app バンドル生成
scripts/build-app.sh
```

## ライセンス

MIT
