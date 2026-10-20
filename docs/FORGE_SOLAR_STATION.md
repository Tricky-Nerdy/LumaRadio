# Forge Solar station and silent signals

This source extends the existing Radio WebSocket receiver and provides a producer for the existing
Forge Broadcast studio. It introduces no alternative Forge interface and does not install or publish
an APK. The new station path is text/data only; legacy soundboard buttons remain a separate feature.
Do not connect station signal events to the legacy soundboard's `_signal` or `_play_pattern` methods.

## Source audit and integration boundary

| Source | Verified access in this change | Use |
| --- | --- | --- |
| `Tricky-Nerdy/LumaRadio`, `command-center-preview-20261020`, commit `1bc85dd3435ba26798e59223b3b26f62cf87cfb6` | Read current source | Reuse its receiver, control/ACK contract, Godot project, and tests |
| `Tricky-Nerdy/Forge`, `main` | Read repository tree and catalog code | Confirm it contains the provenance library, not the live Forge Hub UI |
| Forge Hub Android source release | Source archive listed in Command Center release; download unavailable from this environment | No claim that its contents were inspected or changed |
| PC `~/Documents/ForgeHub` | Omarchy Desktop Commander offline | Existing Broadcast generator, blue UI, templates and saved settings must be inspected before wiring this producer into them |
| PC `~/Documents/Main/Luma` | Same offline PC | Project notes and Markdown not read or modified in this change |
| PC solar/VR project | Source not located in connected Git repositories | Attach adapter after locating current source and instructions; preserve watch, casting, travel and rendering behavior |
| Gists | Current GitHub connector exposes no gist reader | Not audited or changed |

Do not replace the current Forge studio, duplicate its navigation, change its app identities or
signers, rewrite the Obsidian vault, or infer live telemetry from old notes. Reconcile current PC
source with this branch before changing any installed runtime. The existing standalone Command
Center still uses its legacy UI until the new adapter is deliberately connected.

## Station producer

`station.programming.generate_program(request)` can be imported by Forge's current desktop
generator. Keep its existing template, master/session, source/destination, Generate/Remix,
transcript and transport controls. Map the creative-direction boxes to `direction`, the current
solar selection snapshot to `map_context`, and the selected format to `show`.

| Format | Default target | Progression |
| --- | --- | --- |
| `mars_news` | 5 minutes | Lead → report → map/background → next development |
| `star_news` | 6 minutes | Headline → story → science → uncertainty → recap |
| `talk_hour` | 60 minutes | One question → background → perspective → challenge → application → synthesis |
| `interview` | 20 minutes | Guest/purpose → background → experience → follow-up → takeaway |

The clock sums to the requested target. It is a planned running order, not measured playback or
a guarantee that a short cue script fills an hour. There is no audio render in this path.

Example input to the producer or the adapter's `request_program`:

```json
{
  "show": "mars_news",
  "mode": "simulation",
  "topic": "Keeping a fictional Mars settlement supplied with water",
  "host": "Luma",
  "direction": "Calm, curious reporting. Follow the water story from cause to consequences, then the next step.",
  "map_context": {"body": "Mars", "selection": "Gale crater"},
  "sources": []
}
```

Simulation mode is explicitly labeled fictional. Sourced mode requires notes with unique IDs,
titles and substantive content; URLs alone do not count as fetched evidence. Supply `published_at`
when known. Model references must point to supplied IDs. Interview answers in sourced mode need
source notes explicitly marked `guest_transcript: true`; otherwise only host questions are allowed.
The generator audits structure, speakers, repeated cues, literal copying of creative direction,
production markup and source references. These checks cannot prove factual accuracy, natural
acting, or narrative coherence; drafts still require editorial review.

Return statuses are `prompt_ready` (outline and model prompt, no configured model), `draft_ready`
(validated text cues), or `needs_review` (model/validation failed, no partial script exposed).
Preserve that distinction in the existing UI. Never label an outline as generated news or a draft
as an on-air performance. Generation returns only to the requesting app, not to every peer.

For local LM Studio generation, configure `LUMA_STATION_LLM_URL` as its local base URL and
`LUMA_STATION_MODEL` as the actual loaded model ID. Optional `LUMA_STATION_LLM_KEY` stays in
the protected runtime environment. The HTTP client disables proxies and redirects, accepts
loopback/private IP endpoints only, bounds the response, and rejects incomplete output. No live
model response was tested on Omarchy during this change.

## Existing receiver and app contract

Install dependencies from `telemetry/requirements.txt`, then use the existing receiver service
entry point, `python3 telemetry/server.py`. Do not run a second receiver on the same port.
Default bind is `127.0.0.1:8765`. For the existing LAN interface, set `LUMA_HOST` to its specific
private address and provide `LUMA_TLS_CERT` and `LUMA_TLS_KEY`. Clients must trust that certificate;
do not bypass TLS verification. No wildcard/public bind, discovery, port forwarding or new firewall
rules are added. Browser origins are rejected; the existing Forge desktop producer can import
the Python API, and its existing paired backend can use a native WebSocket client.

New station clients pair with a locally configured `LUMA_STATION_PAIRING_KEY` of at least 16
characters. Never place the key in Git, an exported prompt, a gist, a URL, or Obsidian. The Godot
adapter accepts an in-memory key and clears it after handshake. Existing `button`/`ptt` messages
retain their legacy ACK shape and do not render audio in this receiver.

First message:

```json
{"type":"forge.hello","app_id":"solar-vr","key":"<runtime-pairing-key>"}
```

After `forge.ready`, every request has a fresh `id` and an increasing positive `seq` for that
connection. All routed messages use `protocol: "forge.station/1"` and `audio: false`.

| Type | Request fields | Result |
| --- | --- | --- |
| `forge.signal` | `format: "morse"`, `text`, optional `target` | Dot/dash text and visual pulse units: marks 1/3, inner gaps 1, letter gaps 3, word gaps 7 |
| `forge.signal` | `format: "u8"` or `"u16"`, either `text` or `values`, optional `target` | UTF-8 bytes or UTF-16BE code units; explicit unsigned width, values and hex |
| `forge.context` | `map_context`, optional `target` | Current explicit selection snapshot |
| `forge.program` | `request` as above | `forge.program.result` only to the requester |

`target` defaults to `*` for paired peers; an app ID targets one peer. Source identity comes from
the pairing session, not from a sender-supplied field. The sender receives `forge.ack` with the
number of peer sockets written. Zero means no peer delivery; it does not mean success on a
physical display. Acknowledgment of writing is not proof that a peer consumed or rendered a cue.
Old/duplicate sequences are acknowledged without replaying, and disconnected events are not queued.

The 8-/16-bit setting is a **data-word format**, not PCM audio or an automatic change of visual
style. Unicode surrogate pairs are preserved. Unsupported Morse characters and out-of-range
words are rejected rather than silently changed. No physical RF hardware is driven.

## Godot/VR hook

`scripts/forge_station.gd` is an opt-in Node to attach to the existing scene or Forge-owned
controller. It exposes `send_morse`, `send_data`, `send_words`, `publish_map_context` and
`request_program`. Bind its state/errors/receipts to Forge's current status widgets; show offline,
pairing, paired, and no-peer delivery honestly. Bind received payloads to the existing watch/map
or transcript display. A selection snapshot must not overwrite the map's entire scene state.
The adapter does not auto-connect, discover peers, start tones, or modify casting/tracking.

## Validation and remaining work

Python tests exercise exact program clocks, source/guest restrictions, generation validation,
model HTTP requests against a local fake API, failure/truncation/redirect handling, Unicode word
encoding, Morse timing, multi-client routing, targeted delivery, duplicates, pairing, reconnects,
no-peer ACKs and the existing LAN/control regressions. These are local software tests, not a
demonstration of a connected headset, phone, television, real LM Studio instance, or live station.

Godot is unavailable in this workspace, so the new adapter has not passed an engine parse/run
check. A smoke script is supplied: `godot --headless --path . --script res://tests/smoke_station.gd`.
Before runtime integration, run Godot with matching project tooling, wire the existing UI,
test silent TX/RX in both directions on the actual devices, confirm prompt/outline/draft labels,
and verify the current watch/cast/travel behavior. Preserve the private Android signing keys and
the current signed updater feeds; no release or installed version is changed by this branch.
