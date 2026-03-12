#!/bin/bash
# Milestone 2 test: profile-based permissions + NSPanel confirmation dialog
#
# This will:
# 1. Load the finder-test profile
# 2. Perceive Finder's UI tree (silent — no prompt)
# 3. Attempt to click column view button (triggers native macOS confirmation dialog)
#
# The NSPanel dialog will appear on screen — click Allow or Deny.

echo "=== Rescreen M2 Test ==="
echo "A native macOS dialog will appear for confirmation."
echo ""

{
    echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
    echo '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"rescreen_perceive","arguments":{"type":"accessibility","target":"com.apple.finder","max_depth":8,"max_nodes":150}}}'
    echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"rescreen_act","arguments":{"type":"click","target":"com.apple.finder","element":"e137"}}}'
    echo '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"rescreen_status","arguments":{}}}'
} | .build/debug/RescreenBroker --profile finder-test 2>&1 1>/tmp/rs_m2_responses.log

echo ""
echo "=== Results ==="
python3 -c "
import json
with open('/tmp/rs_m2_responses.log') as f:
    for line in f:
        line = line.strip()
        if not line or not line.startswith('{'):
            continue
        try:
            resp = json.loads(line)
            rid = resp.get('id')
            if rid == 2:
                text = resp['result']['content'][0]['text']
                summary = text.split(chr(10)+chr(10))[0]
                print(f'Perceive: {summary}')
            elif rid == 3:
                text = resp['result']['content'][0]['text']
                is_err = resp['result'].get('isError', False)
                status = 'ERROR' if is_err else 'OK'
                print(f'Action [{status}]: {text}')
            elif rid == 4:
                print('Status: Active grants and session info returned')
        except:
            pass
"

echo ""
echo "=== Audit Log ==="
cat ~/.rescreen/logs/*.jsonl 2>/dev/null | python3 -c "
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    e = json.loads(line)
    op = e.get('operation','?')
    result = e.get('result','?')
    app = e.get('target',{}).get('app','')
    conf = e.get('confirmation','')
    print(f'  {op:<25} result={result:<10} conf={conf:<10} app={app}')
"
