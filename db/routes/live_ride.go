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
	DistanceM     float64   `json:"distance_m"`
	ElevationGain float64   `json:"elevation_gain_m"`
}

// LiveRideCreate starts a shareable live-tracking session and automatically
// adds the authenticated owner as the first participant.
func LiveRideCreate(e *core.RequestEvent) error {
	var data struct {
		Title       string `json:"title"`
		TrailID     string `json:"trail_id"`
		DisplayName string `json:"display_name"`
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

	sessions, err := e.App.FindCollectionByNameOrId("live_ride_sessions")
	if err != nil {
		return err
	}
	session := core.NewRecord(sessions)
	session.Set("owner", e.Auth.Id)
	if data.TrailID != "" {
		session.Set("trail", data.TrailID)
	}
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
		participant.Set("distance_m", newest.DistanceM)
		participant.Set("elevation_gain_m", newest.ElevationGain)
		participant.Set("last_seen_at", newest.RecordedAt.UTC())
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
		if err := e.App.Save(session); err != nil {
			return err
		}
	}
	return e.JSON(http.StatusOK, map[string]any{"status": "ended"})
}

// LiveRidePublicSnapshot is intentionally unauthenticated. Possession of the
// cryptographically random share token is the capability. It returns only the
// fields needed by the spectator UI and never exposes user ids/emails.
func LiveRidePublicSnapshot(e *core.RequestEvent) error {
	token := strings.TrimSpace(e.Request.PathValue("token"))
	if len(token) < 32 {
		return apis.NewNotFoundError("Live ride not found", nil)
	}

	session, err := e.App.FindFirstRecordByData("live_ride_sessions", "share_token", token)
	if err != nil {
		return apis.NewNotFoundError("Live ride not found", err)
	}

	participants, err := e.App.FindRecordsByFilter(
		"live_ride_participants",
		"session={:session}",
		"display_name",
		100,
		0,
		dbx.Params{"session": session.Id},
	)
	if err != nil {
		return err
	}

	riders := make([]map[string]any, 0, len(participants))
	for _, participant := range participants {
		riders = append(riders, map[string]any{
			"id":               participant.Id,
			"display_name":     participant.GetString("display_name"),
			"latitude":         participant.GetFloat("latitude"),
			"longitude":        participant.GetFloat("longitude"),
			"speed_kmh":        participant.GetFloat("speed_kmh"),
			"altitude_m":       participant.GetFloat("altitude_m"),
			"heading_deg":      participant.GetFloat("heading_deg"),
			"accuracy_m":       participant.GetFloat("accuracy_m"),
			"heart_rate_bpm":   participant.GetInt("heart_rate_bpm"),
			"distance_m":       participant.GetFloat("distance_m"),
			"elevation_gain_m": participant.GetFloat("elevation_gain_m"),
			"last_seen_at":     participant.GetDateTime("last_seen_at"),
		})
	}

	return e.JSON(http.StatusOK, map[string]any{
		"title":      session.GetString("title"),
		"trail_id":   session.GetString("trail"),
		"status":     session.GetString("status"),
		"started_at": session.GetDateTime("started_at"),
		"ended_at":   session.GetDateTime("ended_at"),
		"riders":     riders,
	})
}

// LiveRidePublicRoute returns the simplified encoded route geometry only to
// holders of the spectator token. It is fetched once by the viewer rather
// than being resent with every 3-second live snapshot.
func LiveRidePublicRoute(e *core.RequestEvent) error {
	token := strings.TrimSpace(e.Request.PathValue("token"))
	if len(token) < 32 {
		return apis.NewNotFoundError("Live ride not found", nil)
	}

	session, err := e.App.FindFirstRecordByData("live_ride_sessions", "share_token", token)
	if err != nil {
		return apis.NewNotFoundError("Live ride not found", err)
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
		"name":           trail.GetString("name"),
		"polyline":       trail.GetString("polyline"),
		"distance_m":     trail.GetFloat("distance"),
		"elevation_gain": trail.GetFloat("elevation_gain"),
		"min_lat":        trail.GetFloat("min_lat"),
		"max_lat":        trail.GetFloat("max_lat"),
		"min_lon":        trail.GetFloat("min_lon"),
		"max_lon":        trail.GetFloat("max_lon"),
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
	record.Set("distance_m", point.DistanceM)
	record.Set("elevation_gain_m", point.ElevationGain)
}

type liveRideValidationError struct{ message string }

func (e *liveRideValidationError) Error() string { return e.message }
