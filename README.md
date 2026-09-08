# asuku

A native macOS menu bar app for approving [Claude Code](https://docs.anthropic.com/en/docs/claude-code) permission requests and monitoring Claude Code and [Codex CLI](https://developers.openai.com/codex/cli/) usage.

When Claude Code needs permission to run a tool (Bash, Write, Edit, etc.), asuku delivers the request as a macOS notification with Allow / Deny actions. It also provides a dashboard for Claude Code sessions and local usage data, plus Claude and Codex subscription quota monitoring. You can optionally respond to permission requests from your iPhone via [ntfy](https://ntfy.sh).

> **Codex support:** asuku displays Codex subscription quota and rate-limit information. Permission approvals and session monitoring currently use Claude Code hooks; asuku does not install a permission hook for Codex.

[Japanese / 日本語](README-jp.md)

## Supported integrations

| Capability | Claude Code | Codex CLI |
|---|:---:|:---:|
| Permission requests with Allow / Deny | Yes | — |
| Agent notifications | Yes | — |
| Live session status and history | Yes | — |
| 5-hour / 7-day subscription quota | Yes | Yes |
| Local tool usage and cost analytics | Yes | — |

## Features

- **Native macOS notifications** — Permission requests with Allow / Deny actions, plus Claude Code agent notifications
- **Menu bar UI** — Pending requests, quick actions, recent activity, live session status, and quota summaries
- **Dashboard** — Active sessions, plugins, session history, tool usage charts, and quota details
- **Claude and Codex quota** — 5-hour / 7-day subscription usage, reset times, freshness state, and last-known values
- **Claude cost visibility** — Current-session measured cost and a separate local historical token-cost estimate
- **iPhone notifications** — Respond remotely through ntfy + Cloudflare Tunnel (opt-in)
- **Auto Approve** — Optionally allow every Claude Code permission request immediately (disabled by default)
- **Configurable timeout** — Auto-deny after 10–280 seconds, or disable the app-level timeout
- **Sensitive data masking** — Known secret patterns such as tokens, API keys, passwords, and authorization values are masked in notifications
- **One-click hook install** — Registers permission, notification, and statusline hooks in Claude Code settings
- **Launch at login**

## Requirements

- macOS 14.0 (Sonoma) or later
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) for permission handling, notifications, session status, and Claude usage data
- [Codex CLI](https://developers.openai.com/codex/cli/) installed and authenticated for live, account-wide Codex quota (optional)

If Codex CLI is unavailable, asuku falls back to the latest rate-limit data in `~/.codex/sessions`, when present.

## Getting Started

### 1. Install

```bash
brew tap ushironoko/tap
brew install --cask asuku
```

> **Note:** asuku is ad-hoc signed and is not notarized by Apple. If macOS Gatekeeper blocks the app on first launch, run:
>
> ```bash
> xattr -cr /Applications/asuku.app
> ```

### 2. Launch and allow notifications

Open asuku. Grant notification permission when prompted, then go to **System Settings → Notifications → asuku** and select **Alerts** instead of Banners so notification actions are easier to access.

### 3. Install the Claude Code hook

Click **Install Hook...** in the menu bar dropdown, or open **Settings → Install Hook to Claude Code**.

asuku adds `PermissionRequest`, `Notification`, and `statusLine` integration to `~/.claude/settings.json`. Existing hook entries that do not contain `asuku-hook` are preserved, and an existing non-asuku statusline command is chained after `asuku-hook`. Reinstalling replaces an entire `PermissionRequest` or `Notification` entry that contains `asuku-hook`, so keep unrelated commands in separate hook entries.

### 4. Use Claude Code

Start Claude Code as usual. When it needs permission, the request appears in:

- A **macOS notification** with Allow / Deny buttons
- The **menu bar dropdown** with Allow / Deny buttons

The first response wins. By default, unanswered requests are denied after 280 seconds.

### 5. Open the Dashboard

Choose **Dashboard...** from the menu bar dropdown. The dashboard contains:

| Tab | Contents |
|---|---|
| **Sessions** | Active Claude Code sessions, model, context usage, cost, changed lines, project, and a QR code for the Claude session URL when available |
| **Plugins** | Installed Claude Code plugins and their enabled state |
| **History** | Recent sessions with copyable `claude --resume <session-id>` commands |
| **Usage** | Tool, agent, and command counts from local Claude Code telemetry plus current activity |
| **Quota** | Claude/Codex 5-hour and 7-day quota, reset times, Claude session cost, and a local historical cost estimate |

## Codex quota

Codex quota monitoring requires no asuku hook in Codex.

With **Settings → Codex Quota → Show live Codex rate limits** enabled (the default), asuku asks the authenticated Codex CLI for account-wide rate-limit metadata about every two minutes. This includes Codex usage from other clients on the same account, such as pi, and does not run a model turn or spend tokens.

If the live read is disabled or unavailable, asuku falls back to rate-limit events in `~/.codex/sessions`. The fallback updates only after Codex CLI runs a turn, so it may be stale. A **stale** badge means asuku is showing the last known observation rather than a current value. Accounts without subscription quota, such as some API-key configurations, may show no quota data.

Claude quota is received through the Claude Code statusline hook. The always-visible menu bar percentage represents Claude quota; the menu bar dropdown and Dashboard show both Claude and Codex details. The historical Claude cost is a bounded local estimate, not a billing total, and may be marked **partial** when the scan reaches its limit.

## Auto Approve

Open **Settings → Auto Approve** and enable **Automatically approve all permission requests** to allow every incoming Claude Code permission request immediately.

While enabled:

- All requested tools are allowed without review
- Requests already waiting for a response are allowed when you enable the setting
- New permission requests do not appear in macOS or iPhone notifications, or in the pending-request list
- Each approval is recorded as **Auto-approved** in Recent Activity
- The setting remains enabled after restarting asuku until you turn it off

> **Warning:** Auto Approve lets Claude Code run any requested tool without confirmation, including shell commands and file modifications. It is disabled by default. Enable it only for trusted sessions and environments.

## Auto-timeout

The app-level timeout is enabled by default at 280 seconds, safely below Claude Code's 300-second hook timeout.

In **Settings → Auto-Timeout**, you can:

- Choose a timeout from 10 to 280 seconds in 10-second steps
- Disable auto-timeout so requests wait for your response until Claude Code's 300-second hard limit is reached

Changing the setting also reschedules requests that are already pending.

## Data and privacy

Dashboard data comes from local Claude Code settings, statusline, telemetry, and session files, plus Codex rate-limit metadata and local session records. Codex live quota uses a metadata-only `codex app-server` request.

Permission details leave your Mac only when ntfy notifications are enabled. asuku masks known secret patterns before sending notification text, but this is not a complete secrecy guarantee: working directories, file paths, and unrecognized sensitive values may still be included. Review your ntfy server choice and notification contents before enabling remote notifications.

## iPhone Notifications (ntfy)

Optionally receive Claude Code permission requests on your iPhone and respond remotely. This is useful when you are away from your Mac while Claude Code is running.

### How it works

1. A permission request arrives and asuku sends a push notification through [ntfy.sh](https://ntfy.sh)
2. Your iPhone shows the notification with **Allow** / **Deny** buttons
3. Tapping a button sends an authenticated webhook through [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) to your Mac
4. Whichever responds first (Mac or iPhone) wins; the other response is ignored

### Prerequisites

1. Install the [ntfy app](https://apps.apple.com/app/ntfy/id1625396347) on your iPhone
2. In asuku **Settings**, enable **iPhone Notifications (ntfy)**
3. On your iPhone, subscribe to the topic shown in Settings (for example, `asuku-xxxxxxxx-...`)

Then set up Cloudflare Tunnel to route webhook callbacks from ntfy to your Mac.

### Tunnel setup

1. Install cloudflared:

   ```bash
   brew install cloudflare/cloudflare/cloudflared
   ```

2. Start the tunnel:

   ```bash
   cloudflared tunnel --url http://localhost:8945
   ```

3. Copy the displayed `https://xxxxx.trycloudflare.com` URL and paste it into **Webhook URL** in Settings.

The next permission request will appear on both your Mac and iPhone.

> **Note:** Quick Tunnel URLs change every time cloudflared restarts. For a permanent URL, use a [Named Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) with a token from the [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com/).

### Docker setup (alternative)

You can use the included Docker scripts to run cloudflared and, optionally, a self-hosted ntfy server:

```bash
git clone https://github.com/ushironoko/asuku.git
cd asuku

# Use the public ntfy.sh server (simplest)
./docker/start.sh

# Run a self-hosted ntfy server too
./docker/start.sh --selfhosted

# Use a Named Tunnel with a permanent hostname
./docker/start.sh --token <CLOUDFLARE_TUNNEL_TOKEN>

# Named Tunnel plus self-hosted ntfy
./docker/start.sh --selfhosted --token <CLOUDFLARE_TUNNEL_TOKEN>
```

In Quick Tunnel mode, the script prints the generated Webhook URL and, with `--selfhosted`, the ntfy Server URL. Enter them in **Settings → iPhone Notifications (ntfy)** and add the self-hosted server in the iPhone app.

In Named Tunnel mode, configure the public hostname in Cloudflare Zero Trust instead: route the webhook hostname to `http://host.docker.internal:8945`. With self-hosted ntfy, add another hostname routed to `http://ntfy:80`. Enter those public hostnames in asuku Settings.

> **Self-hosted ntfy on iPhone:** The included Compose file starts a basic server but does not configure [iOS instant-notification forwarding](https://docs.ntfy.sh/config/#ios-instant-notifications). Before relying on short-lived permission requests, add the following `environment` block to the `ntfy` service in `docker/docker-compose.yml`:
>
> ```yaml
> environment:
>   - NTFY_BASE_URL=https://<public-ntfy-host>
>   - NTFY_UPSTREAM_BASE_URL=https://ntfy.sh
> ```
>
> With a Quick Tunnel, run `./docker/start.sh --selfhosted` once to obtain the public ntfy URL, add the values, then recreate only the ntfy container so the tunnel URL remains unchanged:
>
> ```bash
> docker compose -f docker/docker-compose.yml --profile selfhosted up -d --force-recreate ntfy
> ```
>
> With a Named Tunnel, use its configured ntfy hostname and add the values before starting the services.

### Stopping

```bash
# If cloudflared is running directly, stop it with Ctrl+C

# If using Docker, stop all profiles
docker compose -f docker/docker-compose.yml --profile selfhosted --profile selfhosted-tunnel down
```

## Troubleshooting

**Permission notifications do not appear**

- Check that notifications are enabled in **System Settings → Notifications → asuku** with the **Alerts** style
- Reinstall the hook and verify that `~/.claude/settings.json` contains `asuku-hook` entries
- Confirm that the menu bar dropdown shows the IPC server as **Running**

**Claude session or quota data does not appear**

- Install or reinstall the hook, then verify that `statusLine.command` in `~/.claude/settings.json` contains `asuku-hook` with the `statusline` subcommand
- Start Claude Code and wait for it to render the statusline
- Subscription quota may be unavailable for API-key accounts

**Codex quota does not appear**

- Confirm that Codex CLI is installed, authenticated, and runnable
- Check that **Settings → Codex Quota → Show live Codex rate limits** is enabled
- For fallback data, run a Codex CLI turn and confirm that `~/.codex/sessions` exists
- Subscription quota may be unavailable for API-key accounts

**iPhone notifications do not work**

- Verify that the Webhook Server shows a green indicator in Settings
- Test local reachability without credentials: `curl -i -X POST http://localhost:8945/webhook/allow/00000000-0000-0000-0000-000000000000` (a `403` confirms that the local server is reachable and rejected the unauthenticated request; it does not test the iPhone tunnel)
- Check that the cloudflared tunnel is running and the Webhook URL is set

**Port conflict**

- If port 8945 is in use, change **Webhook Port** in Settings and restart the webhook server
- Update the manual cloudflared URL, Docker Compose `tunnel-webhook` target, or Named Tunnel route to use the same new port

## Building from source

```bash
# Build and launch
scripts/build-app.sh
open .build/asuku.app

# Release build (Universal Binary)
scripts/build-app.sh --release --universal --version 0.4.3
```

Requires Swift 6.0+.

## Development

```bash
# Build
swift build

# Run all tests
swift test

# Generate an app bundle
scripts/build-app.sh

# Generate an LLVM coverage report
scripts/coverage.sh
```

## License

MIT
