#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp pubspec.yaml "$TMP/pubspec.yaml"
cp -R lib "$TMP/lib"

flutter create . --platforms=ios,android --org pl.marekpiatak --project-name live_ride

cp "$TMP/pubspec.yaml" pubspec.yaml
rm -rf lib
cp -R "$TMP/lib" lib

python3 <<'PY'
from pathlib import Path
import plistlib, re

plist_path = Path('ios/Runner/Info.plist')
with plist_path.open('rb') as f:
    p = plistlib.load(f)
p['CFBundleDisplayName'] = 'Live Ride'
p['CFBundleName'] = 'Live Ride'
p['NSLocationWhenInUseUsageDescription'] = 'Live Ride uses your location for cycling navigation and ride recording.'
p['NSLocationAlwaysAndWhenInUseUsageDescription'] = 'Live Ride uses your location in the background so navigation and LIVE tracking continue with the screen locked.'
p['NSBluetoothAlwaysUsageDescription'] = 'Live Ride uses Bluetooth to receive live heart rate from WHOOP and other heart-rate sensors.'
modes = list(dict.fromkeys([*(p.get('UIBackgroundModes') or []), 'location', 'bluetooth-central']))
p['UIBackgroundModes'] = modes
with plist_path.open('wb') as f:
    plistlib.dump(p, f)

pbx = Path('ios/Runner.xcodeproj/project.pbxproj')
lines = []
for line in pbx.read_text().splitlines():
    if 'PRODUCT_BUNDLE_IDENTIFIER =' in line:
        indent = line[:len(line) - len(line.lstrip())]
        if 'RunnerTests' in line:
            line = f'{indent}PRODUCT_BUNDLE_IDENTIFIER = pl.marekpiatak.liveride.RunnerTests;'
        else:
            line = f'{indent}PRODUCT_BUNDLE_IDENTIFIER = pl.marekpiatak.liveride;'
    lines.append(line)
pbx.write_text('\n'.join(lines) + '\n')

for path in Path('android').rglob('*'):
    if not path.is_file():
        continue
    try:
        text = path.read_text()
    except UnicodeDecodeError:
        continue
    new = text.replace('pl.marekpiatak.live_ride', 'pl.marekpiatak.liveride')
    if new != text:
        path.write_text(new)

manifest = Path('android/app/src/main/AndroidManifest.xml')
text = manifest.read_text()
perms = '''    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />\n    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />\n    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />\n    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />\n    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />\n'''
if 'android.permission.BLUETOOTH_SCAN' not in text:
    text = text.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">', '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n' + perms)
text = re.sub(r'android:label="[^"]*"', 'android:label="Live Ride"', text)
manifest.write_text(text)
PY

flutter pub get

echo
echo "Live Ride native shells created."
echo "iOS bundle: pl.marekpiatak.liveride"
echo "Next: open ios/Runner.xcworkspace, choose your Personal Team, then flutter run --release"
