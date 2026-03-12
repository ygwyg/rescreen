import ApplicationServices
import Foundation

/// Caches the mapping from element IDs (e.g., "e137") to AXUIElement references
/// from the most recent perceive call. This ensures that act() targets the same
/// element the agent saw in the perceive results.
final class AXTreeCache {
    /// Cached element references keyed by their assigned ID.
    private var elements: [String: AXUIElement] = [:]
    private var cachedBundleID: String = ""
    private let lock = NSLock()

    /// Store elements from a tree capture.
    func store(bundleID: String, elements: [(id: String, element: AXUIElement)]) {
        lock.lock()
        defer { lock.unlock() }
        self.cachedBundleID = bundleID
        self.elements = Dictionary(uniqueKeysWithValues: elements)
        Log.debug("Cached \(elements.count) elements for \(bundleID)")
    }

    /// Look up an AXUIElement by its assigned ID.
    func resolve(id: String, bundleID: String) -> AXUIElement? {
        lock.lock()
        defer { lock.unlock() }
        guard self.cachedBundleID == bundleID else {
            Log.debug("Cache miss: cached app is \(self.cachedBundleID), requested \(bundleID)")
            return nil
        }
        return elements[id]
    }

    /// Get the role and name of a cached element for confirmation prompts.
    func describe(id: String, bundleID: String) -> (role: String, name: String?)? {
        guard let element = resolve(id: id, bundleID: bundleID) else { return nil }

        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let axRole = roleValue as? String ?? "AXUnknown"

        var subroleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)
        let axSubrole = subroleValue as? String

        let role = RoleMapping.normalize(axRole: axRole, axSubrole: axSubrole)

        var titleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        let name = (titleValue as? String) ?? {
            var descValue: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
            return descValue as? String
        }()

        return (role, name)
    }

    /// Clear the cache.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        elements.removeAll()
        cachedBundleID = ""
    }
}
