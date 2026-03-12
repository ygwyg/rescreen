import AppKit
import CoreGraphics
import Foundation

/// Enumerates windows and provides geometry information.
final class WindowManager {
    struct WindowInfo: Sendable {
        let windowID: Int
        let ownerPID: Int
        let ownerName: String
        let ownerBundleID: String?
        let title: String
        let bounds: CGRect
        let isOnScreen: Bool
        let layer: Int
        let alpha: Float
    }

    /// Get all on-screen windows for a given process ID.
    func windows(forPID pid: Int32) -> [WindowInfo] {
        return allOnScreenWindows().filter { $0.ownerPID == Int(pid) }
    }

    /// Get all on-screen windows across all apps, in front-to-back z-order.
    /// Used by ZOrderMonitor for occlusion detection.
    func allOnScreenWindows() -> [WindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        // Cache PID → bundle ID lookups
        var bundleIDCache: [Int32: String?] = [:]

        return windowList.compactMap { info -> WindowInfo? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  let windowID = info[kCGWindowNumber as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any]
            else {
                return nil
            }

            let ownerName = info[kCGWindowOwnerName as String] as? String ?? "Unknown"
            let title = info[kCGWindowName as String] as? String ?? ""
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let alpha = info[kCGWindowAlpha as String] as? Float ?? 1.0

            // Resolve bundle ID from PID (cached)
            if !bundleIDCache.keys.contains(ownerPID) {
                let app = NSWorkspace.shared.runningApplications.first { $0.processIdentifier == ownerPID }
                bundleIDCache[ownerPID] = app?.bundleIdentifier
            }

            let x = boundsDict["X"] as? Double ?? 0
            let y = boundsDict["Y"] as? Double ?? 0
            let width = boundsDict["Width"] as? Double ?? 0
            let height = boundsDict["Height"] as? Double ?? 0

            return WindowInfo(
                windowID: windowID,
                ownerPID: Int(ownerPID),
                ownerName: ownerName,
                ownerBundleID: bundleIDCache[ownerPID] ?? nil,
                title: title,
                bounds: CGRect(x: x, y: y, width: width, height: height),
                isOnScreen: true,
                layer: layer,
                alpha: alpha
            )
        }
    }

    /// Get window info as a serializable dictionary.
    func windowDicts(forPID pid: Int32) -> [[String: Any]] {
        return windows(forPID: pid).map { win in
            var dict: [String: Any] = [
                "window_id": win.windowID,
                "owner": win.ownerName,
                "bounds": [
                    "x": Int(win.bounds.origin.x),
                    "y": Int(win.bounds.origin.y),
                    "w": Int(win.bounds.width),
                    "h": Int(win.bounds.height),
                ],
            ]
            if !win.title.isEmpty {
                dict["title"] = win.title
            }
            return dict
        }
    }
}
