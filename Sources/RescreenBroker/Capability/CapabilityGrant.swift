import Foundation

/// Confirmation tier for an operation.
enum ConfirmationTier: String, Codable {
    case silent     // No prompt. Logged only.
    case logged     // No prompt. Logged + reviewable.
    case confirm    // Requires user confirmation before executing.
    case escalate   // Outside current scope — requires new capability grant.
    case block      // Hard denied. No override.
}

/// Grant lifetime scope.
enum GrantScope: String, Codable {
    case session    // Expires when the agent session ends
    case task       // Expires when the current task completes
    case persistent // Survives across sessions (stored in user profile)
    case oneShot    = "one-shot" // Valid for a single use, then revoked
}

/// A single capability grant: (domain, target, constraints).
struct CapabilityGrant: Codable {
    let id: String
    let domain: String              // e.g. "perception.accessibility", "action.input.*"
    let target: CapabilityTarget
    let constraints: [String: String]?
    let scope: GrantScope
    let expires: Date?
    let confirmation: ConfirmationTier
    var revoked: Bool
    var usesRemaining: Int?

    init(
        id: String,
        domain: String,
        target: CapabilityTarget,
        constraints: [String: String]? = nil,
        scope: GrantScope = .session,
        expires: Date? = nil,
        confirmation: ConfirmationTier = .confirm,
        revoked: Bool = false,
        usesRemaining: Int? = nil
    ) {
        self.id = id
        self.domain = domain
        self.target = target
        self.constraints = constraints
        self.scope = scope
        self.expires = expires
        self.confirmation = confirmation
        self.revoked = revoked
        self.usesRemaining = usesRemaining
    }
}

/// What a capability grant applies to.
struct CapabilityTarget: Codable {
    let app: String?            // Bundle ID
    let window: String?         // "*" or title pattern
    let paths: [String]?        // Glob patterns for fs grants
    let urlFilter: [String]?    // URL patterns for browser scoping

    enum CodingKeys: String, CodingKey {
        case app, window, paths
        case urlFilter = "url_filter"
    }

    /// Convenience: create an app-only target.
    static func app(_ bundleID: String) -> CapabilityTarget {
        CapabilityTarget(app: bundleID, window: "*", paths: nil, urlFilter: nil)
    }

    /// Convenience: create a filesystem target.
    static func paths(_ patterns: [String]) -> CapabilityTarget {
        CapabilityTarget(app: nil, window: nil, paths: patterns, urlFilter: nil)
    }
}
