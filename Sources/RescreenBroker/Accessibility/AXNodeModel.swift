import Foundation

/// A normalized UI element from the accessibility tree.
struct AXNode: Sendable {
    let id: String              // "e0", "e1", ... (stable within a single capture)
    let role: String            // Normalized Rescreen role (ARIA-derived)
    let name: String?           // AXTitle or AXDescription
    let value: String?          // AXValue (text content, checkbox state, etc.)
    let states: [String]        // ["focused", "selected", "disabled", etc.]
    let bounds: NodeRect?       // Window-relative position and size
    let childIDs: [String]      // IDs of child nodes (flat-list format)
}

/// Rectangle in window-relative coordinates (top-left origin).
struct NodeRect: Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

// MARK: - Serialization to flat list format

extension AXNode {
    /// Convert to a dictionary suitable for JSON serialization.
    func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "role": role,
        ]
        if let name = name, !name.isEmpty {
            dict["name"] = name
        }
        if let value = value, !value.isEmpty {
            // Truncate very long values (e.g., full file contents)
            if value.count > 500 {
                dict["value"] = String(value.prefix(500)) + "..."
                dict["value_truncated"] = true
            } else {
                dict["value"] = value
            }
        }
        if !states.isEmpty {
            dict["states"] = states
        }
        if let bounds = bounds {
            dict["bounds"] = [
                "x": Int(bounds.x),
                "y": Int(bounds.y),
                "w": Int(bounds.width),
                "h": Int(bounds.height),
            ]
        }
        if !childIDs.isEmpty {
            dict["children"] = childIDs
        }
        return dict
    }
}

// MARK: - Tree Serialization

enum TreeSerializer {
    /// Serialize a flat list of nodes to a JSON-compatible array.
    static func serialize(nodes: [AXNode]) -> [[String: Any]] {
        return nodes.map { $0.toDict() }
    }

    /// Serialize to a compact JSON string.
    static func toJSON(nodes: [AXNode]) -> String {
        let dicts = serialize(nodes: nodes)
        guard let data = try? JSONSerialization.data(withJSONObject: dicts, options: [.sortedKeys]) else {
            return "[]"
        }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
