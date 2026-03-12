# Rescreen

An open protocol and runtime for permissioned AI agent interaction with desktop environments.

Rescreen provides a macOS broker daemon that mediates all agent-to-OS interaction through capability-based permissions, exposed over the [Model Context Protocol (MCP)](https://modelcontextprotocol.io). Agents can perceive UI state, perform actions, access the filesystem, and more — all within explicit permission boundaries.

## Why Rescreen?

AI agents that interact with desktop applications need a structured, secure interface. Without one, agents either get unrestricted access (dangerous) or no access at all (useless). Rescreen sits in between:

- **Permissioned** — Capability grants control exactly what an agent can see and do
- **Auditable** — Every operation is logged with session context
- **Confirmable** — Destructive actions can require user approval via native macOS dialogs
- **Standard** — Uses MCP, so any MCP-compatible client can connect

## Architecture

```
┌──────────────┐     MCP (stdio)     ┌──────────────────────┐     AX / CGEvent     ┌─────────────┐
│   AI Agent   │ ◄──────────────────► │   Rescreen Broker    │ ◄──────────────────► │   macOS UI  │
│  (MCP client)│     JSON-RPC 2.0    │                      │                      │             │
└──────────────┘                     │  ┌────────────────┐  │                      └─────────────┘
                                     │  │ Capability Store│  │
                                     │  │ Audit Logger    │  │
                                     │  │ Confirmation UI │  │
                                     │  └────────────────┘  │
                                     └──────────────────────┘
```

The broker runs as a local process. Agents communicate over stdin/stdout using JSON-RPC 2.0 (MCP transport). The broker translates MCP tool calls into macOS accessibility API calls, input synthesis, screenshots, and filesystem operations — all gated by the capability system.

## Requirements

- macOS 13+
- Swift 6.0+
- Accessibility permission granted to the terminal app running the broker

## Quick Start

```bash
# Build
swift build

# Run with a target app
.build/debug/RescreenBroker --app com.apple.finder

# Run with a permission profile
.build/debug/RescreenBroker --profile my-assistant

# Run with filesystem access
.build/debug/RescreenBroker --app com.apple.finder --fs-allow ~/Documents --fs-allow /tmp

# Use terminal-based confirmation instead of native dialogs
.build/debug/RescreenBroker --app com.apple.finder --tty
```

On first run, the broker creates `~/.rescreen/profiles/` with an example profile and `~/.rescreen/logs/` for audit logs.

### Granting Accessibility Permission

The broker requires macOS accessibility permission. To grant it:

1. Open **System Settings > Privacy & Security > Accessibility**
2. Add and enable the terminal app you're running the broker from (e.g., Terminal.app, iTerm2, or your IDE's terminal)
3. Re-run the broker

## MCP Tools

The broker exposes these tools to MCP clients:

### `rescreen_perceive`

Capture UI state from a target application.

| Parameter | Type | Description |
|-----------|------|-------------|
| `app` | string | **Required.** Bundle ID of the target app |
| `type` | string | `accessibility` (default), `screenshot`, `composite`, `find` |
| `max_depth` | int | Max tree depth (default 8, max 20) |
| `max_nodes` | int | Max nodes to capture (default 300, max 5000) |
| `query` | string | Search query for `find` type |
| `role` | string | Filter by role for `find` type |

**Perception types:**
- **`accessibility`** — Returns the accessibility tree as a flat list of normalized UI elements with ARIA-derived roles, bounds, states, and values
- **`screenshot`** — Returns a PNG screenshot of the app's windows as base64-encoded image content
- **`composite`** — Returns both screenshot and accessibility tree in a single call
- **`find`** — Searches the accessibility tree by text query and/or role filter

### `rescreen_act`

Perform actions on a target application.

| Parameter | Type | Description |
|-----------|------|-------------|
| `app` | string | **Required.** Bundle ID of the target app |
| `action` | string | **Required.** Action type (see below) |
| `element` | string | Element ID from a prior perceive call (e.g., `e42`) |
| `value` | string | Text for `type`, key combo for `press`, text for `clipboard_write` |
| `x`, `y` | number | Screen coordinates (alternative to element ID) |
| `from`, `to` | object | Start/end points for `drag` (`{x, y}`) |
| `duration` | number | Drag duration in seconds (default 0.3) |

**Action types:**

| Action | Domain | Description |
|--------|--------|-------------|
| `click` | `action.input.mouse` | Left click on element or coordinates |
| `double_click` | `action.input.mouse` | Double-click |
| `right_click` | `action.input.mouse` | Right-click (context menu) |
| `hover` | `action.input.mouse` | Move cursor to element/position |
| `drag` | `action.input.mouse` | Drag from one point to another |
| `scroll` | `action.input.mouse` | Scroll at element/position |
| `type` | `action.input.keyboard` | Type text string (max 10,000 chars) |
| `press` | `action.input.keyboard` | Press key combination (e.g., `cmd+s`) |
| `select` | `action.input.select` | Select an element |
| `focus` | `action.app.focus` | Bring app to foreground |
| `launch` | `action.app.launch` | Launch an application |
| `close` | `action.app.close` | Terminate an application |
| `clipboard_read` | `action.clipboard.read` | Read system clipboard |
| `clipboard_write` | `action.clipboard.write` | Write to system clipboard |
| `url` | `perception.accessibility` | Get current URL from browser |

### `rescreen_overview`

List all running applications with window information. No parameters required.

### `rescreen_status`

Get session information and active capability grants. No parameters required.

### `rescreen_filesystem`

Scoped filesystem operations (only available when `--fs-allow` paths are configured).

| Parameter | Type | Description |
|-----------|------|-------------|
| `operation` | string | **Required.** `read`, `write`, `list`, `delete`, `metadata`, `search` |
| `path` | string | **Required.** Target file/directory path |
| `content` | string | File content for `write` |
| `recursive` | bool | Recursive listing for `list` |
| `query` | string | Search term for `search` |

## Permission System

### Capability Grants

Every operation requires a matching capability grant. Grants are tuples of:

- **Domain** — What category of operation (e.g., `perception.accessibility`, `action.input.mouse`)
- **Target** — What app/resource it applies to (bundle ID, paths, URL filters)
- **Confirmation tier** — How the operation is gated:
  - `silent` — No prompt, logged only
  - `logged` — No prompt, logged and reviewable
  - `confirm` — Requires user confirmation via native dialog
  - `escalate` — Requires new capability grant
  - `block` — Hard denied, no override

### Default Grants (--app flag)

When using `--app`, the broker creates default grants:
- `perception.*` — Silent (no confirmation needed)
- `action.input.*` — Requires confirmation
- `action.app.*` — Requires confirmation
- `action.clipboard.*` — Requires confirmation

### Permission Profiles

For fine-grained control, create YAML profiles in `~/.rescreen/profiles/`:

```yaml
name: "My Assistant"
description: "Scoped access for coding workflow"
capabilities:
  - domain: perception.accessibility
    target: { app: "com.microsoft.VSCode" }
    confirmation: silent

  - domain: perception.screenshot
    target: { app: "com.microsoft.VSCode" }
    confirmation: silent

  - domain: action.input.*
    target: { app: "com.microsoft.VSCode" }
    confirmation: confirm

  - domain: filesystem.read
    target: { paths: ["~/Projects/**"] }
    confirmation: silent
```

## Security

### Confirmation Dialogs

Actions requiring confirmation present a native macOS dialog (NSPanel) showing the operation details. The agent cannot proceed without user approval. Use `--tty` for terminal-based confirmation in headless environments.

### Z-Order Occlusion Detection

Before executing visual actions (click, type, scroll, etc.), the broker checks whether unpermitted windows are overlapping the target app's windows. If detected, the action is blocked with an occlusion warning. This prevents attacks where a malicious window is placed over a permitted app to intercept agent actions.

### File Picker Interception

When a file picker dialog (Open/Save) is detected in a permitted app, the broker validates that the selected path is within the allowed filesystem scope before permitting the click on Open/Save buttons.

### Timing Side-Channel Mitigation

Denied requests are padded to a minimum 5ms response time to prevent agents from probing resource existence through response timing differences.

### Path Traversal Protection

All filesystem paths are canonicalized (tilde expansion, symlink resolution, `..` resolution) and validated against allowed path prefixes with directory boundary checking.

### Audit Logging

Every operation is logged to `~/.rescreen/logs/` as JSON lines with:
- Timestamp, session ID
- Operation type and target
- Capability used
- Result (allowed/denied)
- Confirmation tier applied

## Testing

```bash
swift test
```

The test suite covers:
- Path validation and traversal protection
- Capability grant matching and wildcard domains
- Grant lifecycle (expiration, revocation, one-shot)
- Confirmation tier enforcement
- Action-to-domain mapping
- Accessibility role normalization
- Node model serialization
- JSON-RPC request/response building
- Timing normalization

## Project Structure

```
Sources/RescreenBroker/
├── RescreenApp.swift              # Entry point, CLI argument parsing
├── Accessibility/
│   ├── AXNodeModel.swift          # Normalized UI element representation
│   ├── AXTreeCache.swift          # Thread-safe tree caching
│   ├── AXTreeCapture.swift        # Recursive AX tree walker
│   └── RoleMapping.swift          # AXRole → ARIA role normalization
├── Actions/
│   └── InputSynthesizer.swift     # CGEvent-based input synthesis
├── Audit/
│   └── AuditLogger.swift          # Structured JSON audit logging
├── Capability/
│   ├── ActionDomainMapping.swift   # Action type → domain mapping
│   ├── CapabilityGrant.swift       # Grant data structures
│   ├── CapabilityStore.swift       # Permission enforcement engine
│   └── SessionManager.swift        # Session lifecycle
├── Confirmation/
│   ├── ConfirmationHandler.swift   # Confirmation protocol
│   └── ConfirmationPanel.swift     # Native macOS NSPanel implementation
├── Filesystem/
│   ├── FilesystemHandler.swift     # Scoped filesystem operations
│   └── PathValidator.swift         # Path canonicalization and validation
├── MCP/
│   ├── JSONRPCTransport.swift      # Stdio JSON-RPC 2.0 transport
│   ├── MCPServer.swift             # MCP protocol handler
│   ├── MCPTypes.swift              # Request/response types
│   └── TimingNormalizer.swift      # Timing side-channel mitigation
├── Platform/
│   ├── AppResolver.swift           # Bundle ID → AXUIElement resolution
│   ├── ClipboardManager.swift      # System clipboard access
│   ├── FilePickerMonitor.swift     # Open/Save dialog interception
│   ├── ScreenCapture.swift         # CGWindowListCreateImage capture
│   ├── URLMonitor.swift            # Browser URL extraction
│   ├── WindowManager.swift         # Window enumeration
│   └── ZOrderMonitor.swift         # Occlusion detection
├── Profile/
│   └── ProfileLoader.swift         # YAML profile loading
└── Protocol/
    ├── ActHandler.swift             # Action tool handler
    ├── PerceiveHandler.swift        # Perception tool handler
    └── StatusHandler.swift          # Status tool handler
```

## License

MIT
