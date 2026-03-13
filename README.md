# Rescreen

Let AI agents see and use the apps on your Mac.

Rescreen is a small program that sits between an AI agent and your desktop. The agent asks Rescreen to look at an app, click a button, or type some text, and Rescreen does it — but only for the apps you've said are OK.

It uses [MCP](https://modelcontextprotocol.io), so it works with Claude Code, Claude Desktop, Cursor, and anything else that speaks the protocol.

## What it does

You tell Rescreen which apps the agent can touch. Then the agent can:

- See what's on screen (the UI tree, screenshots, or both)
- Click, type, scroll, drag
- Read and write the clipboard
- Read and write files (if you allow a folder)

Everything else is off limits. Every action gets logged.

## Install

```bash
git clone https://github.com/ygwyg/rescreen.git
cd rescreen
make install PREFIX=~/.local
```

This puts the binary at `~/.local/bin/rescreen`. Make sure that's in your `PATH`.

You also need to grant accessibility permission to whatever terminal you run it from. Go to **System Settings > Privacy & Security > Accessibility** and add your terminal app.

Requires macOS 13+ and Swift 6.0+.

## Quick start

**1. Find the bundle ID of the app you want to give the agent access to:**

```
$ rescreen --list-apps
  Chrome            com.google.Chrome
  Slack             com.tinyspeck.slackmacgap
  Figma             com.figma.Desktop
  ...
```

**2. Add Rescreen to your MCP config.** For Claude Code, create `.mcp.json` in your project:

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

**3. Ask the agent to do something:**

> "What tabs do I have open in Chrome?"
> "Click on the search box and type 'hello world'"
> "Take a screenshot of Chrome"

That's it. The agent can now see and interact with Chrome. You approve each action in the chat — there's no separate dialog.

### Multiple apps

```json
{
  "mcpServers": {
    "rescreen": {
      "command": "rescreen",
      "args": ["--app", "com.google.Chrome", "--app", "com.figma.Desktop"]
    }
  }
}
```

### Filesystem access

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

## Other MCP clients

For Claude Desktop, add to `~/Library/Application Support/Claude/claude_desktop_config.json`. For Cursor, add via Settings > MCP Servers. The config format is the same.

Any MCP client that supports stdio transport will work. Rescreen reads JSON-RPC from stdin and writes responses to stdout.

## Tools

Rescreen exposes five MCP tools:

**`rescreen_perceive`** — Look at an app. Returns the UI tree (`accessibility`), a screenshot (`screenshot`), both (`composite`), or search results (`find`).

**`rescreen_act`** — Do something in an app. Supports `click`, `double_click`, `right_click`, `hover`, `drag`, `scroll`, `type`, `press`, `select`, `focus`, `launch`, `close`, `clipboard_read`, `clipboard_write`, and `url`.

**`rescreen_overview`** — List all visible windows and which apps they belong to.

**`rescreen_status`** — Show what permissions are active.

**`rescreen_filesystem`** — Read, write, list, delete, and search files within allowed paths.

## Profiles

If you use the same set of permissions often, save them as a YAML profile in `~/.rescreen/profiles/`:

```yaml
name: "Coding"
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

Then use it with `--profile coding`.

## Security

Rescreen is designed so the agent can only do what you've allowed:

- Actions require a matching capability grant. No grant, no action.
- If an unpermitted window overlaps the target app, Rescreen auto-focuses the target and logs a warning.
- File paths are canonicalized with symlink resolution to prevent traversal attacks.
- File picker clicks are validated against your allowed paths.
- Denied requests are padded to a minimum duration to prevent timing-based probing.
- Everything is logged to `~/.rescreen/logs/` as JSON lines.

## CLI reference

```
rescreen [options]

  --app <bundle-id>     Permit an app (repeatable)
  --profile <name>      Load a profile from ~/.rescreen/profiles/
  --fs-allow <path>     Allow filesystem access to a path (repeatable)
  --confirm             Enable native macOS confirmation dialogs
  --confirm-tty         Enable terminal-based confirmation
  --list-apps           List running apps with bundle IDs
  --version             Show version
  --help                Show help
```

## Testing

```bash
make test
```

## License

MIT — see [LICENSE](LICENSE).
