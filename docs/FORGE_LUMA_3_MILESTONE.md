# Forge / LumaRadio — Luma 3.0 integration milestone

**Project suite:** Forge. **App:** LumaRadio. **Assistant call sign:** Luma Actual. **User:** Gracie Zero One. **Android:** Luma Zero Two. **Discord bot:** Luma Zero Five.

**Status:** Design requirements recorded, not yet a functioning multi-party audio system. Luma 3.0 is a proposed milestone after end-to-end acceptance tests, not a deployed version.

## Primary interface
- Large, centrally placed **push-to-talk microphone** button with press-and-hold operation, clear pressed/transmitting indication, release-to-stop, and an accessible toggle alternative.
- Handheld walkie-talkie appearance: square geometric-icon buttons from the 64-tile atlas, LCD channel/status display, large readable labels, alarm/squawk/static/blaster soundboard, local contained lightbar, brightness and volume controls.
- Dedicated mute, disconnect, receive-only, and emergency stop controls. No recording or sending audio without user activation and permissions.

## Audio behavior
- Phone speaker and Bluetooth headset support, with explicit output selection where the OS permits.
- Respect Android audio focus, Bluetooth routing, call priority, and microphone permission. When a cellular call or another app owns the microphone, **do not promise simultaneous capture or mixing**. Support pause, ducking, and handoff when required.
- Friends and family may join a shared, explicitly authorized room, or have separate Luma instances with independent identity, privacy, permissions and keys. Never automatically join private calls or expose conversation audio to third parties.
- Discord voice integration through the bot after confirming consent and bot permissions. LM Studio can generate text responses; separate STT/TTS/audio bridge handles speech.
- LAN-first pairing with device keys, authenticated commands, replay protection, and opt-in remote microphone/audio; do not infer remote listening capability from successful event-telemetry tests.

## Acceptance criteria for Luma 3.0
1. Android APK and Windows package both install and launch.
2. Central PTT records only while pressed, transmits to paired peer, and stops on release, disconnect, or lost focus.
3. Receive audio plays through phone speaker or selected Bluetooth device, without hijacking an active phone call.
4. Concurrent-app behavior is tested against actual Android/Discord limitations.
5. Icons, sounds, lightbar, menus, and telemetry work in debug; release has no application telemetry.
6. Device-to-device pairing, user opt-in, mute, and privacy boundaries are tested.
7. Discord bridge and optional local LM Studio speech round-trip are separately verified.
8. Every claimed feature has actual test evidence, not only an implementation plan.

## Next development slice
Implement central PTT UI and audio-focus behavior in the Pygame prototype. Validate locally; then select a supported Android packaging/runtime strategy before promising an APK.
