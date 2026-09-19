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

**WHOOP and heart rate** — A dedicated sensor screen: live BPM with a trace,
battery, signal strength, skin-contact state, and the four WHOOP steps that
actually matter (a WHOOP strap does not advertise heart rate until Broadcast
Heart Rate is switched on, which is why it looks missing). The connection is
owned by a service, not a screen, so it survives navigation and reconnects by
itself with backoff when the strap drops out mid-ride.

**Music** — Spotify sign-in with Authorization Code + PKCE, running in
`ASWebAuthenticationSession` on iOS, so no client secret is compiled in and the
Spotify cookie is never handed to Live Ride. Now playing with live progress,
transport controls sized for a gloved thumb, device switching, shuffle, volume,
and your recently played and playlists to start from. A compact music sheet is
one tap from the ride screen.

**Lock Screen Live Activity** — A real WidgetKit extension with ActivityKit, so
a ride shows speed, distance, elapsed, heart rate and the next turn on the Lock
Screen and in the Dynamic Island. It starts and ends with the ride, not with a
screen. Every value is preformatted in Dart, so the widget has no unit logic of
its own to disagree with the handlebar.

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
             live, heart rate, spotify, live activity, location, local
             store, service container
  screens/   ride computer, home shell + tabs, route detail, ride summary,
             login, WHOOP, live sheet, music sheet, data field editor
  widgets/   navigation header, ride map, data grid, controls, chrome fade,
             weather field, music controls, bpm trace, track preview,
             elevation profile, primitives

ios_native/  Swift sources copied into the generated ios/ by bootstrap.sh
  Shared/            RideActivityAttributes.swift (app + widget)
  Runner/            LiveRideActivityBridge.swift (method channel)
  LiveRideWidgets/   widget bundle, Lock Screen UI, extension Info.plist
  scripts/           add_live_activity_target.rb (adds the Xcode target)
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
| `LIVE_RIDE_SPOTIFY_CLIENT_ID` | *(empty)* | Optional; can also be pasted in the app |

No secret is compiled in. The default weather provider needs no key; supply one
only if you point the app at a paid or self-hosted endpoint:

```bash
flutter run --release \
  --dart-define=LIVE_RIDE_WEATHER_URL=https://example.com/v1/forecast \
  --dart-define=LIVE_RIDE_WEATHER_KEY=…
```

## Spotify setup

Spotify requires every app to use its own client ID, so Live Ride ships without
one. Setting it up takes a minute and does not need a rebuild — the Music tab
has a field for it.

1. Open [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard)
   and create an app (the free tier is enough).
2. Add this redirect URI **exactly**:

   ```
   liveride://spotify-callback
   ```

3. Tick **Web API** and save.
4. Paste the client ID into the Music tab, or build with
   `--dart-define=LIVE_RIDE_SPOTIFY_CLIENT_ID=…`.

Playback control needs Spotify **Premium** — that is Spotify's rule for any
third-party app, not a Live Ride limitation. Reading what is playing works on
free accounts. Spotify also needs one active device: start a track in the
Spotify app once and Live Ride takes the controls from there.

## Testing on a real iPhone

```bash
cd live_app
./bootstrap.sh            # add --no-live-activity to skip the widget target
open ios/Runner.xcworkspace
```

In Xcode, select **your team** under Signing & Capabilities for **both**
`Runner` **and** `LiveRideWidgets`, then:

```bash
flutter run --release
```

What to check, in order:

| # | Where | What you should see |
| --- | --- | --- |
| 1 | Launch | Login screen on the dark Live Ride wordmark. Create an account or sign in; your username becomes the rider name. |
| 2 | Every tab | One visual system: white instrument panels, hairline rules, black type, one cyan accent. |
| 3 | LIVE tab → heart rate card | The WHOOP screen. With Broadcast Heart Rate on in the WHOOP app, the strap appears with a WHOOP badge; connecting shows live BPM, a trace, battery and signal. |
| 4 | Music tab | The Spotify setup card, then sign-in in the system browser sheet, then now playing with working transport controls. |
| 5 | START RIDE | The ride computer. After five seconds untouched, the controls retire; one tap brings them back. |
| 6 | Lock the phone during a ride | The Live Activity: speed, distance, elapsed, HR — and the next turn when navigating. Long-press the Dynamic Island for the expanded view. |

If the Lock Screen card does not appear, check Settings → Live Ride → Live
Activities. The Profile tab reports whether iOS has them enabled.

## Known limits

- The Swift sources were written and contract-tested but **not compiled** in
  the environment that produced them: no iOS SDK. They compile on your Mac, and
  a mismatch between the Dart and Swift ends of the Live Activity is covered by
  `test/live_activity_contract_test.dart`, but the first real build is yours.
- The Live Activity needs iOS 16.2+. Below that the Profile tab says so and
  rides work exactly as before.
- Spotify playback control needs Premium and one active Spotify device, both
  of which are Spotify's rules for third-party apps.
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
