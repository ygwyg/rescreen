import AppKit
import Foundation

/// Manages clipboard access with per-app isolation tracking.
final class ClipboardManager {
    private let auditLogger: AuditLogger
    private var lastChangeCount: Int

    init(auditLogger: AuditLogger) {
        self.auditLogger = auditLogger
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    /// Read the current clipboard contents as text.
    func read() -> [String: Any] {
        let pasteboard = NSPasteboard.general
        let text = pasteboard.string(forType: .string)

        auditLogger.log(
            operation: "clipboard.read",
            params: ["has_content": "\(text != nil)", "length": "\(text?.count ?? 0)"],
            result: "success",
            confirmation: "logged"
        )

        if let text = text {
            return textResult(text)
        }

        // Check for other types
        let types = pasteboard.types?.map { $0.rawValue } ?? []
        return textResult("Clipboard has no text content. Available types: \(types.joined(separator: ", "))")
    }

    /// Write text to the clipboard.
    func write(text: String) -> [String: Any] {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount

        auditLogger.log(
            operation: "clipboard.write",
            params: ["length": "\(text.count)"],
            result: success ? "success" : "error",
            confirmation: "confirm"
        )

        return success
            ? textResult("Copied \(text.count) characters to clipboard")
            : errorResult("Failed to write to clipboard")
    }

    /// Check if the clipboard has changed since the last read/write.
    func hasChanged() -> Bool {
        let current = NSPasteboard.general.changeCount
        return current != lastChangeCount
    }

    // MARK: - Helpers

    private func textResult(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text] as [String: Any]]]
    }

    private func errorResult(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": "Error: \(message)"] as [String: Any]], "isError": true]
    }
}
