import AsukuShared
import Foundation

/// Sends push notifications to ntfy.sh for iPhone delivery
@MainActor
final class NtfyNotifier {
    private let config: NtfyConfig
    private let session: URLSession

    init(config: NtfyConfig) {
        self.config = config
        self.session = URLSession(configuration: .ephemeral)
    }

    /// Sends a permission request notification to ntfy. Fails silently (macOS notification is primary).
    func sendPermissionRequest(_ request: PendingRequest) async {
        guard config.isEnabled else { return }

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

        // Action buttons — ntfy supports HTTP actions
        // Include webhook secret as query parameter for authentication
        let token = config.webhookSecret
        let allowURL = "\(webhookBase)/webhook/allow/\(request.id)?token=\(token)"
        let denyURL = "\(webhookBase)/webhook/deny/\(request.id)?token=\(token)"
        let actions = [
            "http, Allow, \(allowURL), method=POST",
            "http, Deny, \(denyURL), method=POST",
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

    private func buildNotificationBody(_ request: PendingRequest) -> String {
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
