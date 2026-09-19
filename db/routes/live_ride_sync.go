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

// Synchronizacja Live Ride.
//
// Telefon jest źródłem prawdy: jazda zapisuje się lokalnie i dopiero potem
// trafia na serwer. Dlatego każdy rekord niesie client_id nadany przez
// aplikację — po nim rozpoznajemy, że to ten sam przejazd, a nie kolejny,
// nawet gdy wysyłka powtórzy się po utracie sieci.

const (
	liveRideMaxPolylineBytes = 1_000_000
	liveRideShareTokenBytes  = 24
	liveRideMaxSyncBatch     = 50
)

type liveRideRidePayload struct {
	ClientID        string    `json:"client_id"`
	Name            string    `json:"name"`
	StartedAt       time.Time `json:"started_at"`
	EndedAt         time.Time `json:"ended_at"`
	ElapsedSeconds  int       `json:"elapsed_seconds"`
	MovingSeconds   int       `json:"moving_seconds"`
	DistanceM       float64   `json:"distance_m"`
	AscentM         float64   `json:"ascent_m"`
	DescentM        float64   `json:"descent_m"`
	MaxSpeedKmh     float64   `json:"max_speed_kmh"`
	AvgHeartRate    int       `json:"avg_heart_rate"`
	MaxHeartRate    int       `json:"max_heart_rate"`
	AvgPower        int       `json:"avg_power"`
	NormalizedPower int       `json:"normalized_power"`
	AvgCadence      int       `json:"avg_cadence"`
	Calories        int       `json:"calories"`
	TrackPolyline   string    `json:"track_polyline"`
	PointCount      int       `json:"point_count"`
	Privacy         string    `json:"privacy"`
	ClientUpdatedAt time.Time `json:"client_updated_at"`
}

type liveRideRoutePayload struct {
	ClientID        string         `json:"client_id"`
	Name            string         `json:"name"`
	Description     string         `json:"description"`
	Tags            []string       `json:"tags"`
	DistanceM       float64        `json:"distance_m"`
	AscentM         float64        `json:"ascent_m"`
	DescentM        float64        `json:"descent_m"`
	Polyline        string         `json:"polyline"`
	Waypoints       []any          `json:"waypoints"`
	Preferences     map[string]any `json:"preferences"`
	Privacy         string         `json:"privacy"`
	ClientUpdatedAt time.Time      `json:"client_updated_at"`
}

// LiveRideSyncRides stores a batch of finished rides for the signed-in user.
func LiveRideSyncRides(e *core.RequestEvent) error {
	user := e.Auth
	if user == nil {
		return apis.NewUnauthorizedError("Authentication required", nil)
	}

	var data struct {
		Rides []liveRideRidePayload `json:"rides"`
	}
	if err := e.BindBody(&data); err != nil {
		return apis.NewBadRequestError("Failed to read request data", err)
	}
	if len(data.Rides) == 0 {
		return e.JSON(http.StatusOK, map[string]any{"synced": []any{}})
	}
	if len(data.Rides) > liveRideMaxSyncBatch {
		return apis.NewBadRequestError("Too many rides in one request", nil)
	}

	collection, err := e.App.FindCollectionByNameOrId("live_ride_rides")
	if err != nil {
		return apis.NewNotFoundError("Live Ride rides collection is missing", err)
	}

	type syncedRide struct {
		ClientID   string `json:"client_id"`
		ID         string `json:"id"`
		ShareToken string `json:"share_token"`
	}
	synced := make([]syncedRide, 0, len(data.Rides))

	for _, payload := range data.Rides {
		if err := validateLiveRideRide(payload); err != nil {
			return apis.NewBadRequestError(err.Error(), nil)
		}

		record, err := findLiveRideByClientID(e, collection, user.Id, payload.ClientID)
		if err != nil {
			return err
		}
		if record == nil {
			record = core.NewRecord(collection)
			record.Set("owner", user.Id)
			record.Set("client_id", payload.ClientID)
		} else if !liveRideIsNewer(payload.ClientUpdatedAt, record) {
			// Serwer ma nowszą wersję: telefon nadpisze ją dopiero, gdy sam
			// zmieni przejazd. Cichy zapis starszych danych kasowałby zmiany
			// zrobione na innym urządzeniu.
			synced = append(synced, syncedRide{
				ClientID:   payload.ClientID,
				ID:         record.Id,
				ShareToken: record.GetString("share_token"),
			})
			continue
		}

		record.Set("name", strings.TrimSpace(payload.Name))
		record.Set("started_at", payload.StartedAt.UTC())
		if !payload.EndedAt.IsZero() {
			record.Set("ended_at", payload.EndedAt.UTC())
		}
		record.Set("elapsed_seconds", payload.ElapsedSeconds)
		record.Set("moving_seconds", payload.MovingSeconds)
		record.Set("distance_m", payload.DistanceM)
		record.Set("ascent_m", payload.AscentM)
		record.Set("descent_m", payload.DescentM)
		record.Set("max_speed_kmh", payload.MaxSpeedKmh)
		record.Set("avg_heart_rate", payload.AvgHeartRate)
		record.Set("max_heart_rate", payload.MaxHeartRate)
		record.Set("avg_power", payload.AvgPower)
		record.Set("normalized_power", payload.NormalizedPower)
		record.Set("avg_cadence", payload.AvgCadence)
		record.Set("calories", payload.Calories)
		record.Set("track_polyline", payload.TrackPolyline)
		record.Set("point_count", payload.PointCount)
		record.Set("privacy", normalizeLiveRidePrivacy(payload.Privacy))
		record.Set("client_updated_at", liveRideUpdatedAt(payload.ClientUpdatedAt))

		if record.GetString("privacy") != "private" && record.GetString("share_token") == "" {
			record.Set("share_token", security.RandomString(liveRideShareTokenBytes))
		}

		if err := e.App.Save(record); err != nil {
			return apis.NewBadRequestError("Failed to store the ride", err)
		}
		synced = append(synced, syncedRide{
			ClientID:   payload.ClientID,
			ID:         record.Id,
			ShareToken: record.GetString("share_token"),
		})
	}

	return e.JSON(http.StatusOK, map[string]any{"synced": synced})
}

// LiveRideSyncRoutes stores planned routes for the signed-in user.
func LiveRideSyncRoutes(e *core.RequestEvent) error {
	user := e.Auth
	if user == nil {
		return apis.NewUnauthorizedError("Authentication required", nil)
	}

	var data struct {
		Routes []liveRideRoutePayload `json:"routes"`
	}
	if err := e.BindBody(&data); err != nil {
		return apis.NewBadRequestError("Failed to read request data", err)
	}
	if len(data.Routes) > liveRideMaxSyncBatch {
		return apis.NewBadRequestError("Too many routes in one request", nil)
	}

	collection, err := e.App.FindCollectionByNameOrId("live_ride_routes")
	if err != nil {
		return apis.NewNotFoundError("Live Ride routes collection is missing", err)
	}

	type syncedRoute struct {
		ClientID   string `json:"client_id"`
		ID         string `json:"id"`
		ShareToken string `json:"share_token"`
	}
	synced := make([]syncedRoute, 0, len(data.Routes))

	for _, payload := range data.Routes {
		if err := validateLiveRideRoute(payload); err != nil {
			return apis.NewBadRequestError(err.Error(), nil)
		}

		record, err := findLiveRideByClientID(e, collection, user.Id, payload.ClientID)
		if err != nil {
			return err
		}
		if record == nil {
			record = core.NewRecord(collection)
			record.Set("owner", user.Id)
			record.Set("client_id", payload.ClientID)
		} else if !liveRideIsNewer(payload.ClientUpdatedAt, record) {
			synced = append(synced, syncedRoute{
				ClientID:   payload.ClientID,
				ID:         record.Id,
				ShareToken: record.GetString("share_token"),
			})
			continue
		}

		record.Set("name", strings.TrimSpace(payload.Name))
		record.Set("description", payload.Description)
		record.Set("tags", payload.Tags)
		record.Set("distance_m", payload.DistanceM)
		record.Set("ascent_m", payload.AscentM)
		record.Set("descent_m", payload.DescentM)
		record.Set("polyline", payload.Polyline)
		record.Set("waypoints", payload.Waypoints)
		record.Set("preferences", payload.Preferences)
		record.Set("privacy", normalizeLiveRidePrivacy(payload.Privacy))
		record.Set("client_updated_at", liveRideUpdatedAt(payload.ClientUpdatedAt))

		if record.GetString("privacy") != "private" && record.GetString("share_token") == "" {
			record.Set("share_token", security.RandomString(liveRideShareTokenBytes))
		}

		if err := e.App.Save(record); err != nil {
			return apis.NewBadRequestError("Failed to store the route", err)
		}
		synced = append(synced, syncedRoute{
			ClientID:   payload.ClientID,
			ID:         record.Id,
			ShareToken: record.GetString("share_token"),
		})
	}

	return e.JSON(http.StatusOK, map[string]any{"synced": synced})
}

type liveRideSegmentPayload struct {
	ClientID  string  `json:"client_id"`
	Name      string  `json:"name"`
	DistanceM float64 `json:"distance_m"`
	AscentM   float64 `json:"ascent_m"`
	Gradient  float64 `json:"avg_gradient"`
	Polyline  string  `json:"polyline"`
	Privacy   string  `json:"privacy"`

	Attempts []liveRideAttemptPayload `json:"attempts"`
}

type liveRideAttemptPayload struct {
	ClientID        string    `json:"client_id"`
	StartedAt       time.Time `json:"started_at"`
	DurationSeconds int       `json:"duration_seconds"`
	AvgSpeedKmh     float64   `json:"avg_speed_kmh"`
	AvgHeartRate    int       `json:"avg_heart_rate"`
	AvgPower        int       `json:"avg_power"`
}

// LiveRideSyncSegments stores the caller's segments and their attempts.
//
// Attempts ride along with their segment rather than through a separate call:
// an attempt without its segment would be a time with nothing to compare it
// to, and the two are always produced together on the phone.
func LiveRideSyncSegments(e *core.RequestEvent) error {
	user := e.Auth
	if user == nil {
		return apis.NewUnauthorizedError("Authentication required", nil)
	}

	var data struct {
		Segments []liveRideSegmentPayload `json:"segments"`
	}
	if err := e.BindBody(&data); err != nil {
		return apis.NewBadRequestError("Failed to read request data", err)
	}
	if len(data.Segments) > liveRideMaxSyncBatch {
		return apis.NewBadRequestError("Too many segments in one request", nil)
	}

	segments, err := e.App.FindCollectionByNameOrId("live_ride_segments")
	if err != nil {
		return apis.NewNotFoundError("Live Ride segments collection is missing", err)
	}
	attempts, err := e.App.FindCollectionByNameOrId("live_ride_segment_attempts")
	if err != nil {
		return apis.NewNotFoundError("Live Ride attempts collection is missing", err)
	}

	type syncedSegment struct {
		ClientID   string `json:"client_id"`
		ID         string `json:"id"`
		ShareToken string `json:"share_token"`
	}
	synced := make([]syncedSegment, 0, len(data.Segments))

	for _, payload := range data.Segments {
		if strings.TrimSpace(payload.ClientID) == "" ||
			strings.TrimSpace(payload.Name) == "" ||
			strings.TrimSpace(payload.Polyline) == "" {
			return apis.NewBadRequestError("client_id, name and polyline are required", nil)
		}
		if len(payload.Polyline) > liveRideMaxPolylineBytes {
			return apis.NewBadRequestError("polyline is too large", nil)
		}

		record, err := findLiveRideByClientID(e, segments, user.Id, payload.ClientID)
		if err != nil {
			return err
		}
		if record == nil {
			record = core.NewRecord(segments)
			record.Set("owner", user.Id)
			record.Set("client_id", payload.ClientID)
		}
		record.Set("name", strings.TrimSpace(payload.Name))
		record.Set("distance_m", payload.DistanceM)
		record.Set("ascent_m", payload.AscentM)
		record.Set("avg_gradient", payload.Gradient)
		record.Set("polyline", payload.Polyline)
		record.Set("privacy", normalizeLiveRidePrivacy(payload.Privacy))
		if record.GetString("privacy") != "private" && record.GetString("share_token") == "" {
			record.Set("share_token", security.RandomString(liveRideShareTokenBytes))
		}
		if err := e.App.Save(record); err != nil {
			return apis.NewBadRequestError("Failed to store the segment", err)
		}

		for _, attempt := range payload.Attempts {
			if strings.TrimSpace(attempt.ClientID) == "" {
				continue
			}
			if attempt.DurationSeconds <= 0 || attempt.DurationSeconds > 24*3600 {
				continue
			}
			existing, err := findLiveRideByClientID(e, attempts, user.Id, attempt.ClientID)
			if err != nil {
				return err
			}
			if existing == nil {
				existing = core.NewRecord(attempts)
				existing.Set("user", user.Id)
				existing.Set("client_id", attempt.ClientID)
			}
			existing.Set("segment", record.Id)
			existing.Set("started_at", attempt.StartedAt.UTC())
			existing.Set("duration_seconds", attempt.DurationSeconds)
			existing.Set("avg_speed_kmh", attempt.AvgSpeedKmh)
			existing.Set("avg_heart_rate", attempt.AvgHeartRate)
			existing.Set("avg_power", attempt.AvgPower)
			if err := e.App.Save(existing); err != nil {
				return apis.NewBadRequestError("Failed to store the attempt", err)
			}
		}

		synced = append(synced, syncedSegment{
			ClientID:   payload.ClientID,
			ID:         record.Id,
			ShareToken: record.GetString("share_token"),
		})
	}

	return e.JSON(http.StatusOK, map[string]any{"synced": synced})
}

// LiveRidePullRoutes returns the signed-in user's routes changed since a
// timestamp, so a freshly installed phone can catch up without downloading
// everything again.
func LiveRidePullRoutes(e *core.RequestEvent) error {
	user := e.Auth
	if user == nil {
		return apis.NewUnauthorizedError("Authentication required", nil)
	}

	since := time.Time{}
	if raw := e.Request.URL.Query().Get("since"); raw != "" {
		parsed, err := time.Parse(time.RFC3339, raw)
		if err != nil {
			return apis.NewBadRequestError("Invalid 'since' timestamp", err)
		}
		since = parsed.UTC()
	}

	filter := "owner = {:owner}"
	params := dbx.Params{"owner": user.Id}
	if !since.IsZero() {
		filter += " && updated > {:since}"
		params["since"] = since.Format("2006-01-02 15:04:05.000Z")
	}

	records, err := e.App.FindRecordsByFilter("live_ride_routes", filter, "-updated", 200, 0, params)
	if err != nil {
		return apis.NewBadRequestError("Failed to read routes", err)
	}

	items := make([]map[string]any, 0, len(records))
	for _, record := range records {
		items = append(items, liveRideRouteJSON(record))
	}
	return e.JSON(http.StatusOK, map[string]any{"routes": items})
}

// LiveRidePublicRouteByToken serves a shared route to anyone holding the link.
func LiveRidePublicRouteByToken(e *core.RequestEvent) error {
	token := strings.TrimSpace(e.Request.PathValue("token"))
	if token == "" {
		return apis.NewNotFoundError("Route not found", nil)
	}

	records, err := e.App.FindRecordsByFilter(
		"live_ride_routes",
		"share_token = {:token} && privacy != 'private'",
		"",
		1,
		0,
		dbx.Params{"token": token},
	)
	if err != nil || len(records) == 0 {
		return apis.NewNotFoundError("Route not found", err)
	}
	return e.JSON(http.StatusOK, liveRideRouteJSON(records[0]))
}

// LiveRideCopyRoute copies a shared route into the caller's own library.
func LiveRideCopyRoute(e *core.RequestEvent) error {
	user := e.Auth
	if user == nil {
		return apis.NewUnauthorizedError("Authentication required", nil)
	}

	token := strings.TrimSpace(e.Request.PathValue("token"))
	records, err := e.App.FindRecordsByFilter(
		"live_ride_routes",
		"share_token = {:token} && privacy != 'private'",
		"",
		1,
		0,
		dbx.Params{"token": token},
	)
	if err != nil || len(records) == 0 {
		return apis.NewNotFoundError("Route not found", err)
	}
	source := records[0]

	if source.GetString("owner") == user.Id {
		return apis.NewBadRequestError("This route is already yours", nil)
	}

	collection, err := e.App.FindCollectionByNameOrId("live_ride_routes")
	if err != nil {
		return apis.NewNotFoundError("Live Ride routes collection is missing", err)
	}

	copied := core.NewRecord(collection)
	copied.Set("owner", user.Id)
	// Kopia dostaje własny client_id: to od teraz osobna trasa, którą
	// kopiujący może zmieniać, nie ruszając oryginału.
	copied.Set("client_id", "copy_"+security.RandomString(16))
	copied.Set("name", source.GetString("name"))
	copied.Set("description", source.GetString("description"))
	copied.Set("tags", source.Get("tags"))
	copied.Set("distance_m", source.GetFloat("distance_m"))
	copied.Set("ascent_m", source.GetFloat("ascent_m"))
	copied.Set("descent_m", source.GetFloat("descent_m"))
	copied.Set("polyline", source.GetString("polyline"))
	copied.Set("waypoints", source.Get("waypoints"))
	copied.Set("preferences", source.Get("preferences"))
	copied.Set("privacy", "private")
	copied.Set("copied_from", source.Id)
	copied.Set("client_updated_at", time.Now().UTC())

	if err := e.App.Save(copied); err != nil {
		return apis.NewBadRequestError("Failed to copy the route", err)
	}

	source.Set("copy_count", source.GetInt("copy_count")+1)
	if err := e.App.Save(source); err != nil {
		// Licznik kopii to statystyka, nie dane zawodnika — jego błąd nie
		// może przewrócić udanej kopii.
		e.App.Logger().Warn("live ride: failed to bump copy_count", "error", err)
	}

	return e.JSON(http.StatusOK, liveRideRouteJSON(copied))
}

// LiveRideSegmentLeaderboard returns the fastest attempt per rider.
func LiveRideSegmentLeaderboard(e *core.RequestEvent) error {
	token := strings.TrimSpace(e.Request.PathValue("token"))
	segments, err := e.App.FindRecordsByFilter(
		"live_ride_segments",
		"share_token = {:token} && privacy != 'private'",
		"",
		1,
		0,
		dbx.Params{"token": token},
	)
	if err != nil || len(segments) == 0 {
		return apis.NewNotFoundError("Segment not found", err)
	}
	segment := segments[0]

	type leaderboardRow struct {
		UserID   string  `json:"user_id"`
		Name     string  `json:"display_name"`
		Seconds  int     `json:"duration_seconds"`
		SpeedKmh float64 `json:"avg_speed_kmh"`
	}

	rows := []struct {
		User     string  `db:"user"`
		Name     string  `db:"name"`
		Seconds  int     `db:"duration_seconds"`
		SpeedKmh float64 `db:"avg_speed_kmh"`
	}{}

	// Najlepszy czas każdego zawodnika, a nie wszystkie jego próby —
	// ranking, w którym jedna osoba zajmuje pięć pierwszych miejsc, nie
	// mówi nic o tym, kto jest szybki.
	query := e.App.DB().NewQuery(`
		SELECT a.user AS user,
		       COALESCE(u.name, u.username, '') AS name,
		       MIN(a.duration_seconds) AS duration_seconds,
		       MAX(a.avg_speed_kmh) AS avg_speed_kmh
		FROM live_ride_segment_attempts a
		LEFT JOIN users u ON u.id = a.user
		WHERE a.segment = {:segment}
		GROUP BY a.user
		ORDER BY duration_seconds ASC
		LIMIT 50
	`).Bind(dbx.Params{"segment": segment.Id})

	if err := query.All(&rows); err != nil {
		return apis.NewBadRequestError("Failed to read the leaderboard", err)
	}

	result := make([]leaderboardRow, 0, len(rows))
	for _, row := range rows {
		result = append(result, leaderboardRow{
			UserID:   row.User,
			Name:     row.Name,
			Seconds:  row.Seconds,
			SpeedKmh: row.SpeedKmh,
		})
	}

	return e.JSON(http.StatusOK, map[string]any{
		"segment": map[string]any{
			"id":         segment.Id,
			"name":       segment.GetString("name"),
			"distance_m": segment.GetFloat("distance_m"),
			"ascent_m":   segment.GetFloat("ascent_m"),
		},
		"leaderboard": result,
	})
}

// ------------------------------------------------------------------ helpers

func findLiveRideByClientID(
	e *core.RequestEvent,
	collection *core.Collection,
	ownerID string,
	clientID string,
) (*core.Record, error) {
	ownerField := "owner"
	if collection.Name == "live_ride_segment_attempts" {
		ownerField = "user"
	}

	records, err := e.App.FindRecordsByFilter(
		collection.Name,
		ownerField+" = {:owner} && client_id = {:client}",
		"",
		1,
		0,
		dbx.Params{"owner": ownerID, "client": clientID},
	)
	if err != nil {
		return nil, apis.NewBadRequestError("Failed to look up the record", err)
	}
	if len(records) == 0 {
		return nil, nil
	}
	return records[0], nil
}

// liveRideIsNewer reports whether the incoming payload is at least as new as
// what the server already stores.
func liveRideIsNewer(clientUpdatedAt time.Time, record *core.Record) bool {
	if clientUpdatedAt.IsZero() {
		// Stare wersje aplikacji nie przysyłają znacznika. Wtedy przyjmujemy
		// dane: lepiej nadpisać niż odrzucić przejazd, którego nikt inny nie
		// zmieniał.
		return true
	}
	stored := record.GetDateTime("client_updated_at").Time()
	if stored.IsZero() {
		return true
	}
	return !clientUpdatedAt.Before(stored)
}

func liveRideUpdatedAt(value time.Time) time.Time {
	if value.IsZero() {
		return time.Now().UTC()
	}
	return value.UTC()
}

func normalizeLiveRidePrivacy(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "public":
		return "public"
	case "link":
		return "link"
	default:
		// Domyślnie prywatne. Pomyłka w literówce nie może upublicznić
		// czyjegoś przejazdu.
		return "private"
	}
}

func validateLiveRideRide(payload liveRideRidePayload) error {
	if strings.TrimSpace(payload.ClientID) == "" {
		return &liveRideValidationError{message: "client_id is required"}
	}
	if strings.TrimSpace(payload.Name) == "" {
		return &liveRideValidationError{message: "name is required"}
	}
	if payload.StartedAt.IsZero() {
		return &liveRideValidationError{message: "started_at is required"}
	}
	if payload.DistanceM < 0 || payload.DistanceM > 2_000_000 {
		return &liveRideValidationError{message: "distance_m is out of range"}
	}
	if payload.ElapsedSeconds < 0 || payload.ElapsedSeconds > 7*24*3600 {
		return &liveRideValidationError{message: "elapsed_seconds is out of range"}
	}
	if len(payload.TrackPolyline) > liveRideMaxPolylineBytes {
		return &liveRideValidationError{message: "track_polyline is too large"}
	}
	return nil
}

func validateLiveRideRoute(payload liveRideRoutePayload) error {
	if strings.TrimSpace(payload.ClientID) == "" {
		return &liveRideValidationError{message: "client_id is required"}
	}
	if strings.TrimSpace(payload.Name) == "" {
		return &liveRideValidationError{message: "name is required"}
	}
	if strings.TrimSpace(payload.Polyline) == "" {
		return &liveRideValidationError{message: "polyline is required"}
	}
	if len(payload.Polyline) > liveRideMaxPolylineBytes {
		return &liveRideValidationError{message: "polyline is too large"}
	}
	if payload.DistanceM < 0 || payload.DistanceM > 2_000_000 {
		return &liveRideValidationError{message: "distance_m is out of range"}
	}
	return nil
}

func liveRideRouteJSON(record *core.Record) map[string]any {
	return map[string]any{
		"id":                record.Id,
		"client_id":         record.GetString("client_id"),
		"name":              record.GetString("name"),
		"description":       record.GetString("description"),
		"tags":              record.Get("tags"),
		"distance_m":        record.GetFloat("distance_m"),
		"ascent_m":          record.GetFloat("ascent_m"),
		"descent_m":         record.GetFloat("descent_m"),
		"polyline":          record.GetString("polyline"),
		"waypoints":         record.Get("waypoints"),
		"preferences":       record.Get("preferences"),
		"privacy":           record.GetString("privacy"),
		"share_token":       record.GetString("share_token"),
		"copy_count":        record.GetInt("copy_count"),
		"updated":           record.GetDateTime("updated").String(),
		"client_updated_at": record.GetDateTime("client_updated_at").String(),
	}
}
