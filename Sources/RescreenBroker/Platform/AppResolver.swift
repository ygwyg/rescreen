import AppKit
import ApplicationServices

/// Resolves running applications by bundle ID and creates AXUIElement references.
final class AppResolver {
    /// Find a running application by bundle ID and return its AXUIElement.
    func resolve(bundleID: String) -> (app: NSRunningApplication, element: AXUIElement)? {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID
        }

        guard let app = apps.first else {
            Log.debug("App not found: \(bundleID)")
            return nil
        }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        return (app, element)
    }

    /// Get the window origin for coordinate conversion (top-left of the frontmost window).
    func getWindowOrigin(for element: AXUIElement) -> CGPoint? {
        // Get windows
        var windowsValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windowsValue)
        guard result == .success, let windows = windowsValue as? [AXUIElement], let firstWindow = windows.first else {
            return nil
        }

        // Get position of the first window
        var posValue: AnyObject?
        let posResult = AXUIElementCopyAttributeValue(firstWindow, kAXPositionAttribute as CFString, &posValue)
        guard posResult == .success, let posVal = posValue, CFGetTypeID(posVal) == AXValueGetTypeID() else {
            return nil
        }

        var position = CGPoint.zero
        // CFGetTypeID check above guarantees this is an AXValue instance
        AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
        return position
    }
}
