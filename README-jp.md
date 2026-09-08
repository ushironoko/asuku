# asuku

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) の許可リクエストを承認し、Claude Code と [Codex CLI](https://developers.openai.com/codex/cli/) の利用状況を確認できるネイティブ macOS メニューバーアプリです。

Claude Code がツール（Bash、Write、Edit など）の実行許可を求めると、macOS 通知で Allow / Deny ボタン付きのリクエストが届きます。Claude Code のセッションやローカル利用状況を確認できるダッシュボードに加え、Claude と Codex のサブスクリプションクォータも表示します。オプションで [ntfy](https://ntfy.sh) を有効にすれば、iPhone から許可リクエストに応答できます。

> **Codex 対応について:** asuku は Codex のサブスクリプションクォータとレート制限情報を表示します。許可リクエストの承認とセッション監視には現在 Claude Code のフックを使用しており、Codex に許可フックをインストールする機能はありません。

[English](README.md)

## 対応機能

| 機能 | Claude Code | Codex CLI |
|---|:---:|:---:|
| Allow / Deny 付き許可リクエスト | 対応 | — |
| エージェント通知 | 対応 | — |
| リアルタイムのセッション状態と履歴 | 対応 | — |
| 5時間／7日のサブスクリプションクォータ | 対応 | 対応 |
| ローカルのツール利用状況とコスト分析 | 対応 | — |

## 機能

- **macOS ネイティブ通知** — Allow / Deny アクション付き許可リクエストと Claude Code のエージェント通知
- **メニューバー UI** — 許可待ちリクエスト、クイックアクション、最近のアクティビティ、セッション状態、クォータ概要
- **ダッシュボード** — アクティブセッション、プラグイン、セッション履歴、ツール利用グラフ、クォータ詳細
- **Claude / Codex クォータ** — 5時間／7日の利用率、リセット時刻、鮮度状態、最後に取得した値
- **Claude のコスト表示** — 現在のセッションで計測されたコストと、ローカル履歴から算出する推定トークンコスト
- **iPhone 通知** — ntfy + Cloudflare Tunnel 経由でリモート応答（オプション）
- **Auto Approve** — Claude Code のすべての許可リクエストを即時 Allow（オプション、初期値 OFF）
- **設定可能なタイムアウト** — 10〜280秒で自動 Deny、またはアプリ側タイムアウトを無効化
- **機密データのマスク** — トークン、API キー、パスワード、認証情報など、既知の機密情報パターンを通知上でマスク
- **ワンクリック Hook インストール** — Claude Code 設定に許可、通知、statusline の各フックを登録
- **ログイン時起動**

## 動作要件

- macOS 14.0（Sonoma）以降
- 許可リクエスト、通知、セッション状態、Claude 利用データを使う場合は [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- リアルタイムかつアカウント全体の Codex クォータを使う場合は、インストールおよび認証済みの [Codex CLI](https://developers.openai.com/codex/cli/)（オプション）

Codex CLI を利用できない場合でも、`~/.codex/sessions` にデータがあれば、最後に記録されたレート制限情報をフォールバックとして表示します。

## はじめ方

### 1. インストール

```bash
brew tap ushironoko/tap
brew install --cask asuku
```

> **Note:** asuku は ad-hoc 署名で、Apple の公証を受けていません。初回起動時に macOS Gatekeeper にブロックされる場合は、以下を実行してください。
>
> ```bash
> xattr -cr /Applications/asuku.app
> ```

### 2. 起動して通知を許可

asuku を起動し、通知の許可を求められたら許可してください。その後、**システム設定 → 通知 → asuku** で通知スタイルをバナーではなく **「通知パネル」（Alerts）** に設定すると、通知アクションにアクセスしやすくなります。

### 3. Claude Code Hook をインストール

メニューバーのドロップダウンで **Install Hook...** をクリックするか、**Settings → Install Hook to Claude Code** を開きます。

asuku は `~/.claude/settings.json` に `PermissionRequest`、`Notification`、`statusLine` の連携を追加します。`asuku-hook` を含まない既存の Hook エントリは保持され、asuku 以外の statusline コマンドがある場合は `asuku-hook` の後段に連結されます。再インストール時は `asuku-hook` を含む `PermissionRequest` または `Notification` エントリ全体が置き換えられるため、無関係なコマンドは別の Hook エントリに分けてください。

### 4. Claude Code を使う

Claude Code をいつも通り起動します。ツール実行の許可が必要になると、次の場所にリクエストが表示されます。

- Allow / Deny ボタン付きの **macOS 通知**
- Allow / Deny ボタン付きの **メニューバードロップダウン**

先に行った応答が採用されます。初期設定では、280秒以内に応答がなければ自動的に Deny されます。

### 5. ダッシュボードを開く

メニューバードロップダウンから **Dashboard...** を選択します。ダッシュボードには次のタブがあります。

| タブ | 内容 |
|---|---|
| **Sessions** | アクティブな Claude Code セッション、モデル、コンテキスト利用率、コスト、変更行数、プロジェクト、利用可能な場合は Claude セッション URL の QR コード |
| **Plugins** | インストール済み Claude Code プラグインと有効／無効状態 |
| **History** | 最近のセッションと、コピー可能な `claude --resume <session-id>` コマンド |
| **Usage** | ローカルの Claude Code テレメトリと現在のアクティビティから集計したツール、エージェント、コマンド利用回数 |
| **Quota** | Claude / Codex の5時間／7日クォータ、リセット時刻、Claude セッションコスト、ローカル履歴コスト推定 |

## Codex クォータ

Codex のクォータ監視に、Codex 側の asuku Hook は必要ありません。

**Settings → Codex Quota → Show live Codex rate limits** を有効にすると（初期値 ON）、asuku は認証済み Codex CLI からアカウント全体のレート制限メタデータを約2分ごとに取得します。同じアカウントを利用する pi など、ほかのクライアントによる Codex 利用分も含まれます。この取得ではモデルのターンを実行せず、トークンも消費しません。

ライブ取得が無効または利用できない場合は、`~/.codex/sessions` 内のレート制限イベントを参照します。このフォールバックは Codex CLI がターンを実行したときだけ更新されるため、古い値になる場合があります。**stale** バッジは、現在値ではなく最後に取得できた値を表示していることを示します。API キー構成など、サブスクリプションクォータを持たないアカウントではデータが表示されないことがあります。

Claude のクォータは Claude Code の statusline Hook 経由で受信します。メニューバーに常時表示されるパーセント値は Claude のクォータで、メニューバードロップダウンと Dashboard には Claude / Codex の両方の詳細が表示されます。Claude の履歴コストはローカルデータを有界に走査した推定値で、請求額ではありません。上限に達した場合は **partial** と表示されることがあります。

## Auto Approve

**Settings → Auto Approve** で **Automatically approve all permission requests** を有効にすると、届いたすべての Claude Code 許可リクエストを即時 Allow できます。

有効な間は次のように動作します。

- すべての要求されたツールを確認なしで許可
- 有効にした時点ですでに許可待ちのリクエストも Allow
- 新しい許可リクエストは macOS／iPhone 通知および許可待ち一覧に表示しない
- 各承認を Recent Activity に **Auto-approved** として記録
- asuku を再起動しても、明示的に OFF にするまで設定を保持

> **警告:** Auto Approve を有効にすると、シェルコマンドやファイル変更を含むすべての要求されたツール実行を Claude Code が確認なしで行えます。初期値は OFF です。信頼できるセッションと環境でのみ有効にしてください。

## Auto-Timeout

アプリ側のタイムアウトは初期値 280秒で有効になっており、Claude Code の300秒 Hook タイムアウトより安全に短く設定されています。

**Settings → Auto-Timeout** では次の設定ができます。

- 10〜280秒の範囲で10秒刻みにタイムアウトを選択
- Auto-Timeout を無効にし、Claude Code の300秒ハードリミットまで応答を待機

設定を変更すると、すでに許可待ちのリクエストにも新しいタイムアウトが適用されます。

## データとプライバシー

Dashboard のデータには、ローカルの Claude Code 設定、statusline、テレメトリ、セッションファイルに加え、Codex のレート制限メタデータとローカルセッション記録を使用します。Codex のライブクォータ取得では、`codex app-server` にメタデータのみを問い合わせます。

許可リクエストの詳細が Mac の外へ送信されるのは、ntfy 通知を有効にした場合だけです。asuku は送信前に既知の機密情報パターンをマスクしますが、完全な秘匿を保証するものではありません。作業ディレクトリ、ファイルパス、未対応の機密値が含まれる場合があります。リモート通知を有効にする前に、利用する ntfy サーバーと通知内容を確認してください。

## iPhone 通知（ntfy）

Claude Code の許可リクエストを iPhone でも受信し、リモートで応答できます。Mac から離れているときに便利なオプション機能です。

### 仕組み

1. 許可リクエストが届くと、asuku が [ntfy.sh](https://ntfy.sh) 経由でプッシュ通知を送信
2. iPhone に **Allow** / **Deny** ボタン付き通知が届く
3. ボタンをタップすると、認証付き Webhook が [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) 経由で Mac に届く
4. Mac と iPhone のうち、先に行った応答が採用され、もう一方は無視される

### 前提

1. iPhone に [ntfy アプリ](https://apps.apple.com/app/ntfy/id1625396347) をインストール
2. asuku の **Settings** で **iPhone Notifications (ntfy)** を有効化
3. iPhone の ntfy アプリで Settings に表示されたトピック（例: `asuku-xxxxxxxx-...`）を購読

続いて Cloudflare Tunnel を設定し、ntfy からの Webhook コールバックを Mac にルーティングします。

### トンネルのセットアップ

1. cloudflared をインストールします。

   ```bash
   brew install cloudflare/cloudflare/cloudflared
   ```

2. トンネルを起動します。

   ```bash
   cloudflared tunnel --url http://localhost:8945
   ```

3. 表示された `https://xxxxx.trycloudflare.com` URL をコピーし、Settings の **Webhook URL** に貼り付けます。

次の許可リクエストから Mac と iPhone の両方に通知が届きます。

> **Note:** Quick Tunnel の URL は cloudflared を再起動するたびに変わります。恒久的な URL が必要な場合は、[Cloudflare Zero Trust ダッシュボード](https://one.dash.cloudflare.com/) でトークンを取得し、[Named Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) を使用してください。

### Docker セットアップ（代替）

同梱の Docker スクリプトで cloudflared と、オプションでセルフホスト ntfy サーバーを起動できます。

```bash
git clone https://github.com/ushironoko/asuku.git
cd asuku

# ntfy.sh 公開サーバーを使う場合（最も簡単）
./docker/start.sh

# セルフホスト ntfy サーバーも起動する場合
./docker/start.sh --selfhosted

# 恒久的なホスト名を持つ Named Tunnel を使う場合
./docker/start.sh --token <CLOUDFLARE_TUNNEL_TOKEN>

# Named Tunnel とセルフホスト ntfy を併用する場合
./docker/start.sh --selfhosted --token <CLOUDFLARE_TUNNEL_TOKEN>
```

Quick Tunnel モードでは、生成された Webhook URL と、`--selfhosted` の場合は ntfy Server URL が表示されます。これらを **Settings → iPhone Notifications (ntfy)** に入力し、セルフホスト時は iPhone アプリにもサーバーを追加してください。

Named Tunnel モードでは、Cloudflare Zero Trust で公開ホスト名を設定します。Webhook 用ホスト名は `http://host.docker.internal:8945` へルーティングし、セルフホスト ntfy を使う場合は `http://ntfy:80` へ向けた別のホスト名も追加します。設定した公開ホスト名を asuku Settings に入力してください。

> **iPhone でセルフホスト ntfy を使う場合:** 同梱の Compose ファイルは基本的なサーバーを起動しますが、[iOS の即時通知転送](https://docs.ntfy.sh/config/#ios-instant-notifications)は設定しません。短時間で期限切れになる許可リクエストに利用する前に、`docker/docker-compose.yml` の `ntfy` サービスへ次の `environment` ブロックを追加してください。
>
> ```yaml
> environment:
>   - NTFY_BASE_URL=https://<public-ntfy-host>
>   - NTFY_UPSTREAM_BASE_URL=https://ntfy.sh
> ```
>
> Quick Tunnel では、最初に `./docker/start.sh --selfhosted` を実行して ntfy の公開 URL を取得し、上記の値を追加してから、トンネル URL を変えないよう ntfy コンテナだけを再作成します。
>
> ```bash
> docker compose -f docker/docker-compose.yml --profile selfhosted up -d --force-recreate ntfy
> ```
>
> Named Tunnel では、設定済みの ntfy 公開ホスト名を使い、サービスを起動する前に上記の値を追加してください。

### 停止

```bash
# cloudflared を直接実行している場合は Ctrl+C で停止

# Docker の全プロファイルを停止
docker compose -f docker/docker-compose.yml --profile selfhosted --profile selfhosted-tunnel down
```

## トラブルシューティング

**許可リクエスト通知が表示されない**

- **システム設定 → 通知 → asuku** で通知が有効になっており、スタイルが **通知パネル（Alerts）** になっているか確認
- Hook を再インストールし、`~/.claude/settings.json` に `asuku-hook` のエントリがあるか確認
- メニューバードロップダウンで IPC Server が **Running** になっているか確認

**Claude のセッションまたはクォータが表示されない**

- Hook をインストールまたは再インストールし、`~/.claude/settings.json` の `statusLine.command` に `asuku-hook` と `statusline` サブコマンドが含まれるか確認
- Claude Code を起動し、statusline が描画されるまで待機
- API キーアカウントではサブスクリプションクォータを利用できない場合があります

**Codex クォータが表示されない**

- Codex CLI がインストールおよび認証済みで、実行可能か確認
- **Settings → Codex Quota → Show live Codex rate limits** が有効か確認
- フォールバックを使う場合は Codex CLI でターンを実行し、`~/.codex/sessions` が存在するか確認
- API キーアカウントではサブスクリプションクォータを利用できない場合があります

**iPhone 通知が届かない**

- Settings で Webhook Server に緑のインジケーターが表示されているか確認
- 認証情報なしでローカル到達を確認: `curl -i -X POST http://localhost:8945/webhook/allow/00000000-0000-0000-0000-000000000000`（`403` が返れば、ローカルサーバーへ到達し、未認証リクエストが拒否されています。iPhone からのトンネル疎通を確認するものではありません）
- cloudflared トンネルが起動中で、Webhook URL が設定されているか確認

**ポート競合**

- ポート 8945 が使用中の場合は、Settings で **Webhook Port** を変更し、Webhook Server を再起動
- 手動 cloudflared の URL、Docker Compose の `tunnel-webhook` 転送先、または Named Tunnel のルートも同じ新しいポートに変更

## ソースからビルド

```bash
# ビルドして起動
scripts/build-app.sh
open .build/asuku.app

# リリースビルド（Universal Binary）
scripts/build-app.sh --release --universal --version 0.4.3
```

Swift 6.0+ が必要です。

## 開発

```bash
# ビルド
swift build

# すべてのテストを実行
swift test

# .app バンドルを生成
scripts/build-app.sh

# LLVM カバレッジレポートを生成
scripts/coverage.sh
```

## ライセンス

MIT
