import asyncio
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from telemetry.server import Relay
from websockets.asyncio.server import serve


class ActualGodotNetworkTests(unittest.IsolatedAsyncioTestCase):
    async def test_godot_peers_exchange_with_actual_python_receiver(self):
        executable = os.environ.get('GODOT_BIN')
        if not executable:
            self.skipTest('Set GODOT_BIN to run the actual engine network integration')
        key = 'integration-test-pairing-key-only'
        relay = Relay(key)
        async with serve(relay.handle, '127.0.0.1', 0, origins=[None]) as server:
            port = server.sockets[0].getsockname()[1]
            env = {**os.environ, 'STATION_TEST_URL': f'ws://127.0.0.1:{port}', 'STATION_TEST_KEY': key}
            env.pop('LUMA_STATION_LLM_URL', None)
            # The receiver and producer run in this process; keep this test model-free.
            with patch.dict(os.environ, {'LUMA_STATION_LLM_URL': ''}):
                process = await asyncio.create_subprocess_exec(executable, '--headless', '--path', str(Path(__file__).resolve().parents[1]),
                    '--script', 'res://tests/network_station.gd', env=env,
                    stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)
                try:
                    output, _ = await asyncio.wait_for(process.communicate(), 30)
                except BaseException:
                    process.kill()
                    await process.wait()
                    raise
            text = output.decode()
            self.assertEqual(process.returncode, 0, text)
            self.assertIn('ENGINE_NETWORK_SMOKE failures: 0', text)
            self.assertNotIn('SCRIPT ERROR', text)
            print('Actual Godot/Python paired station integration passed')
