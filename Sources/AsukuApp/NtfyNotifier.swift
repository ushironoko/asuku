import AsukuAppCore
import AsukuShared
import Foundation

/// Stateless ntfy push notification sender.
/// Config is passed as a parameter — no lifecycle management needed.
enum NtfyNotifier {
    private static let session = URLSession(configuration: .ephemeral)

    /// Sends a permission request notification to ntfy. Fails silently (macOS notification is primary).
    @MainActor
    static func sendPermissionRequest(_ request: PendingRequest, config: NtfyConfig) async {
        guard config.isEnabled else { return }

        // Validate server URL scheme (HTTPS required for remote servers)
        let serverValidation = NtfyConfig.validateServerURL(config.serverURL)
        switch serverValidation {
        case .insecure:
            print(
                "[NtfyNotifier] Refusing to send over insecure HTTP to non-localhost server: \(config.serverURL)"
            )
            return
        case .invalid:
            print("[NtfyNotifier] Invalid server URL: \(config.serverURL)")
            return
        case .valid, .localhost:
            break
        }

        let serverURL = config.serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(serverURL)/\(config.topic)") else {
            print("[NtfyNotifier] Invalid URL: \(serverURL)/\(config.topic)")
            return
        }

        let webhookBase = config.webhookBaseURL.trimmingCharacters(
            in: CharacterSet(charactersIn: "/"))
        guard !webhookBase.isEmpty else {
            print("[NtfyNotifier] Webhook base URL not configured, skipping ntfy notification")
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"

        // ntfy headers
        urlRequest.setValue(
            "Permission Request: \(request.event.toolName)", forHTTPHeaderField: "Title")
        urlRequest.setValue("high", forHTTPHeaderField: "Priority")
        urlRequest.setValue("warning", forHTTPHeaderField: "Tags")

        // Action buttons — ntfy supports HTTP actions with custom headers
        // Token is sent via Authorization header (not URL query) to prevent exposure in logs
        guard let allowURL = buildWebhookURL(
            base: webhookBase, action: "allow", requestID: request.id),
            let denyURL = buildWebhookURL(
                base: webhookBase, action: "deny", requestID: request.id)
        else {
            print("[NtfyNotifier] Failed to build webhook action URLs")
            return
        }
        let actions = [
            "http, Allow, \(allowURL), method=POST, headers.Authorization=Bearer \(config.webhookSecret)",
            "http, Deny, \(denyURL), method=POST, headers.Authorization=Bearer \(config.webhookSecret)",
        ].joined(separator: "; ")
        urlRequest.setValue(actions, forHTTPHeaderField: "Actions")

        // Body: tool info + sanitized command/input
        let body = buildNotificationBody(request)
        urlRequest.httpBody = body.data(using: .utf8)

        do {
            let (_, response) = try await session.data(for: urlRequest)
            if let httpResponse = response as? HTTPURLResponse,
                !(200...299).contains(httpResponse.statusCode)
            {
                print(
                    "[NtfyNotifier] Server returned status \(httpResponse.statusCode)")
            }
        } catch {
            print("[NtfyNotifier] Failed to send notification: \(error)")
        }
    }

    private static func buildWebhookURL(
        base: String, action: String, requestID: String
    ) -> String? {
        guard let _ = URL(string: "\(base)/webhook/\(action)/\(requestID)") else {
            return nil
        }
        return "\(base)/webhook/\(action)/\(requestID)"
    }

    private static func buildNotificationBody(_ request: PendingRequest) -> String {
        var lines: [String] = []

        lines.append("Tool: \(request.event.toolName)")
        lines.append("CWD: \(request.event.cwd)")

        switch request.event.toolName {
        case "Bash":
            if let command = request.event.toolInput["command"]?.stringValue {
                lines.append(
                    "Command: \(InputSanitizer.sanitizeForNotification(command))")
            }
        case "Write", "Edit":
            if let filePath = request.event.toolInput["file_path"]?.stringValue {
                lines.append("File: \(filePath)")
            }
        default:
            let inputDesc = request.event.toolInput.map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            if !inputDesc.isEmpty {
                lines.append(
                    "Input: \(InputSanitizer.sanitizeForNotification(inputDesc))")
            }
        }

        return lines.joined(separator: "\n")
    }
}
