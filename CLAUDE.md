# CLAUDE.md

## Project Overview

**asuku** is a native macOS menu bar application (Swift/SwiftUI) that manages permission requests from Claude Code. It delivers tool execution permission requests (Bash, Write, Edit, etc.) as native macOS notifications with Allow/Deny actions, with optional iPhone notification support via ntfy and Cloudflare Tunnel.

- **Language:** Swift 6.0+
- **Platform:** macOS 14.0+ (Sonoma)
- **Build system:** Swift Package Manager
- **Bundle ID:** `com.asuku.app`
- **License:** MIT

## Architecture

The project has three main targets:

| Target | Type | Path | Description |
|--------|------|------|-------------|
| `AsukuShared` | Library | `Sources/AsukuShared/` | IPC protocol definitions, socket path resolution, webhook parsing |
| `AsukuApp` | Executable | `Sources/AsukuApp/` | Menu bar app with notifications, settings UI, IPC server, webhook server |
| `asuku-hook` | Executable | `Sources/AsukuHook/` | CLI hook binary invoked by Claude Code, communicates with app via Unix Domain Socket |

### Data Flow

1. Claude Code invokes `asuku-hook` via hook config in `~/.claude/settings.json`
2. `asuku-hook` reads JSON from stdin, sends it to `AsukuApp` over a Unix Domain Socket
3. `AsukuApp` shows a macOS notification (and optionally pushes to iPhone via ntfy)
4. User responds Allow/Deny via notification action, menu bar UI, or iPhone webhook
5. Response flows back through the UDS to `asuku-hook`, which writes JSON to stdout
6. Claude Code reads the hook response and proceeds accordingly

### Key Files

- `Sources/AsukuApp/AsukuApp.swift` — `@main` entry point, menu bar extra + settings window
- `Sources/AsukuApp/AppState.swift` — `@Observable` central state container
- `Sources/AsukuApp/IPCServer.swift` — UDS server (NWListener) accepting hook connections
- `Sources/AsukuApp/PendingRequestManager.swift` — Actor managing request lifecycle with 280s auto-deny timeout
- `Sources/AsukuApp/WebhookServer.swift` — HTTP server on localhost:8945 for ntfy webhook callbacks
- `Sources/AsukuApp/NtfyNotifier.swift` — Push notifications to ntfy.sh
- `Sources/AsukuApp/HookInstaller.swift` — Writes hook config to `~/.claude/settings.json`
- `Sources/AsukuHook/IPCClient.swift` — UDS client with retry and timeout handling
- `Sources/AsukuShared/IPCProtocol.swift` — Core IPC message types and wire format (4-byte length prefix + JSON)
- `Sources/AsukuShared/SocketPath.swift` — Socket path resolution with fallbacks

## Build & Development Commands

```bash
# Build all targets
swift build

# Run tests (all test targets)
swift test

# Build macOS .app bundle (requires macOS with codesign)
scripts/build-app.sh

# Docker: start Cloudflare Tunnel for iPhone notifications
docker/start.sh                    # Quick Tunnel (ephemeral URL)
docker/start.sh --selfhosted       # Quick Tunnel + self-hosted ntfy
docker/start.sh --token <TOKEN>    # Named Tunnel (permanent URL)
```

## Test Structure

Tests use the **Swift Testing** framework (`@Test`, `#expect`) — not XCTest.

| Test Target | Path | Coverage |
|-------------|------|----------|
| `AsukuSharedTests` | `Tests/AsukuSharedTests/` | Wire format, IPC messages, AnyCodableValue, input sanitization, webhook parsing |
| `AsukuHookTests` | `Tests/AsukuHookTests/` | Hook input parsing, output generation, error handling |
| `IntegrationTests` | `Tests/IntegrationTests/` | Full IPC roundtrips, UDS server/client, concurrent requests |

## Code Conventions

### Naming

- Types (classes, structs, enums, protocols): `PascalCase`
- Functions, variables, properties: `camelCase`
- Enum cases: `camelCase` (e.g., `PermissionDecision.allow`)

### Concurrency

- Swift 6.0 strict concurrency throughout
- `@MainActor` for all UI-bound code (SwiftUI views, AppState)
- `actor` for thread-safe mutable state (`PendingRequestManager`)
- `@unchecked Sendable` only where compile-time checking is infeasible (`IPCServer`, `WebhookServer`)
- `async`/`await` and `Task {}` for async operations

### Error Handling

- Custom error enums implementing `Error` + `CustomStringConvertible`
- Named error types: `SocketPathError`, `IPCClientError`, `WebhookServerError`, `PermissionRequestError`
- Background operations (ntfy push) fail silently with logging
- `try`/`catch` at call sites; no force unwraps

### Networking

- Apple `Network` framework (`NWListener`, `NWConnection`) for both UDS and HTTP
- `URLSession` for outbound HTTP (ntfy)
- Manual HTTP request/response parsing for the webhook server (no HTTP framework dependency)

### Data Serialization

- `JSONEncoder`/`JSONDecoder` with `.iso8601` date strategy
- Custom `Codable` for dynamic types (`AnyCodableValue`)
- Wire format: 4-byte big-endian length prefix followed by JSON payload

### Security

- Socket directory: `0700` permissions; socket file: `0600`
- Webhook token validated with constant-time comparison
- `InputSanitizer` masks sensitive patterns (TOKEN=, API_KEY=, Bearer, passwords) before display
- 280-second auto-deny timeout (safely under Claude Code's 300s hook timeout)

### State Management

- `@Observable` macro (Observation framework) on `AppState`
- `@State` for SwiftUI view-local state
- `UserDefaults` for persistent settings (`NtfyConfig`)
- `didSet` property observers for reactive UserDefaults writes

## Dependencies

No external Swift package dependencies. The project relies solely on Apple system frameworks:

- `Foundation`, `SwiftUI`, `AppKit`, `Network`, `UserNotifications`, `Observation`, `ServiceManagement`, `Testing`

## Project-Specific Notes

- The hook binary name is `asuku-hook` (with hyphen), matching the target name in Package.swift
- Socket path has multiple fallbacks to handle the Unix socket path 104-character limit: `~/Library/Application Support/asuku/asuku.sock` → `$XDG_RUNTIME_DIR/asuku/asuku.sock` → `/tmp/asuku-<uid>/asuku.sock`
- The webhook server defaults to port 8945 on localhost
- Docker configuration in `docker/` supports two tunnel modes: Quick Tunnel (ephemeral trycloudflare.com URLs) and Named Tunnel (permanent, requires Cloudflare token)
- README exists in both English (`README.md`) and Japanese (`README-jp.md`)

## Commit Message Style

Follow conventional-commit-style prefixes as used in this repo:

- `fix:` for bug fixes
- `docs:` for documentation changes
- `test:` for test additions/changes
- `feat:` or descriptive sentence for new features
- Merge commits use GitHub's default format
