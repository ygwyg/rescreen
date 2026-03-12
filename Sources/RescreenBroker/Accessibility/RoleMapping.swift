import ApplicationServices

/// Maps macOS AXRole (+ optional AXSubrole) to Rescreen's normalized ARIA-derived roles.
enum RoleMapping {
    /// Returns the normalized Rescreen role for a given AXRole and optional AXSubrole.
    static func normalize(axRole: String, axSubrole: String? = nil) -> String {
        // Check subrole-specific mappings first
        if let subrole = axSubrole, let mapped = subroleMap["\(axRole):\(subrole)"] {
            return mapped
        }
        // Fall back to role-only mapping
        return roleMap[axRole] ?? "generic"
    }

    // MARK: - Role Map (AXRole -> Rescreen role)

    private static let roleMap: [String: String] = [
        kAXApplicationRole: "application",
        kAXWindowRole: "window",
        kAXButtonRole: "button",
        kAXRadioButtonRole: "radio",
        kAXCheckBoxRole: "checkbox",
        kAXTextFieldRole: "textbox",
        kAXTextAreaRole: "textbox",
        kAXStaticTextRole: "text",
        kAXHeadingRole: "heading",
        kAXImageRole: "img",
        kAXGroupRole: "group",
        kAXListRole: "list",
        kAXOutlineRole: "tree",
        kAXTableRole: "table",
        kAXRowRole: "row",
        kAXColumnRole: "columnheader",
        kAXCellRole: "cell",
        kAXMenuBarRole: "menubar",
        kAXMenuRole: "menu",
        kAXMenuItemRole: "menuitem",
        kAXMenuBarItemRole: "menuitem",
        kAXToolbarRole: "toolbar",
        kAXTabGroupRole: "tablist",
        kAXScrollAreaRole: "region",
        kAXScrollBarRole: "scrollbar",
        kAXSliderRole: "slider",
        kAXComboBoxRole: "combobox",
        kAXPopUpButtonRole: "listbox",
        kAXProgressIndicatorRole: "progressbar",
        kAXBusyIndicatorRole: "status",
        kAXSplitGroupRole: "group",
        kAXSplitterRole: "separator",
        kAXSheetRole: "dialog",
        kAXDrawerRole: "complementary",
        kAXGrowAreaRole: "generic",
        kAXIncrementorRole: "spinbutton",
        kAXValueIndicatorRole: "generic",
        "AXLink": "link",
        kAXDisclosureTriangleRole: "button",
        kAXGridRole: "grid",
        kAXBrowserRole: "tree",
        kAXLayoutAreaRole: "generic",
        kAXLayoutItemRole: "generic",
        kAXColorWellRole: "generic",
        kAXHelpTagRole: "tooltip",
        kAXMatteRole: "generic",
        kAXRulerRole: "generic",
        kAXRulerMarkerRole: "generic",
        kAXRelevanceIndicatorRole: "meter",
        kAXLevelIndicatorRole: "meter",
        kAXPopoverRole: "dialog",
    ]

    // MARK: - Subrole Map (AXRole:AXSubrole -> Rescreen role)

    private static let subroleMap: [String: String] = [
        "\(kAXWindowRole):\(kAXStandardWindowSubrole)": "window",
        "\(kAXWindowRole):\(kAXDialogSubrole)": "dialog",
        "\(kAXWindowRole):\(kAXFloatingWindowSubrole)": "dialog",
        "\(kAXTextFieldRole):\(kAXSearchFieldSubrole)": "searchbox",
        "\(kAXTextFieldRole):\(kAXSecureTextFieldSubrole)": "textbox",
        "\(kAXCheckBoxRole):\(kAXSwitchSubrole)": "switch",
        "\(kAXMenuItemRole):AXMenuBarItem": "menuitem",
        "\(kAXGroupRole):AXTabGroup": "tablist",
        "\(kAXButtonRole):\(kAXCloseButtonSubrole)": "button",
        "\(kAXButtonRole):\(kAXMinimizeButtonSubrole)": "button",
        "\(kAXButtonRole):\(kAXZoomButtonSubrole)": "button",
        "\(kAXButtonRole):\(kAXFullScreenButtonSubrole)": "button",
        "\(kAXButtonRole):\(kAXIncrementArrowSubrole)": "button",
        "\(kAXButtonRole):\(kAXDecrementArrowSubrole)": "button",
        "\(kAXButtonRole):\(kAXToggleSubrole)": "button",
    ]
}
