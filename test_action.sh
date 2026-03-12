#!/bin/bash
# Interactive test: switch Finder to column view
# Step 1: perceive (populates the element cache)
# Step 2: click e137 (column view radio button) — triggers confirmation prompt

echo "=== Rescreen Action Test ==="
echo "This will:"
echo "  1. Capture Finder's UI tree"
echo "  2. Ask to click the 'column view' button (e137)"
echo "  3. Prompt YOU for confirmation before executing"
echo ""

{
    # Initialize MCP
    echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
    echo '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    # Perceive first (populates element cache)
    echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"rescreen_perceive","arguments":{"type":"accessibility","target":"com.apple.finder","max_depth":8,"max_nodes":150}}}'
    # Click column view button
    echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"rescreen_act","arguments":{"type":"click","target":"com.apple.finder","element":"e137"}}}'
} | .build/debug/RescreenBroker --app com.apple.finder 2>&1 1>/tmp/rs_responses.log

echo ""
echo "=== Results ==="
python3 -c "
import json
with open('/tmp/rs_responses.log') as f:
    for line in f:
        line = line.strip()
        if not line or not line.startswith('{'):
            continue
        try:
            resp = json.loads(line)
            rid = resp.get('id')
            if rid == 2:
                text = resp['result']['content'][0]['text']
                summary = text.split('\n\n')[0]
                print(f'Perceive: {summary}')
            elif rid == 3:
                text = resp['result']['content'][0]['text']
                is_err = resp['result'].get('isError', False)
                status = 'ERROR' if is_err else 'OK'
                print(f'Action [{status}]: {text}')
        except:
            pass
"
