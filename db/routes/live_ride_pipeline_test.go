package routes

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
)

// Cała droga trasy: telefon → serwer → publiczna strona.
//
// To jest test najczęstszej i najgorzej widocznej usterki publicznego LIVE:
// zawodnik widzi trasę w aplikacji, a strona pokazuje sam znacznik. Nie było
// tam żadnego błędu do znalezienia. Sesja wskazywała trasę samym `client_id`,
// serwer szukał jej wśród tras JUŻ ZSYNCHRONIZOWANYCH i po prostu jej nie
// znajdował — po czym zapisywał sesję bez trasy i odpowiadał 200.
//
// Osiem scenariuszy z życia (trasa świeżo z kreatora, z GPX-a, z cudzego
// linku, wybrana po starcie LIVE, zmieniona w trakcie, przeliczona po
// zjechaniu) sprowadza się do jednego pytania: czy serwer przyjmie trasę,
// której jeszcze nie ma. Dlatego testujemy właśnie to.

// authedCall uruchamia uchwyt wymagający zalogowania.
func (f *liveRideFixture) authedCall(
	t *testing.T,
	handler func(*core.RequestEvent) error,
	method string,
	path string,
	pattern string,
	user *core.Record,
	payload any,
) (int, map[string]any) {
	t.Helper()

	var body *bytes.Reader
	if payload != nil {
		encoded, err := json.Marshal(payload)
		if err != nil {
			t.Fatal(err)
		}
		body = bytes.NewReader(encoded)
	} else {
		body = bytes.NewReader(nil)
	}

	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(method, path, body)
	request.Header.Set("Content-Type", "application/json")

	mux := http.NewServeMux()
	mux.HandleFunc(pattern, func(w http.ResponseWriter, r *http.Request) {
		event := &core.RequestEvent{}
		event.App = f.app
		event.Request = r
		event.Response = w
		event.Auth = user
		if err := handler(event); err != nil {
			if apiError, ok := err.(*router.ApiError); ok {
				w.WriteHeader(apiError.Status)
				_ = json.NewEncoder(w).Encode(map[string]any{"message": apiError.Message})
				return
			}
			w.WriteHeader(http.StatusInternalServerError)
			_ = json.NewEncoder(w).Encode(map[string]any{"message": err.Error()})
		}
	})
	mux.ServeHTTP(recorder, request)

	var decoded map[string]any
	if recorder.Body.Len() > 0 {
		_ = json.Unmarshal(recorder.Body.Bytes(), &decoded)
	}
	return recorder.Code, decoded
}

// liveRideOwner tworzy konto i przypisuje je do sesji z atrapy.
func liveRideOwner(t *testing.T, f *liveRideFixture) *core.Record {
	t.Helper()
	users, err := f.app.FindCollectionByNameOrId("users")
	if err != nil {
		t.Fatal(err)
	}
	user := core.NewRecord(users)
	user.Set("email", "rider@example.test")
	user.SetPassword("hunter2hunter2")
	if err := f.app.Save(user); err != nil {
		t.Fatal(err)
	}
	f.session.Set("owner", user.Id)
	if err := f.app.Save(f.session); err != nil {
		t.Fatal(err)
	}
	return user
}

// liveRidePolyline koduje prostą linię na wschód.
func liveRidePolyline(points int) string {
	coordinates := make([][]float64, 0, points)
	for i := 0; i < points; i++ {
		coordinates = append(coordinates, []float64{52.0 + float64(i)*0.001, 21.0})
	}
	return string(liveRidePolylineCodec.EncodeCoords(nil, coordinates))
}

func TestLiveRideAttachRouteAcceptsAnUnsyncedRoute(t *testing.T) {
	f := newLiveRideFixture(t)
	owner := liveRideOwner(t, f)

	status, body := f.authedCall(
		t, LiveRideAttachRoute, http.MethodPost,
		"/live-rides/"+f.session.Id+"/route", "/live-rides/{id}/route",
		owner,
		map[string]any{
			"route": map[string]any{
				"client_id":  "route_local_1",
				"name":       "Berlin → Poczdam",
				"distance_m": 42300,
				"ascent_m":   480,
				"polyline":   liveRidePolyline(40),
				"climbs":     []any{},
				"surfaces":   []any{},
			},
		},
	)
	if status != 200 {
		t.Fatalf("attach status = %d (%v)", status, body)
	}
	if body["has_route"] != true {
		t.Fatalf("has_route = %v", body["has_route"])
	}
	// Pierwsza wersja planu tej sesji.
	if body["revision"] != float64(1) {
		t.Fatalf("revision = %v, want 1", body["revision"])
	}

	// Trasa, której serwer nigdy nie widział, ma zostać zapisana jako
	// PRYWATNA: doczepienie jej do jazdy nie jest zgodą na jej udostępnienie.
	stored, err := f.app.FindRecordsByFilter(
		"live_ride_routes", "client_id = 'route_local_1'", "", 1, 0,
	)
	if err != nil || len(stored) == 0 {
		t.Fatalf("route was not stored: %v", err)
	}
	if stored[0].GetString("privacy") != "private" {
		t.Fatalf("privacy = %q, want private", stored[0].GetString("privacy"))
	}

	// I natychmiast widoczna dla posiadacza linku.
	token := f.session.GetString("share_token")
	routeStatus, routeBody, _ := f.call(
		t, LiveRidePublicRoute, "/live/"+token+"/route", "/live/{token}/route",
	)
	if routeStatus != 200 {
		t.Fatalf("public route status = %d", routeStatus)
	}
	if routeBody["polyline"] == "" || routeBody["polyline"] == nil {
		t.Fatal("public route has no geometry — dokładnie ta usterka, o którą chodzi")
	}
	if routeBody["name"] != "Berlin → Poczdam" {
		t.Fatalf("name = %v", routeBody["name"])
	}
}

func TestLiveRideAttachRouteBumpsRevisionOnlyWhenGeometryChanges(t *testing.T) {
	f := newLiveRideFixture(t)
	owner := liveRideOwner(t, f)
	payload := map[string]any{
		"route": map[string]any{
			"client_id": "route_local_1",
			"name":      "Pętla",
			"polyline":  liveRidePolyline(30),
		},
	}

	_, first := f.authedCall(
		t, LiveRideAttachRoute, http.MethodPost,
		"/live-rides/"+f.session.Id+"/route", "/live-rides/{id}/route", owner, payload,
	)
	if first["revision"] != float64(1) {
		t.Fatalf("first revision = %v", first["revision"])
	}

	// Telefon ponawia doczepianie co tyknięcie licznika jako siatkę
	// bezpieczeństwa. Gdyby każde z nich podbijało wersję, strona pobierałaby
	// całą geometrię co kilka sekund — czyli dokładnie to, czemu
	// wersjonowanie ma zapobiec.
	_, again := f.authedCall(
		t, LiveRideAttachRoute, http.MethodPost,
		"/live-rides/"+f.session.Id+"/route", "/live-rides/{id}/route", owner, payload,
	)
	if again["revision"] != float64(1) {
		t.Fatalf("unchanged route bumped the revision to %v", again["revision"])
	}

	// Przeliczenie trasy po zjechaniu to nowa geometria — i nowa wersja.
	rerouted := map[string]any{
		"route": map[string]any{
			"client_id": "route_local_1",
			"name":      "Pętla",
			"polyline":  liveRidePolyline(45),
		},
	}
	_, third := f.authedCall(
		t, LiveRideAttachRoute, http.MethodPost,
		"/live-rides/"+f.session.Id+"/route", "/live-rides/{id}/route", owner, rerouted,
	)
	if third["revision"] != float64(2) {
		t.Fatalf("reroute revision = %v, want 2", third["revision"])
	}

	// Podmiana trasy w trakcie jazdy zostawia ślad na osi czasu: inaczej mapa
	// po cichu zmienia kształt i wygląda to jak błąd strony.
	events, err := f.app.FindRecordsByFilter(
		"live_ride_events", "kind = 'reroute'", "", 10, 0,
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 {
		t.Fatalf("reroute events = %d, want 1", len(events))
	}
}

func TestLiveRideAttachRouteRejectsAForeignRoute(t *testing.T) {
	f := newLiveRideFixture(t)
	owner := liveRideOwner(t, f)

	// Cudza trasa o znanym identyfikatorze.
	users, _ := f.app.FindCollectionByNameOrId("users")
	stranger := core.NewRecord(users)
	stranger.Set("email", "stranger@example.test")
	stranger.SetPassword("hunter2hunter2")
	if err := f.app.Save(stranger); err != nil {
		t.Fatal(err)
	}
	foreign := core.NewRecord(f.routes)
	foreign.Set("owner", stranger.Id)
	foreign.Set("client_id", "route_secret")
	foreign.Set("name", "Cudza trasa")
	foreign.Set("polyline", liveRidePolyline(10))
	foreign.Set("privacy", "private")
	if err := f.app.Save(foreign); err != nil {
		t.Fatal(err)
	}

	status, _ := f.authedCall(
		t, LiveRideAttachRoute, http.MethodPost,
		"/live-rides/"+f.session.Id+"/route", "/live-rides/{id}/route", owner,
		map[string]any{"route_client_id": "route_secret"},
	)
	// Bez filtra po właścicielu identyfikator z cudzego telefonu przypinałby
	// cudzą trasę do własnego publicznego linku.
	if status != 404 {
		t.Fatalf("status = %d, want 404 for a foreign route", status)
	}
	if f.session.GetString("route") != "" {
		t.Fatal("foreign route was attached")
	}
}

func TestLiveRideAttachRouteRefusesSomeoneElsesRide(t *testing.T) {
	f := newLiveRideFixture(t)
	liveRideOwner(t, f)

	users, _ := f.app.FindCollectionByNameOrId("users")
	stranger := core.NewRecord(users)
	stranger.Set("email", "stranger@example.test")
	stranger.SetPassword("hunter2hunter2")
	if err := f.app.Save(stranger); err != nil {
		t.Fatal(err)
	}

	status, _ := f.authedCall(
		t, LiveRideAttachRoute, http.MethodPost,
		"/live-rides/"+f.session.Id+"/route", "/live-rides/{id}/route", stranger,
		map[string]any{"route": map[string]any{"polyline": liveRidePolyline(10)}},
	)
	if status != 403 {
		t.Fatalf("status = %d, want 403", status)
	}
}

func TestLiveRideDetachRemovesThePlan(t *testing.T) {
	f := newLiveRideFixture(t)
	owner := liveRideOwner(t, f)
	f.authedCall(
		t, LiveRideAttachRoute, http.MethodPost,
		"/live-rides/"+f.session.Id+"/route", "/live-rides/{id}/route", owner,
		map[string]any{"route": map[string]any{
			"client_id": "route_local_1",
			"polyline":  liveRidePolyline(20),
		}},
	)

	_, body := f.authedCall(
		t, LiveRideAttachRoute, http.MethodPost,
		"/live-rides/"+f.session.Id+"/route", "/live-rides/{id}/route", owner,
		map[string]any{"detach": true},
	)
	if body["has_route"] != false {
		t.Fatalf("has_route = %v", body["has_route"])
	}
	// Zakończona nawigacja musi zdjąć plan ze strony, a nie zostawić widza
	// z trasą, którą zawodnik dawno porzucił.
	if body["revision"] != float64(2) {
		t.Fatalf("detach revision = %v, want 2", body["revision"])
	}
}

func TestLiveRideDiagnosticsNamesTheMissingRoute(t *testing.T) {
	f := newLiveRideFixture(t)
	owner := liveRideOwner(t, f)
	rider := f.addRider(t, "Marek", 3, func(record *core.Record) {
		record.Set("user", owner.Id)
		record.Set("share_heart_rate", false)
		record.Set("hr_source", "WHOOP")
		record.Set("hr_updated_at", time.Now().UTC())
	})
	_ = rider

	status, body := f.authedCall(
		t, LiveRideDiagnostics, http.MethodGet,
		"/live-rides/"+f.session.Id+"/diagnostics", "/live-rides/{id}/diagnostics",
		owner, nil,
	)
	if status != 200 {
		t.Fatalf("diagnostics status = %d (%v)", status, body)
	}

	route, _ := body["route"].(map[string]any)
	if route == nil || route["attached"] != false {
		t.Fatalf("route diagnostics = %v", body["route"])
	}

	heart, _ := body["heart_rate"].(map[string]any)
	if heart == nil {
		t.Fatal("heart-rate diagnostics missing")
	}
	// Rozróżnienie, którego brak kosztował najwięcej czasu: pas mierzy,
	// ale zawodnik wyłączył udostępnianie. Bez tego jedno i drugie wygląda
	// na stronie identycznie — jako puste pole.
	if heart["present"] != true {
		t.Fatalf("heart rate present = %v, want true", heart["present"])
	}
	if heart["shared"] != false {
		t.Fatalf("heart rate shared = %v, want false", heart["shared"])
	}
	if heart["source"] != "WHOOP" {
		t.Fatalf("heart rate source = %v", heart["source"])
	}
}

func TestLiveRideDiagnosticsRefusesStrangers(t *testing.T) {
	f := newLiveRideFixture(t)
	liveRideOwner(t, f)
	users, _ := f.app.FindCollectionByNameOrId("users")
	stranger := core.NewRecord(users)
	stranger.Set("email", "stranger@example.test")
	stranger.SetPassword("hunter2hunter2")
	if err := f.app.Save(stranger); err != nil {
		t.Fatal(err)
	}

	status, _ := f.authedCall(
		t, LiveRideDiagnostics, http.MethodGet,
		"/live-rides/"+f.session.Id+"/diagnostics", "/live-rides/{id}/diagnostics",
		stranger, nil,
	)
	if status != 403 {
		t.Fatalf("status = %d, want 403", status)
	}
}

func TestLiveRideTelemetryEndToEnd(t *testing.T) {
	f := newLiveRideFixture(t)
	owner := liveRideOwner(t, f)
	f.addRider(t, "Marek", 0, func(record *core.Record) {
		record.Set("user", owner.Id)
		record.Set("share_heart_rate", true)
		record.Set("share_power", true)
		record.Set("share_battery", true)
		// Świeży zawodnik bez żadnej próbki: pierwsza telemetria ma dopisać
		// „Start" na oś czasu.
		record.Set("last_seen_at", "")
		record.Set("latitude", 0.0)
		record.Set("longitude", 0.0)
	})

	recordedAt := time.Now().UTC()
	status, body := f.authedCall(
		t, LiveRideTelemetry, http.MethodPost,
		"/live-rides/"+f.session.Id+"/telemetry", "/live-rides/{id}/telemetry",
		owner,
		map[string]any{"points": []map[string]any{{
			"recorded_at":      recordedAt.Format(time.RFC3339Nano),
			"latitude":         52.4123,
			"longitude":        13.1187,
			"speed_kmh":        31.4,
			"altitude_m":       84.0,
			"accuracy_m":       4.0,
			"heart_rate_bpm":   143,
			"cadence_rpm":      89,
			"power_watts":      242,
			"distance_m":       12140.0,
			"elevation_gain_m": 310.0,
			"state":            "riding",
			"moving_seconds":   1540,
			"elapsed_seconds":  1710,
			"max_speed_kmh":    58.7,
			"battery_percent":  61,
			"gradient_percent": 8.2,
			"seq":              104,
			"nav": map[string]any{
				"instruction":   "Skręć w lewo w Burgenlandstraße",
				"street":        "Burgenlandstraße",
				"maneuver_type": 15,
				"distance_m":    310.0,
				"remaining_m":   30160.0,
				"eta_seconds":   3450,
				"off_route":     false,
			},
			"climb": map[string]any{
				"index":            2,
				"total":            5,
				"done_m":           1300.0,
				"length_m":         2400.0,
				"gain_m":           152.0,
				"remaining_gain_m": 83.0,
				"avg_gradient":     6.3,
				"max_gradient":     9.1,
				"category":         "3",
			},
			"sources":   map[string]any{"heart_rate": "WHOOP", "power": "Assioma"},
			"batteries": map[string]any{"phone": 61, "heart_rate": 37},
			"freshness": map[string]any{
				"gps_age_seconds": 1.0,
				"hr_age_seconds":  2.0,
				// Ujemny wiek znaczy „nie mam tej danej wcale".
				"cadence_age_seconds": -1.0,
			},
			"averages": map[string]any{
				"avg_heart_rate_bpm": 139,
				"max_heart_rate_bpm": 176,
				"avg_power_watts":    218,
				"max_power_watts":    612,
				"avg_cadence_rpm":    84,
			},
		}}},
	)
	if status != http.StatusAccepted {
		t.Fatalf("telemetry status = %d (%v)", status, body)
	}
	if body["seq"] != float64(104) {
		t.Fatalf("seq = %v", body["seq"])
	}

	// --- to, co zobaczy znajomy bez konta ------------------------------
	rider := liveRideFirstRider(t, liveRideSnapshot(t, f))

	if rider["distance_m"] != 12140.0 {
		t.Fatalf("distance_m = %v", rider["distance_m"])
	}
	if rider["moving_seconds"] != float64(1540) {
		t.Fatalf("moving_seconds = %v", rider["moving_seconds"])
	}
	if rider["elapsed_seconds"] != float64(1710) {
		t.Fatalf("elapsed_seconds = %v", rider["elapsed_seconds"])
	}
	if rider["heart_rate_bpm"] != float64(143) {
		t.Fatalf("heart_rate_bpm = %v", rider["heart_rate_bpm"])
	}
	if rider["power_watts"] != float64(242) || rider["cadence_rpm"] != float64(89) {
		t.Fatalf("power/cadence = %v/%v", rider["power_watts"], rider["cadence_rpm"])
	}
	if rider["hr_source"] != "WHOOP" {
		t.Fatalf("hr_source = %v", rider["hr_source"])
	}
	if rider["avg_power_watts"] != float64(218) || rider["max_heart_rate_bpm"] != float64(176) {
		t.Fatalf("averages missing: %v", rider)
	}

	nav, _ := rider["nav"].(map[string]any)
	if nav == nil || nav["street"] != "Burgenlandstraße" || nav["distance_m"] != 310.0 {
		t.Fatalf("nav = %v", rider["nav"])
	}
	climb, _ := rider["climb"].(map[string]any)
	if climb == nil || climb["index"] != float64(2) || climb["total"] != float64(5) {
		t.Fatalf("climb = %v", rider["climb"])
	}
	batteries, _ := rider["batteries"].(map[string]any)
	if batteries == nil || batteries["heart_rate"] != float64(37) {
		t.Fatalf("batteries = %v", rider["batteries"])
	}

	// Kadencja przyszła z ujemnym wiekiem, więc znacznik ma zostać pusty:
	// „nie mam czujnika" to nie to samo co „czujnik milczy od godziny".
	if _, present := rider["cadence_updated_at"]; present {
		t.Fatal("cadence freshness set although the phone said it has none")
	}
	if rider["hr_updated_at"] == nil {
		t.Fatal("hr_updated_at missing")
	}

	// Pierwsza próbka zostawia „Start" na osi czasu.
	token := f.session.GetString("share_token")
	_, events, _ := f.call(
		t, LiveRidePublicEvents, "/live/"+token+"/events", "/live/{token}/events",
	)
	list, _ := events["events"].([]any)
	// „Start" i wejście na drugi podjazd — obie rzeczy wydarzyły się w tej
	// samej próbce i obie są przejściem, nie zgłoszeniem z telefonu.
	if len(list) != 2 {
		t.Fatalf("events = %d, want 2 (start + climb_start)", len(list))
	}
	newest, _ := list[0].(map[string]any)
	oldest, _ := list[1].(map[string]any)
	if newest["kind"] != "climb_start" || newest["label"] != "2/5" {
		t.Fatalf("newest event = %v", newest)
	}
	if oldest["kind"] != "start" {
		t.Fatalf("oldest event = %v", oldest["kind"])
	}
}

func TestLiveRideTelemetryDerivesStateEvents(t *testing.T) {
	f := newLiveRideFixture(t)
	owner := liveRideOwner(t, f)
	f.addRider(t, "Marek", 5, func(record *core.Record) {
		record.Set("user", owner.Id)
		record.Set("state", "riding")
	})

	send := func(seq int, state string, offRoute bool, minutesAgo int) {
		status, body := f.authedCall(
			t, LiveRideTelemetry, http.MethodPost,
			"/live-rides/"+f.session.Id+"/telemetry", "/live-rides/{id}/telemetry",
			owner,
			map[string]any{"points": []map[string]any{{
				"recorded_at": time.Now().UTC().
					Add(-time.Duration(minutesAgo) * time.Minute).Format(time.RFC3339Nano),
				"latitude":   52.41,
				"longitude":  13.11,
				"distance_m": float64(1000 * seq),
				"state":      state,
				"seq":        seq,
				"nav": map[string]any{
					"instruction": "Jedź prosto",
					"off_route":   offRoute,
				},
			}}},
		)
		if status != http.StatusAccepted {
			t.Fatalf("telemetry seq %d status = %d (%v)", seq, status, body)
		}
	}

	send(1, "riding", false, 4)
	send(2, "stopped", false, 3)
	send(3, "riding", true, 2)
	send(4, "riding", false, 1)

	token := f.session.GetString("share_token")
	_, body, _ := f.call(
		t, LiveRidePublicEvents, "/live/"+token+"/events", "/live/{token}/events",
	)
	list, _ := body["events"].([]any)
	kinds := make([]string, 0, len(list))
	for _, entry := range list {
		event, _ := entry.(map[string]any)
		kinds = append(kinds, event["kind"].(string))
	}
	// Od najnowszego. Przejścia, nie zgłoszenia z telefonu: „zjechał z trasy"
	// pojawia się dokładnie raz, w chwili zmiany pola.
	want := []string{"back_on_route", "off_route", "resume", "auto_pause"}
	if len(kinds) != len(want) {
		t.Fatalf("events = %v, want %v", kinds, want)
	}
	for i, kind := range want {
		if kinds[i] != kind {
			t.Fatalf("events = %v, want %v", kinds, want)
		}
	}
}

func TestLiveRideTelemetryIgnoresALateBatch(t *testing.T) {
	f := newLiveRideFixture(t)
	owner := liveRideOwner(t, f)
	f.addRider(t, "Marek", 5, func(record *core.Record) {
		record.Set("user", owner.Id)
	})

	send := func(seq int, latitude float64) (int, map[string]any) {
		return f.authedCall(
			t, LiveRideTelemetry, http.MethodPost,
			"/live-rides/"+f.session.Id+"/telemetry", "/live-rides/{id}/telemetry",
			owner,
			map[string]any{"points": []map[string]any{{
				"recorded_at": time.Now().UTC().
					Add(time.Duration(seq) * time.Second).Format(time.RFC3339Nano),
				"latitude":   latitude,
				"longitude":  13.11,
				"distance_m": float64(1000 * seq),
				"state":      "riding",
				"seq":        seq,
			}}},
		)
	}

	send(105, 52.50)
	// Paczka z tunelu, która dotarła jako ostatnia. Punkty historii ma prawo
	// uzupełnić; „gdzie on jest teraz" — nie.
	_, late := send(103, 52.10)
	if late["stale"] != true {
		t.Fatalf("late batch response = %v, want stale", late)
	}

	rider := liveRideFirstRider(t, liveRideSnapshot(t, f))
	if rider["latitude"] != 52.50 {
		t.Fatalf("latitude = %v — starsza próbka cofnęła zawodnika", rider["latitude"])
	}
}
