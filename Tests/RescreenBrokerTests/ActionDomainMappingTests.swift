import Testing

@testable import RescreenBroker

@Suite("ActionDomainMapping")
struct ActionDomainMappingTests {
    // MARK: - Action Domains

    @Test("Mouse actions map to action.input.mouse",
          arguments: ["click", "double_click", "right_click", "hover", "drag", "scroll"])
    func mouseActions(action: String) {
        #expect(ActionDomainMapping.domain(for: action) == "action.input.mouse")
    }

    @Test("Keyboard actions map to action.input.keyboard",
          arguments: ["type", "press"])
    func keyboardActions(action: String) {
        #expect(ActionDomainMapping.domain(for: action) == "action.input.keyboard")
    }

    @Test("Select maps to action.input.select")
    func selectAction() {
        #expect(ActionDomainMapping.domain(for: "select") == "action.input.select")
    }

    @Test("App management actions map correctly")
    func appActions() {
        #expect(ActionDomainMapping.domain(for: "focus") == "action.app.focus")
        #expect(ActionDomainMapping.domain(for: "launch") == "action.app.launch")
        #expect(ActionDomainMapping.domain(for: "close") == "action.app.close")
    }

    @Test("Clipboard actions map correctly")
    func clipboardActions() {
        #expect(ActionDomainMapping.domain(for: "clipboard_read") == "action.clipboard.read")
        #expect(ActionDomainMapping.domain(for: "clipboard_write") == "action.clipboard.write")
    }

    @Test("URL action maps to perception domain")
    func urlMapsToPerception() {
        #expect(ActionDomainMapping.domain(for: "url") == "perception.accessibility")
    }

    @Test("Unknown actions get dynamic domain")
    func unknownAction() {
        #expect(ActionDomainMapping.domain(for: "custom_thing") == "action.custom_thing")
    }

    // MARK: - Perception Domains

    @Test("Perception types map correctly")
    func perceptionDomains() {
        #expect(ActionDomainMapping.perceptionDomain(for: "accessibility") == "perception.accessibility")
        #expect(ActionDomainMapping.perceptionDomain(for: "screenshot") == "perception.screenshot")
        #expect(ActionDomainMapping.perceptionDomain(for: "composite") == "perception.composite")
        #expect(ActionDomainMapping.perceptionDomain(for: "overview") == "perception.accessibility")
        #expect(ActionDomainMapping.perceptionDomain(for: "find") == "perception.accessibility")
    }

    @Test("Unknown perception type gets dynamic domain")
    func unknownPerception() {
        #expect(ActionDomainMapping.perceptionDomain(for: "custom") == "perception.custom")
    }

    // MARK: - Filesystem Domains

    @Test("Read operations map to filesystem.read",
          arguments: ["read", "list", "metadata", "search"])
    func readOperations(op: String) {
        #expect(ActionDomainMapping.filesystemDomain(for: op) == "filesystem.read")
    }

    @Test("Write operations map to filesystem.write",
          arguments: ["write", "delete"])
    func writeOperations(op: String) {
        #expect(ActionDomainMapping.filesystemDomain(for: op) == "filesystem.write")
    }

    @Test("Unknown filesystem operation gets dynamic domain")
    func unknownFilesystemOp() {
        #expect(ActionDomainMapping.filesystemDomain(for: "custom") == "filesystem.custom")
    }
}
