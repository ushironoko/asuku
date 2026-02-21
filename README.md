# asuku

macOS menu bar app for managing [Claude Code](https://docs.anthropic.com/en/docs/claude-code) permission requests via native notifications.

When Claude Code needs permission to run a tool (Bash, Write, Edit, etc.), asuku delivers it as a macOS notification with Allow / Deny actions. You can also respond from your iPhone via [ntfy](https://ntfy.sh).

[Japanese / 日本語](README-jp.md)

## Features

- **macOS notifications** — Alert-style with Allow / Deny actions
- **Menu bar UI** — Pending requests, quick actions, recent activity
- **iPhone notifications** — Respond remotely via ntfy + Cloudflare Tunnel (opt-in)
- **Auto-deny timeout** — Automatically denies after 280s
- **Sensitive data masking** — Tokens and API keys are masked in notifications
- **One-click hook install** — Registers hooks in Claude Code settings
- **Launch at login**

## Requirements

- macOS 14.0 (Sonoma) or later
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed

## Getting Started

### 1. Install

```bash
brew tap ushironoko/tap
brew install --no-quarantine --cask asuku
```

> **Note:** `--no-quarantine` is needed because the app is ad-hoc signed (not notarized by Apple). Without it, macOS Gatekeeper may block the app.

### 2. Install the hook

Click **"Install Hook..."** in the menu bar dropdown, or go to **Settings → Install Hook to Claude Code**.

This registers asuku as a [Claude Code hook](https://docs.anthropic.com/en/docs/claude-code/hooks) in `~/.claude/settings.json`.

### 3. Configure notifications

On first launch, grant notification permission when prompted. Then go to **System Settings → Notifications → asuku** and set the style to **Alerts** (not Banners) so that Allow / Deny buttons are always visible.

### 4. Use it

Start Claude Code as usual. When it needs permission, you'll see:

- A **macOS notification** with Allow / Deny buttons
- The request in the **menu bar dropdown** with Allow / Deny buttons

Respond from either place. If you don't respond within 280 seconds, the request is automatically denied.

## iPhone Notifications (ntfy)

Optionally receive permission requests on your iPhone and respond remotely. Useful when you're away from your Mac while Claude Code is running.

### How it works

1. Permission request arrives → asuku sends a push notification via [ntfy.sh](https://ntfy.sh)
2. Your iPhone shows the notification with **Allow** / **Deny** buttons
3. Tapping a button sends a webhook back through [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) to your Mac
4. Whichever responds first (Mac or iPhone) wins — the other is ignored

### Prerequisites

1. Install the [ntfy app](https://apps.apple.com/app/ntfy/id1625396347) on your iPhone
2. In asuku **Settings**, enable **"iPhone Notifications (ntfy)"**
3. On your iPhone, subscribe to the topic shown in Settings (e.g. `asuku-xxxxxxxx-...`)

Then choose either Docker or manual setup below to configure Cloudflare Tunnel.

### Quick setup with Docker

```bash
# Using ntfy.sh public server (simplest)
./docker/start.sh

# Or with a self-hosted ntfy server (more private)
./docker/start.sh --selfhosted
```

The script starts cloudflared (and optionally ntfy) in Docker, then prints the tunnel URLs. Paste them into **Settings → iPhone Notifications (ntfy)**.

### Manual setup

1. Install cloudflared:
   ```bash
   brew install cloudflare/cloudflare/cloudflared
   ```
2. Start the tunnel:
   ```bash
   cloudflared tunnel --url http://localhost:8945
   ```
3. Copy the `https://xxxxx.trycloudflare.com` URL and paste it into **Webhook URL** in Settings

That's it. The next permission request will appear on both your Mac and iPhone.

> **Note:** Quick Tunnel URLs change every time cloudflared restarts. For a permanent URL, use a Named Tunnel with `--token`:
> ```bash
> ./docker/start.sh --token <CLOUDFLARE_TUNNEL_TOKEN>
> ```
> Obtain a token from the [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com/).

### Stopping

```bash
# If using Docker
docker compose -f docker/docker-compose.yml down

# If manual
# Just stop the cloudflared process (Ctrl+C)
```

## Troubleshooting

**Notifications don't appear**
- Check System Settings → Notifications → asuku is enabled with **Alerts** style
- Verify the hook is installed: look for `asuku-hook` entries in `~/.claude/settings.json`

**iPhone notifications not working**
- Verify the webhook server shows a green indicator in Settings
- Test the webhook manually: `curl -X POST http://localhost:8945/webhook/allow/test-id` (should return 403 — this confirms the server is running)
- Check that the cloudflared tunnel is running and the Webhook URL is set

**Port conflict**
- If port 8945 is in use, change the **Webhook Port** in Settings and restart the webhook server

## Building from source

```bash
# Build and launch
scripts/build-app.sh
open .build/asuku.app

# Release build (Universal Binary)
scripts/build-app.sh --release --universal --version 0.1.0
```

Requires Swift 6.0+.

## Development

```bash
# Build
swift build

# Run tests
swift test

# Build .app bundle
scripts/build-app.sh
```

## License

MIT
