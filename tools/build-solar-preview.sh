#!/usr/bin/env bash
set -euo pipefail
SOLAR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOLAR_GODOT="${GODOT_BIN:-godot}"
SOLAR_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
SOLAR_TOOLS="$SOLAR_SDK/build-tools/35.0.0"
SOLAR_OUT="$SOLAR_ROOT/build/solar-export"
mkdir -p "$SOLAR_OUT" "$SOLAR_ROOT/dist"
export SOLAR_PREVIEW_KEYSTORE="$SOLAR_OUT/preview.keystore"
if ! test -f "$SOLAR_PREVIEW_KEYSTORE"; then
  keytool -genkeypair -noprompt -keystore "$SOLAR_PREVIEW_KEYSTORE" -alias androiddebugkey \
    -keyalg RSA -keysize 3072 -validity 365 -storepass android -keypass android \
    -dname 'CN=Luma Forge Solar Build Preview'
fi
python3 - <<'PY'
from pathlib import Path
import json,os
directory=Path(os.environ.get('XDG_CONFIG_HOME',str(Path.home()/'.config')))/'godot'
directory.mkdir(parents=True,exist_ok=True)
settings={'export/android/android_sdk_path':os.environ.get('ANDROID_HOME',os.environ.get('ANDROID_SDK_ROOT','')),
          'export/android/java_sdk_path':os.environ['JAVA_HOME'],
          'export/android/debug_keystore':os.environ['SOLAR_PREVIEW_KEYSTORE'],
          'export/android/debug_keystore_user':'androiddebugkey',
          'export/android/debug_keystore_pass':'android'}
(directory/'editor_settings-4.7.tres').write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'+''.join(k+' = '+json.dumps(v)+'\n' for k,v in settings.items()))
PY
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$SOLAR_PREVIEW_KEYSTORE"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android
"$SOLAR_GODOT" --headless --path "$SOLAR_ROOT" --export-debug 'Android Solar Preview' "$SOLAR_OUT/raw.apk"
python3 "$SOLAR_ROOT/tools/fix_android_authority.py" "$SOLAR_OUT/raw.apk" "$SOLAR_OUT/unsigned.apk" --authority org.trickynerdy.lumasolar.preview.androidx-startup
"$SOLAR_TOOLS/zipalign" -f -P 16 4 "$SOLAR_OUT/unsigned.apk" "$SOLAR_OUT/aligned.apk"
"$SOLAR_TOOLS/apksigner" sign --ks "$SOLAR_PREVIEW_KEYSTORE" --ks-key-alias androiddebugkey --ks-pass pass:android \
  --out "$SOLAR_ROOT/dist/Luma-Forge-Solar-Map-0.3.0-preview.apk" "$SOLAR_OUT/aligned.apk"
"$SOLAR_TOOLS/apksigner" verify --verbose --print-certs "$SOLAR_ROOT/dist/Luma-Forge-Solar-Map-0.3.0-preview.apk"
"$SOLAR_TOOLS/zipalign" -c -P 16 4 "$SOLAR_ROOT/dist/Luma-Forge-Solar-Map-0.3.0-preview.apk"
"$SOLAR_TOOLS/aapt" dump badging "$SOLAR_ROOT/dist/Luma-Forge-Solar-Map-0.3.0-preview.apk" > "$SOLAR_ROOT/dist/Solar-APK-metadata.txt"
grep "name='org.trickynerdy.lumasolar.preview'" "$SOLAR_ROOT/dist/Solar-APK-metadata.txt"
grep "name='android.hardware.vr.headtracking'" "$SOLAR_ROOT/dist/Solar-APK-metadata.txt"
if grep "android.permission.RECORD_AUDIO" "$SOLAR_ROOT/dist/Solar-APK-metadata.txt"; then exit 1; fi
"$SOLAR_TOOLS/aapt" dump xmltree "$SOLAR_ROOT/dist/Luma-Forge-Solar-Map-0.3.0-preview.apk" AndroidManifest.xml > "$SOLAR_ROOT/dist/Solar-manifest.txt"
grep -E 'IMMERSIVE_HMD|com.oculus.intent.category.VR' "$SOLAR_ROOT/dist/Solar-manifest.txt"
"$SOLAR_GODOT" --headless --path "$SOLAR_ROOT" --export-debug 'Linux Solar Preview' "$SOLAR_ROOT/dist/Luma-Forge-Solar-Map.x86_64"
chmod +x "$SOLAR_ROOT/dist/Luma-Forge-Solar-Map.x86_64"
timeout 30 "$SOLAR_ROOT/dist/Luma-Forge-Solar-Map.x86_64" --headless --xr-mode off --quit-after 5 2>&1 | tee "$SOLAR_ROOT/dist/Solar-export-launch.log"
if grep -E 'SCRIPT ERROR|Parse Error|Failed to load script' "$SOLAR_ROOT/dist/Solar-export-launch.log"; then exit 1; fi
grep 'SOLAR_PREVIEW_READY bodies=9 audio_nodes=0' "$SOLAR_ROOT/dist/Solar-export-launch.log"
cd "$SOLAR_ROOT/dist"
sha256sum Luma-Forge-Solar-Map-0.3.0-preview.apk Luma-Forge-Solar-Map.x86_64 > Solar-SHA256.txt
