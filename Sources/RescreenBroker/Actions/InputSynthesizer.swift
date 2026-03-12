import CoreGraphics
import Foundation

/// Synthesizes keyboard and mouse input via CGEvent.
final class InputSynthesizer {

    // MARK: - Keyboard

    /// Press a key combination (e.g., "cmd+s", "return", "shift+tab").
    func pressKeys(_ combo: String, for pid: Int32) -> Bool {
        let parts = combo.lowercased().split(separator: "+").map(String.init)

        var flags: CGEventFlags = []
        var keyName = ""

        for part in parts {
            switch part {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "ctrl", "control": flags.insert(.maskControl)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            default: keyName = part
            }
        }

        guard let keyCode = virtualKeyCode(for: keyName) else {
            Log.error("Unknown key: \(keyName)")
            return false
        }

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else {
            return false
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.postToPid(pid)
        keyUp.postToPid(pid)

        return true
    }

    // MARK: - Mouse

    /// Click at a screen-absolute position.
    func click(at point: CGPoint) -> Bool {
        guard let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ),
        let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            return false
        }

        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)
        return true
    }

    // MARK: - Text Typing

    /// Type a string by sending key events for each character.
    func typeText(_ text: String, for pid: Int32) -> Bool {
        for char in text {
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            else {
                return false
            }

            var unichar = [UniChar]()
            for scalar in String(char).utf16 {
                unichar.append(scalar)
            }
            keyDown.keyboardSetUnicodeString(stringLength: unichar.count, unicodeString: &unichar)
            keyUp.keyboardSetUnicodeString(stringLength: unichar.count, unicodeString: &unichar)

            keyDown.postToPid(pid)
            keyUp.postToPid(pid)

            // Small delay between characters to avoid input buffer issues
            usleep(5000) // 5ms
        }
        return true
    }

    // MARK: - Double Click

    /// Double-click at a screen-absolute position.
    func doubleClick(at point: CGPoint) -> Bool {
        guard let mouseDown1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let mouseUp1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left),
              let mouseDown2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let mouseUp2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else { return false }

        mouseDown1.setIntegerValueField(.mouseEventClickState, value: 1)
        mouseUp1.setIntegerValueField(.mouseEventClickState, value: 1)
        mouseDown2.setIntegerValueField(.mouseEventClickState, value: 2)
        mouseUp2.setIntegerValueField(.mouseEventClickState, value: 2)

        mouseDown1.post(tap: .cghidEventTap)
        mouseUp1.post(tap: .cghidEventTap)
        mouseDown2.post(tap: .cghidEventTap)
        mouseUp2.post(tap: .cghidEventTap)
        return true
    }

    // MARK: - Right Click

    /// Right-click at a screen-absolute position.
    func rightClick(at point: CGPoint) -> Bool {
        guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right),
              let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right)
        else { return false }

        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)
        return true
    }

    // MARK: - Hover

    /// Move the mouse to a screen-absolute position without clicking.
    func hover(at point: CGPoint) -> Bool {
        guard let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        else { return false }

        moveEvent.post(tap: .cghidEventTap)
        return true
    }

    // MARK: - Drag

    /// Drag from one screen-absolute position to another.
    func drag(from start: CGPoint, to end: CGPoint, duration: Double = 0.3) -> Bool {
        guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)
        else { return false }

        mouseDown.post(tap: .cghidEventTap)

        // Interpolate drag path
        let steps = max(10, Int(duration * 60)) // ~60fps
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let x = start.x + (end.x - start.x) * t
            let y = start.y + (end.y - start.y) * t
            let point = CGPoint(x: x, y: y)

            guard let dragEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)
            else { return false }

            dragEvent.post(tap: .cghidEventTap)
            usleep(UInt32(duration / Double(steps) * 1_000_000))
        }

        guard let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)
        else { return false }

        mouseUp.post(tap: .cghidEventTap)
        return true
    }

    // MARK: - Scroll

    /// Scroll in a direction by a given amount (in "lines").
    func scroll(direction: String, amount: Int, at point: CGPoint) -> Bool {
        let dy: Int32
        let dx: Int32

        switch direction {
        case "up": dy = Int32(amount); dx = 0
        case "down": dy = -Int32(amount); dx = 0
        case "left": dy = 0; dx = Int32(amount)
        case "right": dy = 0; dx = -Int32(amount)
        default: return false
        }

        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: dy,
            wheel2: dx,
            wheel3: 0
        ) else {
            return false
        }

        event.post(tap: .cgSessionEventTap)
        return true
    }

    // MARK: - Virtual Key Code Map

    private func virtualKeyCode(for name: String) -> CGKeyCode? {
        return Self.keyCodeMap[name]
    }

    private static let keyCodeMap: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
        "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50, " ": 49, "space": 49,

        "return": 36, "enter": 36, "tab": 9, "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53,

        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,

        "up": 126, "down": 125, "left": 123, "right": 124,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,

        "forwarddelete": 117,
    ]
}
