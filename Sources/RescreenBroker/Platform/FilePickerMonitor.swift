import ApplicationServices
import Foundation

/// Detects active file open/save panels in permitted apps and validates
/// that the selected paths are within the agent's filesystem scope.
final class FilePickerMonitor {
    private let pathValidator: PathValidator?

    struct FilePickerInfo {
        let isActive: Bool
        let type: PickerType
        let currentPath: String?

        enum PickerType {
            case open
            case save
            case unknown
        }
    }

    init(pathValidator: PathValidator?) {
        self.pathValidator = pathValidator
    }

    /// Check if a file picker (NSOpenPanel/NSSavePanel) is active in the given app.
    func detectFilePicker(appElement: AXUIElement) -> FilePickerInfo? {
        // Look for sheet/dialog windows
        var windowsValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement]
        else { return nil }

        for window in windows {
            // Check for sheets (file pickers are typically sheets)
            var sheetsValue: AnyObject?
            if AXUIElementCopyAttributeValue(window, "AXSheets" as CFString, &sheetsValue) == .success,
               let sheets = sheetsValue as? [AXUIElement]
            {
                for sheet in sheets {
                    if let info = analyzeDialog(sheet) {
                        return info
                    }
                }
            }

            // Also check the window itself — some apps show file pickers as standalone windows
            var subroleValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue)
            if let subrole = subroleValue as? String, subrole == "AXDialog" {
                if let info = analyzeDialog(window) {
                    return info
                }
            }
        }

        return nil
    }

    /// Check if clicking an element named "Open" or "Save" in a file picker
    /// would access a path outside the allowed scope.
    func shouldBlockFilePickerAction(elementName: String?, appElement: AXUIElement) -> String? {
        guard let validator = pathValidator else {
            // No fs-allow configured — require confirmation for any file picker action
            return nil
        }

        // Only intercept when clicking "Open", "Save", "Choose" buttons
        guard let name = elementName?.lowercased(),
              name == "open" || name == "save" || name == "choose" || name == "ok"
        else { return nil }

        // Try to detect the file picker and extract the current path
        guard let pickerInfo = detectFilePicker(appElement: appElement),
              pickerInfo.isActive,
              let currentPath = pickerInfo.currentPath
        else { return nil }

        if !validator.isAllowed(currentPath) {
            return "File picker path '\(currentPath)' is outside allowed scope (\(validator.allowedPathsDescription))"
        }

        return nil
    }

    // MARK: - Private

    private func analyzeDialog(_ element: AXUIElement) -> FilePickerInfo? {
        var titleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        let title = (titleValue as? String)?.lowercased() ?? ""

        // Detect picker type by title
        let isOpen = title.contains("open") || title.contains("choose") || title.contains("select")
        let isSave = title.contains("save") || title.contains("export")

        guard isOpen || isSave else { return nil }

        // Try to extract the current path from the dialog
        let currentPath = extractPathFromDialog(element)

        return FilePickerInfo(
            isActive: true,
            type: isOpen ? .open : .save,
            currentPath: currentPath
        )
    }

    private func extractPathFromDialog(_ element: AXUIElement) -> String? {
        // Look for text fields that might contain the filename/path
        return findTextField(in: element, depth: 0, maxDepth: 6)
    }

    private func findTextField(in element: AXUIElement, depth: Int, maxDepth: Int) -> String? {
        guard depth < maxDepth else { return nil }

        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? ""

        if role == "AXTextField" {
            var valueObj: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueObj)
            if let value = valueObj as? String, !value.isEmpty {
                return value
            }
        }

        // Check for path bar / breadcrumb that shows current directory
        if role == "AXStaticText" {
            var valueObj: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueObj)
            if let value = valueObj as? String, value.hasPrefix("/") {
                return value
            }
        }

        var childrenValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement]
        else { return nil }

        for child in children {
            if let path = findTextField(in: child, depth: depth + 1, maxDepth: maxDepth) {
                return path
            }
        }

        return nil
    }
}
