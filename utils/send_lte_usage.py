#!/usr/bin/env python3
import socket
import re
import subprocess
import json
import xml.etree.ElementTree as ET
import urllib.request
import urllib.error
import sys
import time

API_URL = "http://114.207.112.245:8000/api/v1/lte_usage"

def get_lte_interfaces():
    """Find all active lte interfaces and their subnets."""
    interfaces = []
    try:
        output = subprocess.check_output(["ip", "-br", "addr", "show"]).decode()
        for line in output.splitlines():
            parts = line.split()
            if not parts:
                continue
            name = parts[0]
            # Match lte11, lte12, etc.
            match = re.match(r'^lte(\d+)$', name)
            if match:
                subnet = int(match.group(1))
                interfaces.append((name, subnet))
    except Exception as e:
        print(f"Error listing interfaces: {e}")
    return sorted(interfaces)

def get_modem_traffic(subnet):
    """Query the Huawei modem for traffic statistics."""
    modem_ip = f"192.168.{subnet}.1"
    
    # 1. Get Session & Token
    sestok_url = f"http://{modem_ip}/api/webserver/SesTokInfo"
    try:
        req = urllib.request.Request(sestok_url, method="GET")
        with urllib.request.urlopen(req, timeout=5) as response:
            xml_data = response.read()
            root = ET.fromstring(xml_data)
            ses_info = root.findtext("SesInfo")
            tok_info = root.findtext("TokInfo")
    except Exception:
        return None
        
    if not ses_info or not tok_info:
        return None
        
    # 2. Get Traffic Statistics
    stats_url = f"http://{modem_ip}/api/monitoring/traffic-statistics"
    try:
        headers = {
            "Cookie": f"SessionID={ses_info}",
            "__RequestVerificationToken": tok_info
        }
        req = urllib.request.Request(stats_url, headers=headers, method="GET")
        with urllib.request.urlopen(req, timeout=5) as response:
            xml_data = response.read()
            root = ET.fromstring(xml_data)
            
            total_upload = root.findtext("TotalUpload")
            total_download = root.findtext("TotalDownload")
            
            return {
                "upload": int(total_upload) if total_upload else 0,
                "download": int(total_download) if total_download else 0
            }
    except Exception:
        return None

def send_usage(name, upload_mb, download_mb):
    """Send LTE usage data to the API server."""
    payload = {
        "name": name,
        "upload": upload_mb,
        "download": download_mb
    }
    
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(API_URL, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            res_body = response.read().decode('utf-8')
            return True, res_body
    except Exception as e:
        return False, str(e)

def run_once():
    hostname = socket.gethostname()
    interfaces = get_lte_interfaces()
    
    print(f"=== Sending LTE usage to {API_URL} ===")
    
    for name, subnet in interfaces:
        stats = get_modem_traffic(subnet)
        if stats:
            upload_raw = stats["upload"]
            download_raw = stats["download"]
            combined_name = f"{hostname}_{name}"
            
            success, message = send_usage(combined_name, upload_raw, download_raw)
            status_str = "SUCCESS" if success else "FAILED"
            print(f"[{status_str}] {combined_name} -> Upload: {upload_raw} Bytes, Download: {download_raw} Bytes | Response: {message}")
        else:
            print(f"[ERROR] {name} -> Could not fetch traffic data (modem offline or unreachable)")

def main():
    daemon_mode = "--daemon" in sys.argv or "-d" in sys.argv
    
    if daemon_mode:
        print(f"Starting LTE Usage Sender in daemon mode (looping every 60 seconds)...")
        while True:
            try:
                run_once()
            except Exception as e:
                print(f"Error in daemon run: {e}")
            time.sleep(60)
    else:
        run_once()

if __name__ == "__main__":
    main()
