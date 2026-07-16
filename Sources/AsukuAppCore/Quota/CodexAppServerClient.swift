import Foundation

// MARK: - Seam

/// Reads the current account-wide Codex rate limits via `codex app-server`.
///
/// This is the injectable seam `QuotaService` depends on: the production implementation
/// (`ProcessCodexAppServer`) spawns the CLI and runs the JSON-RPC conversation; tests substitute a
/// fake. The returned value is the raw `result` bytes of `account/rateLimits/read` (fed to
/// `CodexAppServerParser`), or nil on any failure — not logged in, binary missing, timeout, or a
/// protocol error. The read spends **zero tokens** (`account/*` is a metadata read; only `turn/*`
/// spends tokens, and this conversation never sends `turn/*`).
public protocol CodexAppServerRunning: Sendable {
    func readRateLimits() async -> Data?
}

// MARK: - Line-oriented duplex transport

/// A bidirectional, newline-framed transport to a JSON-RPC peer. Splitting the transport from the
/// conversation logic lets `CodexAppServerDriver` be integration-tested over an in-memory script,
/// with no real process — where the handshake ordering, id matching, and timeout actually live.
protocol LineDuplex: Sendable {
    /// Write one JSON-RPC message (the transport appends the newline).
    func writeLine(_ line: String) async
    /// The next inbound message line, or nil at EOF / after shutdown.
    func nextLine() async -> String?
    /// Tear down the transport (finish the inbound stream, close stdin, stop the child). Idempotent.
    func shutdown() async
}

// MARK: - JSON-RPC conversation driver (testable, no process)

/// Runs the `account/rateLimits/read` conversation over a `LineDuplex`.
///
/// Sequence: `initialize` (with `clientInfo`, opting into the experimental API) → await the id-0
/// response → `initialized` notification → `account/rateLimits/read` (id 1) → return that response's
/// raw `result` bytes. A hard timeout guards against a hung child. **No `turn/*` is ever sent.**
private enum ReadOutcome: Sendable {
    case done(Data?)
    case timedOut
}

enum CodexAppServerDriver {
    static let clientName = "asuku"
    static let clientVersion = "1.0"

    static let initializeRequest =
        #"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"clientInfo":{"name":"\#(clientName)","version":"\#(clientVersion)"},"capabilities":{"experimentalApi":true}}}"#
    static let initializedNotification = #"{"jsonrpc":"2.0","method":"initialized"}"#
    static let rateLimitsReadRequest = #"{"jsonrpc":"2.0","id":1,"method":"account/rateLimits/read","params":{}}"#

    private struct Envelope {
        let id: Int?
        let resultData: Data?
        let isError: Bool
    }

    static func readRateLimits(over transport: some LineDuplex, timeout: Duration = .seconds(8)) async -> Data? {
        let outcome = await withTaskGroup(of: ReadOutcome.self) { group -> ReadOutcome in
            group.addTask { .done(await conversation(over: transport)) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            // Whichever finished first, tear the transport down so a still-blocked nextLine() in the
            // sibling task unblocks (returns nil) and structured concurrency can drain it.
            await transport.shutdown()
            group.cancelAll()
            _ = await group.next()
            return first
        }
        switch outcome {
        case .done(let data): return data
        case .timedOut: return nil
        }
    }

    private static func conversation(over transport: some LineDuplex) async -> Data? {
        await transport.writeLine(initializeRequest)
        guard await awaitResponse(id: 0, over: transport) != nil else { return nil }
        await transport.writeLine(initializedNotification)
        await transport.writeLine(rateLimitsReadRequest)
        guard let env = await awaitResponse(id: 1, over: transport) else { return nil }
        return env.resultData
    }

    /// Read lines until the response with `wantedId` arrives. Notifications (no id) and responses
    /// with a different id are skipped; an RPC `error` for the wanted id, or EOF, yields nil.
    private static func awaitResponse(id wantedId: Int, over transport: some LineDuplex) async -> Envelope? {
        while let line = await transport.nextLine() {
            guard let env = parseEnvelope(line), let id = env.id else { continue }
            if id != wantedId { continue }
            if env.isError { return nil }
            return env
        }
        return nil
    }

    private static func parseEnvelope(_ line: String) -> Envelope? {
        guard
            let data = line.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let id = obj["id"] as? Int
        let isError = obj["error"] != nil
        var resultData: Data?
        if let result = obj["result"] {
            resultData = try? JSONSerialization.data(withJSONObject: result)
        }
        return Envelope(id: id, resultData: resultData, isError: isError)
    }
}

// MARK: - Newline framer

/// Accumulates arbitrary byte chunks (a read boundary is not a line boundary) and emits complete
/// newline-delimited lines. A pathological, unterminated frame past `maxFrame` is dropped rather
/// than grown without bound. Thread-safe (fed from `FileHandle.readabilityHandler`'s queue).
final class LineFramer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [UInt8] = []
    private let maxFrame: Int
    private let onLine: @Sendable (String) -> Void

    init(maxFrame: Int = 1 << 20, onLine: @escaping @Sendable (String) -> Void) {
        self.maxFrame = maxFrame
        self.onLine = onLine
    }

    func feed(_ data: Data) {
        lock.lock()
        buffer.append(contentsOf: data)
        var lines: [String] = []
        var lineStart = 0
        var i = 0
        while i < buffer.count {
            if buffer[i] == 0x0A {
                lines.append(String(decoding: buffer[lineStart..<i], as: UTF8.self))
                lineStart = i + 1
            }
            i += 1
        }
        if lineStart > 0 { buffer.removeFirst(lineStart) }
        if buffer.count > maxFrame { buffer.removeAll(keepingCapacity: false) }
        lock.unlock()
        for line in lines { onLine(line) }
    }
}

// MARK: - Process-backed transport

/// A single-consumer async line queue. `FileHandle.readabilityHandler` runs serially per handle, so
/// `send` is called in order; `next()` (the driver, the only consumer) drains buffered lines then
/// awaits the next one. Lock-based rather than an `AsyncStream` iterator so it composes cleanly with
/// the owning actor (a `mutating` stream iterator cannot be awaited on actor-isolated storage).
final class LineChannel: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [String] = []
    private var waiter: CheckedContinuation<String?, Never>?
    private var finished = false

    func send(_ line: String) {
        lock.lock()
        if let waiter {
            self.waiter = nil
            lock.unlock()
            waiter.resume(returning: line)
        } else {
            buffer.append(line)
            lock.unlock()
        }
    }

    func finish() {
        lock.lock()
        finished = true
        if let waiter {
            self.waiter = nil
            lock.unlock()
            waiter.resume(returning: nil)
        } else {
            lock.unlock()
        }
    }

    func next() async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            lock.lock()
            if !buffer.isEmpty {
                let line = buffer.removeFirst()
                lock.unlock()
                continuation.resume(returning: line)
            } else if finished {
                lock.unlock()
                continuation.resume(returning: nil)
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }
}

/// A process may terminate on SIGPIPE if we write to a child that already closed its stdin. Ignore
/// it once (lazily, process-wide) so a late write becomes a caught EPIPE instead of a crash.
private let ignoreSIGPIPEOnce: Void = {
    signal(SIGPIPE, SIG_IGN)
}()

/// Spawns `codex app-server` and exposes its stdio as a `LineDuplex`. All `Process`/`FileHandle`
/// mutation is confined to this actor (never handed to another task), avoiding cross-actor sends of
/// non-Sendable Foundation types. stdout is framed into lines via a `LineChannel`; stderr is drained
/// and discarded so a full stderr pipe can't stall the child.
actor ProcessLineDuplex: LineDuplex {
    private let process: Process
    private let stdinHandle: FileHandle
    private let stdoutHandle: FileHandle
    private let stderrHandle: FileHandle
    private let channel: LineChannel
    private var didShutdown = false

    static func start(binary: String, path: String, arguments: [String] = ["app-server"]) -> ProcessLineDuplex? {
        _ = ignoreSIGPIPEOnce
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path
        process.environment = env
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            return nil
        }
        return ProcessLineDuplex(
            process: process,
            stdin: inPipe.fileHandleForWriting,
            stdout: outPipe.fileHandleForReading,
            stderr: errPipe.fileHandleForReading
        )
    }

    private init(process: Process, stdin: FileHandle, stdout: FileHandle, stderr: FileHandle) {
        self.process = process
        self.stdinHandle = stdin
        self.stdoutHandle = stdout
        self.stderrHandle = stderr
        let channel = LineChannel()
        self.channel = channel

        let framer = LineFramer { channel.send($0) }
        stdout.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                channel.finish()
            } else {
                framer.feed(data)
            }
        }
        stderr.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
    }

    func writeLine(_ line: String) async {
        guard !didShutdown else { return }
        try? stdinHandle.write(contentsOf: Data((line + "\n").utf8))
    }

    func nextLine() async -> String? {
        await channel.next()
    }

    func shutdown() async {
        guard !didShutdown else { return }
        didShutdown = true
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        channel.finish()
        try? stdinHandle.close()
        if process.isRunning { process.terminate() } // SIGTERM
        let pid = process.processIdentifier
        try? await Task.sleep(for: .milliseconds(500))
        if process.isRunning { kill(pid, SIGKILL) }
        process.waitUntilExit()
    }
}

// MARK: - Binary discovery

/// Locates the `codex` executable and builds the child PATH. A GUI app launched from Finder inherits
/// a minimal PATH, so we probe well-known absolute directories rather than relying on inherited PATH.
enum CodexBinary {
    /// Absolute directories to probe (and to seed the child PATH with). The child PATH must include
    /// these so a Node/Bun launcher shim (`#!/usr/bin/env node`) can resolve its interpreter.
    static func searchDirectories(
        home: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        var dirs = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            home + "/.bun/bin",
            home + "/.local/bin",
            home + "/.codex/bin",
            home + "/.deno/bin",
            "/usr/bin",
            "/bin",
        ]
        // Absolute entries from the inherited PATH (relative/empty entries are rejected for safety).
        if let path = environment["PATH"] {
            for entry in path.split(separator: ":", omittingEmptySubsequences: true) where entry.hasPrefix("/") {
                dirs.append(String(entry))
            }
        }
        var seen = Set<String>()
        return dirs.filter { seen.insert($0).inserted }
    }

    /// Absolute path to a runnable `codex`, or nil if none is found.
    static func locate(
        fileManager: FileManager = .default,
        home: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        for dir in searchDirectories(home: home, environment: environment) {
            let candidate = dir + "/codex"
            if isRunnable(candidate, fileManager: fileManager) { return candidate }
        }
        return nil
    }

    /// PATH string to hand the child so a launcher shim can resolve its interpreter.
    static func childPath(
        home: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        searchDirectories(home: home, environment: environment).joined(separator: ":")
    }

    /// True when `path` (following symlinks — bun/npm install `codex` as a symlink) resolves to an
    /// executable regular file.
    private static func isRunnable(_ path: String, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return false }
        return fileManager.isExecutableFile(atPath: path)
    }
}

// MARK: - Production implementation

/// `CodexAppServerRunning` backed by a real `codex app-server` subprocess.
public struct ProcessCodexAppServer: CodexAppServerRunning {
    private let timeout: Duration
    private let locate: @Sendable () -> String?
    private let childPath: @Sendable () -> String

    public init(timeout: Duration = .seconds(8)) {
        self.init(timeout: timeout, locate: { CodexBinary.locate() }, childPath: { CodexBinary.childPath() })
    }

    init(timeout: Duration,
         locate: @escaping @Sendable () -> String?,
         childPath: @escaping @Sendable () -> String) {
        self.timeout = timeout
        self.locate = locate
        self.childPath = childPath
    }

    public func readRateLimits() async -> Data? {
        guard let binary = locate() else { return nil }
        guard let transport = ProcessLineDuplex.start(binary: binary, path: childPath()) else { return nil }
        return await CodexAppServerDriver.readRateLimits(over: transport, timeout: timeout)
    }
}
