import AppKit
import Foundation
import ObjectiveC

/// Native macOS confirmation dialog using NSPanel.
/// Runs in a protected layer that the agent's input synthesis cannot reach.
///
/// Security properties:
/// - .nonactivatingPanel: agent's CGEvent input targets the previous active app, not this panel
/// - .screenSaver level: renders above all other windows
/// - The broker's own PID is never a permitted action target
/// Thread-safe box for passing a value between threads.
private final class ResponseBox: @unchecked Sendable {
    var value: ConfirmationResponse = .denied
}

final class NSPanelConfirmationHandler: ConfirmationHandler {
    /// Show a confirmation dialog. Blocks the calling thread until the user responds.
    /// MUST be called from a non-main thread (the MCP I/O thread).
    func requestConfirmation(_ request: ConfirmationRequest) -> ConfirmationResponse {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResponseBox()

        DispatchQueue.main.async {
            box.value = Self.showPanel(request)
            semaphore.signal()
        }

        semaphore.wait()
        return box.value
    }

    // MARK: - Panel Construction

    @MainActor
    private static func showPanel(_ request: ConfirmationRequest) -> ConfirmationResponse {
        let panelWidth: CGFloat = 440
        let panelHeight: CGFloat = 240

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "Rescreen"
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))

        // Shield icon
        let iconLabel = NSTextField(labelWithString: "🛡")
        iconLabel.font = .systemFont(ofSize: 32)
        iconLabel.frame = NSRect(x: 20, y: panelHeight - 60, width: 50, height: 40)
        iconLabel.isBezeled = false
        iconLabel.drawsBackground = false
        iconLabel.isEditable = false
        iconLabel.isSelectable = false
        contentView.addSubview(iconLabel)

        // Title
        let titleLabel = NSTextField(labelWithString: "Confirmation Required")
        titleLabel.font = .boldSystemFont(ofSize: 16)
        titleLabel.frame = NSRect(x: 70, y: panelHeight - 55, width: 340, height: 24)
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        contentView.addSubview(titleLabel)

        // Action
        let actionLabel = NSTextField(labelWithString: "Action: \(request.action)")
        actionLabel.font = .systemFont(ofSize: 13, weight: .medium)
        actionLabel.frame = NSRect(x: 20, y: panelHeight - 90, width: panelWidth - 40, height: 20)
        actionLabel.isBezeled = false
        actionLabel.drawsBackground = false
        actionLabel.isEditable = false
        actionLabel.isSelectable = false
        contentView.addSubview(actionLabel)

        // Detail
        let detailLabel = NSTextField(wrappingLabelWithString: request.detail)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.frame = NSRect(x: 20, y: panelHeight - 160, width: panelWidth - 40, height: 60)
        detailLabel.isEditable = false
        detailLabel.isSelectable = false
        contentView.addSubview(detailLabel)

        // Deny button — delegate must be retained for the lifetime of the modal session
        let delegate = PanelDelegate()
        objc_setAssociatedObject(panel, "panelDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        let denyButton = NSButton(title: "Deny", target: delegate, action: #selector(PanelDelegate.deny(_:)))
        denyButton.frame = NSRect(x: panelWidth - 220, y: 16, width: 96, height: 32)
        denyButton.bezelStyle = .rounded
        denyButton.keyEquivalent = "\u{1b}"
        contentView.addSubview(denyButton)

        // Allow button
        let allowButton = NSButton(title: "Allow", target: delegate, action: #selector(PanelDelegate.allow(_:)))
        allowButton.frame = NSRect(x: panelWidth - 112, y: 16, width: 96, height: 32)
        allowButton.bezelStyle = .rounded
        allowButton.keyEquivalent = "\r"
        contentView.addSubview(allowButton)

        // Capability ID
        if let capID = request.capabilityID {
            let capLabel = NSTextField(labelWithString: "Grant: \(capID)")
            capLabel.font = .systemFont(ofSize: 10)
            capLabel.textColor = .tertiaryLabelColor
            capLabel.frame = NSRect(x: 20, y: 20, width: 200, height: 14)
            capLabel.isBezeled = false
            capLabel.drawsBackground = false
            capLabel.isEditable = false
            capLabel.isSelectable = false
            contentView.addSubview(capLabel)
        }

        panel.contentView = contentView
        panel.center()

        NSSound.beep()

        let modalResult = NSApplication.shared.runModal(for: panel)
        panel.orderOut(nil)

        return modalResult == .OK ? .allowed : .denied
    }
}

// MARK: - Panel Delegate

@MainActor
private class PanelDelegate: NSObject {
    @objc func allow(_ sender: Any?) {
        NSApplication.shared.stopModal(withCode: .OK)
    }

    @objc func deny(_ sender: Any?) {
        NSApplication.shared.stopModal(withCode: .cancel)
    }
}
