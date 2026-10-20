#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/.cache/forge-hub-sdk}}"
PLATFORM="${FORGE_ANDROID_PLATFORM:-35}"
BUILD_TOOLS="${FORGE_ANDROID_BUILD_TOOLS:-35.0.0}"
BT="$SDK/build-tools/$BUILD_TOOLS"
JAR="$SDK/platforms/android-$PLATFORM/android.jar"
OUT="$ROOT/android/build"
KEYSTORE="${FORGE_ANDROID_KEYSTORE:-$HOME/.local/share/forge-hub/forge-preview.keystore}"
ALIAS="${FORGE_ANDROID_KEY_ALIAS:-forge-preview}"
STOREPASS="${FORGE_ANDROID_STOREPASS:-android}"
for name in aapt2 d8 zipalign apksigner; do
    test -x "$BT/$name" || { echo "Missing Android SDK tool: $BT/$name" >&2; exit 1; }
done
test -f "$JAR" || { echo "Missing Android platform: $JAR" >&2; exit 1; }
for name in javac java jar keytool; do command -v "$name" >/dev/null || { echo "Missing JDK tool: $name" >&2; exit 1; }; done
mkdir -p "$OUT/classes" "$OUT/generated" "$OUT/dex" "$ROOT/dist"
rm -f "$OUT/resources.zip" "$OUT/base.apk" "$OUT/aligned.apk" "$OUT/classes.jar"
"$BT/aapt2" compile --dir "$ROOT/android/res" -o "$OUT/resources.zip"
"$BT/aapt2" link -o "$OUT/base.apk" -I "$JAR" --manifest "$ROOT/android/AndroidManifest.xml" \
    --java "$OUT/generated" --min-sdk-version 26 --target-sdk-version 35 "$OUT/resources.zip"
find "$ROOT/android/src" "$OUT/generated" -name '*.java' -print > "$OUT/sources.txt"
javac -encoding UTF-8 -source 8 -target 8 -classpath "$JAR" -d "$OUT/classes" @"$OUT/sources.txt"
jar cf "$OUT/classes.jar" -C "$OUT/classes" .
"$BT/d8" --min-api 26 --lib "$JAR" --output "$OUT/dex" "$OUT/classes.jar"
python3 - "$OUT/base.apk" "$OUT/dex" <<'PY'
import pathlib,sys,zipfile
with zipfile.ZipFile(sys.argv[1], 'a', zipfile.ZIP_DEFLATED) as apk:
    for dex in pathlib.Path(sys.argv[2]).glob('*.dex'):
        apk.write(dex,dex.name)
PY
"$BT/zipalign" -f -p 4 "$OUT/base.apk" "$OUT/aligned.apk"
if ! test -f "$KEYSTORE"; then
    mkdir -p "$(dirname "$KEYSTORE")"
    keytool -genkeypair -keystore "$KEYSTORE" -alias "$ALIAS" -keyalg RSA -keysize 3072 \
        -validity 10000 -storepass "$STOREPASS" -keypass "$STOREPASS" \
        -dname 'CN=Forge Hub Preview, OU=Personal Workshop, O=Tricky Nerdy'
    chmod 600 "$KEYSTORE"
fi
export FORGE_SIGNING_PASSWORD="$STOREPASS"
"$BT/apksigner" sign --ks "$KEYSTORE" --ks-key-alias "$ALIAS" --ks-pass env:FORGE_SIGNING_PASSWORD \
    --key-pass env:FORGE_SIGNING_PASSWORD --out "$ROOT/dist/ForgeHub-0.1.0-preview.apk" "$OUT/aligned.apk"
"$BT/apksigner" verify --verbose --print-certs "$ROOT/dist/ForgeHub-0.1.0-preview.apk"
sha256sum "$ROOT/dist/ForgeHub-0.1.0-preview.apk"
echo "Built: $ROOT/dist/ForgeHub-0.1.0-preview.apk"
