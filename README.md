# Live Ride

Live Ride extends [open-wanderer/wanderer](https://github.com/open-wanderer/wanderer) with real-time group ride tracking and cycling telemetry.

The goal is a self-hosted platform combining the useful parts of Komoot and Strava: route planning and sharing, navigation, activity recording and statistics, plus a public live spectator view for friends and family.

## What is implemented in the first vertical slice

- create and join multi-rider Live Ride sessions
- separate participant join code and public spectator token
- GPS position, speed, heading, altitude, accuracy, distance and elevation gain
- batched telemetry and an offline queue that backfills after connectivity returns
- public MapLibre spectator map with rider cards
- route overlay from the Wanderer trail attached to the ride
- WHOOP / generic Bluetooth LE Heart Rate Service support
- iOS and Android Bluetooth permissions
- integration with Wanderer's existing background GPS / Tracelet stream (no second GPS session)
- server-side validation and private-route disclosure protection
- SvelteKit API proxies for the Flutter client and public viewer

## Repository layout

`main` intentionally stays small and reviewable. It contains a reproducible delta on top of Wanderer rather than a copied upstream tree.

- `UPSTREAM_REF` — exact Wanderer commit used as the base
- `PATCH_SHA256` — checksum of the immutable base Live Ride patch
- `patches/live-ride.patch.gz.b64` — compressed base implementation patch
- `patches/post/` — small audited follow-up fixes
- `scripts/assemble.sh` — creates a full working tree from the pinned upstream
- `.github/workflows/assemble.yml` — assembles and validates the project and, on success, publishes the full source to `assembled`

The `assembled` branch is the branch to use for normal development, Codex, IDE checkout and deployment. It contains the complete Wanderer source plus Live Ride changes and preserves the upstream Git history.

## Pinned upstream

- repository: `open-wanderer/wanderer`
- branch used for development: `feature/app`
- commit: `df31dbb6f1b31f8d9369f1d4b05f5cef0a681bce`

## Build locally

```bash
bash scripts/assemble.sh
cd .work/assembled
```

Then the full project is available under `.work/assembled`.

### Web

```bash
cd web
npm ci
npm run check
```

### Backend

```bash
cd db
go test ./...
```

### Flutter

```bash
cd app
flutter pub get
flutter analyze lib/live_ride lib/heart_rate lib/routes/navigation_screen.dart
flutter test test/heart_rate/ble_heart_rate_parser_test.dart
```

## Current architecture

```text
Wanderer mobile (Flutter)
  existing background GPS / navigation
  + BLE Heart Rate (WHOOP or compatible sensor)
        |
        | batched telemetry
        v
SvelteKit /api/v1 proxy
        |
        v
PocketBase + Go Live Ride routes
        |
        +--> history in live_ride_points
        +--> current rider snapshots
        |
        v
Public /live/<share-token>
MapLibre spectator view
```

## Roadmap after the vertical slice is green

1. PocketBase realtime/SSE instead of 3-second spectator polling.
2. Show other riders directly in the mobile navigation map.
3. Rider gap/ETA calculations and distance ahead/behind on route.
4. Persist ride telemetry into richer activity statistics and charts.
5. Cadence and power sensors using the same generic BLE sensor layer.
6. Offline map packaging for event routes.
7. Production map style/self-hosted tiles instead of the temporary viewer style.
8. Activity feed, achievements/records, heatmaps and other Strava-like features.

## License

Wanderer is licensed under AGPL-3.0. This project is a modification of Wanderer and is intended to remain compatible with the upstream license and its source-availability requirements.
