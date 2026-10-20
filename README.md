# LumaRadio Command Center 0.2.0

A portrait walkie-talkie interface with a rounded radio body, antenna, speaker grille, large hold-to-signal button, honest desktop-link status, mute/volume controls, and Signals / Objectives / Link panels. Alpha through Echo each have a green **Captured** control and a red **Lost** control. All ten objective controls produce distinct locally synthesized tones.

This is a control-and-soundboard preview. **Microphone audio is not transported.** The PTT preview sends pressed/released WebSocket events and plays a local tone. Offline mode is explicitly shown; local sounds remain available without a desktop receiver. Set the WebSocket address under Link when using a compatible receiver. This does not connect to the assistant's cloud voice session.

## Phone installation

Install the companion **Forge Hub 0.1.2-preview** update, then open **Updates → Check Radio Command Center update**. Android asks you to approve installation. Forge verifies the signed publisher manifest, expected package, APK hash, and compatible signer/version when updating an installed Command Center. An existing custom Forge update feed takes priority over the built-in Forge preview feed. Both manifests are hosted on the `command-center-preview` GitHub release.

Command Center uses package `org.lumaradio.commandcenter`, so it installs alongside the old `org.lumaradio.soundboard` preview. The published old preview's original signing key is not available in this checkout; a replacement signed with a different key cannot update that package in place. Forge keeps its existing `org.trickynerdy.forgehub` identity and signing certificate so its saved pairing can survive a normal update. If Forge was uninstalled, pair it with the desktop again after reinstalling.

No phone installation or playback is claimed until tested on a physical device. Runtime checks on Omarchy cover all ten objective button actions and distinct waveforms, PTT release and pause behavior, offline status, mute/volume, invalid-link handling, and native rendered layout. Package checks cover ZIP integrity, APK v2/v3 signatures, expected versions/packages, distinct provider authorities, and 16 KB native-library alignment. Signed feed verification and rejection of a tampered payload are also checked.

## Build

Use Godot 4.7.2, matching Android export templates, a configured JDK/Android SDK, and your preserved private debug keystore. Run:

```bash
godot --headless --path . --script res://tests/smoke_ui.gd
bash tools/build-command-center.sh
```

`tools/fix_android_authority.py` repairs the Android template's duplicate Startup/FileProvider authority before the APK is aligned and signed. Preserve the keystore outside Git for compatible future Command Center updates. An ephemeral CI-generated key must not be used to publish an update over this preview. The existing Android CI workflow exports the legacy package; this preview is built with the dedicated script above.

The companion Forge Android source is included separately with the preview release for reproducibility. No credentials or private signing keys are included in source or release assets.
