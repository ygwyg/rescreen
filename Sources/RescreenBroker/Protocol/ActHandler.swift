import AppKit
import ApplicationServices
import Foundation

/// Handles rescreen_act tool calls.
final class ActHandler {
    private let capabilities: CapabilityStore
    private let appResolver: AppResolver
    private let inputSynthesizer: InputSynthesizer
    private let windowManager: WindowManager
    private let treeCache: AXTreeCache
    private let auditLogger: AuditLogger
    var clipboardManager: ClipboardManager?
    var urlMonitor: URLMonitor?
    var zOrderMonitor: ZOrderMonitor?
    var filePickerMonitor: FilePickerMonitor?

    init(
        capabilities: CapabilityStore,
        appResolver: AppResolver = AppResolver(),
        inputSynthesizer: InputSynthesizer = InputSynthesizer(),
        windowManager: WindowManager = WindowManager(),
        treeCache: AXTreeCache,
        auditLogger: AuditLogger
    ) {
        self.capabilities = capabilities
        self.appResolver = appResolver
        self.inputSynthesizer = inputSynthesizer
        self.windowManager = windowManager
        self.treeCache = treeCache
        self.auditLogger = auditLogger
    }

    func handle(arguments: [String: Any]) -> [String: Any] {
        guard let type = arguments["type"] as? String else {
            return errorResult("Missing required parameter: type")
        }

        let bundleID = (arguments["target"] as? String) ?? capabilities.permittedBundleIDs.first ?? ""

        guard capabilities.canAct(bundleID: bundleID, actionType: type) else {
            return TimingNormalizer.withMinimumDuration {
                auditLogger.log(
                    operation: "act.\(type)",
                    app: bundleID,
                    result: "denied",
                    confirmation: "block"
                )
                return CapabilityStore.notFoundResult
            }
        }

        // Launch doesn't require a running app
        if type == "launch" {
            return handleLaunch(bundleID: bundleID)
        }

        guard let resolved = appResolver.resolve(bundleID: bundleID) else {
            return textResult("Application \(bundleID) is not running.")
        }

        let pid = resolved.app.processIdentifier
        let appName = resolved.app.localizedName ?? bundleID

        // Z-order occlusion check: auto-focus target app if occluded, then warn (never block).
        // Blocking on occlusion is impractical — users always have unpermitted apps open.
        let visualActions: Set<String> = ["click", "double_click", "right_click", "hover", "drag", "type", "press", "scroll", "select"]
        if visualActions.contains(type), let monitor = zOrderMonitor {
            var occlusion = monitor.checkOcclusion(forPID: pid)
            if occlusion.isOccluded {
                // Auto-focus: bring target app to front and retry once
                resolved.app.activate()
                Thread.sleep(forTimeInterval: 0.3)
                occlusion = monitor.checkOcclusion(forPID: pid)
            }
            if occlusion.isOccluded {
                let desc = monitor.describeOcclusion(occlusion)
                Log.debug("Occlusion warning (non-blocking): \(desc)")
                auditLogger.log(
                    operation: "act.\(type)",
                    app: bundleID,
                    result: "occlusion_warning",
                    confirmation: "logged"
                )
            }
        }

        // File picker interception: block clicks on Open/Save if path is out of scope
        if type == "click" || type == "double_click",
           let pickerMonitor = filePickerMonitor,
           let elementID = arguments["element"] as? String,
           let elementInfo = treeCache.describe(id: elementID, bundleID: bundleID)
        {
            if let blockReason = pickerMonitor.shouldBlockFilePickerAction(
                elementName: elementInfo.name,
                appElement: resolved.element
            ) {
                auditLogger.log(
                    operation: "act.\(type)",
                    app: bundleID,
                    element: elementID,
                    result: "blocked_file_picker",
                    confirmation: "block"
                )
                return errorResult("Action blocked: \(blockReason)")
            }
        }

        switch type {
        case "click":
            return handleClick(arguments: arguments, pid: pid, bundleID: bundleID, appName: appName)
        case "double_click":
            return handleDoubleClick(arguments: arguments, pid: pid, bundleID: bundleID, appName: appName)
        case "right_click":
            return handleRightClick(arguments: arguments, pid: pid, bundleID: bundleID, appName: appName)
        case "hover":
            return handleHover(arguments: arguments, pid: pid, bundleID: bundleID, appName: appName)
        case "drag":
            return handleDrag(arguments: arguments, pid: pid, bundleID: bundleID, appName: appName)
        case "type":
            return handleType(arguments: arguments, pid: pid, bundleID: bundleID, appName: appName)
        case "press":
            return handlePress(arguments: arguments, pid: pid, bundleID: bundleID, appName: appName)
        case "scroll":
            return handleScroll(arguments: arguments, bundleID: bundleID, appName: appName)
        case "select":
            return handleSelect(arguments: arguments, bundleID: bundleID, appName: appName)
        case "focus":
            return handleFocus(resolved: resolved, bundleID: bundleID, appName: appName)
        case "close":
            return handleClose(resolved: resolved, bundleID: bundleID, appName: appName)
        case "clipboard_read":
            return handleClipboardRead(bundleID: bundleID)
        case "clipboard_write":
            return handleClipboardWrite(arguments: arguments, bundleID: bundleID)
        case "url":
            return handleURL(bundleID: bundleID)
        default:
            return errorResult("Unknown action type: \(type)")
        }
    }

    // MARK: - Action Handlers

    private func handleClick(arguments: [String: Any], pid: Int32, bundleID: String, appName: String) -> [String: Any] {
        if let elementID = arguments["element"] as? String {
            let elementDesc = describeElement(id: elementID, bundleID: bundleID)
            let detail = "Click \(elementDesc) in \(appName)"

            let confirmation = capabilities.requestConfirmation(action: "click", detail: detail, bundleID: bundleID)
            switch confirmation {
            case .allowed:
                let result = clickElement(elementID: elementID, bundleID: bundleID, detail: detail)
                let isError = (result["isError"] as? Bool) ?? false
                auditLogger.log(
                    operation: "act.click",
                    app: bundleID,
                    element: elementID,
                    elementRole: treeCache.describe(id: elementID, bundleID: bundleID)?.role,
                    elementName: treeCache.describe(id: elementID, bundleID: bundleID)?.name,
                    result: isError ? "error" : "success",
                    confirmation: "confirm"
                )
                return result
            case .denied(let reason):
                auditLogger.log(
                    operation: "act.click",
                    app: bundleID,
                    element: elementID,
                    result: "denied",
                    confirmation: "confirm"
                )
                return deniedResult(action: "click", reason: reason)
            }
        }

        if let posDict = arguments["position"] as? [String: Any],
           let x = posDict["x"] as? Double,
           let y = posDict["y"] as? Double
        {
            let detail = "Click at position (\(Int(x)), \(Int(y))) in \(appName)"

            let confirmation = capabilities.requestConfirmation(action: "click", detail: detail, bundleID: bundleID)
            switch confirmation {
            case .allowed:
                break
            case .denied(let reason):
                auditLogger.log(operation: "act.click", app: bundleID, params: ["x": "\(Int(x))", "y": "\(Int(y))"], result: "denied", confirmation: "confirm")
                return deniedResult(action: "click", reason: reason)
            }

            let windows = windowManager.windows(forPID: pid)
            guard let window = windows.first else {
                return errorResult("No visible window found")
            }

            let screenX = window.bounds.origin.x + CGFloat(x)
            let screenY = window.bounds.origin.y + CGFloat(y)

            guard x >= 0, y >= 0, CGFloat(x) <= window.bounds.width, CGFloat(y) <= window.bounds.height else {
                return errorResult("Coordinates outside window bounds")
            }

            let success = inputSynthesizer.click(at: CGPoint(x: screenX, y: screenY))
            auditLogger.log(operation: "act.click", app: bundleID, params: ["x": "\(Int(x))", "y": "\(Int(y))"], result: success ? "success" : "error", confirmation: "confirm")
            return success ? textResult("Clicked at (\(Int(x)), \(Int(y)))") : errorResult("Failed to click")
        }

        return errorResult("Click requires 'element' or 'position'")
    }

    private func clickElement(elementID: String, bundleID: String, detail: String) -> [String: Any] {
        guard let element = treeCache.resolve(id: elementID, bundleID: bundleID) else {
            return errorResult("Element \(elementID) not found. Run rescreen_perceive first.")
        }

        // Try AX actions first (most reliable for standard UI controls)
        var result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if result == .success {
            return textResult("Executed: \(detail)")
        }

        result = AXUIElementPerformAction(element, kAXConfirmAction as CFString)
        if result == .success {
            return textResult("Executed: \(detail)")
        }

        result = AXUIElementPerformAction(element, kAXPickAction as CFString)
        if result == .success {
            return textResult("Executed: \(detail)")
        }

        // Fallback: resolve element center and click by coordinate
        var posValue: AnyObject?
        var sizeValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
           AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let posVal = posValue, CFGetTypeID(posVal) == AXValueGetTypeID(),
           let sizeVal = sizeValue, CFGetTypeID(sizeVal) == AXValueGetTypeID()
        {
            var position = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
            let center = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)

            Log.debug("AX actions failed for \(elementID), falling back to coordinate click at \(center)")
            let clickSuccess = inputSynthesizer.click(at: center)
            if clickSuccess {
                return textResult("Executed: \(detail) (via coordinate fallback)")
            }
        }

        return errorResult("Failed to interact with \(elementID) (AX error: \(result.rawValue))")
    }

    private func handleType(arguments: [String: Any], pid: Int32, bundleID: String, appName: String) -> [String: Any] {
        guard let text = arguments["value"] as? String else {
            return errorResult("Type action requires 'value'")
        }

        guard text.count <= 10_000 else {
            return errorResult("Type value too long (\(text.count) chars, max 10000)")
        }

        let preview = text.count > 80 ? String(text.prefix(80)) + "..." : text
        let detail = "Type \"\(preview)\" in \(appName)"

        let confirmation = capabilities.requestConfirmation(action: "type", detail: detail, bundleID: bundleID)
        switch confirmation {
        case .allowed:
            let success = inputSynthesizer.typeText(text, for: pid)
            auditLogger.log(operation: "act.type", app: bundleID, params: ["length": "\(text.count)"], result: success ? "success" : "error", confirmation: "confirm")
            return success ? textResult("Executed: \(detail)") : errorResult("Failed to type")
        case .denied(let reason):
            auditLogger.log(operation: "act.type", app: bundleID, result: "denied", confirmation: "confirm")
            return deniedResult(action: "type", reason: reason)
        }
    }

    private func handlePress(arguments: [String: Any], pid: Int32, bundleID: String, appName: String) -> [String: Any] {
        guard let keys = arguments["keys"] as? String else {
            return errorResult("Press action requires 'keys'")
        }

        let detail = "Press \(keys) in \(appName)"

        let confirmation = capabilities.requestConfirmation(action: "press", detail: detail, bundleID: bundleID)
        switch confirmation {
        case .allowed:
            let success = inputSynthesizer.pressKeys(keys, for: pid)
            auditLogger.log(operation: "act.press", app: bundleID, params: ["keys": keys], result: success ? "success" : "error", confirmation: "confirm")
            return success ? textResult("Executed: \(detail)") : errorResult("Failed to press \(keys)")
        case .denied(let reason):
            auditLogger.log(operation: "act.press", app: bundleID, result: "denied", confirmation: "confirm")
            return deniedResult(action: "press", reason: reason)
        }
    }

    private func handleScroll(arguments: [String: Any], bundleID: String, appName: String) -> [String: Any] {
        let direction = arguments["direction"] as? String ?? "down"
        let amount = arguments["amount"] as? Int ?? 3
        let detail = "Scroll \(direction) by \(amount) in \(appName)"

        let confirmation = capabilities.requestConfirmation(action: "scroll", detail: detail, bundleID: bundleID)
        switch confirmation {
        case .allowed:
            let success = inputSynthesizer.scroll(direction: direction, amount: amount, at: .zero)
            auditLogger.log(operation: "act.scroll", app: bundleID, params: ["direction": direction, "amount": "\(amount)"], result: success ? "success" : "error", confirmation: "logged")
            return success ? textResult("Executed: \(detail)") : errorResult("Failed to scroll")
        case .denied(let reason):
            return deniedResult(action: "scroll", reason: reason)
        }
    }

    private func handleSelect(arguments: [String: Any], bundleID: String, appName: String) -> [String: Any] {
        guard let elementID = arguments["element"] as? String else {
            return errorResult("Select requires 'element'")
        }

        let elementDesc = describeElement(id: elementID, bundleID: bundleID)
        let detail = "Select \(elementDesc) in \(appName)"

        let confirmation = capabilities.requestConfirmation(action: "select", detail: detail, bundleID: bundleID)
        switch confirmation {
        case .allowed:
            let result = clickElement(elementID: elementID, bundleID: bundleID, detail: detail)
            let isError = (result["isError"] as? Bool) ?? false
            auditLogger.log(operation: "act.select", app: bundleID, element: elementID, result: isError ? "error" : "success", confirmation: "confirm")
            return result
        case .denied(let reason):
            auditLogger.log(operation: "act.select", app: bundleID, element: elementID, result: "denied", confirmation: "confirm")
            return deniedResult(action: "select", reason: reason)
        }
    }

    // MARK: - Double Click

    private func handleDoubleClick(arguments: [String: Any], pid: Int32, bundleID: String, appName: String) -> [String: Any] {
        guard let point = resolvePoint(arguments: arguments, pid: pid, bundleID: bundleID) else {
            return errorResult("double_click requires 'element' or 'position'")
        }

        let detail = "Double-click at (\(Int(point.screenPoint.x)), \(Int(point.screenPoint.y))) in \(appName)"
        let confirmation = capabilities.requestConfirmation(action: "double_click", detail: detail, bundleID: bundleID)
        switch confirmation {
        case .allowed:
            let success = inputSynthesizer.doubleClick(at: point.screenPoint)
            auditLogger.log(operation: "act.double_click", app: bundleID, element: point.elementID, result: success ? "success" : "error", confirmation: "confirm")
            return success ? textResult("Executed: \(detail)") : errorResult("Failed to double-click")
        case .denied(let reason):
            return deniedResult(action: "double_click", reason: reason)
        }
    }

    // MARK: - Right Click

    private func handleRightClick(arguments: [String: Any], pid: Int32, bundleID: String, appName: String) -> [String: Any] {
        guard let point = resolvePoint(arguments: arguments, pid: pid, bundleID: bundleID) else {
            return errorResult("right_click requires 'element' or 'position'")
        }

        let detail = "Right-click at (\(Int(point.screenPoint.x)), \(Int(point.screenPoint.y))) in \(appName)"
        let confirmation = capabilities.requestConfirmation(action: "right_click", detail: detail, bundleID: bundleID)
        switch confirmation {
        case .allowed:
            let success = inputSynthesizer.rightClick(at: point.screenPoint)
            auditLogger.log(operation: "act.right_click", app: bundleID, element: point.elementID, result: success ? "success" : "error", confirmation: "confirm")
            return success ? textResult("Executed: \(detail)") : errorResult("Failed to right-click")
        case .denied(let reason):
            return deniedResult(action: "right_click", reason: reason)
        }
    }

    // MARK: - Hover

    private func handleHover(arguments: [String: Any], pid: Int32, bundleID: String, appName: String) -> [String: Any] {
        guard let point = resolvePoint(arguments: arguments, pid: pid, bundleID: bundleID) else {
            return errorResult("hover requires 'element' or 'position'")
        }

        let detail = "Hover at (\(Int(point.screenPoint.x)), \(Int(point.screenPoint.y))) in \(appName)"
        // Hover is less destructive, use logged tier
        let success = inputSynthesizer.hover(at: point.screenPoint)
        auditLogger.log(operation: "act.hover", app: bundleID, element: point.elementID, result: success ? "success" : "error", confirmation: "logged")
        return success ? textResult("Executed: \(detail)") : errorResult("Failed to hover")
    }

    // MARK: - Drag

    private func handleDrag(arguments: [String: Any], pid: Int32, bundleID: String, appName: String) -> [String: Any] {
        guard let fromDict = arguments["from"] as? [String: Any],
              let toDict = arguments["to"] as? [String: Any],
              let fromX = fromDict["x"] as? Double, let fromY = fromDict["y"] as? Double,
              let toX = toDict["x"] as? Double, let toY = toDict["y"] as? Double
        else {
            return errorResult("drag requires 'from' {x,y} and 'to' {x,y} positions")
        }

        let windows = windowManager.windows(forPID: pid)
        guard let window = windows.first else {
            return errorResult("No visible window found")
        }

        let screenFrom = CGPoint(x: window.bounds.origin.x + fromX, y: window.bounds.origin.y + fromY)
        let screenTo = CGPoint(x: window.bounds.origin.x + toX, y: window.bounds.origin.y + toY)

        let detail = "Drag from (\(Int(fromX)),\(Int(fromY))) to (\(Int(toX)),\(Int(toY))) in \(appName)"
        let confirmation = capabilities.requestConfirmation(action: "drag", detail: detail, bundleID: bundleID)
        switch confirmation {
        case .allowed:
            let duration = arguments["duration"] as? Double ?? 0.3
            let success = inputSynthesizer.drag(from: screenFrom, to: screenTo, duration: duration)
            auditLogger.log(operation: "act.drag", app: bundleID, params: ["from": "\(Int(fromX)),\(Int(fromY))", "to": "\(Int(toX)),\(Int(toY))"], result: success ? "success" : "error", confirmation: "confirm")
            return success ? textResult("Executed: \(detail)") : errorResult("Failed to drag")
        case .denied(let reason):
            return deniedResult(action: "drag", reason: reason)
        }
    }

    // MARK: - App Management

    private func handleFocus(resolved: (app: NSRunningApplication, element: AXUIElement), bundleID: String, appName: String) -> [String: Any] {
        let detail = "Focus \(appName)"
        let confirmation = capabilities.requestConfirmation(action: "focus", detail: detail, bundleID: bundleID)
        switch confirmation {
        case .allowed:
            let success = resolved.app.activate()
            auditLogger.log(operation: "act.focus", app: bundleID, result: success ? "success" : "error", confirmation: "confirm")
            return success ? textResult("Focused \(appName)") : errorResult("Failed to focus \(appName)")
        case .denied(let reason):
            return deniedResult(action: "focus", reason: reason)
        }
    }

    private func handleLaunch(bundleID: String) -> [String: Any] {
        let detail = "Launch \(bundleID)"
        let confirmation = capabilities.requestConfirmation(action: "launch", detail: detail, bundleID: bundleID)
        switch confirmation {
        case .allowed:
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                return errorResult("Application \(bundleID) not found on this system")
            }
            let config = NSWorkspace.OpenConfiguration()
            let semaphore = DispatchSemaphore(value: 0)
            final class ErrorBox: @unchecked Sendable { var error: Error?; init() {} }
            let errorBox = ErrorBox()
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                errorBox.error = error
                semaphore.signal()
            }
            semaphore.wait()
            if let error = errorBox.error {
                auditLogger.log(operation: "act.launch", app: bundleID, result: "error", confirmation: "confirm")
                return errorResult("Failed to launch \(bundleID): \(error.localizedDescription)")
            }
            auditLogger.log(operation: "act.launch", app: bundleID, result: "success", confirmation: "confirm")
            return textResult("Launched \(bundleID)")
        case .denied(let reason):
            return deniedResult(action: "launch", reason: reason)
        }
    }

    private func handleClose(resolved: (app: NSRunningApplication, element: AXUIElement), bundleID: String, appName: String) -> [String: Any] {
        let detail = "Close \(appName)"
        let confirmation = capabilities.requestConfirmation(action: "close", detail: detail, bundleID: bundleID)
        switch confirmation {
        case .allowed:
            let success = resolved.app.terminate()
            auditLogger.log(operation: "act.close", app: bundleID, result: success ? "success" : "error", confirmation: "confirm")
            return success ? textResult("Closed \(appName)") : errorResult("Failed to close \(appName)")
        case .denied(let reason):
            return deniedResult(action: "close", reason: reason)
        }
    }

    // MARK: - Clipboard

    private func handleClipboardRead(bundleID: String) -> [String: Any] {
        guard let clipboard = clipboardManager else {
            return errorResult("Clipboard access not available")
        }
        return clipboard.read()
    }

    private func handleClipboardWrite(arguments: [String: Any], bundleID: String) -> [String: Any] {
        guard let clipboard = clipboardManager else {
            return errorResult("Clipboard access not available")
        }
        guard let text = arguments["value"] as? String else {
            return errorResult("clipboard_write requires 'value' parameter")
        }

        let detail = "Write \(text.count) chars to clipboard"
        let confirmation = capabilities.requestConfirmation(action: "clipboard_write", detail: detail, bundleID: bundleID)
        switch confirmation {
        case .allowed:
            return clipboard.write(text: text)
        case .denied(let reason):
            return deniedResult(action: "clipboard_write", reason: reason)
        }
    }

    // MARK: - URL Monitor

    private func handleURL(bundleID: String) -> [String: Any] {
        guard let monitor = urlMonitor else {
            return errorResult("URL monitoring not available")
        }
        guard monitor.isBrowser(bundleID) else {
            return errorResult("\(bundleID) is not a recognized browser")
        }
        if let url = monitor.currentURL(bundleID: bundleID) {
            auditLogger.log(operation: "act.url", app: bundleID, params: ["url": url], result: "success", confirmation: "logged")
            return textResult(url)
        }
        return textResult("Could not detect URL from \(bundleID)")
    }

    // MARK: - Point Resolution

    private struct ResolvedPoint {
        let screenPoint: CGPoint
        let elementID: String?
    }

    /// Resolve element ID or position to screen coordinates.
    private func resolvePoint(arguments: [String: Any], pid: Int32, bundleID: String) -> ResolvedPoint? {
        if let elementID = arguments["element"] as? String {
            if let element = treeCache.resolve(id: elementID, bundleID: bundleID) {
                var posValue: AnyObject?
                var sizeValue: AnyObject?
                if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
                   AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
                   let posVal = posValue, CFGetTypeID(posVal) == AXValueGetTypeID(),
                   let sizeVal = sizeValue, CFGetTypeID(sizeVal) == AXValueGetTypeID()
                {
                    var position = CGPoint.zero
                    var size = CGSize.zero
                    // CFGetTypeID check above guarantees these are AXValue instances
                    AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
                    AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
                    // Click center of element
                    let center = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
                    return ResolvedPoint(screenPoint: center, elementID: elementID)
                }
            }
            return nil
        }

        if let posDict = arguments["position"] as? [String: Any],
           let x = posDict["x"] as? Double,
           let y = posDict["y"] as? Double
        {
            let windows = windowManager.windows(forPID: pid)
            guard let window = windows.first else { return nil }
            // Validate coordinates are within window bounds
            guard x >= 0, y >= 0, CGFloat(x) <= window.bounds.width, CGFloat(y) <= window.bounds.height else {
                return nil
            }
            let screenX = window.bounds.origin.x + CGFloat(x)
            let screenY = window.bounds.origin.y + CGFloat(y)
            return ResolvedPoint(screenPoint: CGPoint(x: screenX, y: screenY), elementID: nil)
        }

        return nil
    }

    // MARK: - Element Description

    private func describeElement(id: String, bundleID: String) -> String {
        if let info = treeCache.describe(id: id, bundleID: bundleID) {
            if let name = info.name, !name.isEmpty {
                return "'\(name)' (\(info.role)) [\(id)]"
            }
            return "\(info.role) [\(id)]"
        }
        return "element \(id) (not in cache)"
    }

    // MARK: - Helpers

    private func textResult(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text] as [String: Any]]]
    }

    private func errorResult(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": "Error: \(message)"] as [String: Any]], "isError": true]
    }

    private func deniedResult(action: String, reason: String) -> [String: Any] {
        ["content": [["type": "text", "text": "Action denied: \(action) — \(reason)"] as [String: Any]], "isError": true]
    }
}
