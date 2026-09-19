# Live Ride — mobile app

Live Ride is a self-hosted cycling platform. This package is the rider-facing
Flutter client: a cycling computer, a GPX navigator, a ride recorder and a LIVE
broadcaster. It shares a server with the web project in `../web`, but none of
its UI, layouts or components.

Server: `https://ride.76-13-3-214.sslip.io` (override with
`--dart-define=LIVE_RIDE_SERVER=…`).

## What it does

**Ride computer** — One screen serves a free ride and a navigated route, so the
instrument never changes between them. Configurable Garmin-style data fields
(2, 4, 6 or 8), large tabular numerals, hairline separators, no decoration.
Fields available: speed, average speed, max speed, distance, elapsed, moving
time, elevation, ascent, gradient, heart rate, average HR, max HR, GPS
accuracy, temperature, wind, rain chance, time of day, remaining distance, ETA.

**Quiet mode** — Five seconds after the last touch the ride computer stops
being an app. The secondary controls fade out, the control bar collapses and
gives its space to the map, and what remains is the instrument: map, route,
rider, next turn, distance left, ETA and every data field. One tap anywhere
brings the controls straight back. Retiring is unhurried (420 ms); returning is
near-instant (150 ms). Hidden chrome stops accepting touches the moment it
starts fading, so a tap can never land on a half-transparent FINISH button.
Nothing retires while the ride is paused, while a sheet or dialog is open, or
while an error is showing; the recenter button stays up whenever the map is not
following the rider, and the GPS/LIVE strip stays up whenever it is carrying a
warning rather than a reassurance. The gesture is explained once per ride with
a small note that fades itself out.

**Navigation** — Valhalla map-matched turn-by-turn on top of an imported GPX:
maneuver arrow, distance to the turn, instruction, street name, remaining
distance and ETA. Route progress comes from projecting the rider onto the route
geometry, never from the straight line to the finish, and the same projection
drives the off-route warning. If the routing service is unreachable the raw GPX
is navigated instead and the header says so rather than pretending.

**Map and GPS** — The rider marker is a real map marker bound to its
geographic coordinates. Follow mode keeps the camera on the rider; a manual pan
turns it off; the recenter button turns it back on. With heading-up enabled the
camera bearing follows the rider and the marker is rotated by
`heading − camera bearing`, so it is never rotated twice.

**Ride recording** — Start, pause, resume, finish. Rides survive screen
rebuilds and tab switches because the recorder is a single long-lived service,
not screen state. On finish the ride is saved locally with its full track and
can be exported as GPX (with heart rate in the Garmin TrackPointExtension).

**GPX import** — A tolerant streaming parser: unknown namespaces, extension
blocks, multiple tracks and segments, `rte`/`wpt` fallbacks, malformed
elevation and time values, UTF-16 and BOM-prefixed files, truncated downloads
and very large tracks. Files that arrive as bytes, as a path or as a stream are
all handled, and a file iCloud has not materialised yet produces a message that
says exactly that. Import failures never report a generic error.

**LIVE** — Start or join a session, share one spectator link, see the join
code, rider name, speed, distance and HR. Telemetry uploads every three seconds
while recording and a failed upload never interrupts the ride.

**Weather** — Open-Meteo by default: no API key, no account. Temperature, feels
like, wind speed and direction, precipitation probability and condition, shown
as a map widget and as data fields. Weather is never awaited on a path that
matters; when it fails the fields read `--`.

**Profile** — Display name, username, units, heading-up, screen-awake, weather
and the data field layout. The display name falls back to the account username,
and is what LIVE spectators and saved rides show. "Rider" appears only when the
account carries no identity at all.

## Metric quality

Raw GPS lies, so the accumulator (`lib/core/ride_metrics_accumulator.dart`)
applies explicit rules, each covered by tests:

- fixes worse than 60 m accuracy are dropped once there is a fix;
- steps implying more than 30 m/s are rejected, and three in a row are treated
  as a re-acquisition that resynchronises without crediting distance;
- a drift gate scaled to the reported accuracy stops a parked bike accumulating
  metres, unless a confident speed reading says the rider is moving;
- moving time only accrues above 3.6 km/h, so average speed is a riding
  average and not a stop-inclusive one;
- elevation is exponentially smoothed with 3 m hysteresis before ascent counts;
- gradient is measured over roughly 120 m of road, clamped to ±35 %.

## Layout

```
lib/
  core/      geo maths, metric accumulator, idle-chrome controller, API
             client, theme, formatters
  models/    route, navigation plan, ride record, metrics, profile, weather
  services/  gpx, route library, ride recorder, storage, profile, weather,
             live, heart rate, location, local store, service container
  screens/   ride computer, home shell + tabs, route detail, ride summary,
             login, live sheet, data field editor
  widgets/   navigation header, ride map, data grid, controls, chrome fade,
             weather field, track preview, elevation profile, primitives
```

Persistence is plain JSON and GPX files under the app documents directory:
`profile/profile.json`, `routes/index.json` plus one GPX per route, and one
JSON per ride under `rides/`. Writes go through a temporary file and a rename,
so an interrupted write cannot corrupt an index.

## First setup on a Mac

```bash
cd live_app
chmod +x bootstrap.sh
./bootstrap.sh
```

The bootstrap generates fresh iOS/Android shells and restores the Live Ride
source. It configures the display name, the iOS bundle id
(`pl.marekpiatak.liveride`), location and background-location permissions,
Bluetooth, the Android foreground-service and wake-lock permissions, and the
supported orientations.

In Xcode choose **Runner → Signing & Capabilities → Automatically manage
signing → your Personal Team**, then:

```bash
flutter pub get
flutter analyze
flutter test
flutter run --release
```

## Build-time configuration

| Define | Default | Purpose |
| --- | --- | --- |
| `LIVE_RIDE_SERVER` | `https://ride.76-13-3-214.sslip.io` | Live Ride server origin |
| `LIVE_RIDE_WEATHER_URL` | `https://api.open-meteo.com/v1/forecast` | Weather endpoint |
| `LIVE_RIDE_WEATHER_KEY` | *(empty)* | Only for providers that need a key |

No secret is compiled in. The default weather provider needs no key; supply one
only if you point the app at a paid or self-hosted endpoint:

```bash
flutter run --release \
  --dart-define=LIVE_RIDE_WEATHER_URL=https://example.com/v1/forecast \
  --dart-define=LIVE_RIDE_WEATHER_KEY=…
```

## Known limits

- Quiet mode hides Live Ride's own controls, not the operating system status
  bar. Hiding that too is a one-line change if you would rather see nothing but
  the instrument, at the cost of the clock and the battery indicator.
- Background recording depends on the rider granting "Always"/background
  location. Without it the platform suspends updates with the screen locked and
  the ride resumes when the app returns to the foreground. Nothing in the app
  assumes otherwise.
- Map tiles are fetched from the server; there is no offline tile cache yet. A
  ride with no tiles still records and still shows every number and maneuver.
- Turn-by-turn instructions require the server's Valhalla endpoint. Without it
  the imported track is navigated without turn callouts.
- The LIVE spectator page shows a planned route only when the session was
  attached to a server-side trail; a GPX imported on the phone stays local.
