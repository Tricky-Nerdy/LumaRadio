#!/usr/bin/env bash
set -euo pipefail
FORGE_STATION_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORGE_STATION_SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
FORGE_STATION_BT="$FORGE_STATION_SDK/build-tools/35.0.0"
FORGE_STATION_JAR="$FORGE_STATION_SDK/platforms/android-35/android.jar"
FORGE_STATION_OUT="$FORGE_STATION_ROOT/build/forge-station"
FORGE_STATION_APP_ID="org.trickynerdy.forgehub.solarpreview"
mkdir -p "$FORGE_STATION_OUT/classes" "$FORGE_STATION_OUT/generated" "$FORGE_STATION_OUT/dex" "$FORGE_STATION_ROOT/dist"
python3 "$FORGE_STATION_ROOT/tools/build_station_web.py"
python3 - "$FORGE_STATION_ROOT/forge-hub/android/AndroidManifest.xml" "$FORGE_STATION_OUT/AndroidManifest.xml" "$FORGE_STATION_APP_ID" <<'PY'
import sys,xml.etree.ElementTree as ET
android='{http://schemas.android.com/apk/res/android}'
ET.register_namespace('android','http://schemas.android.com/apk/res/android')
tree=ET.parse(sys.argv[1]);root=tree.getroot();root.set('package',sys.argv[3])
root.set(android+'versionCode','30');root.set(android+'versionName','0.3.0-solar-preview')
app=root.find('application');app.set(android+'label','Forge Solar Station (preview)')
app.find('activity').set(android+'name','org.trickynerdy.forgehub.MainActivity')
provider=app.find('provider');provider.set(android+'name','org.trickynerdy.forgehub.ApkProvider');provider.set(android+'authorities',sys.argv[3]+'.apks')
tree.write(sys.argv[2],encoding='utf-8',xml_declaration=True)
PY
"$FORGE_STATION_BT/aapt2" compile --dir "$FORGE_STATION_ROOT/forge-hub/android/res" -o "$FORGE_STATION_OUT/resources.zip"
"$FORGE_STATION_BT/aapt2" link -o "$FORGE_STATION_OUT/base.apk" -I "$FORGE_STATION_JAR" \
  --manifest "$FORGE_STATION_OUT/AndroidManifest.xml" --java "$FORGE_STATION_OUT/generated" \
  --min-sdk-version 26 --target-sdk-version 35 -A "$FORGE_STATION_ROOT/forge-hub/android/assets" "$FORGE_STATION_OUT/resources.zip"
find "$FORGE_STATION_ROOT/forge-hub/android/src" "$FORGE_STATION_OUT/generated" -name '*.java' -print > "$FORGE_STATION_OUT/sources.txt"
javac -encoding UTF-8 -source 8 -target 8 -classpath "$FORGE_STATION_JAR" -d "$FORGE_STATION_OUT/classes" @"$FORGE_STATION_OUT/sources.txt"
jar cf "$FORGE_STATION_OUT/classes.jar" -C "$FORGE_STATION_OUT/classes" .
"$FORGE_STATION_BT/d8" --min-api 26 --lib "$FORGE_STATION_JAR" --output "$FORGE_STATION_OUT/dex" "$FORGE_STATION_OUT/classes.jar"
python3 - "$FORGE_STATION_OUT/base.apk" "$FORGE_STATION_OUT/dex" <<'PY'
import pathlib,sys,zipfile
with zipfile.ZipFile(sys.argv[1],'a',zipfile.ZIP_DEFLATED) as z:
    for p in pathlib.Path(sys.argv[2]).glob('*.dex'):z.write(p,p.name)
PY
"$FORGE_STATION_BT/zipalign" -f -p 4 "$FORGE_STATION_OUT/base.apk" "$FORGE_STATION_OUT/aligned.apk"
# CI preview identity is separate from the installed Forge app and its private signer.
keytool -genkeypair -noprompt -keystore "$FORGE_STATION_OUT/preview.keystore" -alias solar-preview \
  -keyalg RSA -keysize 3072 -validity 365 -storepass android -keypass android \
  -dname 'CN=Forge Solar Build Preview'
"$FORGE_STATION_BT/apksigner" sign --ks "$FORGE_STATION_OUT/preview.keystore" --ks-key-alias solar-preview \
  --ks-pass pass:android --out "$FORGE_STATION_ROOT/dist/Forge-Solar-Station-0.3.0-preview.apk" "$FORGE_STATION_OUT/aligned.apk"
"$FORGE_STATION_BT/apksigner" verify --verbose --print-certs "$FORGE_STATION_ROOT/dist/Forge-Solar-Station-0.3.0-preview.apk"
"$FORGE_STATION_BT/zipalign" -c -p 4 "$FORGE_STATION_ROOT/dist/Forge-Solar-Station-0.3.0-preview.apk"
sha256sum "$FORGE_STATION_ROOT/dist/Forge-Solar-Station-0.3.0-preview.apk" > "$FORGE_STATION_ROOT/dist/Forge-Solar-Station-SHA256.txt"
