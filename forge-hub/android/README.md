# Forge Hub Android preview

Native Android Java MVP, package `org.trickynerdy.forgehub`, minimum Android 8/API 26, target API 35. No Gradle or external runtime dependencies are required. The preview includes a local device profile, the LumaRadio launcher and pinned preview APK installer, signed Forge update feed support, and read-only paired LAN telemetry.

## Build

Install Android SDK platform 35 and build-tools 35.0.0 plus a JDK. Run from the project root:

```bash
ANDROID_SDK_ROOT="$HOME/.cache/forge-hub-sdk" bash tools/build-android.sh
```

Output: `dist/ForgeHub-0.1.0-preview.apk`. A preview signing key is created outside the project at `$HOME/.local/share/forge-hub/forge-preview.keystore`. Keep that file private and preserve it for compatible updates. For release signing set `FORGE_ANDROID_KEYSTORE`, `FORGE_ANDROID_KEY_ALIAS`, and `FORGE_ANDROID_STOREPASS` in the build environment; do not commit private keys or passwords. The default preview key password is for local development only.

The initial 2026-10-17 preview was compiled on Omarchy using Java 26 and Android SDK 35, ZIP integrity and 4-byte alignment checked, and APK v2/v3 signatures verified. Initial APK SHA-256: `048f68106e32dbe27d5516667e81939e3adc332bb4869cf2c296f60dfe9477f8`. Public signing-certificate SHA-256: `8ede24e35be4985370c636dd44afe1a62c48c6e1027dcbe1993b6a1e1df7d5ea`. These are build checks, not a claim of phone runtime validation.

## Install and pair

1. Open the APK on Android and approve the OS installation prompt.
2. Create a local profile if desired. This creates no cloud account and sends no signup request.
3. On the Linux Forge desktop UI, enable LAN access and generate a pairing token.
4. On Android, choose **Pair**, enter the desktop base URL such as `http://192.168.1.20:8787`, and paste the token.
5. Refresh to see a real desktop sample. Unknown CPU, GPU, RAM, or network values remain unavailable, never fabricated.

The Android request is `GET /api/status` with `X-Forge-Token`. HTTP endpoints are restricted in application code to private or loopback addresses. A trusted private LAN is required because HTTP does not encrypt its token; HTTPS endpoints are supported. Android allows cleartext traffic only to support this explicit LAN pairing. The token and profile are stored in private app preferences; Android backup is disabled.

## APK safety and updates

LumaRadio points to the existing `Tricky-Nerdy/LumaRadio` release `v0.1.0-preview`. Its downloaded APK must match SHA-256 `58e7374ad0dc80a8c4982e39888a82a83634ec2b4a8e47ec9d75922b799da56e` and package `org.lumaradio.soundboard`. The APK is downloaded to private cache, then exposed read-only to the Android package installer via a nonexported content provider and a temporary URI grant. No root, device-owner privileges, accessibility service, or silent-install mechanism is used. The user grants Forge permission to request APK installations and approves each package in Android.

The actual published Radio APK was downloaded and inspected during integration: the hash and package match, APK signature verification passes, its manifest reports version 1.0.0 (version code 1), minimum API 24, target API 36, and an ARM64 build. These manifest and signature checks do not establish phone install or playback. The published Radio manifest also assigns the same authority to its FileProvider and InitializationProvider; verify actual behavior on the phone before calling that preview runtime tested. Forge Hub's own APK uses a separate provider authority.

Forge self-updates are opt-in and have no default production feed. Configure an HTTPS URL and a trusted RSA public key (PEM or base64 DER SubjectPublicKeyInfo, minimum 2048 bits). The HTTPS JSON envelope is:

```json
{"payload":"BASE64_OF_EXACT_UTF8_PAYLOAD_BYTES","signature":"BASE64_RSA_SHA256_SIGNATURE_OF_PAYLOAD_BYTES"}
```

The decoded payload is:

```json
{"packageName":"org.trickynerdy.forgehub","versionCode":2,"versionName":"0.1.1","url":"https://publisher.example/ForgeHub-0.1.1.apk","sha256":"64_HEXADECIMAL_CHARACTERS"}
```

The implementation verifies the pinned feed public key, newer version code, APK hash, expected package name, and exact current APK signer set before opening the Android installer. Signing-key rotation is intentionally not supported in this MVP. Feed trust is an explicit publisher trust decision. Download redirects must remain HTTPS, package downloads are capped at 256 MB, and manifest/status responses are capped at 1 MB.

## Honest MVP boundaries

- Local profile only; real cloud signup/authentication is not implemented.
- Android installs and launches the existing Radio preview; it does not run Linux tools.
- Desktop component cards route to desktop setup/pairing, with platform constraints visible.
- Foreground manual update check; no unattended background update schedule.
- The 5-minute news / 2-minute story / 5-minute news / 1-minute promotion rundown is labeled a planned station clock. The hub does not claim a continuous audio stream is running.
- Resource use follows productive work. This app neither allocates arbitrary RAM nor spins CPU/GPU solely to hit a utilization floor.
- Initial APK smoke testing must be completed on a real Android device or emulator before claiming runtime validation.

API references used: Android [PackageManager.canRequestPackageInstalls](https://developer.android.com/reference/android/content/pm/PackageManager#canRequestPackageInstalls()), [ContentProvider](https://developer.android.com/reference/android/content/ContentProvider), and [sharing files securely](https://developer.android.com/training/secure-file-sharing).

## Next phase: Forge Recorder on Samsung Android 13

This is a planned extension, not camera code in the current APK. The user starts recording while the activity is visible, grants camera and optional microphone permission, and gets the normal Android camera/microphone indicators and an ongoing foreground-service notification. Save video locally through MediaStore and show the exact saved destination, available storage, and a working Stop control. No rooting or arbitrary downloaded shell commands are needed.

Suggested files for the next implementation: `RecorderActivity.java` (preview, record/stop, duration/storage, touch lock and torch controls), `RecordingService.java` (foreground camera/microphone lifecycle), `CameraController.java` (Camera2 or a separately chosen CameraX dependency), `RecordingStore.java` (MediaStore local output/finalization), and `res/xml/recorder_preferences.xml`. Add camera/microphone foreground-service declarations and the version-appropriate runtime permissions only when those features are implemented and tested. Do not request camera permissions in this preview.

An in-app touch lock can ignore accidental touches while preserving an explicit unlock gesture; it cannot disable Android's power button or bypass the system keyguard. A keep-screen-on setting uses the activity's `FLAG_KEEP_SCREEN_ON` and only applies while its activity is visible. A user-started recording foreground service is the appropriate candidate for continuing after screen off or device lock, but Samsung camera behavior, thermal limits, battery restrictions, and interruption/finalization must be tested on the actual phone before promising it. Torch is hardware-dependent; while the recording camera is in use it should be controlled through its camera session. Retain a visible recording notification and stop action; do not attempt covert recording or suppress platform indicators.

Official references: [foreground-service types and camera/microphone restrictions](https://developer.android.com/develop/background-work/services/fgs/service-types), [foreground-service declarations](https://developer.android.com/develop/background-work/services/fgs/declare), [Android 11 camera/microphone foreground-service rules](https://developer.android.com/about/versions/11/privacy/foreground-services), and [keep the screen on](https://developer.android.com/develop/background-work/background-tasks/awake/screen-on).

Acceptance checks on the Samsung Android 13 device: visible start/stop and permission denial; touch-lock/unlock; screen-on and screen-off cases; power-button device lock; torch availability; long recording and low-storage handling; interruption by a phone call or another camera app; successful playable local video after each stop/interruption; signed user-confirmed app update without settings loss. State unsupported behavior explicitly.
