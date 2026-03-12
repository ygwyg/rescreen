import Foundation

/// Handles scoped filesystem operations with path validation.
final class FilesystemHandler {
    private let pathValidator: PathValidator
    private let auditLogger: AuditLogger
    private let fm = FileManager.default

    init(pathValidator: PathValidator, auditLogger: AuditLogger) {
        self.pathValidator = pathValidator
        self.auditLogger = auditLogger
    }

    func handle(arguments: [String: Any]) -> [String: Any] {
        guard let operation = arguments["operation"] as? String else {
            return errorResult("Missing required parameter: operation")
        }
        guard let path = arguments["path"] as? String else {
            return errorResult("Missing required parameter: path")
        }

        guard let canonical = pathValidator.validate(path) else {
            return TimingNormalizer.withMinimumDuration {
                auditLogger.log(
                    operation: "filesystem.\(operation)",
                    params: ["path": path],
                    result: "denied_path",
                    confirmation: "block"
                )
                return errorResult("Path not allowed: \(path). Allowed: \(pathValidator.allowedPathsDescription)")
            }
        }

        switch operation {
        case "read":
            return handleRead(path: canonical)
        case "write":
            return handleWrite(path: canonical, arguments: arguments)
        case "list":
            return handleList(path: canonical, arguments: arguments)
        case "delete":
            return handleDelete(path: canonical)
        case "metadata":
            return handleMetadata(path: canonical)
        case "search":
            return handleSearch(path: canonical, arguments: arguments)
        default:
            return errorResult("Unknown filesystem operation: \(operation)")
        }
    }

    // MARK: - Read

    private func handleRead(path: String) -> [String: Any] {
        guard fm.fileExists(atPath: path) else {
            return errorResult("File not found: \(path)")
        }

        guard let data = fm.contents(atPath: path) else {
            return errorResult("Cannot read file: \(path)")
        }

        // Check if it's likely a text file (< 1MB and valid UTF-8)
        if data.count > 1_048_576 {
            return errorResult("File too large to read as text (\(data.count) bytes). Max 1MB.")
        }

        if let text = String(data: data, encoding: .utf8) {
            auditLogger.log(operation: "filesystem.read", params: ["path": path, "bytes": "\(data.count)"], result: "success", confirmation: "logged")
            return textResult(text)
        }

        // Binary file — return base64
        let b64 = data.base64EncodedString()
        auditLogger.log(operation: "filesystem.read", params: ["path": path, "bytes": "\(data.count)", "encoding": "base64"], result: "success", confirmation: "logged")
        return textResult("[binary file, \(data.count) bytes]\nbase64: \(b64)")
    }

    // MARK: - Write

    private func handleWrite(path: String, arguments: [String: Any]) -> [String: Any] {
        guard let content = arguments["content"] as? String else {
            return errorResult("Write requires 'content' parameter")
        }

        guard let data = content.data(using: .utf8) else {
            return errorResult("Cannot encode content as UTF-8")
        }

        // Max write size: 10 MB
        guard data.count <= 10 * 1024 * 1024 else {
            return errorResult("Content too large (\(data.count) bytes, max 10MB)")
        }

        // Create parent directories if needed
        let parentDir = (path as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: parentDir) {
            do {
                try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            } catch {
                return errorResult("Failed to create parent directory: \(error.localizedDescription)")
            }
        }

        let existed = fm.fileExists(atPath: path)
        if fm.createFile(atPath: path, contents: data) {
            auditLogger.log(operation: "filesystem.write", params: ["path": path, "bytes": "\(data.count)", "existed": "\(existed)"], result: "success", confirmation: "confirm")
            return textResult(existed ? "Updated \(path) (\(data.count) bytes)" : "Created \(path) (\(data.count) bytes)")
        }
        return errorResult("Failed to write file: \(path)")
    }

    // MARK: - List

    private func handleList(path: String, arguments: [String: Any]) -> [String: Any] {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return errorResult("Not a directory: \(path)")
        }

        let recursive = arguments["recursive"] as? Bool ?? false
        let maxEntries = arguments["max_entries"] as? Int ?? 200

        do {
            let items: [String]
            if recursive {
                guard let enumerator = fm.enumerator(atPath: path) else {
                    return errorResult("Cannot enumerate directory: \(path)")
                }
                var all: [String] = []
                while let item = enumerator.nextObject() as? String {
                    all.append(item)
                    if all.count >= maxEntries { break }
                }
                items = all
            } else {
                items = try fm.contentsOfDirectory(atPath: path)
            }

            var entries: [[String: Any]] = []
            for item in items.prefix(maxEntries) {
                let fullPath = (path as NSString).appendingPathComponent(item)
                var entryIsDir: ObjCBool = false
                fm.fileExists(atPath: fullPath, isDirectory: &entryIsDir)
                entries.append([
                    "name": item,
                    "type": entryIsDir.boolValue ? "directory" : "file",
                ])
            }

            guard let json = try? JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys]),
                  let jsonStr = String(data: json, encoding: .utf8) else {
                return errorResult("Failed to serialize directory listing")
            }

            auditLogger.log(operation: "filesystem.list", params: ["path": path, "entries": "\(entries.count)"], result: "success", confirmation: "logged")
            return textResult(jsonStr)
        } catch {
            return errorResult("Failed to list directory: \(error.localizedDescription)")
        }
    }

    // MARK: - Delete

    private func handleDelete(path: String) -> [String: Any] {
        guard fm.fileExists(atPath: path) else {
            return errorResult("File not found: \(path)")
        }

        do {
            try fm.removeItem(atPath: path)
            auditLogger.log(operation: "filesystem.delete", params: ["path": path], result: "success", confirmation: "confirm")
            return textResult("Deleted: \(path)")
        } catch {
            return errorResult("Failed to delete: \(error.localizedDescription)")
        }
    }

    // MARK: - Metadata

    private func handleMetadata(path: String) -> [String: Any] {
        guard fm.fileExists(atPath: path) else {
            return errorResult("File not found: \(path)")
        }

        do {
            let attrs = try fm.attributesOfItem(atPath: path)
            var meta: [String: Any] = [
                "path": path,
                "type": (attrs[.type] as? FileAttributeType) == .typeDirectory ? "directory" : "file",
            ]
            if let size = attrs[.size] as? Int { meta["size"] = size }
            if let modified = attrs[.modificationDate] as? Date {
                meta["modified"] = ISO8601DateFormatter().string(from: modified)
            }
            if let created = attrs[.creationDate] as? Date {
                meta["created"] = ISO8601DateFormatter().string(from: created)
            }
            if let perms = attrs[.posixPermissions] as? Int {
                meta["permissions"] = String(perms, radix: 8)
            }

            guard let json = try? JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys]),
                  let jsonStr = String(data: json, encoding: .utf8) else {
                return errorResult("Failed to serialize metadata")
            }

            auditLogger.log(operation: "filesystem.metadata", params: ["path": path], result: "success", confirmation: "logged")
            return textResult(jsonStr)
        } catch {
            return errorResult("Failed to get metadata: \(error.localizedDescription)")
        }
    }

    // MARK: - Search

    private func handleSearch(path: String, arguments: [String: Any]) -> [String: Any] {
        guard let pattern = arguments["pattern"] as? String else {
            return errorResult("Search requires 'pattern' parameter")
        }

        let maxResults = arguments["max_results"] as? Int ?? 50

        guard let enumerator = fm.enumerator(atPath: path) else {
            return errorResult("Cannot enumerate directory: \(path)")
        }

        var matches: [String] = []
        while let item = enumerator.nextObject() as? String {
            if item.localizedCaseInsensitiveContains(pattern) {
                matches.append(item)
                if matches.count >= maxResults { break }
            }
        }

        auditLogger.log(operation: "filesystem.search", params: ["path": path, "pattern": pattern, "matches": "\(matches.count)"], result: "success", confirmation: "logged")

        if matches.isEmpty {
            return textResult("No files matching '\(pattern)' found in \(path)")
        }

        guard let json = try? JSONSerialization.data(withJSONObject: matches, options: []),
              let jsonStr = String(data: json, encoding: .utf8) else {
            return errorResult("Failed to serialize search results")
        }

        return textResult(jsonStr)
    }

    // MARK: - Helpers

    private func textResult(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text] as [String: Any]]]
    }

    private func errorResult(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": "Error: \(message)"] as [String: Any]], "isError": true]
    }
}
