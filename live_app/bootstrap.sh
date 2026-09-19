#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The Lock Screen Live Activity needs an extra Xcode target. Skip it with
# --no-live-activity if you want the plainest possible project.
LIVE_ACTIVITY=1
for arg in "$@"; do
  case "$arg" in
    --no-live-activity) LIVE_ACTIVITY=0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

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
p['NSHealthUpdateUsageDescription'] = (
    'Live Ride saves finished rides to Apple Health as cycling workouts, '
    'only when you ask it to.'
)
p['NSHealthShareUsageDescription'] = (
    'Live Ride does not read health data; this entry is required by iOS '
    'whenever an app links HealthKit.'
)
p['NSMotionUsageDescription'] = (
    'Live Ride uses motion data to keep speed and distance accurate and to '
    'detect a crash while riding.'
)
# The ride computer is read at arm's length on a handlebar mount, so it is
# portrait-and-landscape but never upside down.
p['UISupportedInterfaceOrientations'] = [
    'UIInterfaceOrientationPortrait',
    'UIInterfaceOrientationLandscapeLeft',
    'UIInterfaceOrientationLandscapeRight',
]
modes = list(dict.fromkeys([*(p.get('UIBackgroundModes') or []), 'location', 'bluetooth-central']))
p['UIBackgroundModes'] = modes

# Lock Screen / Dynamic Island ride card.
p['NSSupportsLiveActivities'] = True
p['NSSupportsLiveActivitiesFrequentUpdates'] = True

# Spotify signs in through ASWebAuthenticationSession and returns to this
# scheme. It must match the redirect URI registered in the Spotify dashboard
# and SpotifyService.redirectUri exactly.
url_types = [t for t in (p.get('CFBundleURLTypes') or [])
             if 'liveride' not in (t.get('CFBundleURLSchemes') or [])]
url_types.append({
    'CFBundleTypeRole': 'Editor',
    'CFBundleURLName': 'pl.marekpiatak.liveride',
    'CFBundleURLSchemes': ['liveride'],
})
p['CFBundleURLTypes'] = url_types

# Lets Live Ride tell whether the Spotify app is installed.
# 'sms' i 'tel' są potrzebne alarmowi SOS: bez nich canLaunchUrl zwraca
# false i przycisk wyglądałby na zepsuty.
p['LSApplicationQueriesSchemes'] = sorted(
    set([
        *(p.get('LSApplicationQueriesSchemes') or []),
        'spotify',
        'sms',
        'tel',
    ])
)
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
perms = '''    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />\n    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />\n    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />\n    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />\n    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />\n    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />\n    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />\n    <uses-permission android:name="android.permission.WAKE_LOCK" />\n    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.HIGH_SAMPLING_RATE_SENSORS" />\n    <uses-permission android:name="android.permission.health.WRITE_EXERCISE" />\n    <uses-permission android:name="android.permission.health.WRITE_DISTANCE" />\n    <uses-permission android:name="android.permission.health.WRITE_ACTIVE_CALORIES_BURNED" />\n'''
# Android 11+ wymaga deklaracji, do jakich aplikacji chcemy strzelać
# intentem — bez tego alarm SOS nie znalazłby aplikacji SMS ani telefonu.
entries = (
    '        <intent><action android:name="android.intent.action.SENDTO" />'
    '<data android:scheme="smsto" /></intent>\n'
    '        <intent><action android:name="android.intent.action.DIAL" />'
    '<data android:scheme="tel" /></intent>\n'
    '        <package android:name="com.google.android.apps.healthdata" />\n'
)
if 'android.intent.action.SENDTO' not in text:
    if '<queries>' in text:
        # Szablon Fluttera ma już swój blok <queries> — dokładamy się do
        # niego zamiast dodawać drugi, którego Android i tak by nie przyjął.
        text = text.replace('    </queries>', entries + '    </queries>', 1)
    else:
        text = text.replace(
            '</manifest>',
            '    <queries>\n' + entries + '    </queries>\n</manifest>',
        )

if 'android.permission.BLUETOOTH_SCAN' not in text:
    text = text.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">', '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n' + perms)
text = re.sub(r'android:label="[^"]*"', 'android:label="Live Ride"', text)

# Spotify's PKCE callback needs an activity to come back to on Android; iOS
# handles the same scheme through ASWebAuthenticationSession.
callback = '''        <activity
            android:name="com.linusu.flutter_web_auth_2.CallbackActivity"
            android:exported="true">
            <intent-filter android:label="flutter_web_auth_2">
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="liveride" />
            </intent-filter>
        </activity>
'''
if 'flutter_web_auth_2.CallbackActivity' not in text:
    text = text.replace('    </application>', callback + '    </application>')

manifest.write_text(text)

# --- native iOS sources -------------------------------------------------
import shutil

native = Path('ios_native')
if native.exists():
    Path('ios/LiveRideWidgets').mkdir(parents=True, exist_ok=True)
    for name in ['LiveRideWidgetBundle.swift', 'RideLiveActivity.swift', 'Info.plist']:
        shutil.copy(native / 'LiveRideWidgets' / name, Path('ios/LiveRideWidgets') / name)
    # The attributes file is compiled into both targets, so it is copied twice
    # rather than referenced across directories.
    shutil.copy(native / 'Shared' / 'RideActivityAttributes.swift',
                Path('ios/LiveRideWidgets/RideActivityAttributes.swift'))
    shutil.copy(native / 'Shared' / 'RideActivityAttributes.swift',
                Path('ios/Runner/RideActivityAttributes.swift'))
    shutil.copy(native / 'Runner' / 'LiveRideActivityBridge.swift',
                Path('ios/Runner/LiveRideActivityBridge.swift'))

# --- register the bridge in AppDelegate ---------------------------------
delegate_path = Path('ios/Runner/AppDelegate.swift')
delegate = delegate_path.read_text()
if 'LiveRideActivityBridge' not in delegate:
    delegate = delegate.replace(
        'class AppDelegate: FlutterAppDelegate',
        'class AppDelegate: FlutterAppDelegate',
    )
    # Hold a strong reference: the bridge owns the method channel handler.
    delegate = re.sub(
        r'(@objc class AppDelegate: [^\n]*\{\n)',
        r'\1  /// Live Ride: keeps the Lock Screen activity channel alive.\n'
        r'  private var liveActivityBridge: LiveRideActivityBridge?\n\n',
        delegate,
        count=1,
    )

    if 'didInitializeImplicitFlutterEngine' in delegate:
        # Flutter's current template wires plugins through the implicit engine.
        delegate = delegate.replace(
            'GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)',
            'GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)\n'
            '    if let registrar = engineBridge.pluginRegistry.registrar(\n'
            '      forPlugin: "LiveRideActivityBridge"\n'
            '    ) {\n'
            '      liveActivityBridge = LiveRideActivityBridge.register(\n'
            '        with: registrar.messenger()\n'
            '      )\n'
            '    }',
        )
    else:
        delegate = delegate.replace(
            'return super.application(application, didFinishLaunchingWithOptions: launchOptions)',
            'let started = super.application(\n'
            '      application, didFinishLaunchingWithOptions: launchOptions)\n'
            '    if let controller = window?.rootViewController as? FlutterViewController {\n'
            '      liveActivityBridge = LiveRideActivityBridge.register(\n'
            '        with: controller.binaryMessenger\n'
            '      )\n'
            '    }\n'
            '    return started',
        )
    delegate_path.write_text(delegate)
PY

if [ "$LIVE_ACTIVITY" = "1" ]; then
  if ruby -e 'require "xcodeproj"' >/dev/null 2>&1; then
    ruby ios_native/scripts/add_live_activity_target.rb ios pl.marekpiatak.liveride
  else
    echo
    echo "WARNING: the 'xcodeproj' gem is missing, so the Live Activity widget"
    echo "target was not added. It ships with CocoaPods; install it with:"
    echo "    sudo gem install xcodeproj"
    echo "then re-run ./bootstrap.sh. Everything else still works."
  fi
fi

flutter pub get

echo
echo "Live Ride native shells created."
echo "iOS bundle: pl.marekpiatak.liveride"
echo "Configured: location (incl. background), Bluetooth, foreground service,"
echo "            wake lock, Live Activities, liveride:// callback for Spotify."
if [ "$LIVE_ACTIVITY" = "1" ]; then
  echo "Widget extension: pl.marekpiatak.liveride.LiveRideWidgets (iOS 16.2+)"
fi
echo "Next: open ios/Runner.xcworkspace, choose your Personal Team for BOTH"
echo "      targets, then flutter run --release"
if [ "$LIVE_ACTIVITY" = "1" ]; then
  echo
  echo "The widget is embedded BEFORE Flutter's Thin Binary phase, which is"
  echo "what keeps Xcode from reporting 'Cycle inside Runner'. If a future"
  echo "pod install or Xcode upgrade ever puts it back, re-apply the order"
  echo "without touching the target:"
  echo "    ruby ios_native/scripts/add_live_activity_target.rb ios --order-only"
fi
