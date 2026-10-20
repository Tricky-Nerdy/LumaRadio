# Forge Solar Station 0.3.0 previews

A silent station workspace inside the existing Forge Hub Android shell, plus a standalone Godot solar map for OpenXR and desktop use. Built from connected Git sources and the published Forge Android source; no PC connection is required for planning, map selection, or signal previews.

## Apps

| Preview | Package / output | Behavior |
| --- | --- | --- |
| Forge Solar Station | `org.trickynerdy.forgehub.solarpreview` | Existing Forge navigation, cards and theme; bundled offline station workspace, templates, schematic solar map and silent signals |
| Luma Forge Solar Map | `org.trickynerdy.lumasolar.preview` | 3D schematic solar map, world selection/focus, desktop travel, OpenXR controller input, in-world Forge station panel and shared network bridge |
| Linux solar preview | `Luma-Forge-Solar-Map.x86_64` | Same solar scene with desktop controls; exported startup is checked headlessly |

These previews install alongside existing apps. CI uses separate development signers; these APKs do not update or replace the original signed Forge/Radio/solar packages. The original update feeds remain unchanged. Do not uninstall a working app to install a preview.

## Station and signals

Mars News, Star News, Talk Hour and Interviews each have a connected running order, one central topic, consistent host/guest inputs, explicit simulation/source labels, and planned segment times. Creative-direction boxes guide the producer instead of becoming dialogue. Save/load templates locally. Source-based drafts need substantive source notes; guest answers need supplied transcript evidence.

Offline mode produces a running order and generation prompt. Actual AI cue-script drafting requires a paired station receiver with a configured local model. A prompt is never labeled as a generated script, and a planned hour is never labeled as measured playback.

Visual Morse supplies exact mark/gap timing data. The 8-/16-bit modes supply unsigned UTF-8 bytes or UTF-16BE code units, including surrogate pairs. New station and solar paths contain no voice, tones, microphone capture, audio files or physical RF output.

Map positions, sizes and orbit spacing are schematic. This preview supplies no live ephemerides or automatically retrieved current news.

## Run and build

```bash
python3 -m pip install -r telemetry/requirements.txt
python3 telemetry/server.py
```

The existing receiver serves its bundled studio at `http://127.0.0.1:8765/` and accepts the shared WebSocket contract on that same port. Pairing and private-LAN TLS settings are in [the integration guide](docs/FORGE_SOLAR_STATION.md). The receiver can run on any supported host.

```bash
python3 tools/build_station_web.py
bash tools/build-forge-station.sh
GODOT_BIN=/path/to/godot bash tools/build-solar-preview.sh
```

Android builds require JDK 17, Android platform/build-tools 35, and Godot 4.7.2 with matching export templates for the solar APK. Hosted builds verify downloaded tooling hashes, APK signatures/alignment/package metadata, exported Linux startup, browser behavior and engine checks.

## Validation

- Python producer, local model HTTP client, paired routing and existing LAN/control regression tests.
- JavaScript/Python format parity and Unicode/Morse codec checks.
- Real browser tests of offline planning, templates, source guard, map selections, pairing, generation responses and no-peer receipts.
- Godot adapter and solar scene smoke tests; actual Godot peers exchange signals/context/program requests with the Python receiver.
- Native Forge Android compilation, both APK signatures/alignment, OpenXR manifest metadata, rendered desktop/phone layouts and exported solar startup.

A physical headset/phone install and live model editorial-quality review remain pending. These builds do not claim to reproduce unavailable PC-only features such as the original solar app's wristwatch, casting implementation, tracking or room reconstruction.

## Source provenance

The Forge Android shell was recovered from the published `ForgeHub-0.1.2-android-source.zip` release, SHA-256 `1ffcbae166bf7b838414689d57ce8f451aef8d5fc99b52aa24547dfdbdc56619`. Its original styles, navigation helpers, local profile, radio launcher and signed-update code are retained. Source is in [forge-hub/](forge-hub/). The new solar scene is a separate preview built from this repository's shared producer and bridge.

The legacy Radio Command Center 0.2.0 source and original Android build path remain available. Its soundboard behavior is separate from the new silent station path.

