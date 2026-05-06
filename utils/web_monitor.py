import os
import subprocess
import time
import threading
from flask import Flask, Response, render_template_string, request, jsonify

app = Flask(__name__)

# --- CONFIGURATION ---
PORT = 8080
REFRESH_INTERVAL = 0.05  # Seconds between frames (Approx 20fps)

# --- HTML TEMPLATE ---
HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>NMAP V2 - Web Monitor</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { background: #121212; color: #eee; font-family: sans-serif; margin: 0; padding: 10px; }
        .container { display: flex; flex-wrap: wrap; gap: 15px; justify-content: center; }
        .device-card { background: #1e1e1e; border-radius: 8px; padding: 10px; border: 1px solid #333; text-align: center; }
        .device-id { font-weight: bold; margin-bottom: 8px; color: #4CAF50; }
        .screen-container { position: relative; display: inline-block; cursor: crosshair; }
        .screen-img { max-width: 300px; border: 2px solid #000; display: block; background: #000; min-height: 400px; }
        .controls { margin-top: 10px; display: flex; gap: 5px; justify-content: center; }
        button { padding: 8px 12px; cursor: pointer; background: #333; color: white; border: none; border-radius: 4px; font-weight: bold; }
        button:hover { background: #555; }
        .status { font-size: 0.8em; color: #888; margin-top: 5px; }
        h2 { color: #fff; margin-bottom: 20px; }
    </style>
</head>
<body>
    <h2 style="text-align: center;">NMAP V2 Multi-Device Monitor</h2>
    <div style="text-align: center; margin-bottom: 20px;">
        <label style="background: #333; padding: 10px 20px; border-radius: 20px; cursor: pointer;">
            <input type="checkbox" id="allow-touch"> 
            <span style="user-select: none;">🖐️ 화면 터치(제어) 허용</span>
        </label>
    </div>
    <div class="container" id="device-container">
        {% if not devices %}
            <div style="color: #ff5252; padding: 20px; border: 1px dashed #ff5252; border-radius: 8px;">
                No devices detected via ADB.
            </div>
        {% endif %}
        {% for dev in devices %}
        <div class="device-card" id="card-{{ dev }}">
            <div class="device-id">{{ dev }}</div>
            <div class="screen-container">
                <img src="/stream/{{ dev }}" class="screen-img" id="img-{{ dev }}" draggable="false" 
                     onpointerdown="handlePointerDown(event, '{{ dev }}')" 
                     onpointerup="handlePointerUp(event, '{{ dev }}')">
            </div>
            <div class="controls">
                <button onclick="sendKey('{{ dev }}', 3)">HOME</button>
                <button onclick="sendKey('{{ dev }}', 4)">BACK</button>
                <button onclick="sendKey('{{ dev }}', 187)">APPS</button>
            </div>
            <div class="status" id="status-{{ dev }}">Live</div>
        </div>
        {% endfor %}
    </div>

    <script>
        let activePointers = {};

        function handlePointerDown(event, devId) {
            if (!document.getElementById('allow-touch').checked) return;
            const img = document.getElementById('img-' + devId);
            img.setPointerCapture(event.pointerId);
            const rect = img.getBoundingClientRect();
            activePointers[event.pointerId] = {
                startX: (event.clientX - rect.left) / rect.width,
                startY: (event.clientY - rect.top) / rect.height
            };
        }

        function handlePointerUp(event, devId) {
            if (!document.getElementById('allow-touch').checked) return;
            if (!activePointers[event.pointerId]) return;
            const start = activePointers[event.pointerId];
            delete activePointers[event.pointerId];

            const img = document.getElementById('img-' + devId);
            const rect = img.getBoundingClientRect();
            let endX = (event.clientX - rect.left) / rect.width;
            let endY = (event.clientY - rect.top) / rect.height;

            endX = Math.max(0, Math.min(1, endX));
            endY = Math.max(0, Math.min(1, endY));
            const startX = Math.max(0, Math.min(1, start.startX));
            const startY = Math.max(0, Math.min(1, start.startY));

            const dx = endX - startX;
            const dy = endY - startY;
            const distance = Math.sqrt(dx*dx + dy*dy);

            if (distance < 0.02) {
                fetch(`/click/${devId}?x_pct=${endX}&y_pct=${endY}`);
            } else {
                fetch(`/swipe/${devId}?x1_pct=${startX}&y1_pct=${startY}&x2_pct=${endX}&y2_pct=${endY}`);
            }
        }

        function sendKey(devId, keycode) {
            if (!document.getElementById('allow-touch').checked) return;
            fetch(`/key/${devId}?code=${keycode}`);
        }

        setInterval(() => {
            fetch('/devices_raw').then(r => r.json()).then(data => {
                const currentCount = document.querySelectorAll('.device-card').length;
                if (data.length !== currentCount) {
                    console.log("Device count changed, reloading...");
                    location.reload();
                }
            });
        }, 5000);
    </script>
</body>
</html>
"""

def get_adb_devices():
    try:
        output = subprocess.check_output(["adb", "devices"]).decode("utf-8")
        lines = output.strip().split("\n")[1:]
        devs = [line.split()[0] for line in lines if line.strip() and "device" in line]
        return devs
    except:
        return []

def get_screen_size(dev_id):
    try:
        out = subprocess.check_output(["adb", "-s", dev_id, "shell", "wm size"]).decode("utf-8")
        size = out.split(":")[-1].strip().split("x")
        return int(size[0]), int(size[1])
    except:
        return 1080, 2400

@app.route('/')
def index():
    devices = get_adb_devices()
    return render_template_string(HTML_TEMPLATE, devices=devices)

@app.route('/devices_raw')
def devices_raw():
    return jsonify(get_adb_devices())

@app.route('/click/<dev_id>')
def click(dev_id):
    x_pct = float(request.args.get('x_pct', 0))
    y_pct = float(request.args.get('y_pct', 0))
    w, h = get_screen_size(dev_id)
    tx, ty = int(w * x_pct), int(h * y_pct)
    subprocess.Popen(["adb", "-s", dev_id, "shell", "input", "tap", str(tx), str(ty)])
    return "OK"

@app.route('/swipe/<dev_id>')
def swipe(dev_id):
    x1_pct = float(request.args.get('x1_pct', 0))
    y1_pct = float(request.args.get('y1_pct', 0))
    x2_pct = float(request.args.get('x2_pct', 0))
    y2_pct = float(request.args.get('y2_pct', 0))
    w, h = get_screen_size(dev_id)
    tx1, ty1 = int(w * x1_pct), int(h * y1_pct)
    tx2, ty2 = int(w * x2_pct), int(h * y2_pct)
    duration = 300 # milliseconds
    subprocess.Popen(["adb", "-s", dev_id, "shell", "input", "swipe", str(tx1), str(ty1), str(tx2), str(ty2), str(duration)])
    return "OK"

@app.route('/key/<dev_id>')
def key(dev_id):
    code = request.args.get('code', 3)
    subprocess.Popen(["adb", "-s", dev_id, "shell", "input", "keyevent", str(code)])
    return "OK"

def gen_frames(dev_id):
    while True:
        try:
            cmd = ["adb", "-s", dev_id, "exec-out", "screencap", "-p"]
            frame = subprocess.check_output(cmd)
            yield (b'--frame\r\n'
                   b'Content-Type: image/png\r\n\r\n' + frame + b'\r\n')
            time.sleep(REFRESH_INTERVAL)
        except:
            break

@app.route('/stream/<dev_id>')
def stream(dev_id):
    return Response(gen_frames(dev_id),
                    mimetype='multipart/x-mixed-replace; boundary=frame')

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=PORT, threaded=True)
