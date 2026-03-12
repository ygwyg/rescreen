import ApplicationServices
import Foundation

/// Handles rescreen_perceive and rescreen_overview tool calls.
final class PerceiveHandler {
    private let capabilities: CapabilityStore
    private let appResolver: AppResolver
    private let treeCapture: AXTreeCapture
    private let windowManager: WindowManager
    private let screenCapture: ScreenCapture
    private let auditLogger: AuditLogger
    let treeCache: AXTreeCache
    var zOrderMonitor: ZOrderMonitor?

    init(capabilities: CapabilityStore, appResolver: AppResolver, treeCapture: AXTreeCapture,
         windowManager: WindowManager = WindowManager(), treeCache: AXTreeCache = AXTreeCache(),
         screenCapture: ScreenCapture = ScreenCapture(), auditLogger: AuditLogger) {
        self.capabilities = capabilities
        self.appResolver = appResolver
        self.treeCapture = treeCapture
        self.windowManager = windowManager
        self.screenCapture = screenCapture
        self.treeCache = treeCache
        self.auditLogger = auditLogger
    }

    func handle(arguments: [String: Any]) -> [String: Any] {
        guard let type = arguments["type"] as? String else {
            return errorResult("Missing required parameter: type")
        }

        let bundleID = (arguments["target"] as? String) ?? capabilities.permittedBundleIDs.first ?? ""

        guard capabilities.canPerceive(bundleID: bundleID, type: type) else {
            return TimingNormalizer.withMinimumDuration {
                auditLogger.log(
                    operation: "perceive.\(type)",
                    app: bundleID,
                    result: "denied",
                    confirmation: "block"
                )
                return CapabilityStore.notFoundResult
            }
        }

        switch type {
        case "accessibility":
            return handleAccessibility(bundleID: bundleID, arguments: arguments)
        case "screenshot":
            return handleScreenshot(bundleID: bundleID)
        case "composite":
            return handleComposite(bundleID: bundleID, arguments: arguments)
        case "find":
            return handleFind(bundleID: bundleID, arguments: arguments)
        default:
            return errorResult("Unknown perception type: \(type)")
        }
    }

    func handleOverview() -> [String: Any] {
        var allWindows: [[String: Any]] = []

        for bundleID in capabilities.permittedBundleIDs {
            guard let resolved = appResolver.resolve(bundleID: bundleID) else { continue }
            let windows = windowManager.windowDicts(forPID: resolved.app.processIdentifier)
            for var win in windows {
                win["app"] = bundleID
                allWindows.append(win)
            }
        }

        auditLogger.log(
            operation: "perceive.overview",
            result: allWindows.isEmpty ? "empty" : "success",
            confirmation: "silent"
        )

        if allWindows.isEmpty {
            return textResult("No permitted applications are currently running.")
        }

        guard let json = try? JSONSerialization.data(withJSONObject: allWindows, options: [.sortedKeys]),
              let jsonStr = String(data: json, encoding: .utf8) else {
            return errorResult("Failed to serialize window list")
        }

        return textResult(jsonStr)
    }

    // MARK: - Accessibility Perception

    private func handleAccessibility(bundleID: String, arguments: [String: Any]) -> [String: Any] {
        guard let resolved = appResolver.resolve(bundleID: bundleID) else {
            return textResult("Application \(bundleID) is not running.")
        }

        let maxDepth = min(arguments["max_depth"] as? Int ?? 8, 20)
        let maxNodes = min(arguments["max_nodes"] as? Int ?? 300, 5000)

        let options = AXTreeCapture.CaptureOptions(maxDepth: maxDepth, maxNodes: maxNodes)
        let windowOrigin = appResolver.getWindowOrigin(for: resolved.element)
        let result = treeCapture.capture(appElement: resolved.element, windowOrigin: windowOrigin, options: options)

        treeCache.store(bundleID: bundleID, elements: result.elementRefs)

        auditLogger.log(
            operation: "perceive.accessibility",
            app: bundleID,
            params: ["nodes": "\(result.nodes.count)", "max_depth": "\(maxDepth)"],
            result: "success",
            confirmation: "silent"
        )

        if result.nodes.isEmpty {
            return textResult("No accessibility nodes found for \(bundleID).")
        }

        let json = TreeSerializer.toJSON(nodes: result.nodes)
        var summary = "Captured \(result.nodes.count) UI elements from \(bundleID) (max_depth: \(maxDepth), max_nodes: \(maxNodes))"

        // Check z-order occlusion and warn if applicable
        if let monitor = zOrderMonitor {
            let occlusion = monitor.checkOcclusion(forPID: resolved.app.processIdentifier)
            if occlusion.isOccluded {
                let warning = monitor.describeOcclusion(occlusion)
                summary += "\n⚠️ WARNING: \(warning)"
                auditLogger.log(
                    operation: "perceive.accessibility.occlusion_warning",
                    app: bundleID,
                    params: ["occluders": occlusion.occludingWindows.map(\.ownerName).joined(separator: ", ")],
                    result: "warning",
                    confirmation: "silent"
                )
            }
        }

        return [
            "content": [
                ["type": "text", "text": "\(summary)\n\n\(json)"] as [String: Any]
            ]
        ]
    }

    // MARK: - Screenshot Perception

    private func handleScreenshot(bundleID: String) -> [String: Any] {
        guard let resolved = appResolver.resolve(bundleID: bundleID) else {
            return textResult("Application \(bundleID) is not running.")
        }

        let pid = resolved.app.processIdentifier
        guard let capture = screenCapture.captureApp(pid: pid) else {
            return errorResult("Failed to capture screenshot of \(bundleID). Ensure screen recording permission is granted.")
        }

        guard let base64 = screenCapture.encodeBase64PNG(capture.image) else {
            return errorResult("Failed to encode screenshot")
        }

        auditLogger.log(
            operation: "perceive.screenshot",
            app: bundleID,
            params: ["width": "\(capture.image.width)", "height": "\(capture.image.height)"],
            result: "success",
            confirmation: "silent"
        )

        return [
            "content": [
                [
                    "type": "image",
                    "data": base64,
                    "mimeType": "image/png",
                ] as [String: Any],
                [
                    "type": "text",
                    "text": "Screenshot of \(bundleID) (\(capture.image.width)x\(capture.image.height)px)",
                ] as [String: Any],
            ]
        ]
    }

    // MARK: - Composite Perception

    private func handleComposite(bundleID: String, arguments: [String: Any]) -> [String: Any] {
        guard let resolved = appResolver.resolve(bundleID: bundleID) else {
            return textResult("Application \(bundleID) is not running.")
        }

        let pid = resolved.app.processIdentifier
        let maxDepth = arguments["max_depth"] as? Int ?? 8
        let maxNodes = arguments["max_nodes"] as? Int ?? 300

        // First capture a11y tree
        let options = AXTreeCapture.CaptureOptions(maxDepth: maxDepth, maxNodes: maxNodes)
        let windowOrigin = appResolver.getWindowOrigin(for: resolved.element)
        let treeResult = treeCapture.capture(appElement: resolved.element, windowOrigin: windowOrigin, options: options)

        treeCache.store(bundleID: bundleID, elements: treeResult.elementRefs)

        // Then capture screenshot
        let screenshotResult = screenCapture.captureApp(pid: pid)

        auditLogger.log(
            operation: "perceive.composite",
            app: bundleID,
            params: ["nodes": "\(treeResult.nodes.count)", "has_screenshot": "\(screenshotResult != nil)"],
            result: "success",
            confirmation: "silent"
        )

        let treeJSON = TreeSerializer.toJSON(nodes: treeResult.nodes)
        let summary = "Composite view of \(bundleID): \(treeResult.nodes.count) UI elements"

        var content: [[String: Any]] = []

        // Add screenshot if available
        if let capture = screenshotResult, let base64 = screenCapture.encodeBase64PNG(capture.image) {
            content.append([
                "type": "image",
                "data": base64,
                "mimeType": "image/png",
            ])
        }

        content.append([
            "type": "text",
            "text": "\(summary)\n\n\(treeJSON)",
        ])

        return ["content": content]
    }

    // MARK: - Find Perception

    private func handleFind(bundleID: String, arguments: [String: Any]) -> [String: Any] {
        guard let resolved = appResolver.resolve(bundleID: bundleID) else {
            return textResult("Application \(bundleID) is not running.")
        }

        let query = arguments["query"] as? String
        let role = arguments["role"] as? String

        guard query != nil || role != nil else {
            return errorResult("Find requires at least 'query' or 'role' parameter")
        }

        // Capture full tree with higher limits for search
        let options = AXTreeCapture.CaptureOptions(maxDepth: 12, maxNodes: 1000)
        let windowOrigin = appResolver.getWindowOrigin(for: resolved.element)
        let result = treeCapture.capture(appElement: resolved.element, windowOrigin: windowOrigin, options: options)

        treeCache.store(bundleID: bundleID, elements: result.elementRefs)

        // Filter nodes
        let filtered = result.nodes.filter { node in
            var matches = true
            if let q = query?.lowercased() {
                let nameMatch = node.name?.lowercased().contains(q) ?? false
                let valueMatch = node.value?.lowercased().contains(q) ?? false
                matches = nameMatch || valueMatch
            }
            if let r = role?.lowercased(), matches {
                matches = node.role.lowercased() == r
            }
            return matches
        }

        auditLogger.log(
            operation: "perceive.find",
            app: bundleID,
            params: ["query": query ?? "", "role": role ?? "", "matches": "\(filtered.count)"],
            result: "success",
            confirmation: "silent"
        )

        if filtered.isEmpty {
            let searchDesc = [query.map { "query='\($0)'" }, role.map { "role='\($0)'" }].compactMap { $0 }.joined(separator: ", ")
            return textResult("No elements found matching \(searchDesc) in \(bundleID)")
        }

        let json = TreeSerializer.toJSON(nodes: filtered)
        return textResult("Found \(filtered.count) matching elements:\n\n\(json)")
    }

    // MARK: - Helpers

    private func textResult(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text] as [String: Any]]]
    }

    private func errorResult(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": "Error: \(message)"] as [String: Any]], "isError": true]
    }
}
