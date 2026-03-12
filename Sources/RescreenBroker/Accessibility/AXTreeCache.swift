import ApplicationServices
import Foundation

/// Caches the mapping from element IDs (e.g., "e137") to AXUIElement references
/// from perceive calls. Maintains separate caches per app so multi-app workflows
/// don't invalidate each other's element references.
final class AXTreeCache {
    /// Per-app element caches. Each app's perceive overwrites only its own cache.
    private var appCaches: [String: [String: AXUIElement]] = [:]
    private let lock = NSLock()

    /// Store elements from a tree capture for a specific app.
    func store(bundleID: String, elements: [(id: String, element: AXUIElement)]) {
        lock.lock()
        defer { lock.unlock() }
        appCaches[bundleID] = Dictionary(uniqueKeysWithValues: elements)
        Log.debug("Cached \(elements.count) elements for \(bundleID)")
    }

    /// Look up an AXUIElement by its assigned ID within an app's cache.
    func resolve(id: String, bundleID: String) -> AXUIElement? {
        lock.lock()
        defer { lock.unlock() }
        guard let cache = appCaches[bundleID] else {
            Log.debug("Cache miss: no cache for \(bundleID)")
            return nil
        }
        return cache[id]
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

    /// Clear the cache for a specific app, or all apps if bundleID is nil.
    func clear(bundleID: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let bundleID = bundleID {
            appCaches.removeValue(forKey: bundleID)
        } else {
            appCaches.removeAll()
        }
    }
}
