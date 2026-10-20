# Forge Android source and Solar Station preview

Recovered from the published Forge Hub 0.1.2 Android source archive, SHA-256 `1ffcbae166bf7b838414689d57ce8f451aef8d5fc99b52aa24547dfdbdc56619`.

The original Java package, UI helper methods, card/theme/navigation system, local profile, Radio launcher, APK provider and signed update checks are retained. Solar Station is an added offline workspace in that shell. No camera, microphone, audio engine, remote shell or JavaScript-to-Java bridge is introduced.

Build the companion preview from the repository root:

```bash
python3 tools/build_station_web.py
bash tools/build-forge-station.sh
```

The script stages a manifest using package `org.trickynerdy.forgehub.solarpreview`, unique provider authority and a development signer. It produces `dist/Forge-Solar-Station-0.3.0-preview.apk`. This installs alongside the original Forge app and cannot update its signed package. CI development signers are not production update keys; preserve the original private publisher keys separately.

The offline HTML asset is generated from the shared station formats, producer instructions and codecs. Browser tests verify its planning, templates, source checks, solar selection, Unicode signals, pairing and receiver responses. Android compilation/signature checks do not establish successful phone installation.

The original `forge-hub/tools/build-android.sh` remains as recovered source and uses its original identity/output conventions. Do not use it to publish an update without the original signing key and a reviewed version/feed change.
