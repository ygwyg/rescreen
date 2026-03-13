import Foundation

/// Maps MCP action type strings to capability domain strings.
enum ActionDomainMapping {
    static func domain(for actionType: String) -> String {
        switch actionType {
        case "click":        return "action.input.mouse"
        case "double_click": return "action.input.mouse"
        case "right_click":  return "action.input.mouse"
        case "hover":        return "action.input.mouse"
        case "drag":         return "action.input.mouse"
        case "type":         return "action.input.keyboard"
        case "press":        return "action.input.keyboard"
        case "scroll":       return "action.input.mouse"
        case "navigate":     return "action.input.keyboard"
        case "select":       return "action.input.select"
        case "focus":        return "action.app.focus"
        case "launch":       return "action.app.launch"
        case "close":        return "action.app.close"
        case "clipboard_read":  return "action.clipboard.read"
        case "clipboard_write": return "action.clipboard.write"
        case "url":          return "perception.accessibility" // URL reading is a perception, not action
        default:             return "action.\(actionType)"
        }
    }

    static func perceptionDomain(for type: String) -> String {
        switch type {
        case "accessibility": return "perception.accessibility"
        case "screenshot":    return "perception.screenshot"
        case "composite":     return "perception.composite"
        case "overview":      return "perception.accessibility"
        case "find":          return "perception.accessibility"
        default:              return "perception.\(type)"
        }
    }

    static func filesystemDomain(for operation: String) -> String {
        switch operation {
        case "read", "list", "metadata", "search": return "filesystem.read"
        case "write", "delete":                     return "filesystem.write"
        default:                                     return "filesystem.\(operation)"
        }
    }
}
