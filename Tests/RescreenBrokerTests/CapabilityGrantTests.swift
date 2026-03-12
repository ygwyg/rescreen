import Foundation
import Testing

@testable import RescreenBroker

@Suite("CapabilityGrant")
struct CapabilityGrantTests {
    // MARK: - ConfirmationTier

    @Test("Confirmation tiers have correct raw values")
    func confirmationTierRawValues() {
        #expect(ConfirmationTier.silent.rawValue == "silent")
        #expect(ConfirmationTier.logged.rawValue == "logged")
        #expect(ConfirmationTier.confirm.rawValue == "confirm")
        #expect(ConfirmationTier.escalate.rawValue == "escalate")
        #expect(ConfirmationTier.block.rawValue == "block")
    }

    // MARK: - GrantScope

    @Test("Grant scopes have correct raw values")
    func grantScopeRawValues() {
        #expect(GrantScope.session.rawValue == "session")
        #expect(GrantScope.task.rawValue == "task")
        #expect(GrantScope.persistent.rawValue == "persistent")
        #expect(GrantScope.oneShot.rawValue == "one-shot")
    }

    // MARK: - CapabilityTarget

    @Test("App target convenience constructor")
    func appTarget() {
        let target = CapabilityTarget.app("com.test.app")
        #expect(target.app == "com.test.app")
        #expect(target.window == "*")
        #expect(target.paths == nil)
        #expect(target.urlFilter == nil)
    }

    @Test("Paths target convenience constructor")
    func pathsTarget() {
        let target = CapabilityTarget.paths(["~/Documents/**", "/tmp"])
        #expect(target.app == nil)
        #expect(target.paths == ["~/Documents/**", "/tmp"])
    }

    // MARK: - CapabilityGrant Defaults

    @Test("Grant defaults")
    func grantDefaults() {
        let grant = CapabilityGrant(
            id: "test",
            domain: "perception.accessibility",
            target: .app("com.test.app")
        )
        #expect(grant.scope == .session)
        #expect(grant.confirmation == .confirm)
        #expect(grant.revoked == false)
        #expect(grant.expires == nil)
        #expect(grant.usesRemaining == nil)
        #expect(grant.constraints == nil)
    }

    // MARK: - Codable

    @Test("Grant round-trips through JSON")
    func grantCodable() throws {
        let original = CapabilityGrant(
            id: "test-codable",
            domain: "action.input.*",
            target: .app("com.test.app"),
            constraints: ["max_chars": "100"],
            scope: .oneShot,
            confirmation: .silent,
            usesRemaining: 5
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(CapabilityGrant.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.domain == original.domain)
        #expect(decoded.target.app == original.target.app)
        #expect(decoded.scope == original.scope)
        #expect(decoded.confirmation == original.confirmation)
        #expect(decoded.usesRemaining == original.usesRemaining)
        #expect(decoded.constraints?["max_chars"] == "100")
    }

    @Test("CapabilityTarget url_filter uses correct coding key")
    func targetCodingKeys() throws {
        let json = """
        {"app":"com.test.app","url_filter":["*.example.com"]}
        """
        let target = try JSONDecoder().decode(CapabilityTarget.self, from: json.data(using: .utf8)!)
        #expect(target.urlFilter == ["*.example.com"])
    }
}
