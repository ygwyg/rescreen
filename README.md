# Rescreen

An open protocol and runtime for permissioned AI agent interaction with desktop environments.

Rescreen provides a macOS broker daemon that mediates all agent-to-OS interaction through capability-based permissions, exposed over the [Model Context Protocol (MCP)](https://modelcontextprotocol.io). Agents can perceive UI state, take actions, capture screenshots, and more — all within explicit permission boundaries.

## Why Rescreen?

AI agents can read files and run code, but they can't see or interact with the apps on your screen. Rescreen bridges that gap:

- **Permissioned** — You decide which apps the agent can see and interact with
- **Auditable** — Every operation is logged
- **Standard** — Uses MCP, so any MCP-compatible client can connect (Claude, Cursor, etc.)
- **Secure** — Capability grants, z-order occlusion detection, path traversal protection, timing side-channel mitigation

## Architecture

```
┌──────────────┐     MCP (stdio)     ┌──────────────────────┐     AX / CGEvent     ┌─────────────┐
│   AI Agent   │ ◄──────────────────► │   Rescreen Broker    │ ◄──────────────────► │   macOS UI  │
│  (MCP client)│     JSON-RPC 2.0    │                      │                      │             │
└──────────────┘                     │  ┌────────────────┐  │                      └─────────────┘
                                     │  │ Capability Store│  │
                                     │  │ Audit Logger    │  │
                                     │  └────────────────┘  │
                                     └──────────────────────┘
```

The broker translates MCP tool calls into macOS accessibility API calls, input synthesis, screenshots, and filesystem operations — all gated by capability grants.

## Requirements

- macOS 13+
- Swift 6.0+
- Accessibility permission granted to the terminal app running the broker

## Install

```bash
git clone https://github.com/ygwyg/rescreen.git
cd rescreen
make install PREFIX=~/.local
```

This builds a release binary and installs it to `~/.local/bin/rescreen`. Make sure `~/.local/bin` is in your `PATH`.

To uninstall:

```bash
make uninstall PREFIX=~/.local
```

### Granting Accessibility Permission

1. Open **System Settings > Privacy & Security > Accessibility**
2. Add and enable the terminal app you're running the broker from (e.g., Terminal.app, iTerm2)
3. Re-run the broker

## Quick Start

The fastest way to try Rescreen is with Claude Code:

**1. Find the app you want to give the agent access to:**

```
$ rescreen --list-apps
  Chrome            com.google.Chrome
  Slack             com.tinyspeck.slackmacgap
  Finder            com.apple.finder
  ...
```

**2. Add Rescreen as an MCP server.** Create `.mcp.json` in your project (or `~/.mcp.json` globally):

```json
{
  "mcpServers": {
    "rescreen": {
      "command": "rescreen",
      "args": ["--app", "com.google.Chrome"]
    }
  }
}
```

**3. Ask Claude to interact with the app:**

> "What tabs do I have open in Chrome?"
> "Click on the Slack tab"
> "Take a screenshot of Chrome"
> "Find the search box and type 'hello world'"

The agent can now perceive and interact with Chrome. Claude Code's built-in tool approval handles confirmation — you approve each action in the chat, not via a separate dialog.

### Multiple Apps

```json
{
  "mcpServers": {
    "rescreen": {
      "command": "rescreen",
      "args": ["--app", "com.google.Chrome", "--app", "com.tinyspeck.slackmacgap"]
    }
  }
}
```

### With Filesystem Access

```json
{
  "mcpServers": {
    "rescreen": {
      "command": "rescreen",
      "args": ["--app", "com.google.Chrome", "--fs-allow", "/Users/you/Documents"]
    }
  }
}
```

### Using a Profile

```json
{
  "mcpServers": {
    "rescreen": {
      "command": "rescreen",
      "args": ["--profile", "coding"]
    }
  }
}
```

## Other MCP Clients

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "rescreen": {
      "command": "rescreen",
      "args": ["--app", "com.google.Chrome"]
    }
  }
}
```

### Cursor

Add via Settings > MCP Servers > Add:

```json
{
  "mcpServers": {
    "rescreen": {
      "command": "rescreen",
      "args": ["--app", "com.google.Chrome"]
    }
  }
}
```

### Any MCP Client

The broker reads JSON-RPC 2.0 from stdin and writes responses to stdout. All logging goes to stderr. Any MCP client that supports stdio transport can connect.

## CLI Reference

```
rescreen [options]

Options:
  --app <bundle-id>     Add a permitted app (can be repeated)
  --profile <name>      Load a permission profile from ~/.rescreen/profiles/
  --fs-allow <path>     Allow filesystem access to path (can be repeated)
  --confirm             Enable native macOS confirmation dialogs (NSPanel)
  --confirm-tty         Enable terminal-based confirmation
  --list-apps           List running applications with their bundle IDs
  --version             Show version
  --help                Show this help
```

By default, actions execute immediately within the granted scope. The MCP client (Claude Code, Cursor, etc.) handles user confirmation at the chat level. Use `--confirm` or `--confirm-tty` only if you want an additional broker-level confirmation step.

### Finding Bundle IDs

```
$ rescreen --list-apps
Running applications:

  Chrome            com.google.Chrome
  Finder            com.apple.finder
  Slack             com.tinyspeck.slackmacgap
  VS Code           com.microsoft.VSCode

Use --app <bundle-id> to permit an application.
```

Or for any `.app`:

```bash
mdls -name kMDItemCFBundleIdentifier /Applications/Safari.app
```

## MCP Tools

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

- **`accessibility`** — Structured UI tree with ARIA-derived roles, bounds, states, values
- **`screenshot`** — PNG screenshot as base64-encoded image content
- **`composite`** — Both screenshot and accessibility tree in one call
- **`find`** — Search the accessibility tree by text query and/or role

### `rescreen_act`

Perform actions on a target application.

| Parameter | Type | Description |
|-----------|------|-------------|
| `app` | string | **Required.** Bundle ID |
| `action` | string | **Required.** Action type |
| `element` | string | Element ID from perceive (e.g., `e42`) |
| `value` | string | Text for `type`, key combo for `press` |
| `x`, `y` | number | Screen coordinates (fallback) |
| `from`, `to` | object | Drag start/end `{x, y}` |

**Actions:** `click`, `double_click`, `right_click`, `hover`, `drag`, `scroll`, `type`, `press`, `select`, `focus`, `launch`, `close`, `clipboard_read`, `clipboard_write`, `url`

### `rescreen_overview`

List all running applications with window info.

### `rescreen_status`

Get session info and active capability grants.

### `rescreen_filesystem`

Scoped filesystem operations (requires `--fs-allow`).

| Parameter | Type | Description |
|-----------|------|-------------|
| `operation` | string | `read`, `write`, `list`, `delete`, `metadata`, `search` |
| `path` | string | Target path |
| `content` | string | Content for `write` |
| `recursive` | bool | Recursive `list` |
| `query` | string | Search term |

## Permission Profiles

Create YAML profiles in `~/.rescreen/profiles/` for reusable permission sets.

Example profiles are created on first run:

**`coding`** — IDE + browser for pair programming:

```yaml
name: "Coding Assistant"
description: "AI pair programmer with IDE, browser, and project filesystem access"
capabilities:
  - domain: perception.*
    target: { app: "com.microsoft.VSCode" }
    confirmation: silent
  - domain: action.input.*
    target: { app: "com.microsoft.VSCode" }
    confirmation: logged
  - domain: perception.*
    target: { app: "com.google.Chrome" }
    confirmation: silent
```

**`browser-research`** — Read-only browser access:

```yaml
name: "Browser Research"
description: "Read-only browser access for web research"
capabilities:
  - domain: perception.*
    target: { app: "com.google.Chrome" }
    confirmation: silent
  - domain: action.input.mouse
    target: { app: "com.google.Chrome" }
    confirmation: logged
```

## Security

- **Capability grants** — Every operation requires a matching grant. Grants specify domain, target app, and confirmation tier (`silent`, `logged`, `confirm`, `block`).
- **Z-order occlusion** — Visual actions are blocked if unpermitted windows overlap the target app, preventing spoofing attacks.
- **File picker interception** — Validates selected paths against allowed scope before permitting Open/Save clicks.
- **Timing normalization** — Denied requests are padded to 5ms minimum to prevent resource existence probing.
- **Path traversal protection** — All paths canonicalized with symlink resolution and boundary checking.
- **Audit logging** — Every operation logged to `~/.rescreen/logs/` as JSON lines.

## Testing

```bash
make test
```

101 tests covering path validation, capability grants, wildcard matching, role normalization, JSON-RPC, timing normalization, and more.

## License

MIT — see [LICENSE](LICENSE).
