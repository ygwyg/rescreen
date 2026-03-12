import Foundation

/// MCP server that handles the initialize/tools/list/tools/call lifecycle.
final class MCPServer {
    private let perceiveHandler: PerceiveHandler
    private let actHandler: ActHandler
    private let statusHandler: StatusHandler?
    var filesystemHandler: FilesystemHandler?
    var onShutdown: (() -> Void)?

    init(perceiveHandler: PerceiveHandler, actHandler: ActHandler, statusHandler: StatusHandler? = nil) {
        self.perceiveHandler = perceiveHandler
        self.actHandler = actHandler
        self.statusHandler = statusHandler
    }

    func run() {
        Log.info("Rescreen broker starting (MCP stdio transport)")

        let transport = JSONRPCTransport { [self] request in
            return self.handleRequest(request)
        }

        transport.run()
        Log.info("Rescreen broker shutting down (stdin closed)")
        onShutdown?()
    }

    private func handleRequest(_ request: JSONRPCRequest) -> Data? {
        Log.debug("Received method: \(request.method)")

        switch request.method {
        case "initialize":
            return handleInitialize(request)
        case "notifications/initialized":
            Log.info("Client initialized")
            return nil
        case "tools/list":
            return handleToolsList(request)
        case "tools/call":
            return handleToolsCall(request)
        case "ping":
            return ResponseBuilder.success(id: request.id, result: [:] as [String: Any])
        default:
            Log.debug("Unknown method: \(request.method)")
            guard request.id != nil else { return nil }
            return ResponseBuilder.error(
                id: request.id, code: -32601, message: "Method not found: \(request.method)"
            )
        }
    }

    // MARK: - initialize

    private func handleInitialize(_ request: JSONRPCRequest) -> Data {
        let result: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "tools": [:] as [String: Any],
            ] as [String: Any],
            "serverInfo": [
                "name": "rescreen-broker",
                "version": "0.4.0",
            ] as [String: Any],
        ]
        Log.info("Initialized with protocol version 2024-11-05")
        return ResponseBuilder.success(id: request.id, result: result)
    }

    // MARK: - tools/list

    private func handleToolsList(_ request: JSONRPCRequest) -> Data {
        var tools: [[String: Any]] = [
            perceiveTool.toDict(),
            actTool.toDict(),
            overviewTool.toDict(),
        ]
        if statusHandler != nil {
            tools.append(statusTool.toDict())
        }
        if filesystemHandler != nil {
            tools.append(filesystemTool.toDict())
        }
        return ResponseBuilder.success(id: request.id, result: ["tools": tools])
    }

    // MARK: - tools/call

    private func handleToolsCall(_ request: JSONRPCRequest) -> Data {
        guard let params = request.params,
              let toolName = params["name"] as? String,
              let arguments = params["arguments"] as? [String: Any]
        else {
            return ResponseBuilder.error(
                id: request.id, code: -32602, message: "Invalid params: expected name and arguments"
            )
        }

        Log.debug("Tool call: \(toolName)")

        let result: [String: Any]
        switch toolName {
        case "rescreen_perceive":
            result = perceiveHandler.handle(arguments: arguments)
        case "rescreen_act":
            result = actHandler.handle(arguments: arguments)
        case "rescreen_overview":
            result = perceiveHandler.handleOverview()
        case "rescreen_status":
            result = statusHandler?.handle() ?? [
                "content": [["type": "text", "text": "Status not available"] as [String: Any]],
                "isError": true,
            ]
        case "rescreen_filesystem":
            guard let handler = filesystemHandler else {
                return ResponseBuilder.error(id: request.id, code: -32602, message: "Filesystem access not configured. Use --fs-allow to permit paths.")
            }
            result = handler.handle(arguments: arguments)
        default:
            return ResponseBuilder.error(
                id: request.id, code: -32602, message: "Unknown tool: \(toolName)"
            )
        }

        return ResponseBuilder.success(id: request.id, result: result)
    }

    // MARK: - Tool Definitions

    private var perceiveTool: MCPToolDefinition {
        MCPToolDefinition(
            name: "rescreen_perceive",
            description: "Capture the accessibility tree or screenshot of a permitted application window. Returns structured UI elements with roles, names, values, and states.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "type": [
                        "type": "string",
                        "enum": ["accessibility", "screenshot", "composite", "find"],
                        "description": "Perception type. 'accessibility' returns structured UI tree (preferred). 'screenshot' returns a PNG image. 'composite' returns both. 'find' searches for elements by name/role.",
                    ] as [String: Any],
                    "target": [
                        "type": "string",
                        "description": "App bundle ID, e.g. 'com.microsoft.VSCode'. If omitted, uses the default permitted app.",
                    ] as [String: Any],
                    "max_depth": [
                        "type": "integer",
                        "description": "Maximum tree depth (default: 8)",
                    ] as [String: Any],
                    "max_nodes": [
                        "type": "integer",
                        "description": "Maximum nodes to return (default: 300)",
                    ] as [String: Any],
                    "query": [
                        "type": "string",
                        "description": "Search query for 'find' type — matches element names and values",
                    ] as [String: Any],
                    "role": [
                        "type": "string",
                        "description": "Filter by element role for 'find' type (e.g. 'button', 'textField')",
                    ] as [String: Any],
                ] as [String: Any],
                "required": ["type"],
            ] as [String: Any]
        )
    }

    private var actTool: MCPToolDefinition {
        MCPToolDefinition(
            name: "rescreen_act",
            description: "Perform an action on a permitted application. Supports click, double_click, right_click, hover, drag, type, press (keyboard shortcuts), scroll, focus, launch, close, clipboard_read, clipboard_write, and url. Prefer element-based targeting over coordinates.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "type": [
                        "type": "string",
                        "enum": ["click", "double_click", "right_click", "hover", "drag", "type", "press", "scroll", "select", "focus", "launch", "close", "clipboard_read", "clipboard_write", "url"],
                        "description": "Action type",
                    ] as [String: Any],
                    "target": [
                        "type": "string",
                        "description": "App bundle ID",
                    ] as [String: Any],
                    "element": [
                        "type": "string",
                        "description": "Element ID from the a11y tree (e.g. 'e14'). Preferred over coordinates.",
                    ] as [String: Any],
                    "value": [
                        "type": "string",
                        "description": "Text to type (for 'type' action) or clipboard content (for 'clipboard_write')",
                    ] as [String: Any],
                    "keys": [
                        "type": "string",
                        "description": "Key combo (for 'press'), e.g. 'cmd+s'",
                    ] as [String: Any],
                    "position": [
                        "type": "object",
                        "description": "Window-relative coordinates {x, y} (fallback for click/double_click/right_click/hover)",
                        "properties": [
                            "x": ["type": "number"] as [String: Any],
                            "y": ["type": "number"] as [String: Any],
                        ] as [String: Any],
                    ] as [String: Any],
                    "from": [
                        "type": "object",
                        "description": "Drag start position {x, y} (window-relative)",
                        "properties": [
                            "x": ["type": "number"] as [String: Any],
                            "y": ["type": "number"] as [String: Any],
                        ] as [String: Any],
                    ] as [String: Any],
                    "to": [
                        "type": "object",
                        "description": "Drag end position {x, y} (window-relative)",
                        "properties": [
                            "x": ["type": "number"] as [String: Any],
                            "y": ["type": "number"] as [String: Any],
                        ] as [String: Any],
                    ] as [String: Any],
                    "direction": [
                        "type": "string",
                        "enum": ["up", "down", "left", "right"],
                    ] as [String: Any],
                    "amount": [
                        "type": "integer",
                        "description": "Scroll lines (default: 3)",
                    ] as [String: Any],
                    "duration": [
                        "type": "number",
                        "description": "Drag duration in seconds (default: 0.3)",
                    ] as [String: Any],
                ] as [String: Any],
                "required": ["type"],
            ] as [String: Any]
        )
    }

    private var overviewTool: MCPToolDefinition {
        MCPToolDefinition(
            name: "rescreen_overview",
            description: "List all application windows the agent has permission to see.",
            inputSchema: [
                "type": "object",
                "properties": [:] as [String: Any],
            ] as [String: Any]
        )
    }

    private var statusTool: MCPToolDefinition {
        MCPToolDefinition(
            name: "rescreen_status",
            description: "Show current session info, active capability grants, and permitted applications.",
            inputSchema: [
                "type": "object",
                "properties": [:] as [String: Any],
            ] as [String: Any]
        )
    }

    private var filesystemTool: MCPToolDefinition {
        MCPToolDefinition(
            name: "rescreen_filesystem",
            description: "Perform scoped filesystem operations. Access is limited to paths allowed via --fs-allow. Supports read, write, list, delete, metadata, and search.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "operation": [
                        "type": "string",
                        "enum": ["read", "write", "list", "delete", "metadata", "search"],
                        "description": "Filesystem operation",
                    ] as [String: Any],
                    "path": [
                        "type": "string",
                        "description": "File or directory path",
                    ] as [String: Any],
                    "content": [
                        "type": "string",
                        "description": "Content to write (for 'write' operation)",
                    ] as [String: Any],
                    "pattern": [
                        "type": "string",
                        "description": "Search pattern (for 'search' operation)",
                    ] as [String: Any],
                    "recursive": [
                        "type": "boolean",
                        "description": "Recurse into subdirectories (for 'list')",
                    ] as [String: Any],
                    "max_entries": [
                        "type": "integer",
                        "description": "Max entries to return (default: 200)",
                    ] as [String: Any],
                    "max_results": [
                        "type": "integer",
                        "description": "Max search results (default: 50)",
                    ] as [String: Any],
                ] as [String: Any],
                "required": ["operation", "path"],
            ] as [String: Any]
        )
    }
}
