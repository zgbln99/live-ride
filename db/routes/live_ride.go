package routes

import (
	"net/http"
	"strings"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/security"
)

const liveRideMaxTelemetryBatch = 100

type liveRideTelemetryPoint struct {
	RecordedAt    time.Time `json:"recorded_at"`
	Latitude      float64   `json:"latitude"`
	Longitude     float64   `json:"longitude"`
	SpeedKmh      float64   `json:"speed_kmh"`
	AltitudeM     float64   `json:"altitude_m"`
	HeadingDeg    float64   `json:"heading_deg"`
	AccuracyM     float64   `json:"accuracy_m"`
	HeartRateBpm  int       `json:"heart_rate_bpm"`
	CadenceRpm    int       `json:"cadence_rpm"`
	PowerWatts    int       `json:"power_watts"`
	DistanceM     float64   `json:"distance_m"`
	ElevationGain float64   `json:"elevation_gain_m"`

	// Stan zawodnika i statystyki sesji jadą z najnowszą próbką, bo tylko
	// telefon je zna: serwer nie odróżni świateł od pauzy ani nie policzy
	// czasu w ruchu z próbek, które przyszły z opóźnieniem.
	State          string  `json:"state"`
	MovingSeconds  int     `json:"moving_seconds"`
	MaxSpeedKmh    float64 `json:"max_speed_kmh"`
	BatteryPercent int     `json:"battery_percent"`

	// Postoje rozbite tak, jak rozbija je licznik: automatyczne (rower stał)
	// i ręczne (rowerzysta zatrzymał pomiar). Bez tego strona umiałaby podać
	// tylko różnicę „całkowity minus w ruchu", a w niej siedzą także sekundy
	// krótsze od progu auto-pauzy.
	AutoPausedSeconds   int `json:"auto_paused_seconds"`
	ManualPausedSeconds int `json:"manual_paused_seconds"`
}

// normalizeLiveRideState przyjmuje tylko nazwy, które strona umie pokazać.
func normalizeLiveRideState(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "paused":
		return "paused"
	case "stopped":
		return "stopped"
	case "riding":
		return "riding"
	default:
		return ""
	}
}

// LiveRideCreate starts a shareable live-tracking session and automatically
// adds the authenticated owner as the first participant.
func LiveRideCreate(e *core.RequestEvent) error {
	var data struct {
		Title       string `json:"title"`
		TrailID     string `json:"trail_id"`
		DisplayName string `json:"display_name"`
		// Trasa z biblioteki Live Ride, po client_id nadanym przez telefon.
		// Bez niej publiczna strona nie ma czego narysować jako planu.
		RouteClientID string `json:"route_client_id"`
		Visibility    string `json:"visibility"`
		ExpireOnEnd   bool   `json:"expire_on_end"`
	}
	if err := e.BindBody(&data); err != nil {
		return apis.NewBadRequestError("Failed to read request data", err)
	}

	title := strings.TrimSpace(data.Title)
	if title == "" {
		title = "Live Ride"
	}
	if len(title) > 160 {
		return apis.NewBadRequestError("Title is too long", nil)
	}
	if data.TrailID != "" {
		trail, err := e.App.FindRecordById("trails", data.TrailID)
		if err != nil {
			return apis.NewBadRequestError("Unknown trail", err)
		}
		// A public spectator token must never turn knowledge of an arbitrary
		// private trail id into route disclosure. Only public trails or trails
		// authored by the authenticated user's local actor may be attached.
		if !trail.GetBool("public") {
			actor, actorErr := e.App.FindFirstRecordByData("activitypub_actors", "user", e.Auth.Id)
			if actorErr != nil || trail.GetString("author") != actor.Id {
				return apis.NewForbiddenError("Private trail cannot be shared in this live ride", nil)
			}
		}
	}

	// Trasę wskazuje się własnym client_id, więc właściciel może przypiąć
	// wyłącznie swoją: cudza trasa nie ma szansy trafić na czyjś publiczny
	// link nawet przez pomyłkę w identyfikatorze.
	routeID := ""
	if clientID := strings.TrimSpace(data.RouteClientID); clientID != "" {
		routes, err := e.App.FindRecordsByFilter(
			"live_ride_routes",
			"owner = {:owner} && client_id = {:client}",
			"",
			1,
			0,
			dbx.Params{"owner": e.Auth.Id, "client": clientID},
		)
		if err == nil && len(routes) > 0 {
			routeID = routes[0].Id
		}
	}

	sessions, err := e.App.FindCollectionByNameOrId("live_ride_sessions")
	if err != nil {
		return err
	}
	session := core.NewRecord(sessions)
	session.Set("owner", e.Auth.Id)
	if data.TrailID != "" {
		session.Set("trail", data.TrailID)
	}
	if routeID != "" {
		session.Set("route", routeID)
	}
	switch strings.ToLower(strings.TrimSpace(data.Visibility)) {
	case "public":
		session.Set("visibility", "public")
	case "disabled":
		session.Set("visibility", "disabled")
	default:
		// Domyślnie „z linku": działa dla każdego, kto dostał adres, i dla
		// nikogo poza tym. Literówka nie może upublicznić czyjejś trasy.
		session.Set("visibility", "unlisted")
	}
	session.Set("expire_on_end", data.ExpireOnEnd)
	session.Set("title", title)
	session.Set("share_token", security.RandomString(40))
	session.Set("join_token", normalizeLiveRideJoinToken(security.RandomString(12)))
	session.Set("status", "active")
	session.Set("started_at", time.Now().UTC())
	if err := e.App.Save(session); err != nil {
		return err
	}

	participant, err := ensureLiveRideParticipant(e, session, strings.TrimSpace(data.DisplayName))
	if err != nil {
		_ = e.App.Delete(session)
		return err
	}

	return e.JSON(http.StatusCreated, map[string]any{
		"id":             session.Id,
		"participant_id": participant.Id,
		"share_token":    session.GetString("share_token"),
		"join_token":     session.GetString("join_token"),
		"status":         session.GetString("status"),
		"visibility":     liveRideVisibility(session),
		"expire_on_end":  session.GetBool("expire_on_end"),
		"has_route":      routeID != "" || data.TrailID != "",
		"started_at":     session.GetDateTime("started_at"),
	})
}

// LiveRideJoin accepts a short invitation token that is separate from the
// public spectator URL. A spectator link therefore never grants write access
// or lets someone silently become a participant.
func LiveRideJoin(e *core.RequestEvent) error {
	var data struct {
		JoinToken   string `json:"join_token"`
		DisplayName string `json:"display_name"`
	}
	if err := e.BindBody(&data); err != nil {
		return apis.NewBadRequestError("Failed to read request data", err)
	}

	joinToken := normalizeLiveRideJoinToken(data.JoinToken)
	if len(joinToken) < 8 {
		return apis.NewBadRequestError("Invalid join token", nil)
	}
	session, err := e.App.FindFirstRecordByData("live_ride_sessions", "join_token", joinToken)
	if err != nil || session.GetString("status") != "active" {
		return apis.NewNotFoundError("Active live ride not found", err)
	}

	participant, err := ensureLiveRideParticipant(e, session, strings.TrimSpace(data.DisplayName))
	if err != nil {
		return err
	}

	return e.JSON(http.StatusOK, map[string]any{
		"id":             session.Id,
		"participant_id": participant.Id,
		"share_token":    session.GetString("share_token"),
		"join_token":     session.GetString("join_token"),
		"status":         session.GetString("status"),
		"started_at":     session.GetDateTime("started_at"),
	})
}

// LiveRideTelemetry accepts a batch so the mobile app can backfill samples
// gathered while the data connection was unavailable. The participant's
// current-state record is updated from the newest sample for cheap spectator
// snapshots, while the point collection retains the history.
func LiveRideTelemetry(e *core.RequestEvent) error {
	session, err := activeLiveRideByID(e, e.Request.PathValue("id"))
	if err != nil {
		return err
	}

	participant, err := e.App.FindFirstRecordByFilter(
		"live_ride_participants",
		"session={:session} && user={:user}",
		dbx.Params{"session": session.Id, "user": e.Auth.Id},
	)
	if err != nil {
		return apis.NewForbiddenError("Join the live ride before sending telemetry", nil)
	}

	var data struct {
		Points []liveRideTelemetryPoint `json:"points"`
	}
	if err := e.BindBody(&data); err != nil {
		return apis.NewBadRequestError("Failed to read request data", err)
	}
	if len(data.Points) == 0 || len(data.Points) > liveRideMaxTelemetryBatch {
		return apis.NewBadRequestError("points must contain between 1 and 100 samples", nil)
	}

	pointsCollection, err := e.App.FindCollectionByNameOrId("live_ride_points")
	if err != nil {
		return err
	}

	accepted := 0
	var newest *liveRideTelemetryPoint
	for i := range data.Points {
		point := data.Points[i]
		if err := validateLiveRidePoint(point); err != nil {
			return apis.NewBadRequestError("Invalid telemetry sample", err)
		}

		// Idempotency for reconnect/backfill retries. The migration adds a
		// unique (participant, recorded_at) index as a final race-safe guard.
		if _, err := e.App.FindFirstRecordByFilter(
			"live_ride_points",
			"participant={:participant} && recorded_at={:recordedAt}",
			dbx.Params{"participant": participant.Id, "recordedAt": point.RecordedAt.UTC()},
		); err == nil {
			if newest == nil || point.RecordedAt.After(newest.RecordedAt) {
				copy := point
				newest = &copy
			}
			continue
		}

		record := core.NewRecord(pointsCollection)
		record.Set("session", session.Id)
		record.Set("participant", participant.Id)
		setLiveRidePointFields(record, point)
		if err := e.App.Save(record); err != nil {
			return err
		}
		accepted++

		if newest == nil || point.RecordedAt.After(newest.RecordedAt) {
			copy := point
			newest = &copy
		}
	}

	if newest != nil {
		participant.Set("latitude", newest.Latitude)
		participant.Set("longitude", newest.Longitude)
		participant.Set("speed_kmh", newest.SpeedKmh)
		participant.Set("altitude_m", newest.AltitudeM)
		participant.Set("heading_deg", newest.HeadingDeg)
		participant.Set("accuracy_m", newest.AccuracyM)
		participant.Set("heart_rate_bpm", newest.HeartRateBpm)
		participant.Set("cadence_rpm", newest.CadenceRpm)
		participant.Set("power_watts", newest.PowerWatts)
		participant.Set("distance_m", newest.DistanceM)
		participant.Set("elevation_gain_m", newest.ElevationGain)
		participant.Set("last_seen_at", newest.RecordedAt.UTC())
		if state := normalizeLiveRideState(newest.State); state != "" {
			participant.Set("state", state)
		}
		if newest.MovingSeconds > 0 {
			participant.Set("moving_seconds", newest.MovingSeconds)
		}
		// Sumy postojów tylko rosną. Telefon po restarcie aplikacji przysyła
		// je od zera i nie ma prawa skasować tego, co już przejechane.
		if newest.AutoPausedSeconds > participant.GetInt("auto_paused_seconds") {
			participant.Set("auto_paused_seconds", newest.AutoPausedSeconds)
		}
		if newest.ManualPausedSeconds > participant.GetInt("manual_paused_seconds") {
			participant.Set("manual_paused_seconds", newest.ManualPausedSeconds)
		}
		// Rekord prędkości nigdy nie maleje w trakcie jazdy — telefon, który
		// po restarcie przysłał niższą wartość, nie może skasować maksimum.
		if newest.MaxSpeedKmh > participant.GetFloat("max_speed_kmh") {
			participant.Set("max_speed_kmh", newest.MaxSpeedKmh)
		}
		if newest.BatteryPercent > 0 && newest.BatteryPercent <= 100 {
			participant.Set("battery_percent", newest.BatteryPercent)
		}
		if err := e.App.Save(participant); err != nil {
			return err
		}
	}

	return e.JSON(http.StatusAccepted, map[string]any{
		"accepted": accepted,
		"received": len(data.Points),
	})
}

// LiveRideStop ends a session. Only the owner can stop it.
func LiveRideStop(e *core.RequestEvent) error {
	session, err := e.App.FindRecordById("live_ride_sessions", e.Request.PathValue("id"))
	if err != nil {
		return apis.NewNotFoundError("Live ride not found", err)
	}
	if session.GetString("owner") != e.Auth.Id {
		return apis.NewForbiddenError("Only the live ride owner can stop it", nil)
	}
	if session.GetString("status") != "ended" {
		session.Set("status", "ended")
		session.Set("ended_at", time.Now().UTC())
		// Podsumowanie liczy się raz, tutaj. Po mecie te liczby już się nie
		// zmienią, a publiczna strona nie ma prawa przy każdym wejściu
		// przewalać całej historii punktów.
		if summary := liveRideBuildSummary(e, session); summary != nil {
			session.Set("summary", summary)
		}
		if err := e.App.Save(session); err != nil {
			return err
		}
	}
	return e.JSON(http.StatusOK, map[string]any{
		"status":     "ended",
		"link_alive": !liveRideShareExpired(session, time.Now().UTC()),
	})
}

// LiveRidePublicRoute returns the planned route to holders of the spectator
// token. It is fetched once by the viewer rather than being resent with every
// live snapshot.
//
// Dwa źródła, bo dwie epoki: trasa z biblioteki Live Ride (polilinia w
// precyzji 6, z profilem wysokości i podjazdami) i stara ścieżka Wanderera
// (`trails`, polilinia w precyzji 5). Odpowiedź zawsze mówi, w której
// precyzji jest zakodowana — zgadywanie po stronie strony rysowało trasę
// dziesięć razy bliżej równika, niż była naprawdę.
func LiveRidePublicRoute(e *core.RequestEvent) error {
	access, err := liveRideResolveShare(e)
	if err != nil {
		return err
	}
	session := access.session
	liveRideNoStore(e, liveRideVisibility(session) == "public")

	if access.state != "ok" {
		return e.JSON(http.StatusOK, map[string]any{"status": access.state, "polyline": ""})
	}

	if routeID := session.GetString("route"); routeID != "" {
		if route, err := e.App.FindRecordById("live_ride_routes", routeID); err == nil {
			return e.JSON(http.StatusOK, liveRideRouteJSONForViewer(route))
		}
	}

	trailID := session.GetString("trail")
	if trailID == "" {
		return e.JSON(http.StatusOK, map[string]any{"polyline": ""})
	}

	trail, err := e.App.FindRecordById("trails", trailID)
	if err != nil {
		return apis.NewNotFoundError("Live ride route not found", err)
	}
	return e.JSON(http.StatusOK, map[string]any{
		"name":     trail.GetString("name"),
		"polyline": trail.GetString("polyline"),
		// Kolekcja `trails` koduje polilinie w precyzji 5 (go-polyline),
		// a nie 6 jak reszta Live Ride.
		"precision":  5,
		"distance_m": trail.GetFloat("distance"),
		"ascent_m":   trail.GetFloat("elevation_gain"),
		"min_lat":    trail.GetFloat("min_lat"),
		"max_lat":    trail.GetFloat("max_lat"),
		"min_lon":    trail.GetFloat("min_lon"),
		"max_lon":    trail.GetFloat("max_lon"),
	})
}

func activeLiveRideByID(e *core.RequestEvent, id string) (*core.Record, error) {
	session, err := e.App.FindRecordById("live_ride_sessions", id)
	if err != nil {
		return nil, apis.NewNotFoundError("Live ride not found", err)
	}
	if session.GetString("status") != "active" {
		return nil, apis.NewBadRequestError("Live ride has ended", nil)
	}
	return session, nil
}

func ensureLiveRideParticipant(e *core.RequestEvent, session *core.Record, displayName string) (*core.Record, error) {
	displayName = liveRideDisplayName(e, displayName)

	if existing, err := e.App.FindFirstRecordByFilter(
		"live_ride_participants",
		"session={:session} && user={:user}",
		dbx.Params{"session": session.Id, "user": e.Auth.Id},
	); err == nil {
		// A rider who renamed themselves in the app must not stay published
		// under the name captured when they first joined.
		if existing.GetString("display_name") != displayName {
			existing.Set("display_name", displayName)
			if err := e.App.Save(existing); err != nil {
				return nil, err
			}
		}
		return existing, nil
	}

	collection, err := e.App.FindCollectionByNameOrId("live_ride_participants")
	if err != nil {
		return nil, err
	}
	participant := core.NewRecord(collection)
	participant.Set("session", session.Id)
	participant.Set("user", e.Auth.Id)
	participant.Set("display_name", displayName)
	// Chwila dołączenia, nie chwila pierwszego fiksa. Publiczna strona liczy
	// z niej, jak długo zawodnik jest w jeździe, także zanim GPS odpowie.
	participant.Set("joined_at", time.Now().UTC())
	if err := e.App.Save(participant); err != nil {
		return nil, err
	}
	return participant, nil
}

// liveRideDisplayName resolves the name spectators see, preferring what the
// app sent, then the account profile name, then the username. "Rider" is only
// used when the account carries no identity at all.
func liveRideDisplayName(e *core.RequestEvent, requested string) string {
	candidates := []string{
		strings.TrimSpace(requested),
		strings.TrimSpace(e.Auth.GetString("name")),
		strings.TrimSpace(e.Auth.GetString("username")),
	}
	for _, candidate := range candidates {
		if candidate == "" {
			continue
		}
		if len(candidate) > 80 {
			candidate = candidate[:80]
		}
		return candidate
	}
	return "Rider"
}

func normalizeLiveRideJoinToken(token string) string {
	return strings.ToUpper(strings.TrimSpace(token))
}

func validateLiveRidePoint(point liveRideTelemetryPoint) error {
	if point.RecordedAt.IsZero() {
		return &liveRideValidationError{"recorded_at is required"}
	}
	if point.Latitude < -90 || point.Latitude > 90 {
		return &liveRideValidationError{"latitude must be between -90 and 90"}
	}
	if point.Longitude < -180 || point.Longitude > 180 {
		return &liveRideValidationError{"longitude must be between -180 and 180"}
	}
	if point.SpeedKmh < 0 || point.SpeedKmh > 200 {
		return &liveRideValidationError{"speed_kmh is outside the supported range"}
	}
	if point.AccuracyM < 0 || point.AccuracyM > 5000 {
		return &liveRideValidationError{"accuracy_m is outside the supported range"}
	}
	if point.HeartRateBpm < 0 || point.HeartRateBpm > 260 {
		return &liveRideValidationError{"heart_rate_bpm is outside the supported range"}
	}
	if point.CadenceRpm < 0 || point.CadenceRpm > 250 {
		return &liveRideValidationError{"cadence_rpm is outside the supported range"}
	}
	if point.PowerWatts < 0 || point.PowerWatts > 2500 {
		return &liveRideValidationError{"power_watts is outside the supported range"}
	}
	return nil
}

func setLiveRidePointFields(record *core.Record, point liveRideTelemetryPoint) {
	record.Set("recorded_at", point.RecordedAt.UTC())
	record.Set("latitude", point.Latitude)
	record.Set("longitude", point.Longitude)
	record.Set("speed_kmh", point.SpeedKmh)
	record.Set("altitude_m", point.AltitudeM)
	record.Set("heading_deg", point.HeadingDeg)
	record.Set("accuracy_m", point.AccuracyM)
	record.Set("heart_rate_bpm", point.HeartRateBpm)
	record.Set("power_watts", point.PowerWatts)
	record.Set("cadence_rpm", point.CadenceRpm)
	record.Set("distance_m", point.DistanceM)
	record.Set("elevation_gain_m", point.ElevationGain)
}

// liveRideHasPrivacyFields reports whether the rider ever stated a choice.
func liveRideHasPrivacyFields(participant *core.Record) bool {
	return participant.GetBool("share_position") ||
		participant.GetBool("share_speed") ||
		participant.GetBool("share_heart_rate") ||
		participant.GetBool("share_power")
}

type liveRideValidationError struct{ message string }

func (e *liveRideValidationError) Error() string { return e.message }
