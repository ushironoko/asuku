import Foundation
import Testing

@testable import AsukuAppCore

@Suite("CodexBinary discovery")
struct CodexBinaryTests {
    /// Create a temp dir containing an executable regular file named `codex`, returning the dir.
    private func tempDirWithExecutableCodex() throws -> String {
        let dir = NSTemporaryDirectory() + "asuku-codexbin-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/codex"
        FileManager.default.createFile(atPath: path, contents: Data("#!/bin/sh\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
        return dir
    }

    @Test("locate finds an executable codex on an absolute PATH entry")
    func locateFromPath() throws {
        let dir = try tempDirWithExecutableCodex()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let found = CodexBinary.locate(home: "/nonexistent-home", environment: ["PATH": dir])
        #expect(found == dir + "/codex")
    }

    @Test("locate returns nil when no codex exists")
    func locateMissing() {
        let empty = NSTemporaryDirectory() + "asuku-codexbin-empty-\(UUID().uuidString)"
        let found = CodexBinary.locate(home: "/nonexistent-home", environment: ["PATH": empty])
        #expect(found == nil)
    }

    @Test("locate ignores a directory named codex")
    func locateIgnoresDirectory() throws {
        let dir = NSTemporaryDirectory() + "asuku-codexbin-dir-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir + "/codex", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(CodexBinary.locate(home: "/nonexistent-home", environment: ["PATH": dir]) == nil)
    }

    @Test("childPath rejects relative/empty PATH entries but keeps absolute ones")
    func childPathFiltersRelative() {
        let path = CodexBinary.childPath(home: "/home/u", environment: ["PATH": "relative:/abs/bin::/another"])
        let entries = path.split(separator: ":").map(String.init)
        #expect(entries.contains("/abs/bin"))
        #expect(entries.contains("/another"))
        #expect(!entries.contains("relative"))
        #expect(!entries.contains(""))
        // Well-known dirs are always seeded so a launcher shim can resolve its interpreter.
        #expect(entries.contains("/opt/homebrew/bin"))
    }

    @Test("app-server retries a later Codex candidate when an earlier launcher cannot run")
    func appServerRetriesCandidates() async throws {
        let directory = NSTemporaryDirectory() + "asuku-codex-candidates-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let brokenDirectory = directory + "/.bun/bin"
        let workingDirectory = directory + "/.local/bin"
        try FileManager.default.createDirectory(atPath: brokenDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true)

        let broken = brokenDirectory + "/codex"
        FileManager.default.createFile(
            atPath: broken,
            contents: Data("#!/usr/bin/env asuku-missing-interpreter\n".utf8),
            attributes: [.posixPermissions: 0o755]
        )

        let working = workingDirectory + "/codex"
        let appServerStub = #"""
        #!/bin/sh
        IFS= read -r _
        printf '%s\n' '{"jsonrpc":"2.0","id":0,"result":{"userAgent":"stub"}}'
        IFS= read -r _
        IFS= read -r _
        printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"rateLimits":{"primary":{"usedPercent":73,"windowDurationMins":300}}}}'
        """#
        FileManager.default.createFile(
            atPath: working,
            contents: Data(appServerStub.utf8),
            attributes: [.posixPermissions: 0o755]
        )

        let candidates = CodexBinary.locateAll(
            home: directory,
            environment: ["PATH": "/usr/bin:/bin"]
        ).filter { $0 == broken || $0 == working }
        #expect(candidates == [broken, working])

        let server = ProcessCodexAppServer(
            timeout: .seconds(2),
            locateCandidates: { candidates },
            childPath: { "/usr/bin:/bin" }
        )
        let data = try #require(await server.readRateLimits())
        let usage = try #require(CodexAppServerParser.parse(data, now: Date()))
        #expect(usage.window(.fiveHour)?.usedPercent == 73)
    }

    /// Live end-to-end against the installed `codex`. Skipped unless ASUKU_LIVE_CODEX=1 (needs a
    /// logged-in codex). Verifies the real ProcessCodexAppServer transport + parser round-trip.
    @Test("live: reads real account rate limits from the installed codex",
          .enabled(if: ProcessInfo.processInfo.environment["ASUKU_LIVE_CODEX"] == "1"))
    func liveReadRateLimits() async throws {
        let data = try #require(await ProcessCodexAppServer().readRateLimits())
        let usage = try #require(CodexAppServerParser.parse(data, now: Date()))
        #expect(usage.provider == .codex)
        #expect(usage.source == .codexAppServer)
        #expect(!usage.windows.isEmpty)
    }
}
