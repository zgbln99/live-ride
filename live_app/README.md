# Live Ride — clean mobile app

This is the new standalone Flutter client. It does not use the old mobile UI, routing, layouts, or components.

## What is already in this clean client

- fixed Live Ride server: `https://ride.76-13-3-214.sslip.io`
- PocketBase/Wanderer-compatible login API, without exposing old branding
- direct GPX import from iOS Files / iCloud and Android file providers
- local GPX library stored in the app documents directory
- Valhalla turn-by-turn navigation through `/api/v1/valhalla/navigate`
- MapLibre + Live Ride route styling
- Garmin-style navigation layout: maneuver / map / Speed + Distance
- always-visible Exit / LIVE / Settings / Recenter controls
- LIVE session create/join/share/stop
- telemetry upload every ~3 seconds while navigating
- WHOOP / generic BLE Heart Rate Service scanning and live BPM

## First setup on Mac

```bash
cd live_app
chmod +x bootstrap.sh
./bootstrap.sh
```

The bootstrap generates fresh iOS/Android shells and then restores the Live Ride source code. It also configures:

- app display name: `Live Ride`
- iOS bundle id: `pl.marekpiatak.liveride`
- location permissions
- background location
- Bluetooth / WHOOP permission
- Android BLE/location permissions

Then:

```bash
open ios/Runner.xcworkspace
```

In Xcode choose **Runner → Signing & Capabilities → Automatically manage signing → your Personal Team**.

Run:

```bash
flutter run --release
```

## Important

The old `app/` directory is intentionally untouched while the clean client is being proven on-device. Once this client has passed GPX, WHOOP, navigation, and LIVE tests, the old mobile client can be archived/removed.
