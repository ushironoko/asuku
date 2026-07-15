// Vendored from quota-glance (github.com/ushironoko/quota-glance) @ 1ba693b, MIT License.
// Upstream: Core/Sources/QGSupport/FileSystem.swift.
// Flattened into AsukuAppCore (QG module split dropped) for the Quota tab integration.

import Foundation

/// Minimal filesystem seam. Treated as *internal wiring* in tests — exercised through the real
/// `LocalFileSystem` against a temp directory rather than a mock, so atomic-write/permission
/// behavior is genuinely tested.
public protocol FileSystem: Sendable {
    func fileExists(at path: String) -> Bool
    func readData(at path: String) throws -> Data
    /// Files directly under `path` (names only), sorted; empty if the directory is missing.
    func contentsOfDirectory(at path: String) -> [String]
    /// Recursively find files matching `suffix` under `path`, sorted by modification date descending.
    func filesRecursively(under path: String, withSuffix suffix: String) -> [String]
    func writeAtomically(_ data: Data, to path: String) throws
    func modificationDate(at path: String) -> Date?
    /// Byte size of the file at `path`, or nil if unavailable.
    func fileSize(at path: String) -> UInt64?
}

public struct LocalFileSystem: FileSystem {
    public init() {}

    private var fm: FileManager { FileManager.default }

    public func fileExists(at path: String) -> Bool {
        fm.fileExists(atPath: path)
    }

    public func readData(at path: String) throws -> Data {
        do { return try Data(contentsOf: URL(fileURLWithPath: path)) }
        catch { throw FileSystemError.read }
    }

    public func contentsOfDirectory(at path: String) -> [String] {
        (try? fm.contentsOfDirectory(atPath: path))?.sorted() ?? []
    }

    public func filesRecursively(under path: String, withSuffix suffix: String) -> [String] {
        let base = URL(fileURLWithPath: path)
        // Do not descend into symlinked directories, and skip symlinked files, to keep scanning
        // confined to the real subtree under `path`.
        guard let en = fm.enumerator(
            at: base,
            includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return []
        }
        var matches: [(String, Date)] = []
        for case let url as URL in en where url.lastPathComponent.hasSuffix(suffix) {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            let mod = values?.contentModificationDate ?? .distantPast
            matches.append((url.path, mod))
        }
        return matches.sorted { $0.1 > $1.1 }.map(\.0)
    }

    public func writeAtomically(_ data: Data, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Data.write(.atomic) writes to a temp file then renames — no torn reads for other processes.
        do { try data.write(to: url, options: .atomic) }
        catch { throw FileSystemError.write }
    }

    public func modificationDate(at path: String) -> Date? {
        (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    public func fileSize(at path: String) -> UInt64? {
        (try? fm.attributesOfItem(atPath: path))?[.size] as? UInt64
    }
}

/// Local IO error, self-contained (no dependency on other model types).
enum FileSystemError: Error { case read, write }
