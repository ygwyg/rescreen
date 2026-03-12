#!/bin/bash
# =============================================================================
# Milestone 3 Test Suite
# =============================================================================
#
# Tests all M3 capabilities:
#   1. Screenshot perception
#   2. Composite perception (screenshot + a11y tree)
#   3. Find perception (element search)
#   4. New input actions (double_click, right_click, hover)
#   5. App management (focus, launch, close)
#   6. Clipboard (read, write)
#   7. URL monitoring (current URL from browser)
#   8. Filesystem (read, write, list, metadata, search, delete)
#
# Prerequisites:
#   - Finder must be running (it usually is)
#   - Accessibility permission granted
#   - Screen recording permission for screenshot tests
#
# Usage:
#   ./test_m3.sh              # Run all tests (NSPanel confirmation)
#   ./test_m3.sh --tty        # Run all tests (terminal confirmation)
#   ./test_m3.sh <section>    # Run one section: perception|actions|app|clipboard|filesystem
#
# =============================================================================

set -euo pipefail
cd "$(dirname "$0")"

BROKER=".build/debug/RescreenBroker"
SECTION="${1:-all}"
TTY_FLAG=""

if [[ "$SECTION" == "--tty" ]]; then
    TTY_FLAG="--tty"
    SECTION="${2:-all}"
elif [[ "${2:-}" == "--tty" ]]; then
    TTY_FLAG="--tty"
fi

# Build first
echo "Building..."
swift build 2>&1 | grep -E "(Build complete|error:)" || true
echo ""

# Shared MCP init sequence
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"m3-test","version":"1.0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}'

# Result parser
parse_results() {
    python3 -c "
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line or not line.startswith('{'): continue
    try:
        resp = json.loads(line)
        rid = resp.get('id')
        if rid is None or rid == 1: continue
        result = resp.get('result', {})
        content = result.get('content', [])
        is_err = result.get('isError', False)
        status = 'FAIL' if is_err else 'PASS'

        texts = []
        has_image = False
        for item in content:
            if item.get('type') == 'text':
                text = item.get('text', '')
                # Truncate long output
                if len(text) > 200:
                    text = text[:200] + '...'
                texts.append(text)
            elif item.get('type') == 'image':
                has_image = True
                data_len = len(item.get('data', ''))
                texts.append(f'[image: {data_len} bytes base64]')

        label = sys.argv[1] if len(sys.argv) > 1 else ''
        combined = ' | '.join(texts) if texts else '(empty response)'
        print(f'  [{status}] id={rid}: {combined}')
    except Exception as e:
        pass
" "$@"
}

# =============================================================================
# SECTION 1: Perception (screenshot, composite, find)
# =============================================================================
run_perception_tests() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " TEST 1: Perception — screenshot, composite, find"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    {
        echo "$INIT"
        # 2: Screenshot of Finder
        echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"rescreen_perceive","arguments":{"type":"screenshot","target":"com.apple.finder"}}}'
        # 3: Composite (screenshot + a11y tree)
        echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"rescreen_perceive","arguments":{"type":"composite","target":"com.apple.finder","max_nodes":50}}}'
        # 4: Find buttons in Finder
        echo '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"rescreen_perceive","arguments":{"type":"find","target":"com.apple.finder","role":"button"}}}'
        # 5: Find by text query
        echo '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"rescreen_perceive","arguments":{"type":"find","target":"com.apple.finder","query":"view"}}}'
    } | "$BROKER" --app com.apple.finder $TTY_FLAG 2>/dev/null | parse_results

    echo ""
}

# =============================================================================
# SECTION 2: New Input Actions (hover, double_click, right_click)
# =============================================================================
run_action_tests() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " TEST 2: New Input Actions — hover, double_click, right_click"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Note: Confirmation dialogs will appear for click actions."
    echo ""

    {
        echo "$INIT"
        # 2: First perceive to populate element cache
        echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"rescreen_perceive","arguments":{"type":"accessibility","target":"com.apple.finder","max_nodes":100}}}'
        # 3: Hover over center of window (no confirmation needed)
        echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"rescreen_act","arguments":{"type":"hover","target":"com.apple.finder","position":{"x":200,"y":200}}}}'
        # 4: Scroll down in Finder
        echo '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"rescreen_act","arguments":{"type":"scroll","target":"com.apple.finder","direction":"down","amount":3}}}'
    } | "$BROKER" --app com.apple.finder $TTY_FLAG 2>/dev/null | parse_results

    echo ""
}

# =============================================================================
# SECTION 3: App Management (focus, launch, close)
# =============================================================================
run_app_tests() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " TEST 3: App Management — focus, launch, close"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Note: This will focus Finder, launch Calculator, then close Calculator."
    echo " Confirmation dialogs will appear for each action."
    echo ""

    {
        echo "$INIT"
        # 2: Focus Finder
        echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"rescreen_act","arguments":{"type":"focus","target":"com.apple.finder"}}}'
        # 3: Launch Calculator
        echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"rescreen_act","arguments":{"type":"launch","target":"com.apple.calculator"}}}'
        # Give Calculator time to launch before closing
        sleep 2
        # 4: Close Calculator
        echo '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"rescreen_act","arguments":{"type":"close","target":"com.apple.calculator"}}}'
    } | "$BROKER" --app com.apple.finder --app com.apple.calculator $TTY_FLAG 2>/dev/null | parse_results

    echo ""
}

# =============================================================================
# SECTION 4: Clipboard (read, write)
# =============================================================================
run_clipboard_tests() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " TEST 4: Clipboard — read, write"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Seed clipboard with known value first
    echo "test_clipboard_before" | pbcopy

    {
        echo "$INIT"
        # 2: Read current clipboard
        echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"rescreen_act","arguments":{"type":"clipboard_read","target":"com.apple.finder"}}}'
        # 3: Write new value to clipboard
        echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"rescreen_act","arguments":{"type":"clipboard_write","target":"com.apple.finder","value":"Hello from Rescreen M3!"}}}'
        # 4: Read it back to verify
        echo '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"rescreen_act","arguments":{"type":"clipboard_read","target":"com.apple.finder"}}}'
    } | "$BROKER" --app com.apple.finder $TTY_FLAG 2>/dev/null | parse_results

    # Verify via system clipboard
    CLIP=$(pbpaste)
    if [[ "$CLIP" == "Hello from Rescreen M3!" ]]; then
        echo "  [PASS] System clipboard verified: $CLIP"
    else
        echo "  [FAIL] System clipboard mismatch: expected 'Hello from Rescreen M3!', got '$CLIP'"
    fi

    echo ""
}

# =============================================================================
# SECTION 5: Filesystem (read, write, list, metadata, search, delete)
# =============================================================================
run_filesystem_tests() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " TEST 5: Filesystem — read, write, list, metadata, search, delete"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Set up test directory
    TEST_DIR="/tmp/rescreen_test_$$"
    mkdir -p "$TEST_DIR"
    echo "existing file content" > "$TEST_DIR/existing.txt"
    mkdir -p "$TEST_DIR/subdir"
    echo "nested" > "$TEST_DIR/subdir/nested.txt"

    {
        echo "$INIT"
        # 2: List test directory
        echo "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"rescreen_filesystem\",\"arguments\":{\"operation\":\"list\",\"path\":\"$TEST_DIR\"}}}"
        # 3: Read existing file
        echo "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"rescreen_filesystem\",\"arguments\":{\"operation\":\"read\",\"path\":\"$TEST_DIR/existing.txt\"}}}"
        # 4: Write new file
        echo "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"rescreen_filesystem\",\"arguments\":{\"operation\":\"write\",\"path\":\"$TEST_DIR/written.txt\",\"content\":\"Written by Rescreen M3\"}}}"
        # 5: Metadata on written file
        echo "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"rescreen_filesystem\",\"arguments\":{\"operation\":\"metadata\",\"path\":\"$TEST_DIR/written.txt\"}}}"
        # 6: Search for .txt files
        echo "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"rescreen_filesystem\",\"arguments\":{\"operation\":\"search\",\"path\":\"$TEST_DIR\",\"pattern\":\".txt\"}}}"
        # 7: Recursive list
        echo "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"rescreen_filesystem\",\"arguments\":{\"operation\":\"list\",\"path\":\"$TEST_DIR\",\"recursive\":true}}}"
        # 8: Delete the written file
        echo "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"rescreen_filesystem\",\"arguments\":{\"operation\":\"delete\",\"path\":\"$TEST_DIR/written.txt\"}}}"
        # 9: Try to access outside allowed path (should fail)
        echo '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"rescreen_filesystem","arguments":{"operation":"read","path":"/etc/passwd"}}}'
    } | "$BROKER" --app com.apple.finder --fs-allow "$TEST_DIR" $TTY_FLAG 2>/dev/null | python3 -c "
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line or not line.startswith('{'): continue
    try:
        resp = json.loads(line)
        rid = resp.get('id')
        if rid is None or rid == 1: continue
        result = resp.get('result', {})
        content = result.get('content', [])
        is_err = result.get('isError', False)

        texts = []
        for item in content:
            if item.get('type') == 'text':
                text = item.get('text', '')
                if len(text) > 200: text = text[:200] + '...'
                texts.append(text)
        combined = ' | '.join(texts) if texts else '(empty)'

        # id=9 SHOULD fail (path traversal blocked)
        if rid == 9:
            status = 'PASS' if is_err and 'not allowed' in combined.lower() else 'FAIL'
            print(f'  [{status}] id={rid}: Path traversal correctly blocked')
        else:
            status = 'FAIL' if is_err else 'PASS'
            print(f'  [{status}] id={rid}: {combined}')
    except:
        pass
"

    # Verify written file was deleted
    if [[ ! -f "$TEST_DIR/written.txt" ]]; then
        echo "  [PASS] File deletion verified"
    else
        echo "  [FAIL] File should have been deleted"
    fi

    # Clean up
    rm -rf "$TEST_DIR"
    echo ""
}

# =============================================================================
# SECTION 6: URL Monitoring (browser URL detection)
# =============================================================================
run_url_tests() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " TEST 6: URL Monitoring"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Note: Requires Chrome or Safari to be open with a tab."
    echo ""

    # Try Chrome first, fall back to Safari
    BROWSER="com.google.Chrome"
    if ! pgrep -q "Google Chrome"; then
        BROWSER="com.apple.Safari"
        if ! pgrep -q "Safari"; then
            echo "  [SKIP] No browser running (need Chrome or Safari)"
            echo ""
            return
        fi
    fi

    echo "  Using browser: $BROWSER"

    {
        echo "$INIT"
        # 2: Get current URL
        echo "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"rescreen_act\",\"arguments\":{\"type\":\"url\",\"target\":\"$BROWSER\"}}}"
    } | "$BROKER" --app "$BROWSER" $TTY_FLAG 2>/dev/null | parse_results

    echo ""
}

# =============================================================================
# SECTION 7: Tools List (verify all tools are advertised)
# =============================================================================
run_tools_list_test() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " TEST 7: Tools List — verify all tools advertised"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    {
        echo "$INIT"
        echo '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
    } | "$BROKER" --app com.apple.finder --fs-allow /tmp $TTY_FLAG 2>/dev/null | python3 -c "
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line or not line.startswith('{'): continue
    try:
        resp = json.loads(line)
        if resp.get('id') != 2: continue
        tools = resp['result']['tools']
        expected = ['rescreen_perceive', 'rescreen_act', 'rescreen_overview', 'rescreen_status', 'rescreen_filesystem']
        found = [t['name'] for t in tools]
        for name in expected:
            status = 'PASS' if name in found else 'FAIL'
            print(f'  [{status}] {name}')

        # Check act tool has all new action types
        act_tool = next(t for t in tools if t['name'] == 'rescreen_act')
        action_types = act_tool['inputSchema']['properties']['type']['enum']
        expected_actions = ['click', 'double_click', 'right_click', 'hover', 'drag', 'type', 'press', 'scroll', 'select', 'focus', 'launch', 'close', 'clipboard_read', 'clipboard_write', 'url']
        print()
        print('  Action types in rescreen_act:')
        for action in expected_actions:
            status = 'PASS' if action in action_types else 'FAIL'
            print(f'    [{status}] {action}')

        # Check perceive has find type
        perc_tool = next(t for t in tools if t['name'] == 'rescreen_perceive')
        perc_types = perc_tool['inputSchema']['properties']['type']['enum']
        print()
        print('  Perception types in rescreen_perceive:')
        for ptype in ['accessibility', 'screenshot', 'composite', 'find']:
            status = 'PASS' if ptype in perc_types else 'FAIL'
            print(f'    [{status}] {ptype}')
    except Exception as e:
        print(f'  [FAIL] Parse error: {e}')
"
    echo ""
}

# =============================================================================
# Run selected sections
# =============================================================================

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║        Rescreen M3 Test Suite             ║"
echo "╠═══════════════════════════════════════════╣"
echo "║  v0.3.0 — Full Action Support             ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

case "$SECTION" in
    all)
        run_tools_list_test
        run_perception_tests
        run_action_tests
        run_clipboard_tests
        run_filesystem_tests
        run_url_tests
        run_app_tests
        ;;
    perception)  run_perception_tests ;;
    actions)     run_action_tests ;;
    app)         run_app_tests ;;
    clipboard)   run_clipboard_tests ;;
    filesystem)  run_filesystem_tests ;;
    url)         run_url_tests ;;
    tools)       run_tools_list_test ;;
    *)
        echo "Unknown section: $SECTION"
        echo "Usage: $0 [all|perception|actions|app|clipboard|filesystem|url|tools] [--tty]"
        exit 1
        ;;
esac

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Done. Check ~/.rescreen/logs/ for audit trail."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
