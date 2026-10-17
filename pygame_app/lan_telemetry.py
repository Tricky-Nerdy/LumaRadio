"""Opt-in LAN telemetry sender. No microphone, no automatic discovery or uploads."""
import hashlib
import hmac
import json
import os
import socket
import time

MAX_BYTES = 2048

def sign_message(event, key, sequence=0):
    if not key or len(key) < 16:
        raise ValueError("Pairing key must have at least 16 characters")
    body = {"event": event, "seq": sequence, "utc": int(time.time())}
    encoded = json.dumps(body, separators=(",", ":"), sort_keys=True).encode()
    mac = hmac.new(key.encode(), encoded, hashlib.sha256).hexdigest()
    return json.dumps({"body": body, "mac": mac}, separators=(",", ":")).encode() + b"\n"

def send_event(host, port, key, event, sequence=0, timeout=1.5):
    if not host or not (1 <= int(port) <= 65535):
        raise ValueError("Invalid receiver")
    payload = sign_message(event, key, sequence)
    if len(payload) > MAX_BYTES:
        raise ValueError("Event too large")
    with socket.create_connection((host, int(port)), timeout=timeout) as sock:
        sock.settimeout(timeout)
        sock.sendall(payload)
        return sock.recv(64).strip() == b"ACK"

def enabled():
    return os.environ.get("LUMARADIO_LAN_ENABLED") == "1"
