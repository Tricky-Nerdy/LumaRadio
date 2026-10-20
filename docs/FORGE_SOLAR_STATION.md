# Forge Solar station integration

The new previews reuse the published Forge Android shell and the Radio receiver. The standalone solar scene uses the same producer contract and does not depend on a particular PC. No existing installed app, publisher signing key or update feed was changed.

## Source audit

| Source | Result |
| --- | --- |
| Radio Command Center branch, base commit `1bc85dd3435ba26798e59223b3b26f62cf87cfb6` | Reused receiver/control ACK contract, Godot project, source and tests |
| Released Forge Hub 0.1.2 Android source | Recovered through a hosted build, hash-checked, inspected and included under `forge-hub/`; existing UI helpers/styles retained |
| Forge repository main branch | Inspected; contains the provenance library rather than the current desktop Broadcast UI |
| PC/Obsidian/gists | Not accessed in this continuation; original PC-only source/features are not claimed as recovered |

The Forge companion adds a Solar workspace within its existing navigation and opens that workspace from its Broadcast control. Its studio is bundled as one self-contained HTML asset, with no remote page load, JavaScript-to-Java bridge, microphone access or automatic host connection. The existing legacy Radio app remains separate.

The Godot solar preview is a new scene with a separate export identity. World positions and sizes are stylized. OpenXR initializes when a runtime is available; desktop mode supplies click selection and WASD movement. Controller rays select worlds and operate the in-world panel; thumbstick scroll works over the panel and travel works away from it.

## Producer contract

Call `station.programming.generate_program(request)` from an existing Forge backend, or send `forge.program` through the paired receiver. A request specifies:

- `show`: `mars_news`, `star_news`, `talk_hour` or `interview`.
- `topic`, `direction`, `host`, optional `guest`, whole-minute `minutes`.
- `mode`: `simulation` (explicit fiction) or `sourced`.
- `map_context`: an explicit selection snapshot, not a claim of live telemetry.
- `sources`: source notes with unique ID, title, substantive notes, optional URL/date, and `guest_transcript: true` only for supplied guest answers.

| Format | Default target | Progression |
| --- | --- | --- |
| Mars News | 5 min | Lead → report → map/background → next development |
| Star News | 6 min | Headline → story → science → uncertainty → recap |
| Talk Hour | 60 min | One question → background → perspective → challenge → application → synthesis |
| Interviews | 20 min | Guest/purpose → background → experience → follow-up → takeaway |

The exact running order sums to the requested target; it does not measure a completed performance. Creative direction is never intended as reader-facing dialogue.

`prompt_ready` means an outline and generation brief, `draft_ready` means validated text cues, and `needs_review` means failed/incomplete model output was withheld. Draft validation checks beat order, speaker consistency, source references, unsupported guest answers, literal direction copying, duplicate cues and production markup. It cannot prove factual accuracy, natural delivery or narrative quality. A URL is attribution metadata, not fetched evidence.

Configure a local model host with `LUMA_STATION_LLM_URL`, `LUMA_STATION_MODEL`, and optionally `LUMA_STATION_LLM_KEY` in its protected runtime environment. Proxy/redirect routing to external endpoints is disabled. No live model output quality is claimed from fake-model integration tests.

## Receiver and pairing

Run the existing `python3 telemetry/server.py` service. It serves the studio and WebSocket protocol on the same port, 8765 by default. Loopback is the default bind. Do not start another receiver on an occupied port.

For LAN access, use a specific private `LUMA_HOST`, `LUMA_TLS_CERT`, `LUMA_TLS_KEY`, and a protected `LUMA_STATION_PAIRING_KEY` of at least 16 characters. No wildcard/public bind or port forwarding is introduced. With a private CA, explicitly install the CA on Android; the Forge preview trusts user-installed and system CAs. The Godot Link panel also accepts a public PEM certificate as an explicit trust anchor. Hostname/IP validation remains enabled; private keys never belong in the client UI.

Browsers served by the receiver, bundled offline files, the Forge Android studio origin and native clients can use the paired contract. Keys stay in memory, are cleared after the handshake, and are excluded from saved templates. Do not place them in Git, gists, URLs or Obsidian.

First message:

```json
{"type":"forge.hello","app_id":"solar-vr","key":"<runtime-pairing-key>"}
```

After `forge.ready`, each request includes a fresh `id` and increasing positive `seq` for that connection. Routed messages use `protocol: "forge.station/1"` and `audio: false`.

| Type | Fields | Result |
| --- | --- | --- |
| `forge.signal` | `format: "morse"`, `text`, optional `target` | Dot/dash string and timing pulses: marks 1/3, inner gaps 1, letter gaps 3, word gaps 7 |
| `forge.signal` | `format: "u8"` or `"u16"`, exactly one of `text` or `values` | Unsigned bytes/code units and hexadecimal representation |
| `forge.context` | `map_context`, optional `target` | Explicit map selection snapshot |
| `forge.program` | `request` | Program result only to its requester |

The default target is `*` for paired peers; a peer ID targets one app. Source identity comes from its pairing session. `forge.ack.delivered` counts peer sockets written, not physical display rendering. Zero means no peer delivery. Old sequences are acknowledged without replay, and disconnected messages are not queued. Legacy button/PTT ACKs remain compatible and the receiver renders no audio.

The 8-/16-bit setting is a data-word format, not PCM or a retro graphics mode. Unsupported Morse and out-of-range numeric words are rejected. These apps do not drive radio-transmitter hardware.

## Validation and remaining physical checks

The build checks Python producer/network/model contracts, JavaScript parity, real browser interactions, Godot parsing and scene behavior, actual Godot-to-Python paired exchange, native Android compilation, APK signatures/alignment/identities/OpenXR metadata, rendered layouts and exported Linux startup.

Physical Quest/controller comfort, device install/runtime, TLS trust setup on the user's LAN, live model editorial quality, and casting between actual devices remain unverified. The original app's PC-only wristwatch/cast/tracking implementation is not in this source snapshot. Keep these separate previews distinct from that original app until those sources and device behaviors are reconciled.
