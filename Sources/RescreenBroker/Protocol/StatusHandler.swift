import Foundation

/// Handles the rescreen_status MCP tool — returns session info and active grants.
final class StatusHandler {
    private let sessionManager: SessionManager
    private let capabilityStore: CapabilityStore

    init(sessionManager: SessionManager, capabilityStore: CapabilityStore) {
        self.sessionManager = sessionManager
        self.capabilityStore = capabilityStore
    }

    func handle() -> [String: Any] {
        let status: [String: Any] = [
            "session": sessionManager.info(),
            "grants": capabilityStore.grantsInfo(),
            "permitted_apps": Array(capabilityStore.permittedBundleIDs).sorted(),
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: status, options: [.sortedKeys, .prettyPrinted]),
              let json = String(data: data, encoding: .utf8) else {
            return [
                "content": [
                    ["type": "text", "text": "Error: Failed to serialize status"] as [String: Any]
                ],
                "isError": true,
            ]
        }

        return [
            "content": [
                ["type": "text", "text": json] as [String: Any]
            ]
        ]
    }
}
