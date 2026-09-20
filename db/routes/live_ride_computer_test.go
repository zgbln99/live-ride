package routes

import (
	"testing"
	"time"

	"github.com/pocketbase/pocketbase/core"
)

// Publiczny LIVE jako komputer pokładowy, a nie tracker GPS.
//
// Każdy test odpowiada jednej rzeczy, której strona wcześniej nie umiała
// pokazać, choć aplikacja miała ją na ekranie. Wszystkie chodzą przez ten sam
// uchwyt HTTP, którego używa produkcja, więc sprawdzają odpowiedź, a nie
// funkcję pomocniczą.

func liveRideSnapshot(t *testing.T, f *liveRideFixture) map[string]any {
	t.Helper()
	token := f.session.GetString("share_token")
	status, body, _ := f.call(
		t, LiveRidePublicSnapshot, "/live/"+token, "/live/{token}",
	)
	if status != 200 {
		t.Fatalf("snapshot status = %d, want 200", status)
	}
	return body
}

func liveRideFirstRider(t *testing.T, body map[string]any) map[string]any {
	t.Helper()
	riders, _ := body["riders"].([]any)
	if len(riders) == 0 {
		t.Fatal("snapshot has no riders")
	}
	rider, _ := riders[0].(map[string]any)
	if rider == nil {
		t.Fatal("rider is not an object")
	}
	return rider
}

func TestLiveRideSnapshotCarriesNavigation(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 3, func(rider *core.Record) {
		rider.Set("nav_instruction", "Skręć w lewo w Burgenlandstraße")
		rider.Set("nav_street", "Burgenlandstraße")
		rider.Set("nav_maneuver_type", 15)
		rider.Set("nav_distance_m", 310.0)
		rider.Set("nav_remaining_m", 17800.0)
		rider.Set("nav_eta_seconds", 2760)
		rider.Set("elapsed_seconds", 1710)
		rider.Set("gradient_percent", 8.2)
	})

	rider := liveRideFirstRider(t, liveRideSnapshot(t, f))
	nav, _ := rider["nav"].(map[string]any)
	if nav == nil {
		t.Fatal("snapshot has no navigation state")
	}
	// Instrukcja przychodzi gotowa z telefonu i nie jest tutaj składana:
	// dwie warstwy nawigacji rozjechałyby się na pierwszym rondzie.
	if nav["instruction"] != "Skręć w lewo w Burgenlandstraße" {
		t.Fatalf("instruction = %v", nav["instruction"])
	}
	if nav["street"] != "Burgenlandstraße" {
		t.Fatalf("street = %v", nav["street"])
	}
	if nav["distance_m"] != 310.0 {
		t.Fatalf("distance_m = %v", nav["distance_m"])
	}
	if rider["elapsed_seconds"] != float64(1710) {
		t.Fatalf("elapsed_seconds = %v", rider["elapsed_seconds"])
	}
	if rider["gradient_percent"] != 8.2 {
		t.Fatalf("gradient_percent = %v", rider["gradient_percent"])
	}
	// Średnia liczona po stronie serwera z dystansu i czasu w ruchu.
	if rider["average_speed_kmh"] == nil {
		t.Fatal("average_speed_kmh missing")
	}
}

func TestLiveRideSnapshotCarriesClimb(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 3, func(rider *core.Record) {
		rider.Set("climb_index", 2)
		rider.Set("climb_total", 5)
		rider.Set("climb_done_m", 1300.0)
		rider.Set("climb_length_m", 2400.0)
		rider.Set("climb_gain_m", 152.0)
		rider.Set("climb_remaining_gain_m", 83.0)
		rider.Set("climb_avg_gradient", 6.3)
		rider.Set("climb_max_gradient", 9.1)
		rider.Set("climb_category", "3")
	})

	rider := liveRideFirstRider(t, liveRideSnapshot(t, f))
	climb, _ := rider["climb"].(map[string]any)
	if climb == nil {
		t.Fatal("snapshot has no climb")
	}
	if climb["index"] != float64(2) || climb["total"] != float64(5) {
		t.Fatalf("climb index/total = %v/%v", climb["index"], climb["total"])
	}
	if climb["remaining_gain_m"] != 83.0 {
		t.Fatalf("remaining_gain_m = %v", climb["remaining_gain_m"])
	}
}

func TestLiveRideClimbDisappearsAfterTheSummit(t *testing.T) {
	f := newLiveRideFixture(t)
	// Zerowa długość znaczy „zawodnik nie jest na żadnym podjeździe".
	// Kafelek ma wtedy zniknąć, a nie zamrozić się na stu procentach.
	f.addRider(t, "Marek", 3, func(rider *core.Record) {
		rider.Set("climb_length_m", 0.0)
		rider.Set("climb_index", 2)
	})

	rider := liveRideFirstRider(t, liveRideSnapshot(t, f))
	if _, present := rider["climb"]; present {
		t.Fatal("climb should be absent once the rider is past the summit")
	}
}

func TestLiveRideNavigationNeedsPositionConsent(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 3, func(rider *core.Record) {
		rider.Set("share_position", false)
		rider.Set("nav_instruction", "Skręć w lewo w Cichą")
		rider.Set("climb_length_m", 800.0)
		rider.Set("gradient_percent", 7.4)
	})

	rider := liveRideFirstRider(t, liveRideSnapshot(t, f))
	// „Za 90 m w lewo w Cichą" samo w sobie mówi, gdzie ktoś jest, więc
	// dzieli ustawienie prywatności z pozycją.
	for _, field := range []string{"nav", "climb", "gradient_percent", "latitude"} {
		if _, present := rider[field]; present {
			t.Fatalf("%s leaked without position consent", field)
		}
	}
}

func TestLiveRideSensorsCarrySourceAndFreshness(t *testing.T) {
	f := newLiveRideFixture(t)
	moment := time.Now().UTC().Add(-40 * time.Second)
	f.addRider(t, "Marek", 3, func(rider *core.Record) {
		rider.Set("share_heart_rate", true)
		rider.Set("share_battery", true)
		rider.Set("hr_source", "WHOOP")
		rider.Set("hr_updated_at", moment)
		rider.Set("hr_battery_percent", 37)
		rider.Set("avg_heart_rate_bpm", 139)
		rider.Set("max_heart_rate_bpm", 176)
	})

	rider := liveRideFirstRider(t, liveRideSnapshot(t, f))
	if rider["heart_rate_bpm"] != float64(148) {
		t.Fatalf("heart_rate_bpm = %v", rider["heart_rate_bpm"])
	}
	if rider["hr_source"] != "WHOOP" {
		t.Fatalf("hr_source = %v", rider["hr_source"])
	}
	// Bez znacznika strona nie ma jak odróżnić tętna sprzed sekundy od
	// tętna sprzed czterech minut.
	if rider["hr_updated_at"] == nil {
		t.Fatal("hr_updated_at missing")
	}
	batteries, _ := rider["batteries"].(map[string]any)
	if batteries == nil || batteries["heart_rate"] != float64(37) {
		t.Fatalf("batteries = %v", rider["batteries"])
	}
}

func TestLiveRideSensorBatteryFollowsItsOwnConsent(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 3, func(rider *core.Record) {
		rider.Set("share_battery", true)
		rider.Set("share_heart_rate", false)
		rider.Set("hr_battery_percent", 37)
	})

	rider := liveRideFirstRider(t, liveRideSnapshot(t, f))
	batteries, _ := rider["batteries"].(map[string]any)
	if batteries == nil {
		t.Fatal("batteries missing")
	}
	// Bateria czujnika, którego danych zawodnik nie udostępnia, zdradza, że
	// ten czujnik w ogóle ma — a tego też nie udostępnił.
	if _, present := batteries["heart_rate"]; present {
		t.Fatal("heart-rate battery leaked without heart-rate consent")
	}
	if batteries["phone"] != float64(71) {
		t.Fatalf("phone battery = %v", batteries["phone"])
	}
}

func TestLiveRideHiddenStartWithholdsPosition(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 3, func(rider *core.Record) {
		// Zawodnik stoi dokładnie tam, gdzie wystartował.
		rider.Set("start_lat", 50.78)
		rider.Set("start_lon", 16.92)
		rider.Set("hide_start_m", 500)
	})

	rider := liveRideFirstRider(t, liveRideSnapshot(t, f))
	if _, present := rider["latitude"]; present {
		t.Fatal("position leaked inside the hidden start radius")
	}
	if rider["location_hidden"] != true {
		t.Fatal("strona musi wiedzieć, że to ukrycie, a nie brak fiksa")
	}
	// Dystans i czas zostają: ukryta jest okolica domu, nie cała jazda.
	if rider["distance_m"] != 21400.0 {
		t.Fatalf("distance_m = %v", rider["distance_m"])
	}
}

func TestLiveRideHiddenStartReleasesPositionFurtherAway(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 3, func(rider *core.Record) {
		// Start dwa kilometry na południe od bieżącej pozycji.
		rider.Set("start_lat", 50.76)
		rider.Set("start_lon", 16.92)
		rider.Set("hide_start_m", 500)
	})

	rider := liveRideFirstRider(t, liveRideSnapshot(t, f))
	if rider["latitude"] != 50.78 {
		t.Fatalf("latitude = %v, want the real position outside the radius", rider["latitude"])
	}
}

func TestLiveRideCoarseLocationRoundsServerSide(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 3, func(rider *core.Record) {
		rider.Set("latitude", 50.781234)
		rider.Set("longitude", 16.924567)
		rider.Set("location_coarse", true)
	})

	rider := liveRideFirstRider(t, liveRideSnapshot(t, f))
	if rider["latitude"] != 50.781 || rider["longitude"] != 16.925 {
		t.Fatalf("coarse position = %v, %v", rider["latitude"], rider["longitude"])
	}
	if rider["location_coarse"] != true {
		t.Fatal("strona musi wiedzieć, że pozycja jest przybliżona")
	}
	// Dokładność bieżącego fiksa przeczyłaby zaokrągleniu.
	if _, present := rider["accuracy_m"]; present {
		t.Fatal("accuracy leaked with a coarse position")
	}
}

func TestLiveRideDelayedLocationWithholdsFreshFix(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 3, func(record *core.Record) {
		record.Set("location_delay_seconds", 60)
	})
	// Same świeże punkty: nic nie jest jeszcze dość stare, żeby to pokazać.
	f.addPoints(t, rider, 3, time.Now().UTC().Add(-20*time.Second), 5*time.Second)

	view := liveRideFirstRider(t, liveRideSnapshot(t, f))
	if _, present := view["latitude"]; present {
		t.Fatal("delayed location must not fall back to the live fix")
	}
	if view["location_delayed"] != true {
		t.Fatal("strona musi wiedzieć, że pozycja jest opóźniona")
	}
}

func TestLiveRideDelayedLocationUsesTheOlderSample(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 3, func(record *core.Record) {
		record.Set("location_delay_seconds", 60)
	})
	// Sześć punktów co minutę, ostatni z tej chwili. Szerokość rośnie
	// o 0,001 na próbkę, więc widać po niej, którą z nich wydał serwer.
	f.addPoints(t, rider, 6, time.Now().UTC().Add(-5*time.Minute), time.Minute)

	view := liveRideFirstRider(t, liveRideSnapshot(t, f))
	latitude, _ := view["latitude"].(float64)
	if latitude == 0 {
		t.Fatal("delayed location missing although old samples exist")
	}
	// Najświeższa próbka (50.785) jest wstrzymana, wydana została ta sprzed
	// minuty. Gdyby opóźnienie pokazywało bieżący punkt, nie byłoby
	// opóźnieniem.
	if latitude != 50.784 {
		t.Fatalf("latitude = %v, want the sample from before the cutoff", latitude)
	}
}

func TestLiveRideEventsAreReadableWithTheToken(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 3, nil)
	for index, kind := range []string{"start", "off_route", "back_on_route"} {
		event := core.NewRecord(f.events)
		event.Set("session", f.session.Id)
		event.Set("participant", rider.Id)
		event.Set("at", time.Now().UTC().Add(-time.Duration(30-index*10)*time.Minute))
		event.Set("kind", kind)
		event.Set("seq", index+1)
		event.Set("distance_m", float64(1000*(index+1)))
		if err := f.app.Save(event); err != nil {
			t.Fatal(err)
		}
	}

	token := f.session.GetString("share_token")
	status, body, _ := f.call(
		t, LiveRidePublicEvents, "/live/"+token+"/events", "/live/{token}/events",
	)
	if status != 200 {
		t.Fatalf("events status = %d", status)
	}
	events, _ := body["events"].([]any)
	if len(events) != 3 {
		t.Fatalf("events = %d, want 3", len(events))
	}
	// Od najnowszego, bo tak się to czyta i tak pokazuje strona.
	first, _ := events[0].(map[string]any)
	if first["kind"] != "back_on_route" {
		t.Fatalf("first event = %v", first["kind"])
	}
}

func TestLiveRideExpiredLinkGivesNoEvents(t *testing.T) {
	f := newLiveRideFixture(t)
	f.session.Set("expires_at", time.Now().UTC().Add(-time.Hour))
	if err := f.app.Save(f.session); err != nil {
		t.Fatal(err)
	}
	rider := f.addRider(t, "Marek", 3, nil)
	event := core.NewRecord(f.events)
	event.Set("session", f.session.Id)
	event.Set("participant", rider.Id)
	event.Set("at", time.Now().UTC())
	event.Set("kind", "off_route")
	event.Set("seq", 1)
	if err := f.app.Save(event); err != nil {
		t.Fatal(err)
	}

	token := f.session.GetString("share_token")
	_, body, _ := f.call(
		t, LiveRidePublicEvents, "/live/"+token+"/events", "/live/{token}/events",
	)
	if body["status"] != "expired" {
		t.Fatalf("status = %v", body["status"])
	}
	// Wygasły link nie jest furtką do historii jazdy.
	if events, _ := body["events"].([]any); len(events) != 0 {
		t.Fatalf("expired link returned %d events", len(events))
	}
}

func TestLiveRideRouteCarriesRevisionAndCheckpoints(t *testing.T) {
	f := newLiveRideFixture(t)
	route := core.NewRecord(f.routes)
	route.Set("name", "Berlin → Poczdam")
	route.Set("polyline", string(liveRidePolylineCodec.EncodeCoords(nil, [][]float64{
		{52.5, 13.4}, {52.4, 13.2}, {52.39, 13.06},
	})))
	route.Set("distance_m", 42300.0)
	route.Set("waypoints", []map[string]any{
		{"name": "Start", "lat": 52.5, "lon": 13.4, "distance_m": 0.0},
		{"name": "Wannsee", "lat": 52.43, "lon": 13.17, "distance_m": 12400.0},
		{"name": "", "lat": 52.41, "lon": 13.1, "distance_m": 20000.0},
		{"name": "Meta", "lat": 52.39, "lon": 13.06, "distance_m": 42300.0},
	})
	if err := f.app.Save(route); err != nil {
		t.Fatal(err)
	}
	f.session.Set("route", route.Id)
	f.session.Set("route_revision", 3)
	if err := f.app.Save(f.session); err != nil {
		t.Fatal(err)
	}

	token := f.session.GetString("share_token")
	status, body, _ := f.call(
		t, LiveRidePublicRoute, "/live/"+token+"/route", "/live/{token}/route",
	)
	if status != 200 {
		t.Fatalf("route status = %d", status)
	}
	if body["revision"] != float64(3) {
		t.Fatalf("revision = %v", body["revision"])
	}
	checkpoints, _ := body["checkpoints"].([]any)
	// Start i meta mają na stronie własne miejsce, a bezimienny punkt jest
	// szczegółem układania trasy — zostaje jeden checkpoint.
	if len(checkpoints) != 1 {
		t.Fatalf("checkpoints = %d, want 1", len(checkpoints))
	}
	first, _ := checkpoints[0].(map[string]any)
	if first["name"] != "Wannsee" {
		t.Fatalf("checkpoint = %v", first["name"])
	}
}

func TestLiveRideSnapshotCarriesRouteRevision(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 3, nil)
	f.session.Set("route_revision", 4)
	f.session.Set("event_seq", 11)
	if err := f.app.Save(f.session); err != nil {
		t.Fatal(err)
	}

	body := liveRideSnapshot(t, f)
	// Strona pobiera geometrię dopiero wtedy, gdy ta liczba urośnie.
	if body["route_revision"] != float64(4) {
		t.Fatalf("route_revision = %v", body["route_revision"])
	}
	if body["event_seq"] != float64(11) {
		t.Fatalf("event_seq = %v", body["event_seq"])
	}
}

func TestLiveRideStaleSampleIsIgnored(t *testing.T) {
	participant := core.NewRecord(core.NewBaseCollection("x"))
	participant.Set("telemetry_seq", 105)

	older := &liveRideTelemetryPoint{Seq: 103, RecordedAt: time.Now().UTC()}
	if !liveRideStaleSample(participant, older) {
		t.Fatal("sample 103 must not overwrite the state written by 105")
	}
	newer := &liveRideTelemetryPoint{Seq: 106, RecordedAt: time.Now().UTC()}
	if liveRideStaleSample(participant, newer) {
		t.Fatal("sample 106 must be accepted")
	}
	// Ta sama próbka wysłana ponownie też jest stara: numer nie urósł.
	same := &liveRideTelemetryPoint{Seq: 105, RecordedAt: time.Now().UTC()}
	if !liveRideStaleSample(participant, same) {
		t.Fatal("resent sample must not rewrite the state")
	}
}

func TestLiveRideStaleSampleFallsBackToTime(t *testing.T) {
	// Telefon starej wersji nie numeruje. Wtedy rozstrzyga znacznik czasu,
	// a nie „brak numeru znaczy nowsze".
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 30, nil)

	older := &liveRideTelemetryPoint{RecordedAt: time.Now().UTC().Add(-2 * time.Minute)}
	if !liveRideStaleSample(rider, older) {
		t.Fatal("older sample must not overwrite a newer state")
	}
	newer := &liveRideTelemetryPoint{RecordedAt: time.Now().UTC()}
	if liveRideStaleSample(rider, newer) {
		t.Fatal("newer sample must be accepted")
	}
}

func TestLiveRideHistoryRespectsPrivacy(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 3, func(record *core.Record) {
		record.Set("share_speed", true)
		record.Set("share_heart_rate", false)
		record.Set("share_power", false)
	})
	f.addPoints(t, rider, 6, time.Now().UTC().Add(-10*time.Minute), time.Minute)

	token := f.session.GetString("share_token")
	status, body, _ := f.call(
		t, LiveRideHistory, "/live/"+token+"/history", "/live/{token}/history",
	)
	if status != 200 {
		t.Fatalf("history status = %d", status)
	}
	riders, _ := body["riders"].([]any)
	if len(riders) != 1 {
		t.Fatalf("riders = %d, want 1", len(riders))
	}
	entry, _ := riders[0].(map[string]any)
	samples, _ := entry["samples"].([]any)
	if len(samples) == 0 {
		t.Fatal("history has no samples")
	}
	first, _ := samples[0].(map[string]any)
	if _, present := first["speed_kmh"]; !present {
		t.Fatal("speed missing although the rider shares it")
	}
	// Historia, z której da się odczytać tętno wyłączone przełącznikiem,
	// byłaby obejściem tego przełącznika.
	for _, field := range []string{"heart_rate_bpm", "power_watts", "cadence_rpm"} {
		if _, present := first[field]; present {
			t.Fatalf("%s leaked into the history without consent", field)
		}
	}
}

func TestLiveRideHistoryHonoursTheLocationDelay(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 3, func(record *core.Record) {
		record.Set("location_delay_seconds", 300)
	})
	// Same świeże punkty — wszystkie młodsze niż opóźnienie.
	f.addPoints(t, rider, 4, time.Now().UTC().Add(-2*time.Minute), 20*time.Second)

	token := f.session.GetString("share_token")
	_, body, _ := f.call(
		t, LiveRideHistory, "/live/"+token+"/history", "/live/{token}/history",
	)
	// Bez tego wystarczyłoby poprosić o historię „do teraz", żeby ominąć
	// opóźnienie wprowadzone dla bieżącej pozycji.
	if riders, _ := body["riders"].([]any); len(riders) != 0 {
		t.Fatalf("history leaked %d riders inside the delay window", len(riders))
	}
}

func TestLiveRideHistoryNeedsPositionConsent(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 3, func(record *core.Record) {
		record.Set("share_position", false)
	})
	f.addPoints(t, rider, 4, time.Now().UTC().Add(-10*time.Minute), time.Minute)

	token := f.session.GetString("share_token")
	_, body, _ := f.call(
		t, LiveRideHistory, "/live/"+token+"/history", "/live/{token}/history",
	)
	if riders, _ := body["riders"].([]any); len(riders) != 0 {
		t.Fatal("history exposed a rider who does not share position")
	}
}
