import CoreGraphics
import Foundation

/// Monitors window z-order to detect when unpermitted windows overlap
/// permitted windows, preventing UI overlay attacks.
final class ZOrderMonitor {
    private let windowManager: WindowManager
    private let permittedBundleIDs: () -> Set<String>
    private let brokerPID: Int32
    private let parentPID: Int32

    struct OcclusionReport {
        let isOccluded: Bool
        let occludingWindows: [OccludingWindow]
    }

    struct OccludingWindow {
        let ownerName: String
        let bundleID: String?
        let overlapRect: CGRect
    }

    init(windowManager: WindowManager, permittedBundleIDs: @escaping () -> Set<String>) {
        self.windowManager = windowManager
        self.permittedBundleIDs = permittedBundleIDs
        self.brokerPID = ProcessInfo.processInfo.processIdentifier
        self.parentPID = getppid()
    }

    /// Check if any unpermitted windows overlap the windows of a permitted app.
    ///
    /// CGWindowListCopyWindowInfo returns windows in front-to-back order when using
    /// kCGWindowListOptionOnScreenOnly, so earlier entries are in front of later ones.
    func checkOcclusion(forPID pid: Int32) -> OcclusionReport {
        let allWindows = windowManager.allOnScreenWindows()
        let permitted = permittedBundleIDs()

        // Find the target app's windows
        let targetWindows = allWindows.filter { $0.ownerPID == Int(pid) }

        guard !targetWindows.isEmpty else {
            return OcclusionReport(isOccluded: false, occludingWindows: [])
        }

        var occluders: [OccludingWindow] = []

        for targetWindow in targetWindows {
            for window in allWindows {
                // Skip the target app's own windows
                if window.ownerPID == Int(pid) { continue }

                // Skip the broker's own windows (confirmation panel)
                if window.ownerPID == Int(brokerPID) { continue }

                // Skip the parent process (terminal running the broker)
                if window.ownerPID == Int(parentPID) { continue }

                // Skip windows from other permitted apps
                if let bundleID = window.ownerBundleID, permitted.contains(bundleID) { continue }

                // Skip tiny windows (menu bar items, status icons, etc.)
                if window.bounds.width < 10 || window.bounds.height < 10 { continue }

                // Skip transparent windows
                if window.alpha < 0.1 { continue }

                // Skip windows at negative layers (desktop elements)
                if window.layer < 0 { continue }

                // Skip system-level processes (menu bar, dock, compositor, notch fill)
                let systemOwners: Set<String> = ["Window Server", "WindowManager", "Dock", "Control Center", "SystemUIServer", "Notification Center"]
                if systemOwners.contains(window.ownerName) { continue }

                // Check if this window overlaps the target
                let overlap = targetWindow.bounds.intersection(window.bounds)
                if !overlap.isNull && overlap.width > 5 && overlap.height > 5 {
                    // Only flag if the window is in FRONT of our target
                    // (appears earlier in the array = higher z-order)
                    if let windowIdx = allWindows.firstIndex(where: { $0.windowID == window.windowID }),
                       let targetIdx = allWindows.firstIndex(where: { $0.windowID == targetWindow.windowID }),
                       windowIdx < targetIdx
                    {
                        occluders.append(OccludingWindow(
                            ownerName: window.ownerName,
                            bundleID: window.ownerBundleID,
                            overlapRect: overlap
                        ))
                    }
                }
            }
        }

        return OcclusionReport(
            isOccluded: !occluders.isEmpty,
            occludingWindows: occluders
        )
    }

    /// Returns a human-readable description of occlusion for error messages.
    func describeOcclusion(_ report: OcclusionReport) -> String {
        let names = Set(report.occludingWindows.map { $0.ownerName })
        return "Window obscured by: \(names.joined(separator: ", ")). Bring the target window to the front first."
    }
}
