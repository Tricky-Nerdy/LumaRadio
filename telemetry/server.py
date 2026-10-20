"""Existing Radio receiver with silent Forge station and signal routing."""
from __future__ import annotations

import asyncio
import hmac
import ipaddress
import json
import os
import re
import ssl
import sys
import time
from collections import deque
from datetime import datetime, timezone
from pathlib import Path
from functools import lru_cache
from http import HTTPStatus

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from station.programming import generate_program
from station.signals import encode_signal
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed
from websockets.datastructures import Headers
from websockets.http11 import Response

HOST = os.getenv("LUMA_HOST", "127.0.0.1")
PORT = int(os.getenv("LUMA_PORT", "8765"))
LOG = Path(__file__).with_name("events.jsonl")
PROTOCOL = "forge.station/1"
MAX_BYTES = 65536


@lru_cache(maxsize=1)
def studio_html():
    from tools.build_station_web import render_bundle
    return render_bundle().encode('utf-8')


def studio_response(connection, request):
    if request.headers.get('Upgrade', '').lower() == 'websocket':
        return None
    if request.path not in ('/', '/index.html'):
        return Response(HTTPStatus.NOT_FOUND, 'Not Found', Headers({'Content-Length': '0'}), b'')
    body = studio_html()
    return Response(HTTPStatus.OK, 'OK', Headers({'Content-Type': 'text/html; charset=utf-8',
                    'Content-Length': str(len(body)), 'Cache-Control': 'no-store',
                    'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer'}), body)


class Relay:
    def __init__(self, pairing_key="", *, completion=None, log=None):
        self.pairing_key = pairing_key
        self.completion = completion
        self.log = log
        self.peers = {}
        self.generation_slots = asyncio.Semaphore(2)

    async def _send(self, ws, event):
        await ws.send(json.dumps(event, ensure_ascii=False, allow_nan=False))

    async def _forward(self, event, sender, target):
        peers = [ws for app, ws in self.peers.items()
                 if ws is not sender and (target == "*" or app == target)]
        async def deliver(ws):
            try:
                await asyncio.wait_for(self._send(ws, event), timeout=2)
                return True
            except (ConnectionClosed, TimeoutError, OSError):
                return False
        return sum(await asyncio.gather(*(deliver(ws) for ws in peers)))

    async def handle(self, ws):
        app_id, last_seq = None, 0
        recent = deque()
        try:
            async for raw in ws:
                try:
                    now = time.monotonic()
                    while recent and now - recent[0] > 1:
                        recent.popleft()
                    if len(recent) >= 30:
                        raise ValueError("Signal rate exceeded")
                    recent.append(now)
                    if not isinstance(raw, str) or len(raw.encode("utf-8")) > MAX_BYTES:
                        raise ValueError("Expected bounded JSON text")
                    event = json.loads(raw)
                    if not isinstance(event, dict):
                        raise ValueError("Expected an object")
                    kind = event.get("type")
                    # Preserve Command Center's existing control/ACK contract.
                    # This receiver never renders voice or tones.
                    if kind in ("button", "ptt"):
                        value = event.get("value", "")
                        if not isinstance(value, str) or len(value) > 100:
                            raise ValueError("Invalid legacy control")
                        if self.log:
                            with Path(self.log).open("a", encoding="utf-8") as handle:
                                handle.write(json.dumps({"timestamp": datetime.now(timezone.utc).isoformat(),
                                                         "type": kind, "value": value}) + "\n")
                        await self._send(ws, {"type": "ack", "value": value})
                        continue
                    if kind == "forge.hello":
                        key = event.get("key", "")
                        if len(self.pairing_key) < 16 or not isinstance(key, str) or not hmac.compare_digest(key.encode(), self.pairing_key.encode()):
                            await ws.close(1008, "Pairing required")
                            return
                        candidate = event.get("app_id", "")
                        if app_id is not None or not isinstance(candidate, str) or not re.fullmatch(r"[a-zA-Z0-9_.-]{1,64}", candidate):
                            raise ValueError("Invalid app ID")
                        if candidate in self.peers or len(self.peers) >= 16:
                            raise ValueError("App ID connected or station full")
                        app_id = candidate
                        self.peers[app_id] = ws
                        await self._send(ws, {"type": "forge.ready", "protocol": PROTOCOL, "app_id": app_id,
                                              "formats": ["morse", "u8", "u16"], "audio": False})
                        continue
                    if app_id is None:
                        raise ValueError("Pair before using station data")
                    eid, seq = event.get("id"), event.get("seq")
                    if not isinstance(eid, str) or not re.fullmatch(r"[a-zA-Z0-9_.-]{1,80}", eid) or type(seq) is not int or seq < 1:
                        raise ValueError("Invalid ID or sequence")
                    if seq <= last_seq:
                        await self._send(ws, {"type": "forge.ack", "id": eid, "seq": seq, "duplicate": True, "delivered": 0})
                        continue
                    if kind == "forge.program":
                        last_seq = seq
                        async with self.generation_slots:
                            result = await asyncio.to_thread(generate_program, event.get("request"), self.completion)
                        await self._send(ws, {"type": "forge.program.result", "protocol": PROTOCOL,
                                              "id": eid, "seq": seq, "program": result, "audio": False})
                        continue
                    target = event.get("target", "*")
                    if not isinstance(target, str) or (target != "*" and not re.fullmatch(r"[a-zA-Z0-9_.-]{1,64}", target)):
                        raise ValueError("Invalid target")
                    if kind == "forge.signal":
                        payload = encode_signal(event)
                    elif kind == "forge.context":
                        payload = event.get("map_context")
                        if not isinstance(payload, dict) or len(json.dumps(payload, allow_nan=False)) > 2000:
                            raise ValueError("Invalid map context")
                    else:
                        raise ValueError("Unknown event type")
                    last_seq = seq
                    routed = {"type": kind, "protocol": PROTOCOL, "id": eid, "seq": seq,
                              "source": app_id, "target": target, "payload": payload, "audio": False}
                    delivered = await self._forward(routed, ws, target)
                    await self._send(ws, {"type": "forge.ack", "id": eid, "seq": seq,
                                          "delivered": delivered, "duplicate": False})
                except (ValueError, TypeError, KeyError, OverflowError):
                    await self._send(ws, {"type": "forge.error", "message": "Invalid station input; check pairing, event fields, or source notes.", "audio": False})
        except ConnectionClosed:
            pass
        finally:
            if app_id is not None and self.peers.get(app_id) is ws:
                del self.peers[app_id]


def transport_context(host):
    address = ipaddress.ip_address(host)
    if address.is_unspecified or address.is_multicast or not (address.is_loopback or address.is_private):
        raise ValueError("Bind to a specific loopback or LAN interface")
    cert, key = os.getenv("LUMA_TLS_CERT"), os.getenv("LUMA_TLS_KEY")
    if not address.is_loopback and not (cert and key):
        raise ValueError("LAN receiver requires TLS certificate and private key")
    if cert or key:
        if not (cert and key):
            raise ValueError("Configure both TLS certificate and key")
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(cert, key)
        return context
    return None


async def main():
    context = transport_context(HOST)
    relay = Relay(os.getenv("LUMA_STATION_PAIRING_KEY", ""), log=LOG if os.getenv("LUMARADIO_DEBUG") == "1" else None)
    authority = f'[{HOST}]' if ':' in HOST else HOST
    scheme = 'https' if context else 'http'
    studio_origin = f'{scheme}://{authority}:{PORT}' if PORT else re.compile(r'^http://127\.0\.0\.1:\d+$')
    async with serve(relay.handle, HOST, PORT, ssl=context, origins=[None, 'null', 'https://forge.invalid', studio_origin],
                     process_request=studio_response, max_size=MAX_BYTES, max_queue=16, close_timeout=2) as server:
        bound_port = server.sockets[0].getsockname()[1]
        print(f"Luma Radio controls + silent station on {HOST}:{bound_port}", flush=True)
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())

