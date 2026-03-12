import ApplicationServices
import Foundation

/// Captures and normalizes the macOS accessibility tree for a given application.
final class AXTreeCapture {
    struct CaptureOptions {
        var maxDepth: Int = 8
        var maxNodes: Int = 300
    }

    /// Result of a tree capture — includes both serializable nodes and raw AXUIElement refs.
    struct CaptureResult {
        let nodes: [AXNode]
        let elementRefs: [(id: String, element: AXUIElement)]
    }

    /// Capture the accessibility tree for an app.
    func capture(appElement: AXUIElement, windowOrigin: CGPoint?, options: CaptureOptions = CaptureOptions()) -> CaptureResult {
        var nodes: [AXNode] = []
        var elementRefs: [(id: String, element: AXUIElement)] = []
        var counter = 0
        let origin = windowOrigin ?? .zero

        walkElement(appElement, depth: 0, options: options, nodes: &nodes, elementRefs: &elementRefs, counter: &counter, windowOrigin: origin)

        return CaptureResult(nodes: nodes, elementRefs: elementRefs)
    }

    // MARK: - Recursive Tree Walker

    private func walkElement(
        _ element: AXUIElement,
        depth: Int,
        options: CaptureOptions,
        nodes: inout [AXNode],
        elementRefs: inout [(id: String, element: AXUIElement)],
        counter: inout Int,
        windowOrigin: CGPoint
    ) {
        guard depth < options.maxDepth, counter < options.maxNodes else { return }

        let nodeID = "e\(counter)"
        counter += 1

        // Store the raw reference for later action targeting
        elementRefs.append((id: nodeID, element: element))

        // Get role and subrole
        let axRole = getStringAttribute(element, kAXRoleAttribute as CFString) ?? "AXUnknown"
        let axSubrole = getStringAttribute(element, kAXSubroleAttribute as CFString)
        let role = RoleMapping.normalize(axRole: axRole, axSubrole: axSubrole)

        // Get name (prefer AXTitle, fall back to AXDescription)
        let name = getStringAttribute(element, kAXTitleAttribute as CFString)
            ?? getStringAttribute(element, kAXDescriptionAttribute as CFString)

        // Get value
        let value = getStringValue(element)

        // Get states
        let states = getStates(element)

        // Get bounds (window-relative)
        let bounds = getBounds(element, windowOrigin: windowOrigin)

        // Get children
        let children = getChildren(element)
        var childIDs: [String] = []

        // Create the node (childIDs will be computed after recursion)
        let nodeIndex = nodes.count
        nodes.append(AXNode(
            id: nodeID,
            role: role,
            name: name,
            value: value,
            states: states,
            bounds: bounds,
            childIDs: [] // Placeholder, updated below
        ))

        // Recurse into children
        for child in children {
            guard counter < options.maxNodes else { break }
            let childID = "e\(counter)"
            childIDs.append(childID)
            walkElement(child, depth: depth + 1, options: options, nodes: &nodes, elementRefs: &elementRefs, counter: &counter, windowOrigin: windowOrigin)
        }

        // Update the node with actual child IDs
        nodes[nodeIndex] = AXNode(
            id: nodeID,
            role: role,
            name: name,
            value: value,
            states: states,
            bounds: bounds,
            childIDs: childIDs
        )
    }

    // MARK: - AXUIElement Attribute Helpers

    private func getStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func getStringValue(_ element: AXUIElement) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard result == .success else { return nil }

        if let str = value as? String {
            return str
        }
        if let num = value as? NSNumber {
            return num.stringValue
        }
        return nil
    }

    private func getStates(_ element: AXUIElement) -> [String] {
        var states: [String] = []

        if getBoolAttribute(element, kAXFocusedAttribute as CFString) == true {
            states.append("focused")
        }
        if getBoolAttribute(element, kAXSelectedAttribute as CFString) == true {
            states.append("selected")
        }
        if getBoolAttribute(element, kAXEnabledAttribute as CFString) == false {
            states.append("disabled")
        }
        if getBoolAttribute(element, kAXExpandedAttribute as CFString) == true {
            states.append("expanded")
        }

        return states
    }

    private func getBoolAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private func getBounds(_ element: AXUIElement, windowOrigin: CGPoint) -> NodeRect? {
        var posValue: AnyObject?
        var sizeValue: AnyObject?

        let posResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue)
        let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)

        guard posResult == .success, sizeResult == .success,
              let posVal = posValue, let sizeVal = sizeValue,
              CFGetTypeID(posVal) == AXValueGetTypeID(),
              CFGetTypeID(sizeVal) == AXValueGetTypeID()
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        // CFGetTypeID check above guarantees these are AXValue instances
        AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)

        // Convert to window-relative coordinates
        return NodeRect(
            x: Double(position.x - windowOrigin.x),
            y: Double(position.y - windowOrigin.y),
            width: Double(size.width),
            height: Double(size.height)
        )
    }

    private func getChildren(_ element: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard result == .success, let children = value as? [AXUIElement] else {
            return []
        }
        return children
    }
}
