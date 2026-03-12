import Foundation

/// A confirmation request shown to the user.
struct ConfirmationRequest {
    let action: String
    let detail: String
    let capabilityID: String?
}

/// User's response to a confirmation request.
enum ConfirmationResponse {
    case allowed
    case denied
}

/// Protocol for confirmation handlers (TTY, NSPanel, etc.)
protocol ConfirmationHandler {
    func requestConfirmation(_ request: ConfirmationRequest) -> ConfirmationResponse
}

/// Fallback confirmation handler that reads from /dev/tty.
final class TTYConfirmationHandler: ConfirmationHandler {
    func requestConfirmation(_ request: ConfirmationRequest) -> ConfirmationResponse {
        let prompt = """

        ┌─────────────────────────────────────────────────
        │  Rescreen Confirmation Required
        │
        │  Action: \(request.action)
        │  Detail: \(request.detail)
        │
        │  Allow this action? [y/N]
        └─────────────────────────────────────────────────
        """
        FileHandle.standardError.write(prompt.data(using: .utf8)!)
        FileHandle.standardError.write("\n> ".data(using: .utf8)!)

        guard let tty = fopen("/dev/tty", "r") else {
            Log.error("Cannot open /dev/tty for confirmation — denying action")
            return .denied
        }
        defer { fclose(tty) }

        var buf = [CChar](repeating: 0, count: 256)
        guard fgets(&buf, 256, tty) != nil else {
            return .denied
        }
        let response = String(cString: &buf)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return (response == "y" || response == "yes") ? .allowed : .denied
    }
}
