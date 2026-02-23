import Foundation

// MARK: - Protocol Version

public let ipcProtocolVersion = 1

// MARK: - Wire Format

/// 4-byte big-endian length prefix + JSON payload
public enum IPCWireFormat {
    /// Maximum allowed frame size (1 MB)
    public static let maxFrameSize: UInt32 = 1_048_576

    public static func encode(_ data: Data) -> Data {
        var length = UInt32(data.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(data)
        return frame
    }

    /// Attempts to extract a complete frame from the buffer.
    /// Returns (payload, bytesConsumed) or nil if insufficient data or oversized frame.
    public static func decode(_ buffer: Data) -> (payload: Data, bytesConsumed: Int)? {
        guard buffer.count >= 4 else { return nil }
        let length = buffer.withUnsafeBytes { ptr in
            ptr.load(as: UInt32.self).bigEndian
        }
        guard length <= maxFrameSize else { return nil }
        let totalLength = 4 + Int(length)
        guard buffer.count >= totalLength else { return nil }
        let payload = buffer.subdata(in: 4..<totalLength)
        return (payload, totalLength)
    }
}

// MARK: - IPC Message Types

public struct IPCMessage: Codable, Sendable {
    public let protocolVersion: Int
    public let payload: IPCPayload

    public init(protocolVersion: Int = ipcProtocolVersion, payload: IPCPayload) {
        self.protocolVersion = protocolVersion
        self.payload = payload
    }
}

public enum IPCPayload: Codable, Sendable {
    case permissionRequest(PermissionRequestEvent)
    case notification(NotificationEvent)
    case heartbeat

    private enum CodingKeys: String, CodingKey {
        case type
        case data
    }

    private enum PayloadType: String, Codable {
        case permissionRequest
        case notification
        case heartbeat
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .permissionRequest(let event):
            try container.encode(PayloadType.permissionRequest, forKey: .type)
            try container.encode(event, forKey: .data)
        case .notification(let event):
            try container.encode(PayloadType.notification, forKey: .type)
            try container.encode(event, forKey: .data)
        case .heartbeat:
            try container.encode(PayloadType.heartbeat, forKey: .type)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PayloadType.self, forKey: .type)
        switch type {
        case .permissionRequest:
            let event = try container.decode(PermissionRequestEvent.self, forKey: .data)
            self = .permissionRequest(event)
        case .notification:
            let event = try container.decode(NotificationEvent.self, forKey: .data)
            self = .notification(event)
        case .heartbeat:
            self = .heartbeat
        }
    }
}

// MARK: - Event Types

public struct PermissionRequestEvent: Codable, Sendable {
    public let requestId: String
    public let sessionId: String
    public let toolName: String
    public let toolInput: [String: AnyCodableValue]
    public let cwd: String
    public let timestamp: Date

    public init(
        requestId: String = UUID().uuidString,
        sessionId: String,
        toolName: String,
        toolInput: [String: AnyCodableValue],
        cwd: String,
        timestamp: Date = Date()
    ) {
        self.requestId = requestId
        self.sessionId = sessionId
        self.toolName = toolName
        self.toolInput = toolInput
        self.cwd = cwd
        self.timestamp = timestamp
    }
}

public struct NotificationEvent: Codable, Sendable {
    public let sessionId: String
    public let title: String
    public let body: String
    public let timestamp: Date

    public init(
        sessionId: String,
        title: String,
        body: String,
        timestamp: Date = Date()
    ) {
        self.sessionId = sessionId
        self.title = title
        self.body = body
        self.timestamp = timestamp
    }
}

// MARK: - Response Types

public struct IPCResponse: Codable, Sendable {
    public let protocolVersion: Int
    public let requestId: String
    public let decision: PermissionDecision

    public init(
        protocolVersion: Int = ipcProtocolVersion,
        requestId: String,
        decision: PermissionDecision
    ) {
        self.protocolVersion = protocolVersion
        self.requestId = requestId
        self.decision = decision
    }
}

public enum PermissionDecision: String, Codable, Sendable {
    case allow
    case deny
}

// MARK: - IPC Error Response

public struct IPCError: Codable, Sendable {
    public let protocolVersion: Int
    public let error: String

    public init(protocolVersion: Int = ipcProtocolVersion, error: String) {
        self.protocolVersion = protocolVersion
        self.error = error
    }
}

// MARK: - AnyCodableValue

public enum AnyCodableValue: Codable, Sendable, CustomStringConvertible {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    public var description: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        case .array(let a): return a.description
        case .dictionary(let d): return d.description
        case .null: return "null"
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var dictionaryValue: [String: AnyCodableValue]? {
        if case .dictionary(let d) = self { return d }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([AnyCodableValue].self) {
            self = .array(a)
        } else if let d = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(d)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported value type"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .array(let a): try container.encode(a)
        case .dictionary(let d): try container.encode(d)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - Sanitization

public enum InputSanitizer {
    private static let sensitivePatterns: [String] = [
        "TOKEN=", "API_KEY=", "SECRET=", "PASSWORD=", "PRIVATE_KEY=",
        "Authorization:", "Bearer ", "Basic ",
        "AWS_SECRET", "GITHUB_TOKEN", "NPM_TOKEN",
    ]

    /// Masks sensitive patterns in the input string
    public static func sanitize(_ input: String) -> String {
        var result = input
        for pattern in sensitivePatterns {
            var searchStart = result.startIndex
            while searchStart < result.endIndex {
                guard
                    let range = result.range(
                        of: pattern, options: .caseInsensitive,
                        range: searchStart..<result.endIndex)
                else { break }
                // Find the value after the pattern (up to whitespace, quote, or end)
                let valueStart = range.upperBound
                var valueEnd = valueStart
                while valueEnd < result.endIndex {
                    let char = result[valueEnd]
                    if char.isWhitespace || char == "\"" || char == "'" || char == ","
                        || char == "}"
                    {
                        break
                    }
                    valueEnd = result.index(after: valueEnd)
                }
                if valueStart < valueEnd {
                    result.replaceSubrange(valueStart..<valueEnd, with: "***")
                    searchStart = result.index(valueStart, offsetBy: 3)
                } else {
                    searchStart = range.upperBound
                }
            }
        }
        return result
    }

    /// Truncates and sanitizes for notification display
    public static func sanitizeForNotification(_ input: String, maxLength: Int = 200) -> String {
        let sanitized = sanitize(input)
        if sanitized.count > maxLength {
            return String(sanitized.prefix(maxLength)) + "..."
        }
        return sanitized
    }
}
