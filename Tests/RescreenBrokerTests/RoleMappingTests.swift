import ApplicationServices
import Testing

@testable import RescreenBroker

@Suite("RoleMapping")
struct RoleMappingTests {
    // MARK: - Basic Role Mapping

    @Test("Common AX roles map to expected Rescreen roles")
    func commonRoles() {
        #expect(RoleMapping.normalize(axRole: kAXButtonRole) == "button")
        #expect(RoleMapping.normalize(axRole: kAXTextFieldRole) == "textbox")
        #expect(RoleMapping.normalize(axRole: kAXCheckBoxRole) == "checkbox")
        #expect(RoleMapping.normalize(axRole: kAXWindowRole) == "window")
        #expect(RoleMapping.normalize(axRole: kAXApplicationRole) == "application")
        #expect(RoleMapping.normalize(axRole: kAXStaticTextRole) == "text")
        #expect(RoleMapping.normalize(axRole: kAXImageRole) == "img")
        #expect(RoleMapping.normalize(axRole: kAXGroupRole) == "group")
        #expect(RoleMapping.normalize(axRole: kAXMenuRole) == "menu")
        #expect(RoleMapping.normalize(axRole: kAXMenuItemRole) == "menuitem")
        #expect(RoleMapping.normalize(axRole: kAXSliderRole) == "slider")
        #expect(RoleMapping.normalize(axRole: kAXTableRole) == "table")
        #expect(RoleMapping.normalize(axRole: kAXRowRole) == "row")
        #expect(RoleMapping.normalize(axRole: kAXCellRole) == "cell")
    }

    @Test("Container roles map correctly")
    func containerRoles() {
        #expect(RoleMapping.normalize(axRole: kAXListRole) == "list")
        #expect(RoleMapping.normalize(axRole: kAXOutlineRole) == "tree")
        #expect(RoleMapping.normalize(axRole: kAXTabGroupRole) == "tablist")
        #expect(RoleMapping.normalize(axRole: kAXToolbarRole) == "toolbar")
        #expect(RoleMapping.normalize(axRole: kAXMenuBarRole) == "menubar")
        #expect(RoleMapping.normalize(axRole: kAXScrollAreaRole) == "region")
    }

    @Test("Form control roles map correctly")
    func formControlRoles() {
        #expect(RoleMapping.normalize(axRole: kAXRadioButtonRole) == "radio")
        #expect(RoleMapping.normalize(axRole: kAXComboBoxRole) == "combobox")
        #expect(RoleMapping.normalize(axRole: kAXPopUpButtonRole) == "listbox")
        #expect(RoleMapping.normalize(axRole: kAXProgressIndicatorRole) == "progressbar")
    }

    // MARK: - Subrole Overrides

    @Test("Window subroles override base role")
    func windowSubroles() {
        #expect(RoleMapping.normalize(axRole: kAXWindowRole, axSubrole: kAXDialogSubrole) == "dialog")
        #expect(RoleMapping.normalize(axRole: kAXWindowRole, axSubrole: kAXFloatingWindowSubrole) == "dialog")
        #expect(RoleMapping.normalize(axRole: kAXWindowRole, axSubrole: kAXStandardWindowSubrole) == "window")
    }

    @Test("Search field subrole overrides textfield")
    func searchFieldSubrole() {
        #expect(RoleMapping.normalize(axRole: kAXTextFieldRole, axSubrole: kAXSearchFieldSubrole) == "searchbox")
    }

    @Test("Switch subrole overrides checkbox")
    func switchSubrole() {
        #expect(RoleMapping.normalize(axRole: kAXCheckBoxRole, axSubrole: kAXSwitchSubrole) == "switch")
    }

    @Test("Button subroles still map to button")
    func buttonSubroles() {
        #expect(RoleMapping.normalize(axRole: kAXButtonRole, axSubrole: kAXCloseButtonSubrole) == "button")
        #expect(RoleMapping.normalize(axRole: kAXButtonRole, axSubrole: kAXMinimizeButtonSubrole) == "button")
        #expect(RoleMapping.normalize(axRole: kAXButtonRole, axSubrole: kAXZoomButtonSubrole) == "button")
    }

    // MARK: - Unknown Roles

    @Test("Unknown role maps to generic")
    func unknownRole() {
        #expect(RoleMapping.normalize(axRole: "AXCompletelyMadeUp") == "generic")
    }

    @Test("Unknown subrole falls back to role mapping")
    func unknownSubrole() {
        #expect(RoleMapping.normalize(axRole: kAXButtonRole, axSubrole: "AXMadeUpSubrole") == "button")
    }

    @Test("Nil subrole uses role mapping")
    func nilSubrole() {
        #expect(RoleMapping.normalize(axRole: kAXButtonRole, axSubrole: nil) == "button")
    }

    // MARK: - Link Role (String-Based)

    @Test("Link role maps correctly")
    func linkRole() {
        #expect(RoleMapping.normalize(axRole: "AXLink") == "link")
    }
}
