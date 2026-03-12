import AppKit
import ApplicationServices
import Foundation

@main
struct RescreenApp {
    static func main() {
        // MARK: - Check accessibility permissions

        guard AXIsProcessTrusted() else {
            Log.error("""
                Accessibility permission not granted.

                To fix this:
                1. Open System Settings > Privacy & Security > Accessibility
                2. Add and enable the terminal app you're running this from
                3. Re-run this broker
                """)
            exit(1)
        }

        // MARK: - Parse CLI arguments

        var targetBundleIDs: [String] = []
        var profileName: String? = nil
        var useGUI = true // Use NSPanel confirmation by default
        var fsAllowPaths: [String] = []

        let args = CommandLine.arguments
        var i = 1
        while i < args.count {
            switch args[i] {
            case "--app":
                i += 1
                if i < args.count { targetBundleIDs.append(args[i]) }
            case "--profile":
                i += 1
                if i < args.count { profileName = args[i] }
            case "--fs-allow":
                i += 1
                if i < args.count { fsAllowPaths.append(args[i]) }
            case "--tty":
                useGUI = false
            case "--list-apps":
                listRunningApps()
                exit(0)
            case "--version":
                FileHandle.standardError.write("rescreen 0.4.0\n".data(using: .utf8)!)
                exit(0)
            case "--help":
                FileHandle.standardError.write("""
                    Rescreen Broker v0.4.0

                    Usage: RescreenBroker [options]

                    Options:
                      --app <bundle-id>     Add a permitted app (can be repeated)
                      --profile <name>      Load a permission profile from ~/.rescreen/profiles/
                      --fs-allow <path>     Allow filesystem access to path (can be repeated)
                      --tty                 Use terminal confirmation instead of native dialog
                      --list-apps           List running applications with their bundle IDs
                      --version             Show version
                      --help                Show this help

                    Examples:
                      RescreenBroker --app com.apple.finder
                      RescreenBroker --profile coding-assistant
                      RescreenBroker --app com.google.Chrome --fs-allow ~/Documents
                      RescreenBroker --app com.apple.finder --fs-allow /tmp --fs-allow ~/Desktop

                    """.data(using: .utf8)!)
                exit(0)
            default:
                Log.error("Unknown argument: \(args[i]). Use --help for usage.")
            }
            i += 1
        }

        // MARK: - Initialize core components

        let capabilityStore = CapabilityStore()
        let sessionID = UUID().uuidString
        let auditLogger = AuditLogger(sessionID: sessionID)
        let profileLoader = ProfileLoader()

        // Ensure profile directory exists
        profileLoader.ensureProfileDir()

        // Load profile if specified
        if let name = profileName {
            do {
                let (profile, grants) = try profileLoader.load(name: name)
                capabilityStore.addGrants(grants)
                Log.info("Loaded profile '\(profile.name)' with \(grants.count) grants")
            } catch {
                Log.error("Failed to load profile '\(name)': \(error)")
                Log.info("Available profiles: \(profileLoader.availableProfiles().joined(separator: ", "))")
                exit(1)
            }
        }

        // Add default grants for --app targets
        for bundleID in targetBundleIDs {
            let grants = CapabilityStore.defaultGrants(for: bundleID)
            capabilityStore.addGrants(grants)
        }

        // Require at least one --app or --profile
        if profileName == nil && targetBundleIDs.isEmpty {
            Log.error("No apps specified. Use --app <bundle-id> or --profile <name>. See --help for usage.")
            exit(1)
        }

        // MARK: - Set up confirmation handler

        let confirmationHandler: ConfirmationHandler
        if useGUI {
            confirmationHandler = NSPanelConfirmationHandler()
            Log.info("Using native macOS confirmation dialog")
        } else {
            confirmationHandler = TTYConfirmationHandler()
            Log.info("Using TTY confirmation (--tty mode)")
        }
        capabilityStore.confirmationHandler = confirmationHandler

        // MARK: - Initialize remaining components

        let appResolver = AppResolver()
        let treeCapture = AXTreeCapture()
        let windowManager = WindowManager()
        let treeCache = AXTreeCache()

        let sessionManager = SessionManager(sessionID: sessionID, capabilityStore: capabilityStore, auditLogger: auditLogger)

        let screenCapture = ScreenCapture()
        let clipboardManager = ClipboardManager(auditLogger: auditLogger)
        let urlMonitor = URLMonitor(appResolver: appResolver)

        let perceiveHandler = PerceiveHandler(
            capabilities: capabilityStore,
            appResolver: appResolver,
            treeCapture: treeCapture,
            windowManager: windowManager,
            treeCache: treeCache,
            screenCapture: screenCapture,
            auditLogger: auditLogger
        )

        let actHandler = ActHandler(
            capabilities: capabilityStore,
            appResolver: appResolver,
            treeCache: treeCache,
            auditLogger: auditLogger
        )
        actHandler.clipboardManager = clipboardManager
        actHandler.urlMonitor = urlMonitor

        // Z-order monitor for occlusion detection
        let zOrderMonitor = ZOrderMonitor(
            windowManager: windowManager,
            permittedBundleIDs: { capabilityStore.permittedBundleIDs }
        )
        perceiveHandler.zOrderMonitor = zOrderMonitor
        actHandler.zOrderMonitor = zOrderMonitor

        // File picker monitor (shares PathValidator with filesystem handler if configured)
        let filePickerPathValidator: PathValidator? = fsAllowPaths.isEmpty ? nil : PathValidator(allowedPaths: fsAllowPaths)
        actHandler.filePickerMonitor = FilePickerMonitor(pathValidator: filePickerPathValidator)

        let statusHandler = StatusHandler(
            sessionManager: sessionManager,
            capabilityStore: capabilityStore
        )

        let mcpServer = MCPServer(
            perceiveHandler: perceiveHandler,
            actHandler: actHandler,
            statusHandler: statusHandler
        )

        // Set up filesystem handler if paths are allowed
        if !fsAllowPaths.isEmpty {
            let pathValidator = PathValidator(allowedPaths: fsAllowPaths)
            let fsHandler = FilesystemHandler(pathValidator: pathValidator, auditLogger: auditLogger)
            mcpServer.filesystemHandler = fsHandler
            Log.info("Filesystem access allowed: \(fsAllowPaths.joined(separator: ", "))")
        }

        mcpServer.onShutdown = {
            sessionManager.endSession()
        }

        Log.info("Session: \(sessionID)")
        Log.info("Permitted apps: \(capabilityStore.permittedBundleIDs.sorted().joined(separator: ", "))")
        Log.info("Active grants: \(capabilityStore.activeGrants().count)")

        // MARK: - Run

        if useGUI {
            // GUI mode: main thread runs AppKit run loop, MCP I/O on background thread.
            // This is required for NSPanel confirmation dialogs to function.
            let mcpThread = Thread {
                mcpServer.run()
                DispatchQueue.main.async {
                    NSApplication.shared.terminate(nil)
                }
            }
            mcpThread.name = "Rescreen-MCP-IO"
            mcpThread.start()

            let app = NSApplication.shared
            app.setActivationPolicy(.accessory) // No dock icon
            app.run()
        } else {
            // TTY mode: synchronous stdin loop on main thread (M1 behavior).
            mcpServer.run()
        }
    }

    /// List all running GUI applications with their bundle IDs.
    private static func listRunningApps() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        let maxNameLen = apps.map { ($0.localizedName ?? "").count }.max() ?? 20

        FileHandle.standardError.write("Running applications:\n\n".data(using: .utf8)!)
        for app in apps {
            let name = app.localizedName ?? "Unknown"
            let bundleID = app.bundleIdentifier ?? "unknown"
            let padding = String(repeating: " ", count: max(1, maxNameLen - name.count + 2))
            FileHandle.standardError.write("  \(name)\(padding)\(bundleID)\n".data(using: .utf8)!)
        }
        FileHandle.standardError.write("\nUse --app <bundle-id> to permit an application.\n".data(using: .utf8)!)
    }
}
