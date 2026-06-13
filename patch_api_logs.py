import os

def patch_file(path):
    with open(path, 'r') as f:
        lines = f.readlines()
        
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if 'curl -s -X POST "http://${API_SERVER:-localhost:8000}/api/v1/update_status"' in line:
            # Usually it's spread over 2 lines. 
            # line 1: curl ... -H "Content-Type: application/json" \
            # line 2:      -d "..." > /dev/null
            if '\\' in line:
                payload_line = lines[i+1]
                if '> /dev/null' in payload_line:
                    payload = payload_line.split('-d "')[1].split('" >')[0]
                    # We can extract the raw string inside -d "..."
                    indent = len(line) - len(line.lstrip())
                    ind_str = " " * indent
                    out.append(f'{ind_str}REQ_PAYLOAD="{payload}"\n')
                    out.append(f'{ind_str}echo "[$(date +\\"%H:%M:%S.%3N\\")] [REQ] /api/v1/update_status | Payload: $REQ_PAYLOAD" >> "$CAPTURE_LOG_DIR/api_trace.log"\n')
                    out.append(f'{ind_str}RES=$(curl -s -X POST "http://${{API_SERVER:-localhost:8000}}/api/v1/update_status" -H "Content-Type: application/json" -d "$REQ_PAYLOAD")\n')
                    out.append(f'{ind_str}echo "[$(date +\\"%H:%M:%S.%3N\\")] [RES] $RES" >> "$CAPTURE_LOG_DIR/api_trace.log"\n')
                    i += 2
                    continue
        out.append(line)
        i += 1
        
    with open(path, 'w') as f:
        f.writelines(out)

patch_file("wifi_single/macro/monitor.sh")
print("monitor.sh patched")
