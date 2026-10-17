"""LumaRadio PC telemetry receiver. Local-network use with explicit pairing key."""
import argparse
import hashlib
import hmac
import json
import os
import socketserver
import time

class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        raw = self.rfile.readline(2049)
        if len(raw) > 2048:
            return
        try:
            msg = json.loads(raw)
            body = msg["body"]
            encoded = json.dumps(body, separators=(",", ":"), sort_keys=True).encode()
            expected = hmac.new(self.server.pairing_key.encode(), encoded, hashlib.sha256).hexdigest()
            if not hmac.compare_digest(expected, msg["mac"]):
                return
            if abs(time.time() - int(body["utc"])) > 60:
                return
            if not isinstance(body["event"], str) or len(body["event"]) > 512:
                return
            print(json.dumps({"peer": self.client_address[0], **body}), flush=True)
            self.wfile.write(b"ACK\n")
        except (ValueError, KeyError, TypeError, UnicodeError):
            return

class Receiver(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="127.0.0.1", help="Use a specific LAN address to enable phone access")
    p.add_argument("--port", type=int, default=8765)
    args = p.parse_args()
    key = os.environ.get("LUMARADIO_PAIRING_KEY", "")
    if len(key) < 16:
        raise SystemExit("Set LUMARADIO_PAIRING_KEY to a secret of at least 16 characters")
    with Receiver((args.host, args.port), Handler) as server:
        server.pairing_key = key
        print(f"Receiver listening on {args.host}:{args.port}", flush=True)
        server.serve_forever()

if __name__ == "__main__":
    main()
