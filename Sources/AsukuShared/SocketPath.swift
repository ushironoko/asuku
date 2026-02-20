import Foundation

public enum SocketPath {
    /// Maximum path length for Unix Domain Socket on macOS
    private static let maxPathLength = 104

    /// Default socket directory: ~/Library/Application Support/asuku/
    private static var defaultDirectory: String {
        let appSupport =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("asuku").path
    }

    /// Resolves the socket path, ensuring it fits within the UDS path length limit.
    /// Falls back to shorter paths if the default exceeds 104 characters.
    public static func resolve() throws -> String {
        let defaultPath = (defaultDirectory as NSString).appendingPathComponent("asuku.sock")

        if defaultPath.utf8.count <= maxPathLength {
            try ensureDirectory(defaultDirectory)
            return defaultPath
        }

        // Fallback: use XDG_RUNTIME_DIR if available
        if let xdgRuntime = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"] {
            let xdgPath =
                (xdgRuntime as NSString)
                .appendingPathComponent("asuku")
            let sockPath = (xdgPath as NSString).appendingPathComponent("asuku.sock")
            if sockPath.utf8.count <= maxPathLength {
                try ensureDirectory(xdgPath)
                return sockPath
            }
        }

        // Fallback: use /tmp with user-specific directory
        let uid = getuid()
        let tmpDir = "/tmp/asuku-\(uid)"
        let tmpPath = (tmpDir as NSString).appendingPathComponent("asuku.sock")
        if tmpPath.utf8.count <= maxPathLength {
            try ensureDirectory(tmpDir)
            return tmpPath
        }

        throw SocketPathError.pathTooLong(defaultPath)
    }

    /// Ensures the directory exists with secure permissions (0700)
    private static func ensureDirectory(_ path: String) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false

        if fm.fileExists(atPath: path, isDirectory: &isDir) {
            guard isDir.boolValue else {
                throw SocketPathError.notADirectory(path)
            }
            // Verify and fix permissions
            try setDirectoryPermissions(path)
        } else {
            try fm.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    private static func setDirectoryPermissions(_ path: String) throws {
        let fm = FileManager.default
        let attributes = try fm.attributesOfItem(atPath: path)
        if let permissions = attributes[.posixPermissions] as? Int, permissions != 0o700 {
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        }
    }

    /// Sets secure permissions on the socket file (0600)
    public static func setSocketPermissions(_ path: String) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path
        )
    }

    /// Removes the socket file if it exists
    public static func removeSocketIfExists(_ path: String) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }
    }
}

public enum SocketPathError: Error, CustomStringConvertible {
    case pathTooLong(String)
    case notADirectory(String)

    public var description: String {
        switch self {
        case .pathTooLong(let path):
            return
                "Socket path exceeds 104 character limit: \(path) (\(path.utf8.count) bytes). Configure a shorter path."
        case .notADirectory(let path):
            return "Expected directory at path but found a file: \(path)"
        }
    }
}
