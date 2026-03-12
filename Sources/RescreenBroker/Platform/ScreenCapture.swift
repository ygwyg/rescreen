import CoreGraphics
import Foundation
import ImageIO

/// Captures screenshots of application windows using CGWindowListCreateImage.
final class ScreenCapture {

    /// Capture a screenshot of a specific window by its CGWindowID.
    func captureWindow(windowID: CGWindowID) -> CGImage? {
        return CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .nominalResolution]
        )
    }

    /// Capture a screenshot of all windows belonging to a PID.
    func captureApp(pid: Int32) -> (image: CGImage, bounds: CGRect)? {
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

        var appWindowIDs: [CGWindowID] = []
        var unionBounds = CGRect.null

        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32, ownerPID == pid,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any]
            else { continue }

            if let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
                appWindowIDs.append(windowID)
                unionBounds = unionBounds.union(rect)
            }
        }

        guard !appWindowIDs.isEmpty else { return nil }

        // Validate dimensions to prevent OOM from malformed window bounds
        let maxDimension: CGFloat = 10000
        guard unionBounds.width > 0, unionBounds.height > 0,
              unionBounds.width <= maxDimension, unionBounds.height <= maxDimension
        else {
            Log.error("Screenshot bounds out of range: \(unionBounds)")
            return nil
        }

        // Capture the primary (first) window
        guard let image = captureWindow(windowID: appWindowIDs[0]) else { return nil }
        return (image, unionBounds)
    }

    /// Encode a CGImage as PNG data.
    func encodePNG(_ image: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutableData as CFMutableData, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutableData as Data
    }

    /// Encode a CGImage as base64 PNG string.
    func encodeBase64PNG(_ image: CGImage) -> String? {
        guard let data = encodePNG(image) else { return nil }
        return data.base64EncodedString()
    }
}
