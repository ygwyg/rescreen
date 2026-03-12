import Foundation

/// Result of a confirmation check.
enum ConfirmationResult {
    case allowed
    case denied(reason: String)
}

/// Manages capability grants and enforces permissions.
final class CapabilityStore {
    private var grants: [CapabilityGrant] = []
    private let lock = NSLock()
    var confirmationHandler: ConfirmationHandler?

    // MARK: - Grant Management

    func addGrant(_ grant: CapabilityGrant) {
        lock.lock()
        defer { lock.unlock() }
        grants.append(grant)
        Log.info("Grant added: \(grant.id) [\(grant.domain)] -> \(grant.target.app ?? "no-app") (\(grant.scope.rawValue))")
    }

    func addGrants(_ newGrants: [CapabilityGrant]) {
        for grant in newGrants {
            addGrant(grant)
        }
    }

    func revokeGrant(id: String) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = grants.firstIndex(where: { $0.id == id }) {
            grants[idx].revoked = true
            Log.info("Grant revoked: \(id)")
        }
    }

    func revokeAll(scope: GrantScope) {
        lock.lock()
        defer { lock.unlock() }
        for i in grants.indices {
            if grants[i].scope == scope {
                grants[i].revoked = true
            }
        }
        Log.info("All \(scope.rawValue) grants revoked")
    }

    func activeGrants() -> [CapabilityGrant] {
        lock.lock()
        defer { lock.unlock() }
        return grants.filter { !isExpired($0) }
    }

    /// All bundle IDs that have at least one active grant.
    var permittedBundleIDs: Set<String> {
        Set(activeGrants().compactMap { $0.target.app })
    }

    // MARK: - Permission Checks

    /// Find the best matching active grant for a domain + bundle ID.
    func findGrant(domain: String, bundleID: String?) -> CapabilityGrant? {
        lock.lock()
        defer { lock.unlock() }
        for grant in grants {
            guard !isExpired(grant) else { continue }

            // Check domain match (supports wildcard suffix)
            guard domainMatches(grantDomain: grant.domain, requestDomain: domain) else { continue }

            // Check target match
            if let requestApp = bundleID, let grantApp = grant.target.app {
                guard grantApp == requestApp else { continue }
            }

            return grant
        }
        return nil
    }

    func canPerceive(bundleID: String, type: String = "accessibility") -> Bool {
        let domain = ActionDomainMapping.perceptionDomain(for: type)
        return findGrant(domain: domain, bundleID: bundleID) != nil
    }

    func canAct(bundleID: String, actionType: String) -> Bool {
        let domain = ActionDomainMapping.domain(for: actionType)
        return findGrant(domain: domain, bundleID: bundleID) != nil
    }

    // MARK: - Confirmation

    /// Request confirmation for an action, respecting the grant's confirmation tier.
    func requestConfirmation(action: String, detail: String, bundleID: String?) -> ConfirmationResult {
        let domain = ActionDomainMapping.domain(for: action)
        let grant = findGrant(domain: domain, bundleID: bundleID)
        let tier = grant?.confirmation ?? .confirm

        switch tier {
        case .silent, .logged:
            Log.info("[AUDIT] \(tier.rawValue): \(action) — \(detail)")
            return .allowed

        case .confirm:
            guard let handler = confirmationHandler else {
                // No confirmation handler available — fall back to deny
                Log.error("No confirmation handler available — denying action")
                return .denied(reason: "No confirmation channel available")
            }
            let response = handler.requestConfirmation(
                ConfirmationRequest(action: action, detail: detail, capabilityID: grant?.id)
            )
            switch response {
            case .allowed:
                Log.info("[AUDIT] CONFIRMED: \(action) — \(detail)")
                // Decrement one-shot grants
                if let g = grant, g.scope == .oneShot {
                    lock.lock()
                    if let idx = grants.firstIndex(where: { $0.id == g.id }) {
                        if let remaining = grants[idx].usesRemaining {
                            grants[idx].usesRemaining = remaining - 1
                        } else {
                            grants[idx].revoked = true
                        }
                    }
                    lock.unlock()
                }
                return .allowed
            case .denied:
                Log.info("[AUDIT] DENIED by user: \(action) — \(detail)")
                return .denied(reason: "User denied the action")
            }

        case .escalate:
            Log.info("[AUDIT] ESCALATE (denied): \(action) — \(detail)")
            return .denied(reason: "Action requires capability escalation")

        case .block:
            Log.info("[AUDIT] BLOCKED: \(action) — \(detail)")
            return .denied(reason: "Action is blocked by policy")
        }
    }

    /// Uniform "not found" response for out-of-scope requests.
    static var notFoundResult: [String: Any] {
        [
            "content": [
                ["type": "text", "text": "Resource not found."]
            ]
        ]
    }

    // MARK: - Grant Helpers

    /// Create a default set of grants for a bundle ID (backward compat with --app flag).
    static func defaultGrants(for bundleID: String) -> [CapabilityGrant] {
        return [
            CapabilityGrant(
                id: "cap_perceive_\(bundleID)",
                domain: "perception.*",
                target: .app(bundleID),
                scope: .session,
                confirmation: .silent
            ),
            CapabilityGrant(
                id: "cap_act_\(bundleID)",
                domain: "action.input.*",
                target: .app(bundleID),
                scope: .session,
                confirmation: .logged
            ),
            CapabilityGrant(
                id: "cap_app_\(bundleID)",
                domain: "action.app.*",
                target: .app(bundleID),
                scope: .session,
                confirmation: .logged
            ),
            CapabilityGrant(
                id: "cap_clipboard_\(bundleID)",
                domain: "action.clipboard.*",
                target: .app(bundleID),
                scope: .session,
                confirmation: .logged
            ),
        ]
    }

    // MARK: - Internal

    private func isExpired(_ grant: CapabilityGrant) -> Bool {
        if grant.revoked { return true }
        if let expires = grant.expires, Date() > expires { return true }
        if let uses = grant.usesRemaining, uses <= 0 { return true }
        return false
    }

    /// Check if a grant domain matches a requested domain.
    /// Supports wildcard: "action.input.*" matches "action.input.keyboard".
    private func domainMatches(grantDomain: String, requestDomain: String) -> Bool {
        if grantDomain == requestDomain { return true }

        // Wildcard: "action.input.*" matches "action.input.keyboard"
        if grantDomain.hasSuffix(".*") {
            let prefix = String(grantDomain.dropLast(2)) // "action.input"
            // Require at least one dot-segment to prevent overly broad matches
            // (e.g., grant "a.*" should not match everything starting with "a")
            guard prefix.contains(".") || prefix.count >= 3 else { return false }
            // Ensure the request domain either equals the prefix or extends it with a dot
            return requestDomain == prefix || requestDomain.hasPrefix(prefix + ".")
        }

        return false
    }

    /// Serialize active grants for the status tool.
    func grantsInfo() -> [[String: Any]] {
        return activeGrants().map { grant in
            var info: [String: Any] = [
                "id": grant.id,
                "domain": grant.domain,
                "scope": grant.scope.rawValue,
                "confirmation": grant.confirmation.rawValue,
            ]
            if let app = grant.target.app { info["app"] = app }
            if let expires = grant.expires {
                let formatter = ISO8601DateFormatter()
                info["expires"] = formatter.string(from: expires)
            }
            if let uses = grant.usesRemaining { info["uses_remaining"] = uses }
            return info
        }
    }
}
