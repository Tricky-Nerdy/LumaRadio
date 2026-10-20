import asyncio
import json
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from telemetry.server import Relay, transport_context
from websockets.asyncio.client import connect
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

KEY = "test-pairing-key-not-a-real-secret"


class StationNetworkTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.relay = Relay(KEY)
        self.server = await serve(self.relay.handle, "127.0.0.1", 0, origins=[None], max_size=65536)
        self.url = f"ws://127.0.0.1:{self.server.sockets[0].getsockname()[1]}"
        self.clients = []

    async def asyncTearDown(self):
        for ws in self.clients:
            await ws.close()
        self.server.close()
        await self.server.wait_closed()

    async def recv(self, ws):
        return json.loads(await asyncio.wait_for(ws.recv(), timeout=2))

    async def peer(self, name, key=KEY):
        ws = await connect(self.url)
        self.clients.append(ws)
        await ws.send(json.dumps({"type": "forge.hello", "app_id": name, "key": key}))
        response = await self.recv(ws)
        self.assertEqual(response["type"], "forge.ready")
        self.assertFalse(response["audio"])
        return ws

    async def send(self, ws, event):
        await ws.send(json.dumps(event))

    async def test_solar_radio_forge_and_tv_exchange_silent_signals(self):
        solar = await self.peer("solar-vr")
        consumers = [await self.peer(name) for name in ("radio", "forge-hub", "tv")]
        await self.send(solar, {"type": "forge.signal", "id": "morse-1", "seq": 1, "format": "morse", "text": "CQ MARS"})
        ack = await self.recv(solar)
        self.assertEqual(ack["delivered"], 3)
        for consumer in consumers:
            event = await self.recv(consumer)
            self.assertEqual(event["source"], "solar-vr")
            self.assertEqual(event["payload"]["code"], "-.-. --.- / -- .- .-. ...")
            self.assertFalse(event["audio"])

    async def test_targeted_16bit_and_duplicates_do_not_replay(self):
        solar, radio, tv = await self.peer("solar"), await self.peer("radio"), await self.peer("tv")
        event = {"type": "forge.signal", "id": "data-1", "seq": 1, "target": "radio",
                 "format": "u16", "text": "🌍", "source": "forged-source"}
        await self.send(solar, event)
        self.assertEqual((await self.recv(solar))["delivered"], 1)
        routed = await self.recv(radio)
        self.assertEqual(routed["payload"]["values"], [0xD83C, 0xDF0D])
        self.assertEqual(routed["source"], "solar")
        await self.send(solar, event)
        self.assertTrue((await self.recv(solar))["duplicate"])
        for peer in (radio, tv):
            with self.assertRaises(TimeoutError):
                await asyncio.wait_for(peer.recv(), timeout=0.03)

    async def test_ack_without_peers_does_not_claim_delivery(self):
        solar = await self.peer("solar")
        await self.send(solar, {"type": "forge.signal", "id": "x", "seq": 1, "format": "u8", "text": "Mars"})
        self.assertEqual((await self.recv(solar))["delivered"], 0)

    async def test_station_generation_is_requester_only_and_honest_offline(self):
        radio, tv = await self.peer("radio"), await self.peer("tv")
        with patch.dict(os.environ, {}, clear=True):
            await self.send(radio, {"type": "forge.program", "id": "show-1", "seq": 1,
                                    "request": {"show": "interview", "topic": "Martian gardens"}})
            reply = await self.recv(radio)
        self.assertEqual(reply["type"], "forge.program.result")
        self.assertEqual(reply["program"]["status"], "prompt_ready")
        self.assertEqual(reply["program"]["plan"]["title"], "Interviews")
        with self.assertRaises(TimeoutError):
            await asyncio.wait_for(tv.recv(), timeout=0.03)

    async def test_bad_key_and_unpaired_data_are_rejected(self):
        ws = await connect(self.url)
        self.clients.append(ws)
        await self.send(ws, {"type": "forge.signal", "id": "x", "seq": 1, "format": "morse", "text": "SOS"})
        self.assertEqual((await self.recv(ws))["type"], "forge.error")
        await self.send(ws, {"type": "forge.hello", "app_id": "bad", "key": "wrong"})
        with self.assertRaises(ConnectionClosed):
            await self.recv(ws)
        self.assertEqual(ws.close_code, 1008)

    async def test_legacy_buttons_still_ack_without_playback(self):
        ws = await connect(self.url)
        self.clients.append(ws)
        for event in ({"type": "button", "value": "ALPHA CAPTURED"}, {"type": "ptt", "value": "down"}):
            await self.send(ws, event)
            self.assertEqual(await self.recv(ws), {"type": "ack", "value": event["value"]})

    async def test_invalid_events_do_not_break_following_controls(self):
        peer = await self.peer("radio")
        invalid = [[], {"type": "forge.signal", "id": "x", "seq": True, "format": "u8", "values": [1]},
                   {"type": "forge.signal", "id": "x", "seq": 1, "format": "u16", "values": [65536]},
                   {"type": "forge.program", "id": "p", "seq": 2, "request": {"mode": "sourced", "topic": "News"}}]
        for event in invalid:
            await self.send(peer, event)
            self.assertEqual((await self.recv(peer))["type"], "forge.error")
        await self.send(peer, {"type": "button", "value": "QSL"})
        self.assertEqual((await self.recv(peer))["type"], "ack")

    async def test_map_context_and_app_reconnect(self):
        solar, radio = await self.peer("solar"), await self.peer("radio")
        await self.send(solar, {"type": "forge.context", "id": "map-1", "seq": 1, "map_context": {"body": "Mars", "selection": "Gale crater"}})
        self.assertEqual((await self.recv(solar))["delivered"], 1)
        self.assertEqual((await self.recv(radio))["payload"]["body"], "Mars")
        await solar.close()
        await asyncio.sleep(0)
        solar2 = await self.peer("solar")
        await self.send(solar2, {"type": "forge.signal", "id": "new-session", "seq": 1, "format": "u8", "values": [255]})
        self.assertEqual((await self.recv(solar2))["delivered"], 1)
        self.assertEqual((await self.recv(radio))["payload"]["values"], [255])

    def test_no_public_or_unencrypted_lan_listener(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertIsNone(transport_context("127.0.0.1"))
            for host in ("0.0.0.0", "8.8.8.8", "192.168.1.4", "224.0.0.1"):
                with self.subTest(host=host), self.assertRaises(ValueError):
                    transport_context(host)


if __name__ == "__main__":
    unittest.main()
