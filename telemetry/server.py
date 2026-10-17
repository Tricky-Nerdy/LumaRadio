"""Local-only LumaRadio telemetry receiver. No cloud or tracking."""
import asyncio
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from websockets.asyncio.server import serve

HOST = os.getenv('LUMA_HOST', '0.0.0.0')
PORT = int(os.getenv('LUMA_PORT', '8765'))
LOG = Path(__file__).with_name('events.jsonl')

async def handle(ws):
    async for raw in ws:
        try:
            event = json.loads(raw)
            if not isinstance(event, dict) or event.get('type') not in ('button', 'ptt'):
                continue
            event = {'timestamp': datetime.now(timezone.utc).isoformat(), 'type': event['type'], 'value': str(event.get('value', ''))[:100]}
            with LOG.open('a') as f:
                f.write(json.dumps(event) + '\n')
            await ws.send(json.dumps({'type': 'ack', 'value': event['value']}))
        except (ValueError, TypeError):
            continue

async def main():
    async with serve(handle, HOST, PORT):
        print(f'Luma telemetry listening on {HOST}:{PORT}', flush=True)
        await asyncio.Future()

if __name__ == '__main__':
    asyncio.run(main())
