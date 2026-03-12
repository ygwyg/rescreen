import Foundation
import Testing

@testable import RescreenBroker

@Suite("MCPTypes")
struct MCPTypesTests {
    // MARK: - RequestID

    @Test("RequestID encodes and decodes int")
    func requestIDInt() throws {
        let id = RequestID.int(42)
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(RequestID.self, from: data)
        #expect(decoded == .int(42))
    }

    @Test("RequestID encodes and decodes string")
    func requestIDString() throws {
        let id = RequestID.string("abc-123")
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(RequestID.self, from: data)
        #expect(decoded == .string("abc-123"))
    }

    // MARK: - JSONRPCRequest Parsing

    @Test("Parses valid JSON-RPC request with int ID")
    func parseValidRequestIntID() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}
        """
        let request = try JSONRPCRequest.parse(from: json.data(using: .utf8)!)
        #expect(request.jsonrpc == "2.0")
        #expect(request.id == .int(1))
        #expect(request.method == "tools/list")
    }

    @Test("Parses valid JSON-RPC request with string ID")
    func parseValidRequestStringID() throws {
        let json = """
        {"jsonrpc":"2.0","id":"req-abc","method":"initialize","params":{"protocolVersion":"2024-11-05"}}
        """
        let request = try JSONRPCRequest.parse(from: json.data(using: .utf8)!)
        #expect(request.id == .string("req-abc"))
        #expect(request.method == "initialize")
        let params = request.params
        #expect(params?["protocolVersion"] as? String == "2024-11-05")
    }

    @Test("Parses notification (no ID)")
    func parseNotification() throws {
        let json = """
        {"jsonrpc":"2.0","method":"notifications/initialized"}
        """
        let request = try JSONRPCRequest.parse(from: json.data(using: .utf8)!)
        #expect(request.id == nil)
        #expect(request.method == "notifications/initialized")
    }

    @Test("Parse failure throws on invalid JSON")
    func parseInvalidJSON() {
        let data = "not json at all".data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try JSONRPCRequest.parse(from: data)
        }
    }

    @Test("Parse handles missing method gracefully")
    func parseMissingMethod() throws {
        let json = """
        {"jsonrpc":"2.0","id":1}
        """
        let request = try JSONRPCRequest.parse(from: json.data(using: .utf8)!)
        #expect(request.method == "")
    }

    // MARK: - ResponseBuilder

    @Test("Success response includes result and JSON-RPC version")
    func successResponse() throws {
        let data = ResponseBuilder.success(
            id: .int(1),
            result: ["content": [["type": "text", "text": "hello"]]]
        )
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["jsonrpc"] as? String == "2.0")
        #expect(json?["id"] as? Int == 1)
        #expect(json?["result"] != nil)
    }

    @Test("Success response with string ID")
    func successResponseStringID() throws {
        let data = ResponseBuilder.success(id: .string("abc"), result: ["ok": true])
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["id"] as? String == "abc")
    }

    @Test("Error response includes error code and message")
    func errorResponse() throws {
        let data = ResponseBuilder.error(id: .int(1), code: -32601, message: "Method not found")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["jsonrpc"] as? String == "2.0")
        #expect(json?["id"] as? Int == 1)
        let error = json?["error"] as? [String: Any]
        #expect(error?["code"] as? Int == -32601)
        #expect(error?["message"] as? String == "Method not found")
    }

    @Test("Error response with nil ID uses null")
    func errorResponseNilID() throws {
        let data = ResponseBuilder.error(id: nil, code: -32700, message: "Parse error")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["id"] is NSNull)
    }

    // MARK: - MCPToolDefinition

    @Test("Tool definition serializes correctly")
    func toolDefinition() {
        let tool = MCPToolDefinition(
            name: "rescreen_perceive",
            description: "Capture UI state",
            inputSchema: [
                "type": "object",
                "properties": [
                    "app": ["type": "string"],
                ] as [String: Any],
            ]
        )
        let dict = tool.toDict()
        #expect(dict["name"] as? String == "rescreen_perceive")
        #expect(dict["description"] as? String == "Capture UI state")
        #expect(dict["inputSchema"] != nil)
    }
}
