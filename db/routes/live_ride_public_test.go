package routes

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/pocketbase/pocketbase/core"
	pbtests "github.com/pocketbase/pocketbase/tests"
	"github.com/pocketbase/pocketbase/tools/router"
	"github.com/pocketbase/pocketbase/tools/security"
)

// Testy publicznej strony LIVE.
//
// Sprawdzają dokładnie to, co widzi znajomy bez konta: co dostanie pod
// poprawnym tokenem, czego NIE dostanie pod tokenem wygasłym i czego nigdy
// nie dostanie, jeśli zawodnik czegoś nie udostępnił. Filtr prywatności
// musi trzymać po stronie serwera, bo tylko tam nie da się go obejść.

type liveRideFixture struct {
	app         *pbtests.TestApp
	sessions    *core.Collection
	participant *core.Collection
	points      *core.Collection
	routes      *core.Collection
	events      *core.Collection
	session     *core.Record
}

func newLiveRideFixture(t *testing.T) *liveRideFixture {
	t.Helper()

	app, err := pbtests.NewTestApp(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(app.Cleanup)

	users, err := app.FindCollectionByNameOrId("users")
	if err != nil {
		t.Fatal(err)
	}

	sessions := core.NewBaseCollection("live_ride_sessions")
	sessions.Fields.Add(
		&core.RelationField{Name: "owner", CollectionId: users.Id, MaxSelect: 1},
		&core.TextField{Name: "title", Max: 160},
		&core.TextField{Name: "share_token", Max: 64},
		&core.TextField{Name: "join_token", Max: 32},
		&core.SelectField{Name: "status", Values: []string{"active", "ended"}, MaxSelect: 1},
		&core.SelectField{Name: "visibility", Values: []string{"public", "unlisted", "disabled"}, MaxSelect: 1},
		&core.SelectField{Name: "kind", Values: []string{"solo", "group"}, MaxSelect: 1},
		&core.BoolField{Name: "expire_on_end"},
		&core.DateField{Name: "started_at"},
		&core.DateField{Name: "ended_at"},
		&core.DateField{Name: "expires_at"},
		&core.JSONField{Name: "summary", MaxSize: 20000},
		&core.TextField{Name: "trail", Max: 40},
		&core.TextField{Name: "route", Max: 40},
		&core.NumberField{Name: "route_revision", OnlyInt: true},
		&core.DateField{Name: "route_updated_at"},
		&core.NumberField{Name: "event_seq", OnlyInt: true},
		&core.NumberField{Name: "meetup_lat"},
		&core.NumberField{Name: "meetup_lon"},
		&core.TextField{Name: "meetup_label", Max: 160},
	)
	if err := app.Save(sessions); err != nil {
		t.Fatal(err)
	}

	participants := core.NewBaseCollection("live_ride_participants")
	participants.Fields.Add(
		&core.RelationField{Name: "session", CollectionId: sessions.Id, MaxSelect: 1},
		&core.RelationField{Name: "user", CollectionId: users.Id, MaxSelect: 1},
		&core.TextField{Name: "display_name", Max: 80},
		&core.NumberField{Name: "latitude"},
		&core.NumberField{Name: "longitude"},
		&core.NumberField{Name: "speed_kmh"},
		&core.NumberField{Name: "altitude_m"},
		&core.NumberField{Name: "heading_deg"},
		&core.NumberField{Name: "accuracy_m"},
		&core.NumberField{Name: "heart_rate_bpm", OnlyInt: true},
		&core.NumberField{Name: "cadence_rpm", OnlyInt: true},
		&core.NumberField{Name: "power_watts", OnlyInt: true},
		&core.NumberField{Name: "distance_m"},
		&core.NumberField{Name: "elevation_gain_m"},
		&core.NumberField{Name: "moving_seconds", OnlyInt: true},
		&core.NumberField{Name: "max_speed_kmh"},
		&core.NumberField{Name: "battery_percent", OnlyInt: true},
		&core.BoolField{Name: "share_position"},
		&core.BoolField{Name: "share_speed"},
		&core.BoolField{Name: "share_heart_rate"},
		&core.BoolField{Name: "share_power"},
		&core.BoolField{Name: "share_battery"},
		&core.SelectField{Name: "state", Values: []string{"riding", "paused", "stopped"}, MaxSelect: 1},
		&core.SelectField{Name: "role", Values: []string{"rider", "leader"}, MaxSelect: 1},
		&core.DateField{Name: "last_seen_at"},
		&core.DateField{Name: "joined_at"},
		&core.NumberField{Name: "auto_paused_seconds", OnlyInt: true},
		&core.NumberField{Name: "manual_paused_seconds", OnlyInt: true},
	)
	// Pola komputera pokładowego pochodzą z migracji. Powielamy je tutaj
	// nazwa w nazwę, bo testowa aplikacja PocketBase startuje bez migracji —
	// gdyby któraś nazwa się rozjechała, testy przechodziłyby na schemacie,
	// którego nie ma na produkcji.
	participants.Fields.Add(
		&core.NumberField{Name: "elapsed_seconds", OnlyInt: true},
		&core.NumberField{Name: "gradient_percent"},
		&core.TextField{Name: "nav_instruction", Max: 200},
		&core.TextField{Name: "nav_street", Max: 160},
		&core.NumberField{Name: "nav_maneuver_type", OnlyInt: true},
		&core.NumberField{Name: "nav_distance_m"},
		&core.NumberField{Name: "nav_remaining_m"},
		&core.NumberField{Name: "nav_eta_seconds", OnlyInt: true},
		&core.BoolField{Name: "nav_off_route"},
		&core.NumberField{Name: "nav_off_route_m"},
		&core.NumberField{Name: "climb_index", OnlyInt: true},
		&core.NumberField{Name: "climb_total", OnlyInt: true},
		&core.NumberField{Name: "climb_done_m"},
		&core.NumberField{Name: "climb_length_m"},
		&core.NumberField{Name: "climb_gain_m"},
		&core.NumberField{Name: "climb_remaining_gain_m"},
		&core.NumberField{Name: "climb_avg_gradient"},
		&core.NumberField{Name: "climb_max_gradient"},
		&core.TextField{Name: "climb_category", Max: 16},
		&core.NumberField{Name: "telemetry_seq", OnlyInt: true},
		&core.NumberField{Name: "sensor_speed_kmh"},
		&core.NumberField{Name: "sensor_distance_m"},
		&core.TextField{Name: "hr_source", Max: 40},
		&core.TextField{Name: "power_source", Max: 40},
		&core.TextField{Name: "cadence_source", Max: 40},
		&core.TextField{Name: "speed_source", Max: 40},
		&core.DateField{Name: "gps_updated_at"},
		&core.DateField{Name: "hr_updated_at"},
		&core.DateField{Name: "power_updated_at"},
		&core.DateField{Name: "cadence_updated_at"},
		&core.DateField{Name: "nav_updated_at"},
		&core.NumberField{Name: "avg_heart_rate_bpm", OnlyInt: true},
		&core.NumberField{Name: "max_heart_rate_bpm", OnlyInt: true},
		&core.NumberField{Name: "avg_power_watts", OnlyInt: true},
		&core.NumberField{Name: "max_power_watts", OnlyInt: true},
		&core.NumberField{Name: "avg_cadence_rpm", OnlyInt: true},
		&core.NumberField{Name: "hr_battery_percent", OnlyInt: true},
		&core.NumberField{Name: "power_battery_percent", OnlyInt: true},
		&core.NumberField{Name: "cadence_battery_percent", OnlyInt: true},
		&core.NumberField{Name: "speed_battery_percent", OnlyInt: true},
		&core.NumberField{Name: "location_delay_seconds", OnlyInt: true},
		&core.BoolField{Name: "location_coarse"},
		&core.NumberField{Name: "hide_start_m", OnlyInt: true},
		&core.NumberField{Name: "hide_finish_m", OnlyInt: true},
		&core.NumberField{Name: "start_lat"},
		&core.NumberField{Name: "start_lon"},
		&core.JSONField{Name: "insights", MaxSize: 4000},
	)
	if err := app.Save(participants); err != nil {
		t.Fatal(err)
	}

	liveRoutes := core.NewBaseCollection("live_ride_routes")
	liveRoutes.Fields.Add(
		&core.RelationField{Name: "owner", CollectionId: users.Id, MaxSelect: 1},
		&core.TextField{Name: "client_id", Max: 64},
		&core.TextField{Name: "name", Max: 160},
		&core.NumberField{Name: "distance_m"},
		&core.NumberField{Name: "ascent_m"},
		&core.NumberField{Name: "descent_m"},
		&core.TextField{Name: "polyline", Max: 1000000},
		&core.JSONField{Name: "waypoints", MaxSize: 200000},
		&core.JSONField{Name: "elevation_profile", MaxSize: 400000},
		&core.JSONField{Name: "climbs", MaxSize: 100000},
		&core.JSONField{Name: "surfaces", MaxSize: 100000},
		&core.SelectField{Name: "privacy", Values: []string{"private", "link", "public"}, MaxSelect: 1},
		&core.TextField{Name: "share_token", Max: 64},
		&core.DateField{Name: "client_updated_at"},
	)
	if err := app.Save(liveRoutes); err != nil {
		t.Fatal(err)
	}

	events := core.NewBaseCollection("live_ride_events")
	events.Fields.Add(
		&core.RelationField{Name: "session", CollectionId: sessions.Id, MaxSelect: 1},
		&core.RelationField{Name: "participant", CollectionId: participants.Id, MaxSelect: 1},
		&core.DateField{Name: "at"},
		&core.SelectField{Name: "kind", MaxSelect: 1, Values: []string{
			"start", "stop", "resume", "pause", "auto_pause",
			"climb_start", "climb_end", "off_route", "back_on_route",
			"reroute", "checkpoint", "finish", "sos",
		}},
		&core.TextField{Name: "label", Max: 120},
		&core.NumberField{Name: "distance_m"},
		&core.NumberField{Name: "value"},
		&core.NumberField{Name: "seq", OnlyInt: true},
	)
	if err := app.Save(events); err != nil {
		t.Fatal(err)
	}

	points := core.NewBaseCollection("live_ride_points")
	points.Fields.Add(
		&core.RelationField{Name: "session", CollectionId: sessions.Id, MaxSelect: 1},
		&core.RelationField{Name: "participant", CollectionId: participants.Id, MaxSelect: 1},
		&core.DateField{Name: "recorded_at"},
		&core.NumberField{Name: "latitude"},
		&core.NumberField{Name: "longitude"},
		&core.NumberField{Name: "speed_kmh"},
		&core.NumberField{Name: "heart_rate_bpm", OnlyInt: true},
		&core.NumberField{Name: "power_watts", OnlyInt: true},
	)
	if err := app.Save(points); err != nil {
		t.Fatal(err)
	}

	session := core.NewRecord(sessions)
	session.Set("title", "Sudety · sobotnia pętla")
	session.Set("share_token", security.RandomString(40))
	session.Set("join_token", "ABCD1234")
	session.Set("status", "active")
	session.Set("visibility", "unlisted")
	session.Set("started_at", time.Now().UTC().Add(-time.Hour))
	if err := app.Save(session); err != nil {
		t.Fatal(err)
	}

	return &liveRideFixture{
		app:         app,
		sessions:    sessions,
		participant: participants,
		points:      points,
		routes:      liveRoutes,
		events:      events,
		session:     session,
	}
}

// addRider creates one participant with an explicit privacy choice.
func (f *liveRideFixture) addRider(t *testing.T, name string, seenSecondsAgo int, mutate func(*core.Record)) *core.Record {
	t.Helper()
	rider := core.NewRecord(f.participant)
	rider.Set("session", f.session.Id)
	rider.Set("display_name", name)
	rider.Set("latitude", 50.78)
	rider.Set("longitude", 16.92)
	rider.Set("speed_kmh", 31.4)
	rider.Set("distance_m", 21400.0)
	rider.Set("elevation_gain_m", 612.0)
	rider.Set("moving_seconds", 4310)
	rider.Set("max_speed_kmh", 68.2)
	rider.Set("heart_rate_bpm", 148)
	rider.Set("power_watts", 243)
	rider.Set("cadence_rpm", 88)
	rider.Set("battery_percent", 71)
	rider.Set("state", "riding")
	rider.Set("share_position", true)
	rider.Set("share_speed", true)
	rider.Set("joined_at", time.Now().UTC().Add(-2*time.Hour))
	rider.Set("last_seen_at", time.Now().UTC().Add(-time.Duration(seenSecondsAgo)*time.Second))
	if mutate != nil {
		mutate(rider)
	}
	if err := f.app.Save(rider); err != nil {
		t.Fatal(err)
	}
	return rider
}

func (f *liveRideFixture) addPoints(t *testing.T, rider *core.Record, count int, start time.Time, step time.Duration) {
	t.Helper()
	for i := 0; i < count; i++ {
		point := core.NewRecord(f.points)
		point.Set("session", f.session.Id)
		point.Set("participant", rider.Id)
		point.Set("recorded_at", start.Add(time.Duration(i)*step).UTC())
		point.Set("latitude", 50.78+float64(i)*0.001)
		point.Set("longitude", 16.92+float64(i)*0.001)
		point.Set("heart_rate_bpm", 140+i%10)
		point.Set("power_watts", 200+i%20)
		if err := f.app.Save(point); err != nil {
			t.Fatal(err)
		}
	}
}

// call runs one public handler exactly the way the HTTP router would.
func (f *liveRideFixture) call(
	t *testing.T,
	handler func(*core.RequestEvent) error,
	path string,
	pattern string,
) (int, map[string]any, http.Header) {
	t.Helper()

	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, path, nil)
	// PathValue jest wypełniane przez ServeMux, więc w teście używamy go tak
	// samo jak produkcja — inaczej sprawdzalibyśmy inny kod niż działający.
	mux := http.NewServeMux()
	var status int
	var body map[string]any
	var header http.Header

	mux.HandleFunc(pattern, func(w http.ResponseWriter, r *http.Request) {
		event := &core.RequestEvent{}
		event.App = f.app
		event.Request = r
		event.Response = w
		if err := handler(event); err != nil {
			if apiError, ok := err.(*router.ApiError); ok {
				w.WriteHeader(apiError.Status)
				_ = json.NewEncoder(w).Encode(map[string]any{"message": apiError.Message})
				return
			}
			w.WriteHeader(http.StatusInternalServerError)
		}
	})
	mux.ServeHTTP(recorder, request)

	status = recorder.Code
	header = recorder.Header()
	if recorder.Body.Len() > 0 {
		_ = json.Unmarshal(recorder.Body.Bytes(), &body)
	}
	return status, body, header
}

func (f *liveRideFixture) snapshot(t *testing.T, token string) (int, map[string]any, http.Header) {
	return f.call(t, LiveRidePublicSnapshot, "/live/"+token, "/live/{token}")
}

func (f *liveRideFixture) track(t *testing.T, token, since string) (int, map[string]any, http.Header) {
	path := "/live/" + token + "/track"
	if since != "" {
		path += "?since=" + since
	}
	return f.call(t, LiveRidePublicTrack, path, "/live/{token}/track")
}

func riders(body map[string]any) []map[string]any {
	raw, _ := body["riders"].([]any)
	out := make([]map[string]any, 0, len(raw))
	for _, entry := range raw {
		if rider, ok := entry.(map[string]any); ok {
			out = append(out, rider)
		}
	}
	return out
}

// ------------------------------------------------------------------ tokeny

func TestLiveRideSnapshotValidToken(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 3, nil)

	status, body, header := f.snapshot(t, f.session.GetString("share_token"))
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if body["title"] != "Sudety · sobotnia pętla" {
		t.Errorf("title = %v", body["title"])
	}
	if body["status"] != "active" {
		t.Errorf("status = %v, want active", body["status"])
	}
	if len(riders(body)) != 1 {
		t.Fatalf("riders = %d, want 1", len(riders(body)))
	}
	// Migawka jest nieświeża sekundę później, a link „z linku" nie ma prawa
	// trafić do wyszukiwarki przez pośrednika.
	if got := header.Get("Cache-Control"); !strings.Contains(got, "no-store") {
		t.Errorf("Cache-Control = %q", got)
	}
	if got := header.Get("X-Robots-Tag"); !strings.Contains(got, "noindex") {
		t.Errorf("X-Robots-Tag = %q", got)
	}
}

func TestLiveRideSnapshotPublicSessionIsIndexable(t *testing.T) {
	f := newLiveRideFixture(t)
	f.session.Set("visibility", "public")
	if err := f.app.Save(f.session); err != nil {
		t.Fatal(err)
	}

	_, _, header := f.snapshot(t, f.session.GetString("share_token"))
	if header.Get("X-Robots-Tag") != "" {
		t.Errorf("publiczna jazda nie powinna dostawać noindex, dostała %q", header.Get("X-Robots-Tag"))
	}
}

func TestLiveRideSnapshotUnknownToken(t *testing.T) {
	f := newLiveRideFixture(t)
	status, _, _ := f.snapshot(t, security.RandomString(40))
	if status != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", status)
	}
}

func TestLiveRideSnapshotShortTokenIsNotFound(t *testing.T) {
	f := newLiveRideFixture(t)
	// Krótki token nie ma prawa uruchomić zapytania do bazy.
	status, _, _ := f.snapshot(t, "abc")
	if status != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", status)
	}
}

func TestLiveRideSnapshotExpiredToken(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 3, nil)
	f.session.Set("expires_at", time.Now().UTC().Add(-time.Minute))
	if err := f.app.Save(f.session); err != nil {
		t.Fatal(err)
	}

	_, body, _ := f.snapshot(t, f.session.GetString("share_token"))
	if body["status"] != "expired" {
		t.Fatalf("status = %v, want expired", body["status"])
	}
	// Wygasły link nie jest furtką do pozycji.
	if len(riders(body)) != 0 {
		t.Errorf("wygasły link wydał %d zawodników", len(riders(body)))
	}
}

func TestLiveRideSnapshotExpiresOnEnd(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 3, nil)
	f.session.Set("expire_on_end", true)
	f.session.Set("status", "ended")
	f.session.Set("ended_at", time.Now().UTC())
	if err := f.app.Save(f.session); err != nil {
		t.Fatal(err)
	}

	_, body, _ := f.snapshot(t, f.session.GetString("share_token"))
	if body["status"] != "expired" {
		t.Fatalf("status = %v, want expired", body["status"])
	}
}

func TestLiveRideSnapshotDisabledSharing(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 3, nil)
	f.session.Set("visibility", "disabled")
	if err := f.app.Save(f.session); err != nil {
		t.Fatal(err)
	}

	_, body, _ := f.snapshot(t, f.session.GetString("share_token"))
	if body["status"] != "disabled" {
		t.Fatalf("status = %v, want disabled", body["status"])
	}
	if len(riders(body)) != 0 {
		t.Errorf("wyłączony link wydał %d zawodników", len(riders(body)))
	}
}

// -------------------------------------------------------------- prywatność

func TestLiveRideSnapshotHidesHeartRateAndPower(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 3, nil) // share_heart_rate i share_power domyślnie false

	_, body, _ := f.snapshot(t, f.session.GetString("share_token"))
	rider := riders(body)[0]

	for _, field := range []string{"heart_rate_bpm", "power_watts", "cadence_rpm", "battery_percent"} {
		if _, present := rider[field]; present {
			t.Errorf("pole %q wyszło do widza mimo braku zgody", field)
		}
	}
	// To, na co zgoda jest, ma wyjść.
	for _, field := range []string{"latitude", "longitude", "speed_kmh", "distance_m"} {
		if _, present := rider[field]; !present {
			t.Errorf("pole %q powinno być widoczne", field)
		}
	}
}

func TestLiveRideSnapshotHidesPositionWhenRefused(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 3, func(rider *core.Record) {
		rider.Set("share_position", false)
		rider.Set("share_speed", true)
	})

	_, body, _ := f.snapshot(t, f.session.GetString("share_token"))
	rider := riders(body)[0]

	for _, field := range []string{"latitude", "longitude", "distance_m", "elevation_gain_m"} {
		if _, present := rider[field]; present {
			t.Errorf("pole %q wyszło mimo wyłączonej pozycji", field)
		}
	}
	if _, present := rider["speed_kmh"]; !present {
		t.Error("prędkość powinna zostać, bo zgoda na nią jest osobna")
	}
	// Nazwa zostaje zawsze: bez niej nie wiadomo, kogo się śledzi.
	if rider["display_name"] != "Marek" {
		t.Errorf("display_name = %v", rider["display_name"])
	}
}

func TestLiveRideSnapshotShowsEnabledFields(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 3, func(rider *core.Record) {
		rider.Set("share_heart_rate", true)
		rider.Set("share_power", true)
		rider.Set("share_battery", true)
	})

	_, body, _ := f.snapshot(t, f.session.GetString("share_token"))
	rider := riders(body)[0]

	if rider["heart_rate_bpm"] != float64(148) {
		t.Errorf("heart_rate_bpm = %v", rider["heart_rate_bpm"])
	}
	if rider["power_watts"] != float64(243) {
		t.Errorf("power_watts = %v", rider["power_watts"])
	}
	if rider["battery_percent"] != float64(71) {
		t.Errorf("battery_percent = %v", rider["battery_percent"])
	}
}

func TestLiveRideLegacyParticipantKeepsDefaults(t *testing.T) {
	f := newLiveRideFixture(t)
	// Uczestnik sprzed wprowadzenia pól prywatności: wszystkie na false.
	f.addRider(t, "Stary", 3, func(rider *core.Record) {
		rider.Set("share_position", false)
		rider.Set("share_speed", false)
	})

	_, body, _ := f.snapshot(t, f.session.GetString("share_token"))
	rider := riders(body)[0]

	if _, present := rider["latitude"]; !present {
		t.Error("uczestnik bez zapisanych preferencji powinien mieć domyślnie widoczną pozycję")
	}
	if _, present := rider["heart_rate_bpm"]; present {
		t.Error("tętno nie należy do domyślnie widocznych pól")
	}
}

// -------------------------------------------------------------------- stan

func TestLiveRideRiderStates(t *testing.T) {
	now := time.Now().UTC()

	cases := []struct {
		name     string
		state    string
		speed    float64
		seenAgo  time.Duration
		ended    bool
		expected string
	}{
		{"jedzie", "riding", 31, 3 * time.Second, false, "riding"},
		{"postój", "stopped", 0, 3 * time.Second, false, "stopped"},
		{"pauza", "paused", 0, 3 * time.Second, false, "paused"},
		{"offline wygrywa ze stanem", "riding", 31, 5 * time.Minute, false, "offline"},
		{"koniec jazdy", "riding", 31, 3 * time.Second, true, "ended"},
		// Stara aplikacja nie przysyła stanu — wnioskujemy z prędkości.
		{"bez stanu, stoi", "", 0.2, 3 * time.Second, false, "stopped"},
		{"bez stanu, jedzie", "", 24, 3 * time.Second, false, "riding"},
	}

	f := newLiveRideFixture(t)
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rider := core.NewRecord(f.participant)
			rider.Set("session", f.session.Id)
			rider.Set("display_name", tc.name)
			rider.Set("state", tc.state)
			rider.Set("speed_kmh", tc.speed)
			rider.Set("last_seen_at", now.Add(-tc.seenAgo))

			got, _ := liveRideRiderState(rider, now, tc.ended)
			if got != tc.expected {
				t.Errorf("state = %q, want %q", got, tc.expected)
			}
		})
	}
}

// Zawodnik, od którego jeszcze nic nie przyszło, CZEKA — nie zniknął.
//
// To są dwie różne wiadomości dla obserwującego. „Brak aktualnych danych"
// czyta się jak awarię i skłania do telefonu; „oczekiwanie na GPS" mówi, że
// wszystko jest w porządku i za chwilę coś się pojawi. Różnicę widać
// najostrzej w tej jednej sekundzie, w której znajomy otwiera link wysłany
// przed chwilą.
func TestLiveRideRiderWithoutTelemetryIsWaiting(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := core.NewRecord(f.participant)
	rider.Set("session", f.session.Id)
	rider.Set("display_name", "Nikt")

	state, age := liveRideRiderState(rider, time.Now().UTC(), false)
	if state != "waiting" {
		t.Errorf("state = %q, want waiting", state)
	}
	// Brak jakiejkolwiek telemetrii to nieskończony wiek, a nie zero sekund.
	if age <= liveRideOfflineAfterSeconds {
		t.Errorf("age = %v, want a very large value", age)
	}

	// Ale po zakończeniu jazdy stan zamknięcia wygrywa ze wszystkim.
	if state, _ := liveRideRiderState(rider, time.Now().UTC(), true); state != "ended" {
		t.Errorf("state po mecie = %q, want ended", state)
	}
}

// Najważniejsza obietnica publicznej strony: zawodnik jest w migawce od
// chwili udostępnienia linku, a nie od pierwszego przejechanego metra.
func TestLiveRideRiderVisibleBeforeAnyMovement(t *testing.T) {
	f := newLiveRideFixture(t)
	joined := time.Now().UTC().Add(-20 * time.Second)
	rider := core.NewRecord(f.participant)
	rider.Set("session", f.session.Id)
	rider.Set("display_name", "Marek")
	rider.Set("joined_at", joined)
	rider.Set("share_position", true)
	rider.Set("share_speed", true)
	if err := f.app.Save(rider); err != nil {
		t.Fatal(err)
	}

	_, body, _ := f.snapshot(t, f.session.GetString("share_token"))
	list := riders(body)
	if len(list) != 1 {
		t.Fatalf("migawka ma %d zawodników, chciano 1", len(list))
	}
	entry := list[0]

	if entry["display_name"] != "Marek" {
		t.Errorf("display_name = %v, want Marek", entry["display_name"])
	}
	if entry["state"] != "waiting" {
		t.Errorf("state = %v, want waiting", entry["state"])
	}
	if entry["has_fix"] != false {
		t.Errorf("has_fix = %v, want false", entry["has_fix"])
	}
	if entry["joined_at"] == nil {
		t.Error("chwila dołączenia musi być znana, zanim przyjdzie pierwszy fiks")
	}
	// Zero to poprawna szerokość geograficzna. Wysłane jako „brak pozycji"
	// postawiłoby znacznik na Atlantyku.
	if _, present := entry["latitude"]; present {
		t.Error("nieistniejąca pozycja nie ma prawa trafić do migawki")
	}
	if _, present := entry["longitude"]; present {
		t.Error("nieistniejąca pozycja nie ma prawa trafić do migawki")
	}
}

// Pierwszy fiks wystarcza; ruch nie jest do niczego potrzebny.
func TestLiveRideFirstFixAppearsWithoutMovement(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 2, func(record *core.Record) {
		// Stoi przed domem: zero przejechanych metrów, zero prędkości.
		record.Set("distance_m", 0.0)
		record.Set("speed_kmh", 0.0)
		record.Set("moving_seconds", 0)
		record.Set("state", "stopped")
	})
	_ = rider

	_, body, _ := f.snapshot(t, f.session.GetString("share_token"))
	entry := riders(body)[0]

	if entry["state"] != "stopped" {
		t.Errorf("state = %v, want stopped", entry["state"])
	}
	if entry["has_fix"] != true {
		t.Errorf("has_fix = %v, want true", entry["has_fix"])
	}
	if entry["latitude"] == nil || entry["longitude"] == nil {
		t.Error("pozycja stojącego zawodnika musi być widoczna")
	}
	if entry["distance_m"] != 0.0 {
		t.Errorf("distance_m = %v, want 0", entry["distance_m"])
	}
}

// Postoje wychodzą rozbite na dwa rodzaje i tylko wtedy, gdy istnieją.
func TestLiveRideSnapshotCarriesPauseBreakdown(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 3, func(record *core.Record) {
		record.Set("auto_paused_seconds", 640)
		record.Set("manual_paused_seconds", 300)
	})
	f.addRider(t, "Paweł", 3, nil)

	_, body, _ := f.snapshot(t, f.session.GetString("share_token"))
	list := riders(body)

	var marek, pawel map[string]any
	for _, entry := range list {
		switch entry["display_name"] {
		case "Marek":
			marek = entry
		case "Paweł":
			pawel = entry
		}
	}
	if marek == nil || pawel == nil {
		t.Fatalf("brakuje zawodników w migawce: %v", list)
	}
	if marek["auto_paused_seconds"] != 640.0 {
		t.Errorf("auto_paused_seconds = %v, want 640", marek["auto_paused_seconds"])
	}
	if marek["manual_paused_seconds"] != 300.0 {
		t.Errorf("manual_paused_seconds = %v, want 300", marek["manual_paused_seconds"])
	}
	// Zero postojów to brak pola, a nie „zero sekund na przystanku": strona
	// ma wtedy w ogóle nie pokazywać tego wiersza.
	if _, present := pawel["auto_paused_seconds"]; present {
		t.Error("zerowe postoje nie mają prawa trafić do migawki")
	}
}

// Postoje to część telemetrii pozycyjnej i dzielą jej ustawienie prywatności.
func TestLiveRidePauseBreakdownFollowsPositionPrivacy(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 3, func(record *core.Record) {
		record.Set("share_position", false)
		record.Set("auto_paused_seconds", 640)
		record.Set("manual_paused_seconds", 300)
	})

	_, body, _ := f.snapshot(t, f.session.GetString("share_token"))
	entry := riders(body)[0]

	for _, field := range []string{"auto_paused_seconds", "manual_paused_seconds"} {
		if _, present := entry[field]; present {
			t.Errorf("%s wyciekło mimo wyłączonego udostępniania pozycji", field)
		}
	}
}

func TestLiveRideSnapshotReportsOfflineRider(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 400, nil)

	_, body, _ := f.snapshot(t, f.session.GetString("share_token"))
	rider := riders(body)[0]

	if rider["state"] != "offline" {
		t.Errorf("state = %v, want offline", rider["state"])
	}
	// Ostatnia znana pozycja zostaje — o tym, że jest stara, mówi `state`.
	if _, present := rider["latitude"]; !present {
		t.Error("ostatnia znana pozycja powinna zostać w migawce")
	}
	if body["server_time"] == nil {
		t.Error("migawka musi nieść czas serwera, żeby widz nie liczył po swoim zegarze")
	}
}

// -------------------------------------------------------------------- grupa

func TestLiveRideSnapshotGroupRide(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 3, nil)
	f.addRider(t, "Paweł", 8, nil)
	f.addRider(t, "Kuba", 600, func(rider *core.Record) { rider.Set("state", "stopped") })

	_, body, _ := f.snapshot(t, f.session.GetString("share_token"))
	list := riders(body)
	if len(list) != 3 {
		t.Fatalf("riders = %d, want 3", len(list))
	}

	states := map[string]string{}
	for _, rider := range list {
		states[rider["display_name"].(string)] = rider["state"].(string)
	}
	if states["Marek"] != "riding" {
		t.Errorf("Marek = %q", states["Marek"])
	}
	if states["Kuba"] != "offline" {
		t.Errorf("Kuba = %q, want offline", states["Kuba"])
	}
}

// ---------------------------------------------------------------- ślad

func TestLiveRideTrackFullThenIncremental(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 3, nil)
	start := time.Now().UTC().Add(-time.Hour).Truncate(time.Second)
	f.addPoints(t, rider, 20, start, time.Second)

	_, body, _ := f.track(t, f.session.GetString("share_token"), "")
	tracks, _ := body["tracks"].([]any)
	if len(tracks) != 1 {
		t.Fatalf("tracks = %d, want 1", len(tracks))
	}
	first := tracks[0].(map[string]any)
	if first["points"] != float64(20) {
		t.Errorf("points = %v, want 20", first["points"])
	}
	if first["polyline"] == "" {
		t.Error("pełny ślad przyszedł pusty")
	}
	cursor, _ := first["cursor"].(string)
	if cursor == "" {
		t.Fatal("brak kursora, więc przyrostów nie da się pobrać")
	}

	// Kolejne pobranie od kursora nie może oddać tego samego jeszcze raz.
	_, body, _ = f.track(t, f.session.GetString("share_token"), cursor)
	if tracks, _ = body["tracks"].([]any); len(tracks) != 0 {
		t.Errorf("przyrost bez nowych punktów zwrócił %d śladów", len(tracks))
	}
	if body["incremental"] != true {
		t.Error("odpowiedź nie oznaczyła się jako przyrostowa")
	}

	// Po dołożeniu punktów przyrost oddaje TYLKO nowe.
	f.addPoints(t, rider, 5, start.Add(30*time.Second), time.Second)
	_, body, _ = f.track(t, f.session.GetString("share_token"), cursor)
	tracks, _ = body["tracks"].([]any)
	if len(tracks) != 1 {
		t.Fatalf("tracks = %d, want 1", len(tracks))
	}
	if got := tracks[0].(map[string]any)["points"]; got != float64(5) {
		t.Errorf("points = %v, want 5 — przyrost nie może powtarzać historii", got)
	}
}

func TestLiveRideTrackRespectsPositionPrivacy(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 3, func(r *core.Record) {
		r.Set("share_position", false)
		r.Set("share_speed", true)
	})
	f.addPoints(t, rider, 10, time.Now().UTC().Add(-time.Hour), time.Second)

	_, body, _ := f.track(t, f.session.GetString("share_token"), "")
	if tracks, _ := body["tracks"].([]any); len(tracks) != 0 {
		t.Errorf("ślad wyszedł mimo wyłączonej pozycji (%d)", len(tracks))
	}
}

func TestLiveRideTrackExpiredLinkGivesNothing(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 3, nil)
	f.addPoints(t, rider, 10, time.Now().UTC().Add(-time.Hour), time.Second)
	f.session.Set("expires_at", time.Now().UTC().Add(-time.Minute))
	if err := f.app.Save(f.session); err != nil {
		t.Fatal(err)
	}

	_, body, _ := f.track(t, f.session.GetString("share_token"), "")
	if body["status"] != "expired" {
		t.Errorf("status = %v, want expired", body["status"])
	}
	if tracks, _ := body["tracks"].([]any); len(tracks) != 0 {
		t.Errorf("wygasły link wydał %d śladów", len(tracks))
	}
}

func TestLiveRideTrackSamplesLongRides(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 3, nil)
	// Więcej punktów niż limit: ślad ma zostać rozrzedzony, a nie ucięty.
	count := liveRideTrackMaxPoints + 500
	f.addPoints(t, rider, count, time.Now().UTC().Add(-6*time.Hour), time.Second)

	_, body, _ := f.track(t, f.session.GetString("share_token"), "")
	tracks, _ := body["tracks"].([]any)
	first := tracks[0].(map[string]any)

	points := int(first["points"].(float64))
	if points > liveRideTrackMaxPoints+2 {
		t.Errorf("points = %d, want at most %d", points, liveRideTrackMaxPoints)
	}
	if first["sampled"] != true {
		t.Error("rozrzedzony ślad musi się do tego przyznać")
	}
	// Ostatni punkt zostaje zawsze: bez niego linia kończy się przed
	// znacznikiem zawodnika.
	if points < 2 {
		t.Fatalf("points = %d", points)
	}
}

func TestLiveRideTrackRejectsBadCursor(t *testing.T) {
	f := newLiveRideFixture(t)
	status, _, _ := f.track(t, f.session.GetString("share_token"), "wczoraj")
	if status != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", status)
	}
}

// ------------------------------------------------------------ podsumowanie

func TestLiveRideSummaryAfterEnd(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 3, func(r *core.Record) {
		r.Set("share_heart_rate", true)
		r.Set("share_power", true)
	})
	f.addPoints(t, rider, 30, time.Now().UTC().Add(-time.Hour), time.Minute)

	f.session.Set("status", "ended")
	f.session.Set("ended_at", time.Now().UTC())

	event := &core.RequestEvent{}
	event.App = f.app
	summary := liveRideBuildSummary(event, f.session)
	if summary == nil {
		t.Fatal("brak podsumowania")
	}

	rows, _ := summary["riders"].([]map[string]any)
	if len(rows) != 1 {
		t.Fatalf("riders = %d", len(rows))
	}
	row := rows[0]
	if row["distance_m"] != 21400.0 {
		t.Errorf("distance_m = %v", row["distance_m"])
	}
	if row["avg_heart_rate_bpm"] == nil {
		t.Error("średnie tętno powinno być policzone, bo zawodnik je udostępnia")
	}
	if summary["elapsed_seconds"].(int) <= 0 {
		t.Errorf("elapsed_seconds = %v", summary["elapsed_seconds"])
	}
}

func TestLiveRideSummaryOmitsPrivateFields(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 3, nil) // bez zgody na tętno i moc
	f.addPoints(t, rider, 10, time.Now().UTC().Add(-time.Hour), time.Minute)

	f.session.Set("ended_at", time.Now().UTC())
	event := &core.RequestEvent{}
	event.App = f.app

	rows, _ := liveRideBuildSummary(event, f.session)["riders"].([]map[string]any)
	for _, field := range []string{"avg_heart_rate_bpm", "avg_power_watts"} {
		if _, present := rows[0][field]; present {
			t.Errorf("pole %q trafiło do podsumowania mimo braku zgody", field)
		}
	}
}

// --------------------------------------------------------------- pomocnicze

func TestLiveRideShareExpiredRules(t *testing.T) {
	now := time.Date(2026, 5, 1, 12, 0, 0, 0, time.UTC)
	f := newLiveRideFixture(t)

	cases := []struct {
		name    string
		mutate  func(*core.Record)
		expired bool
	}{
		{"aktywna bez ograniczeń", func(*core.Record) {}, false},
		{"data w przyszłości", func(s *core.Record) {
			s.Set("expires_at", now.Add(time.Hour))
		}, false},
		{"data w przeszłości", func(s *core.Record) {
			s.Set("expires_at", now.Add(-time.Hour))
		}, true},
		{"po zakończeniu, ale bez reguły", func(s *core.Record) {
			s.Set("status", "ended")
		}, false},
		{"po zakończeniu z regułą", func(s *core.Record) {
			s.Set("status", "ended")
			s.Set("expire_on_end", true)
		}, true},
		{"reguła bez zakończenia", func(s *core.Record) {
			s.Set("expire_on_end", true)
		}, false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			session := core.NewRecord(f.sessions)
			session.Set("status", "active")
			tc.mutate(session)
			if got := liveRideShareExpired(session, now); got != tc.expired {
				t.Errorf("liveRideShareExpired = %v, want %v", got, tc.expired)
			}
		})
	}
}

func TestLiveRideVisibilityDefaultsToUnlisted(t *testing.T) {
	f := newLiveRideFixture(t)
	for _, tc := range []struct{ stored, want string }{
		{"public", "public"},
		{"unlisted", "unlisted"},
		{"disabled", "disabled"},
		// Sesja sprzed wprowadzenia pola i każda literówka lądują na
		// najostrożniejszym ustawieniu.
		{"", "unlisted"},
		{"wszyscy", "unlisted"},
	} {
		session := core.NewRecord(f.sessions)
		session.Set("visibility", tc.stored)
		if got := liveRideVisibility(session); got != tc.want {
			t.Errorf("liveRideVisibility(%q) = %q, want %q", tc.stored, got, tc.want)
		}
	}
}

func TestNormalizeLiveRideState(t *testing.T) {
	for input, want := range map[string]string{
		"riding":  "riding",
		" PAUSED": "paused",
		"stopped": "stopped",
		"":        "",
		"pedals":  "",
	} {
		if got := normalizeLiveRideState(input); got != want {
			t.Errorf("normalizeLiveRideState(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestLiveRideFileName(t *testing.T) {
	for input, want := range map[string]string{
		"Sudety · sobotnia pętla": "Sudety-sobotnia-p-tla",
		"  ":                      "live-ride-trasa",
		"../../etc/passwd":        "etc-passwd",
		"Trasa_2026":              "Trasa_2026",
	} {
		if got := liveRideFileName(input); got != want {
			t.Errorf("liveRideFileName(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestLiveRideEscapeXML(t *testing.T) {
	got := liveRideEscapeXML(`Trasa & "test" <b>`)
	for _, forbidden := range []string{"<b>", `"test"`} {
		if strings.Contains(got, forbidden) {
			t.Errorf("liveRideEscapeXML nie zabezpieczył %q: %s", forbidden, got)
		}
	}
	if !strings.Contains(got, "&amp;") {
		t.Errorf("ampersand nie został zamieniony: %s", got)
	}
}

// Nazwa pliku z polskimi znakami musi dać się wstawić do nagłówka HTTP bez
// psucia go — stąd sprowadzenie do ASCII.
func TestLiveRideFileNameIsHeaderSafe(t *testing.T) {
	name := liveRideFileName("Zażółć gęślą jaźń")
	for _, r := range name {
		if r > 127 {
			t.Fatalf("nazwa pliku zawiera znak spoza ASCII: %q", name)
		}
	}
	if name == "" {
		t.Fatal("pusta nazwa pliku")
	}
	// Nagłówek musi dać się złożyć bez cytowania spoza ASCII.
	header := fmt.Sprintf("attachment; filename=%q.gpx", name)
	if !strings.Contains(header, name) {
		t.Fatalf("nagłówek nie zawiera nazwy: %s", header)
	}
}

// ------------------------------------------------------------------- GPX

func newLiveRideRouteFixture(t *testing.T) (*pbtests.TestApp, *core.Record) {
	t.Helper()

	app, err := pbtests.NewTestApp(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(app.Cleanup)

	users, err := app.FindCollectionByNameOrId("users")
	if err != nil {
		t.Fatal(err)
	}

	routes := core.NewBaseCollection("live_ride_routes")
	routes.Fields.Add(
		&core.RelationField{Name: "owner", CollectionId: users.Id, MaxSelect: 1},
		&core.TextField{Name: "client_id", Max: 64},
		&core.TextField{Name: "name", Max: 160},
		&core.TextField{Name: "description", Max: 2000},
		&core.JSONField{Name: "tags", MaxSize: 4000},
		&core.NumberField{Name: "distance_m"},
		&core.NumberField{Name: "ascent_m"},
		&core.NumberField{Name: "descent_m"},
		&core.TextField{Name: "polyline", Max: 1000000},
		&core.JSONField{Name: "waypoints", MaxSize: 200000},
		&core.JSONField{Name: "preferences", MaxSize: 8000},
		&core.JSONField{Name: "elevation_profile", MaxSize: 100000},
		&core.JSONField{Name: "climbs", MaxSize: 40000},
		&core.JSONField{Name: "surfaces", MaxSize: 8000},
		&core.SelectField{Name: "privacy", Values: []string{"private", "link", "public"}, MaxSelect: 1},
		&core.TextField{Name: "share_token", Max: 64},
		&core.NumberField{Name: "copy_count", OnlyInt: true},
		&core.DateField{Name: "client_updated_at"},
	)
	if err := app.Save(routes); err != nil {
		t.Fatal(err)
	}

	coordinates := [][]float64{
		{50.780000, 16.920000},
		{50.781000, 16.921500},
		{50.782200, 16.923100},
		{50.783900, 16.925000},
	}

	route := core.NewRecord(routes)
	route.Set("client_id", "route_1")
	route.Set("name", "Sudety · sobotnia pętla")
	route.Set("description", "Dwa podjazdy & kawa")
	route.Set("polyline", string(liveRidePolylineCodec.EncodeCoords(nil, coordinates)))
	route.Set("distance_m", 46400.0)
	route.Set("ascent_m", 1180.0)
	route.Set("privacy", "link")
	route.Set("share_token", security.RandomString(liveRideShareTokenBytes))
	route.Set("elevation_profile", []any{
		map[string]any{"d": 0, "e": 320},
		map[string]any{"d": 200, "e": 380},
		map[string]any{"d": 600, "e": 500},
	})
	if err := app.Save(route); err != nil {
		t.Fatal(err)
	}
	return app, route
}

func liveRideRouteRequest(
	t *testing.T,
	app *pbtests.TestApp,
	handler func(*core.RequestEvent) error,
	path, pattern string,
) (int, string, http.Header) {
	t.Helper()
	recorder := httptest.NewRecorder()
	mux := http.NewServeMux()
	mux.HandleFunc(pattern, func(w http.ResponseWriter, r *http.Request) {
		event := &core.RequestEvent{}
		event.App = app
		event.Request = r
		event.Response = w
		if err := handler(event); err != nil {
			if apiError, ok := err.(*router.ApiError); ok {
				w.WriteHeader(apiError.Status)
				return
			}
			w.WriteHeader(http.StatusInternalServerError)
		}
	})
	mux.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, path, nil))
	return recorder.Code, recorder.Body.String(), recorder.Header()
}

func TestLiveRideRouteGPXDownload(t *testing.T) {
	app, route := newLiveRideRouteFixture(t)
	token := route.GetString("share_token")

	status, body, header := liveRideRouteRequest(
		t, app, LiveRideRouteGPX,
		"/live-routes/"+token+"/gpx", "/live-routes/{token}/gpx",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if got := header.Get("Content-Type"); !strings.HasPrefix(got, "application/gpx+xml") {
		t.Errorf("Content-Type = %q", got)
	}
	// Bez tego przeglądarka wyświetli XML zamiast zapisać plik.
	if got := header.Get("Content-Disposition"); !strings.Contains(got, "attachment") {
		t.Errorf("Content-Disposition = %q", got)
	}
	for _, want := range []string{"<gpx", "<trkseg>", `lat="50.780000"`, `lon="16.920000"`, "</gpx>"} {
		if !strings.Contains(body, want) {
			t.Errorf("GPX nie zawiera %q", want)
		}
	}
	// Profil wysokości jest, więc punkty muszą mieć <ele>.
	if !strings.Contains(body, "<ele>") {
		t.Error("GPX powinien nieść wysokości, bo trasa ma profil")
	}
	// Ampersand z opisu nie może rozwalić dokumentu.
	if strings.Contains(body, "podjazdy & kawa") {
		t.Error("ampersand nie został zabezpieczony w XML")
	}
}

func TestLiveRideRouteGPXWithoutProfileHasNoElevation(t *testing.T) {
	app, route := newLiveRideRouteFixture(t)
	route.Set("elevation_profile", nil)
	if err := app.Save(route); err != nil {
		t.Fatal(err)
	}

	_, body, _ := liveRideRouteRequest(
		t, app, LiveRideRouteGPX,
		"/live-routes/"+route.GetString("share_token")+"/gpx", "/live-routes/{token}/gpx",
	)
	// Zmyślone zero n.p.m. psułoby każdy program, który otworzy plik.
	if strings.Contains(body, "<ele>") {
		t.Error("GPX bez profilu nie może zawierać wysokości")
	}
}

func TestLiveRidePrivateRouteIsNotShared(t *testing.T) {
	app, route := newLiveRideRouteFixture(t)
	route.Set("privacy", "private")
	if err := app.Save(route); err != nil {
		t.Fatal(err)
	}
	token := route.GetString("share_token")

	for _, handler := range []struct {
		name    string
		fn      func(*core.RequestEvent) error
		path    string
		pattern string
	}{
		{"strona", LiveRidePublicRoutePage, "/live-routes/" + token, "/live-routes/{token}"},
		{"gpx", LiveRideRouteGPX, "/live-routes/" + token + "/gpx", "/live-routes/{token}/gpx"},
	} {
		t.Run(handler.name, func(t *testing.T) {
			status, _, _ := liveRideRouteRequest(t, app, handler.fn, handler.path, handler.pattern)
			if status != http.StatusNotFound {
				t.Fatalf("status = %d, want 404 — prywatna trasa nie istnieje dla widza", status)
			}
		})
	}
}

func TestLiveRidePublicRoutePageOmitsInternalIds(t *testing.T) {
	app, route := newLiveRideRouteFixture(t)
	status, body, _ := liveRideRouteRequest(
		t, app, LiveRidePublicRoutePage,
		"/live-routes/"+route.GetString("share_token"), "/live-routes/{token}",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}

	var payload map[string]any
	if err := json.Unmarshal([]byte(body), &payload); err != nil {
		t.Fatal(err)
	}
	for _, field := range []string{"id", "client_id", "owner"} {
		if _, present := payload[field]; present {
			t.Errorf("pole %q nie powinno wychodzić na publiczną stronę", field)
		}
	}
	if payload["precision"] != float64(liveRidePolylinePrecision) {
		t.Errorf("precision = %v, want %d", payload["precision"], liveRidePolylinePrecision)
	}
	if payload["elevation_profile"] == nil {
		t.Error("brak profilu wysokości w odpowiedzi")
	}
}
