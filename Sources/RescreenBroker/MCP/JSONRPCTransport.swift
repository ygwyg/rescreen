import Foundation

/// Reads JSON-RPC messages from stdin and writes responses to stdout.
/// Thread-safe: the write lock protects stdout when MCP I/O runs on a background thread.
final class JSONRPCTransport {
    typealias RequestHandler = (JSONRPCRequest) -> Data?

    private let handler: RequestHandler
    private let writeLock = NSLock()

    init(handler: @escaping RequestHandler) {
        self.handler = handler
    }

    /// Maximum allowed input line length (10 MB) to prevent memory exhaustion.
    private static let maxLineLength = 10 * 1024 * 1024

    func run() {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }

            // Reject excessively long lines
            guard line.count <= Self.maxLineLength else {
                Log.error("Input line too long (\(line.count) bytes), rejecting")
                let errorResponse = ResponseBuilder.error(
                    id: nil, code: -32600, message: "Request too large"
                )
                writeResponse(errorResponse)
                continue
            }

            guard let data = line.data(using: .utf8) else {
                Log.error("Failed to decode stdin line as UTF-8")
                continue
            }

            do {
                let request = try JSONRPCRequest.parse(from: data)

                // Validate JSON-RPC version
                guard request.jsonrpc == "2.0" else {
                    let errorResponse = ResponseBuilder.error(
                        id: request.id, code: -32600, message: "Unsupported JSON-RPC version"
                    )
                    writeResponse(errorResponse)
                    continue
                }

                if let responseData = handler(request) {
                    writeResponse(responseData)
                }
            } catch {
                let errorResponse = ResponseBuilder.error(
                    id: nil, code: -32700, message: "Parse error: \(error.localizedDescription)"
                )
                writeResponse(errorResponse)
            }
        }
    }

    private func writeResponse(_ data: Data) {
        writeLock.lock()
        defer { writeLock.unlock() }

        guard var output = String(data: data, encoding: .utf8) else { return }
        output += "\n"
        if let outputData = output.data(using: .utf8) {
            FileHandle.standardOutput.write(outputData)
        }
    }
}

// MARK: - Logging (always to stderr, thread-safe)

enum Log {
    private static let lock = NSLock()

    static func info(_ message: String) {
        write("[INFO] \(message)")
    }

    static func error(_ message: String) {
        write("[ERROR] \(message)")
    }

    static func debug(_ message: String) {
        write("[DEBUG] \(message)")
    }

    private static func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = "rescreen: \(message)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
