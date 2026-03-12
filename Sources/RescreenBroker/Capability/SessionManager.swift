import Foundation

/// Manages the lifecycle of a broker session.
final class SessionManager {
    let sessionID: String
    let startTime: Date
    private let capabilityStore: CapabilityStore
    private let auditLogger: AuditLogger

    init(sessionID: String, capabilityStore: CapabilityStore, auditLogger: AuditLogger) {
        self.sessionID = sessionID
        self.startTime = Date()
        self.capabilityStore = capabilityStore
        self.auditLogger = auditLogger

        Log.info("Session started: \(sessionID)")
        auditLogger.log(
            operation: "session.start",
            result: "success",
            confirmation: "silent"
        )
    }

    /// End the session — revoke all session-scoped and task-scoped grants.
    func endSession() {
        capabilityStore.revokeAll(scope: .session)
        capabilityStore.revokeAll(scope: .task)

        auditLogger.log(
            operation: "session.end",
            result: "success",
            confirmation: "silent"
        )
        Log.info("Session ended: \(sessionID)")
    }

    /// Session info for the status tool.
    func info() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        let elapsed = Int(Date().timeIntervalSince(startTime))
        return [
            "session_id": sessionID,
            "started": formatter.string(from: startTime),
            "elapsed_seconds": elapsed,
        ]
    }
}
