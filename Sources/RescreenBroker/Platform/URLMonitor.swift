import ApplicationServices
import Foundation

/// Monitors active URLs in browser applications via accessibility API.
final class URLMonitor {
    private let appResolver: AppResolver

    /// Known browser bundle IDs and the a11y path to the URL bar.
    private static let browserURLAttributes: [String: URLExtractionStrategy] = [
        "com.google.Chrome": .textField(role: "AXTextField", identifier: "Address and search bar"),
        "com.apple.Safari": .textField(role: "AXTextField", identifier: nil), // Safari uses the first text field in the toolbar
        "org.mozilla.firefox": .textField(role: "AXTextField", identifier: nil),
        "com.microsoft.edgemac": .textField(role: "AXTextField", identifier: "Address and search bar"),
        "company.thebrowser.Browser": .textField(role: "AXTextField", identifier: nil), // Arc
    ]

    enum URLExtractionStrategy {
        case textField(role: String, identifier: String?)
    }

    init(appResolver: AppResolver = AppResolver()) {
        self.appResolver = appResolver
    }

    /// Get the current URL from a browser app.
    func currentURL(bundleID: String) -> String? {
        guard Self.browserURLAttributes[bundleID] != nil else { return nil }
        guard let resolved = appResolver.resolve(bundleID: bundleID) else { return nil }

        let appElement = resolved.element

        // Try to get the focused window's URL bar
        var windowValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let window = windowValue
        else { return nil }

        // Search for URL text field recursively (limited depth)
        // AXUIElement is a CFTypeRef alias, so the cast from AnyObject is safe here
        // but we guard it anyway for robustness
        guard CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return findURLTextField(in: (window as! AXUIElement), depth: 0, maxDepth: 6)
    }

    /// Check if a bundle ID is a known browser.
    func isBrowser(_ bundleID: String) -> Bool {
        return Self.browserURLAttributes[bundleID] != nil
    }

    // MARK: - Private

    private func findURLTextField(in element: AXUIElement, depth: Int, maxDepth: Int) -> String? {
        guard depth < maxDepth else { return nil }

        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? ""

        if role == "AXTextField" || role == "AXComboBox" || role == "AXSearchField" {
            var valueObj: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueObj)
            if let value = valueObj as? String, !value.isEmpty, looksLikeURL(value) {
                return value
            }

            // Some browsers expose the URL in the description or title
            var descObj: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descObj)
            if let desc = descObj as? String, !desc.isEmpty, looksLikeURL(desc) {
                return desc
            }
        }

        // Chrome sometimes exposes the URL via AXDocument attribute on the web area
        if role == "AXWebArea" || role == "AXGroup" {
            var urlObj: AnyObject?
            AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &urlObj)
            if let url = urlObj as? URL {
                return url.absoluteString
            }
            // Also try AXDocument
            AXUIElementCopyAttributeValue(element, "AXDocument" as CFString, &urlObj)
            if let urlStr = urlObj as? String, looksLikeURL(urlStr) {
                return urlStr
            }
        }

        // Recurse into children
        var childrenValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement]
        else { return nil }

        for child in children {
            if let url = findURLTextField(in: child, depth: depth + 1, maxDepth: maxDepth) {
                return url
            }
        }

        return nil
    }

    private func looksLikeURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return true }
        // Check for domain-like patterns (e.g., "google.com/search...")
        if trimmed.contains(".") && !trimmed.contains(" ") && trimmed.count > 4 { return true }
        return false
    }
}
