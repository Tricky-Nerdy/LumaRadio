# LumaRadio local Wi-Fi audio and debug telemetry protocol (draft)

Goal: a **consent-based local-network radio**, connecting Android (Termux optional), Windows/Omarchy, and the Luma Discord bot's audio bridge without exposing either device to the public internet.

## Trust boundaries
- **Opt-in**: no remote listening or transmission until the user explicitly enables it on the device. Display a persistent RX/TX indicator, a mute/stop control, and current peer.
- **LAN only by default**: bind PC receiver to its LAN interface, firewall allowlist the phone, and use an authenticated encrypted channel (e.g. TLS WebSocket with paired key or WireGuard). Do not disable TLS verification or expose arbitrary command execution.
- **Audio directions**: phone → PC (push-to-talk); PC → phone (receive/play); PC → Discord only after the bot's voice permissions and routing are verified. LM Studio processes text, not raw audio; STT/TTS or PCM routing is a separate subsystem.
- **Soundboard**: locally generated effects can be played on phone or sent as an explicitly initiated event to the paired PC, which generates the same effect. Use timestamps, sequence numbers, acknowledgments, jitter buffering and volume limits.
- **Debug telemetry only**: JSONL records with UTC timestamp, session, platform, event, peer ID, latency, underrun/drop count and errors. Do not store microphone audio by default. Release builds have no application telemetry.
- **Termux**: optional companion to collect app logs via supported methods, check Wi-Fi reachability and exchange diagnostic files with Omarchy. A normal app cannot silently grant itself ADB or Termux permissions, and reinstalling an APK does not establish remote access.
- **Verification**: test RX/TX separately on LAN, mute/disconnect behavior, packet loss and reconnects, no traffic with remote mode disabled, and debug/release log behavior.

## Status
This is an architecture contract, **not an implemented or verified audio connection**. Current Pygame code is an offline soundboard. The bot has previously shown a model-startup restart loop; do not depend on its health for the standalone app.
