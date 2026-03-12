import Foundation

// MARK: - JSON-RPC 2.0 Types

enum RequestID: Codable, Sendable, Equatable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            throw DecodingError.typeMismatch(
                RequestID.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected int or string")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        }
    }
}

struct JSONRPCRequest {
    let jsonrpc: String
    let id: RequestID?
    let method: String
    let params: [String: Any]?

    static func parse(from data: Data) throws -> JSONRPCRequest {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JSONRPCError.parseError
        }
        let jsonrpc = json["jsonrpc"] as? String ?? "2.0"
        let method = json["method"] as? String ?? ""
        let params = json["params"] as? [String: Any]

        var id: RequestID? = nil
        if let intID = json["id"] as? Int {
            id = .int(intID)
        } else if let strID = json["id"] as? String {
            id = .string(strID)
        }

        return JSONRPCRequest(jsonrpc: jsonrpc, id: id, method: method, params: params)
    }
}

enum JSONRPCError: Error {
    case parseError
    case methodNotFound
    case invalidParams
    case internalError(String)
}

// MARK: - Response Building

struct ResponseBuilder: Sendable {
    static func success(id: RequestID?, result: Any) -> Data {
        var response: [String: Any] = ["jsonrpc": "2.0"]
        if let id = id {
            switch id {
            case .int(let v): response["id"] = v
            case .string(let v): response["id"] = v
            }
        }
        response["result"] = result
        if let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]) {
            return data
        }
        // Fallback: return a serialization error instead of crashing
        Log.error("Failed to serialize success response")
        let fallback: [String: Any] = ["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32603, "message": "Internal: response serialization failed"] as [String: Any]]
        return (try? JSONSerialization.data(withJSONObject: fallback, options: [])) ?? Data()
    }

    static func error(id: RequestID?, code: Int, message: String) -> Data {
        var response: [String: Any] = ["jsonrpc": "2.0"]
        if let id = id {
            switch id {
            case .int(let v): response["id"] = v
            case .string(let v): response["id"] = v
            }
        } else {
            response["id"] = NSNull()
        }
        response["error"] = ["code": code, "message": message] as [String: Any]
        return (try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])) ?? Data()
    }
}

// MARK: - MCP Tool Definition

struct MCPToolDefinition {
    let name: String
    let description: String
    let inputSchema: [String: Any]

    func toDict() -> [String: Any] {
        return [
            "name": name,
            "description": description,
            "inputSchema": inputSchema,
        ]
    }
}
