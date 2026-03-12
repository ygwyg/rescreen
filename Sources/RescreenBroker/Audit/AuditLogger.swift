import Foundation

/// A structured audit log entry.
struct AuditEntry: Codable {
    let timestamp: String
    let session: String
    let capabilityUsed: String?
    let operation: String
    let target: AuditTarget
    let params: [String: String]?
    let result: String
    let confirmation: String

    enum CodingKeys: String, CodingKey {
        case timestamp, session, operation, target, params, result, confirmation
        case capabilityUsed = "capability_used"
    }
}

struct AuditTarget: Codable {
    let app: String?
    let element: String?
    let elementRole: String?
    let elementName: String?

    enum CodingKeys: String, CodingKey {
        case app, element
        case elementRole = "element_role"
        case elementName = "element_name"
    }
}

/// Writes structured JSON audit logs to ~/.rescreen/logs/.
final class AuditLogger {
    private let sessionID: String
    private let logDir: String
    private let fileHandle: FileHandle?
    private let formatter: ISO8601DateFormatter
    private let writeLock = NSLock()

    init(sessionID: String) {
        self.sessionID = sessionID
        self.formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Create log directory
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.logDir = "\(home)/.rescreen/logs"

        do {
            try FileManager.default.createDirectory(
                atPath: logDir,
                withIntermediateDirectories: true
            )
        } catch {
            Log.error("Failed to create log directory: \(error)")
        }

        // Open log file for this session
        let dateStr = {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            return df.string(from: Date())
        }()
        let logPath = "\(logDir)/\(dateStr)_\(sessionID.prefix(8)).jsonl"

        FileManager.default.createFile(atPath: logPath, contents: nil)
        self.fileHandle = FileHandle(forWritingAtPath: logPath)
        fileHandle?.seekToEndOfFile()

        Log.info("Audit log: \(logPath)")
    }

    deinit {
        fileHandle?.closeFile()
    }

    /// Log an audit entry.
    func log(
        operation: String,
        app: String? = nil,
        element: String? = nil,
        elementRole: String? = nil,
        elementName: String? = nil,
        params: [String: String]? = nil,
        result: String,
        confirmation: String,
        capabilityID: String? = nil
    ) {
        let entry = AuditEntry(
            timestamp: formatter.string(from: Date()),
            session: sessionID,
            capabilityUsed: capabilityID,
            operation: operation,
            target: AuditTarget(
                app: app,
                element: element,
                elementRole: elementRole,
                elementName: elementName
            ),
            params: params,
            result: result,
            confirmation: confirmation
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(entry)
            if var line = String(data: data, encoding: .utf8) {
                line += "\n"
                if let lineData = line.data(using: .utf8) {
                    writeLock.lock()
                    fileHandle?.write(lineData)
                    writeLock.unlock()
                }
            }
        } catch {
            Log.error("Failed to write audit log: \(error)")
        }
    }
}
