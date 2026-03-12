import Foundation
import Testing

@testable import RescreenBroker

@Suite("CapabilityStore")
struct CapabilityStoreTests {
    // MARK: - Grant Management

    @Test("Adding a grant makes it findable")
    func addAndFindGrant() {
        let store = CapabilityStore()
        let grant = CapabilityGrant(
            id: "test-1",
            domain: "perception.accessibility",
            target: .app("com.test.app"),
            scope: .session,
            confirmation: .silent
        )
        store.addGrant(grant)
        let found = store.findGrant(domain: "perception.accessibility", bundleID: "com.test.app")
        #expect(found != nil)
        #expect(found?.id == "test-1")
    }

    @Test("Finding grant for wrong bundle ID returns nil")
    func wrongBundleIDReturnsNil() {
        let store = CapabilityStore()
        store.addGrant(CapabilityGrant(
            id: "test-1",
            domain: "perception.accessibility",
            target: .app("com.test.app"),
            scope: .session,
            confirmation: .silent
        ))
        let found = store.findGrant(domain: "perception.accessibility", bundleID: "com.other.app")
        #expect(found == nil)
    }

    @Test("Finding grant for wrong domain returns nil")
    func wrongDomainReturnsNil() {
        let store = CapabilityStore()
        store.addGrant(CapabilityGrant(
            id: "test-1",
            domain: "perception.accessibility",
            target: .app("com.test.app"),
            scope: .session,
            confirmation: .silent
        ))
        let found = store.findGrant(domain: "action.input.mouse", bundleID: "com.test.app")
        #expect(found == nil)
    }

    // MARK: - Wildcard Domain Matching

    @Test("Wildcard domain matches subtypes")
    func wildcardMatchesSubtypes() {
        let store = CapabilityStore()
        store.addGrant(CapabilityGrant(
            id: "wildcard",
            domain: "action.input.*",
            target: .app("com.test.app"),
            scope: .session,
            confirmation: .silent
        ))
        #expect(store.findGrant(domain: "action.input.mouse", bundleID: "com.test.app") != nil)
        #expect(store.findGrant(domain: "action.input.keyboard", bundleID: "com.test.app") != nil)
    }

    @Test("Wildcard domain matches the prefix itself")
    func wildcardMatchesPrefix() {
        let store = CapabilityStore()
        store.addGrant(CapabilityGrant(
            id: "wildcard",
            domain: "action.input.*",
            target: .app("com.test.app"),
            scope: .session,
            confirmation: .silent
        ))
        #expect(store.findGrant(domain: "action.input", bundleID: "com.test.app") != nil)
    }

    @Test("Wildcard does not match unrelated domains")
    func wildcardDoesNotOvermatch() {
        let store = CapabilityStore()
        store.addGrant(CapabilityGrant(
            id: "wildcard",
            domain: "action.input.*",
            target: .app("com.test.app"),
            scope: .session,
            confirmation: .silent
        ))
        #expect(store.findGrant(domain: "action.app.focus", bundleID: "com.test.app") == nil)
        #expect(store.findGrant(domain: "perception.accessibility", bundleID: "com.test.app") == nil)
    }

    @Test("Single-segment wildcard prefix is rejected")
    func shortWildcardRejected() {
        let store = CapabilityStore()
        // "a.*" has prefix "a" — only 1 char, no dot, should be rejected
        store.addGrant(CapabilityGrant(
            id: "bad-wildcard",
            domain: "a.*",
            target: .app("com.test.app"),
            scope: .session,
            confirmation: .silent
        ))
        #expect(store.findGrant(domain: "a.b.c", bundleID: "com.test.app") == nil)
    }

    @Test("Top-level wildcard with dot segment works")
    func topLevelWildcardWithDot() {
        let store = CapabilityStore()
        store.addGrant(CapabilityGrant(
            id: "perception-wildcard",
            domain: "perception.*",
            target: .app("com.test.app"),
            scope: .session,
            confirmation: .silent
        ))
        #expect(store.findGrant(domain: "perception.accessibility", bundleID: "com.test.app") != nil)
        #expect(store.findGrant(domain: "perception.screenshot", bundleID: "com.test.app") != nil)
    }

    // MARK: - Revocation

    @Test("Revoking a grant makes it unfindable")
    func revokeGrant() {
        let store = CapabilityStore()
        store.addGrant(CapabilityGrant(
            id: "revoke-me",
            domain: "perception.accessibility",
            target: .app("com.test.app"),
            scope: .session,
            confirmation: .silent
        ))
        store.revokeGrant(id: "revoke-me")
        #expect(store.findGrant(domain: "perception.accessibility", bundleID: "com.test.app") == nil)
    }

    @Test("Revoking all grants of a scope")
    func revokeAllByScope() {
        let store = CapabilityStore()
        store.addGrant(CapabilityGrant(
            id: "session-1",
            domain: "perception.accessibility",
            target: .app("com.test.app"),
            scope: .session,
            confirmation: .silent
        ))
        store.addGrant(CapabilityGrant(
            id: "persistent-1",
            domain: "perception.accessibility",
            target: .app("com.other.app"),
            scope: .persistent,
            confirmation: .silent
        ))
        store.revokeAll(scope: .session)
        #expect(store.findGrant(domain: "perception.accessibility", bundleID: "com.test.app") == nil)
        #expect(store.findGrant(domain: "perception.accessibility", bundleID: "com.other.app") != nil)
    }

    // MARK: - Expiration

    @Test("Expired grant is not found")
    func expiredGrantNotFound() {
        let store = CapabilityStore()
        store.addGrant(CapabilityGrant(
            id: "expired",
            domain: "perception.accessibility",
            target: .app("com.test.app"),
            scope: .session,
            expires: Date().addingTimeInterval(-60), // expired 1 minute ago
            confirmation: .silent
        ))
        #expect(store.findGrant(domain: "perception.accessibility", bundleID: "com.test.app") == nil)
    }

    @Test("Non-expired grant is found")
    func nonExpiredGrantFound() {
        let store = CapabilityStore()
        store.addGrant(CapabilityGrant(
            id: "active",
            domain: "perception.accessibility",
            target: .app("com.test.app"),
            scope: .session,
            expires: Date().addingTimeInterval(3600), // expires in 1 hour
            confirmation: .silent
        ))
        #expect(store.findGrant(domain: "perception.accessibility", bundleID: "com.test.app") != nil)
    }

    // MARK: - One-Shot Grants

    @Test("Grant with zero uses remaining is expired")
    func zeroUsesExpired() {
        let store = CapabilityStore()
        store.addGrant(CapabilityGrant(
            id: "used-up",
            domain: "perception.accessibility",
            target: .app("com.test.app"),
            scope: .oneShot,
            confirmation: .silent,
            usesRemaining: 0
        ))
        #expect(store.findGrant(domain: "perception.accessibility", bundleID: "com.test.app") == nil)
    }

    @Test("Grant with positive uses remaining is active")
    func positiveUsesActive() {
        let store = CapabilityStore()
        store.addGrant(CapabilityGrant(
            id: "has-uses",
            domain: "perception.accessibility",
            target: .app("com.test.app"),
            scope: .oneShot,
            confirmation: .silent,
            usesRemaining: 3
        ))
        #expect(store.findGrant(domain: "perception.accessibility", bundleID: "com.test.app") != nil)
    }

    // MARK: - Convenience Methods

    @Test("canPerceive returns true with matching grant")
    func canPerceive() {
        let store = CapabilityStore()
        store.addGrants(CapabilityStore.defaultGrants(for: "com.test.app"))
        #expect(store.canPerceive(bundleID: "com.test.app"))
    }

    @Test("canPerceive returns false without grant")
    func cannotPerceiveWithoutGrant() {
        let store = CapabilityStore()
        #expect(!store.canPerceive(bundleID: "com.test.app"))
    }

    @Test("canAct returns true with matching grant")
    func canAct() {
        let store = CapabilityStore()
        store.addGrants(CapabilityStore.defaultGrants(for: "com.test.app"))
        #expect(store.canAct(bundleID: "com.test.app", actionType: "click"))
    }

    @Test("canAct returns false for ungranted app")
    func cannotActWithoutGrant() {
        let store = CapabilityStore()
        #expect(!store.canAct(bundleID: "com.test.app", actionType: "click"))
    }

    // MARK: - Default Grants

    @Test("Default grants cover perception, input, app, and clipboard")
    func defaultGrantsCoverage() {
        let grants = CapabilityStore.defaultGrants(for: "com.test.app")
        let domains = Set(grants.map(\.domain))
        #expect(domains.contains("perception.*"))
        #expect(domains.contains("action.input.*"))
        #expect(domains.contains("action.app.*"))
        #expect(domains.contains("action.clipboard.*"))
    }

    @Test("Default grants target the correct app")
    func defaultGrantsTargetApp() {
        let grants = CapabilityStore.defaultGrants(for: "com.test.app")
        for grant in grants {
            #expect(grant.target.app == "com.test.app")
        }
    }

    @Test("Default perception grants are silent")
    func defaultPerceptionIsSilent() {
        let grants = CapabilityStore.defaultGrants(for: "com.test.app")
        let perceptionGrant = grants.first { $0.domain == "perception.*" }
        #expect(perceptionGrant?.confirmation == .silent)
    }

    @Test("Default action grants use logged tier")
    func defaultActionIsLogged() {
        let grants = CapabilityStore.defaultGrants(for: "com.test.app")
        let actionGrant = grants.first { $0.domain == "action.input.*" }
        #expect(actionGrant?.confirmation == .logged)
    }

    // MARK: - Permitted Bundle IDs

    @Test("permittedBundleIDs reflects active grants")
    func permittedBundleIDs() {
        let store = CapabilityStore()
        store.addGrants(CapabilityStore.defaultGrants(for: "com.test.app"))
        store.addGrants(CapabilityStore.defaultGrants(for: "com.other.app"))
        let ids = store.permittedBundleIDs
        #expect(ids.contains("com.test.app"))
        #expect(ids.contains("com.other.app"))
    }

    // MARK: - Confirmation Tiers

    @Test("Silent tier allows without handler")
    func silentAllowsWithoutHandler() {
        let store = CapabilityStore()
        store.addGrant(CapabilityGrant(
            id: "silent-grant",
            domain: "action.input.*",
            target: .app("com.test.app"),
            scope: .session,
            confirmation: .silent
        ))
        let result = store.requestConfirmation(action: "click", detail: "test", bundleID: "com.test.app")
        if case .allowed = result { } else {
            Issue.record("Expected .allowed but got denied")
        }
    }

    @Test("Logged tier allows without handler")
    func loggedAllowsWithoutHandler() {
        let store = CapabilityStore()
        store.addGrant(CapabilityGrant(
            id: "logged-grant",
            domain: "action.input.*",
            target: .app("com.test.app"),
            scope: .session,
            confirmation: .logged
        ))
        let result = store.requestConfirmation(action: "click", detail: "test", bundleID: "com.test.app")
        if case .allowed = result { } else {
            Issue.record("Expected .allowed but got denied")
        }
    }

    @Test("Block tier denies regardless")
    func blockTierDenies() {
        let store = CapabilityStore()
        store.addGrant(CapabilityGrant(
            id: "blocked-grant",
            domain: "action.input.*",
            target: .app("com.test.app"),
            scope: .session,
            confirmation: .block
        ))
        let result = store.requestConfirmation(action: "click", detail: "test", bundleID: "com.test.app")
        if case .denied(let reason) = result {
            #expect(reason.contains("blocked"))
        } else {
            Issue.record("Expected .denied but got allowed")
        }
    }

    @Test("Escalate tier denies regardless")
    func escalateTierDenies() {
        let store = CapabilityStore()
        store.addGrant(CapabilityGrant(
            id: "escalate-grant",
            domain: "action.input.*",
            target: .app("com.test.app"),
            scope: .session,
            confirmation: .escalate
        ))
        let result = store.requestConfirmation(action: "click", detail: "test", bundleID: "com.test.app")
        if case .denied(let reason) = result {
            #expect(reason.contains("escalation"))
        } else {
            Issue.record("Expected .denied but got allowed")
        }
    }

    @Test("Confirm tier denies when no handler is set")
    func confirmDeniesWithoutHandler() {
        let store = CapabilityStore()
        store.addGrant(CapabilityGrant(
            id: "confirm-grant",
            domain: "action.input.*",
            target: .app("com.test.app"),
            scope: .session,
            confirmation: .confirm
        ))
        // No confirmationHandler set
        let result = store.requestConfirmation(action: "click", detail: "test", bundleID: "com.test.app")
        if case .denied = result { } else {
            Issue.record("Expected .denied but got allowed")
        }
    }

    // MARK: - grantsInfo

    @Test("grantsInfo serializes active grants")
    func grantsInfo() {
        let store = CapabilityStore()
        store.addGrants(CapabilityStore.defaultGrants(for: "com.test.app"))
        let info = store.grantsInfo()
        #expect(!info.isEmpty)
        let firstGrant = info[0]
        #expect(firstGrant["domain"] as? String != nil)
        #expect(firstGrant["scope"] as? String != nil)
        #expect(firstGrant["app"] as? String == "com.test.app")
    }
}
