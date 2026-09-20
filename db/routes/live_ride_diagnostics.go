package routes

import (
	"math"
	"net/http"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
)

// Diagnostyka LIVE dla właściciela jazdy.
//
// Aplikacja wie, co WYSŁAŁA. Nie wie, co serwer PRZYJĄŁ — a różnica między
// tymi dwiema rzeczami to dokładnie ta klasa usterek, przez którą publiczna
// strona bywała pusta mimo działającego licznika: pas HR mierzył, telefon
// wysyłał, a pole zostawało wyłączone przełącznikiem prywatności i nigdzie
// nie było tego widać.
//
// Dlatego odpowiedź opisuje STAN SERWERA, nie telefonu. Zawodnik otwiera ten
// ekran i widzi to samo, co zobaczyłby widz — plus powody, dla których
// czegoś tam nie ma.
//
// Nigdy nie trafia do publicznego API: wymaga zalogowania i własności sesji.
func LiveRideDiagnostics(e *core.RequestEvent) error {
	session, err := e.App.FindRecordById("live_ride_sessions", e.Request.PathValue("id"))
	if err != nil {
		return apis.NewNotFoundError("Live ride not found", err)
	}
	if session.GetString("owner") != e.Auth.Id {
		return apis.NewForbiddenError("Only the live ride owner can read diagnostics", nil)
	}

	now := time.Now().UTC()
	participant, err := e.App.FindFirstRecordByFilter(
		"live_ride_participants",
		"session={:session} && user={:user}",
		dbx.Params{"session": session.Id, "user": e.Auth.Id},
	)
	if err != nil {
		return e.JSON(http.StatusOK, map[string]any{
			"server_time": now.Format(time.RFC3339),
			"session": map[string]any{
				"status":  session.GetString("status"),
				"joined":  false,
				"viewers": LiveRideViewers(session.Id),
			},
		})
	}

	diagnostics := map[string]any{
		"server_time": now.Format(time.RFC3339),
		"session": map[string]any{
			"status":     session.GetString("status"),
			"visibility": liveRideVisibility(session),
			"joined":     true,
			"started_at": session.GetDateTime("started_at"),
			"expired":    liveRideShareExpired(session, now),
			// Liczba otwartych strumieni, nie liczba ludzi. Żaden odcisk
			// przeglądarki, cookie ani adres nigdzie nie jest zapisywany.
			"viewers":   LiveRideViewers(session.Id),
			"event_seq": session.GetInt("event_seq"),
		},
		"telemetry": map[string]any{
			"seq":          participant.GetInt("telemetry_seq"),
			"last_seen_at": participant.GetDateTime("last_seen_at"),
			"age_seconds":  liveRideAgeSeconds(participant, "last_seen_at", now),
			"state":        participant.GetString("state"),
		},
		"gps": liveRideSignalJSON(
			participant, now, "gps_updated_at",
			liveRideHasFix(participant),
			map[string]any{"accuracy_m": participant.GetFloat("accuracy_m")},
		),
		"heart_rate": liveRideSignalJSON(
			participant, now, "hr_updated_at",
			participant.GetInt("heart_rate_bpm") > 0,
			map[string]any{
				"bpm":     participant.GetInt("heart_rate_bpm"),
				"source":  participant.GetString("hr_source"),
				"shared":  liveRideShares(participant, "share_heart_rate"),
				"battery": liveRideOptionalInt(participant, "hr_battery_percent"),
			},
		),
		"power": liveRideSignalJSON(
			participant, now, "power_updated_at",
			participant.GetInt("power_watts") > 0,
			map[string]any{
				"watts":   participant.GetInt("power_watts"),
				"source":  participant.GetString("power_source"),
				"shared":  liveRideShares(participant, "share_power"),
				"battery": liveRideOptionalInt(participant, "power_battery_percent"),
			},
		),
		"cadence": liveRideSignalJSON(
			participant, now, "cadence_updated_at",
			participant.GetInt("cadence_rpm") > 0,
			map[string]any{
				"rpm":     participant.GetInt("cadence_rpm"),
				"source":  participant.GetString("cadence_source"),
				"shared":  liveRideShares(participant, "share_power"),
				"battery": liveRideOptionalInt(participant, "cadence_battery_percent"),
			},
		),
		"navigation": liveRideSignalJSON(
			participant, now, "nav_updated_at",
			participant.GetString("nav_instruction") != "" || participant.GetBool("nav_off_route"),
			map[string]any{
				"instruction": participant.GetString("nav_instruction"),
				"street":      participant.GetString("nav_street"),
				"distance_m":  participant.GetFloat("nav_distance_m"),
				"off_route":   participant.GetBool("nav_off_route"),
			},
		),
		"privacy": map[string]any{
			"position":               liveRideShares(participant, "share_position"),
			"speed":                  liveRideShares(participant, "share_speed"),
			"heart_rate":             liveRideShares(participant, "share_heart_rate"),
			"power":                  liveRideShares(participant, "share_power"),
			"battery":                liveRideShares(participant, "share_battery"),
			"location_delay_seconds": participant.GetInt("location_delay_seconds"),
			"location_coarse":        participant.GetBool("location_coarse"),
			"hide_start_m":           participant.GetInt("hide_start_m"),
			"hide_finish_m":          participant.GetInt("hide_finish_m"),
		},
		"phone_battery": liveRideOptionalInt(participant, "battery_percent"),
	}

	diagnostics["route"] = liveRideRouteDiagnostics(e, session)
	return e.JSON(http.StatusOK, diagnostics)
}

// liveRideRouteDiagnostics mówi, czy serwer NAPRAWDĘ ma plan tej jazdy.
//
// Najczęstsza usterka publicznego LIVE brzmiała „widzę trasę w aplikacji,
// nie widzę jej na stronie". Serwer nie zgłaszał wtedy żadnego błędu, bo
// z jego punktu widzenia nic złego się nie działo: sesja po prostu nie
// miała trasy. Tutaj widać to jednym spojrzeniem.
func liveRideRouteDiagnostics(e *core.RequestEvent, session *core.Record) map[string]any {
	result := map[string]any{
		"attached": false,
		"revision": session.GetInt("route_revision"),
	}
	if updated := session.GetDateTime("route_updated_at").Time(); !updated.IsZero() {
		result["updated_at"] = updated.UTC().Format(time.RFC3339)
	}
	routeID := session.GetString("route")
	if routeID == "" {
		if trail := session.GetString("trail"); trail != "" {
			result["attached"] = true
			result["source"] = "trail"
		}
		return result
	}
	route, err := e.App.FindRecordById("live_ride_routes", routeID)
	if err != nil {
		result["error"] = "route record missing"
		return result
	}
	result["attached"] = true
	result["source"] = "live_route"
	result["name"] = route.GetString("name")
	result["distance_m"] = route.GetFloat("distance_m")
	result["points"] = len(route.GetString("polyline"))
	result["checkpoints"] = len(liveRideCheckpoints(route))
	return result
}

// liveRideSignalJSON opisuje jeden sygnał: czy jest, jak stary, co niesie.
func liveRideSignalJSON(
	participant *core.Record,
	now time.Time,
	field string,
	present bool,
	extra map[string]any,
) map[string]any {
	result := map[string]any{"present": present}
	if age := liveRideAgeSeconds(participant, field, now); age != nil {
		result["age_seconds"] = age
	}
	for key, value := range extra {
		if value == nil {
			continue
		}
		if text, ok := value.(string); ok && text == "" {
			continue
		}
		result[key] = value
	}
	return result
}

// liveRideAgeSeconds zwraca wiek znacznika albo nil, gdy go nie ma.
//
// nil, a nie zero: „nigdy nie przyszło" i „przyszło przed chwilą" to dwie
// przeciwne wiadomości i nie wolno ich zapisać tą samą liczbą.
func liveRideAgeSeconds(participant *core.Record, field string, now time.Time) any {
	moment := participant.GetDateTime(field).Time()
	if moment.IsZero() {
		return nil
	}
	return math.Round(now.Sub(moment.UTC()).Seconds())
}

// liveRideOptionalInt zwraca liczbę albo nil, gdy pola nie ustawiono.
func liveRideOptionalInt(participant *core.Record, field string) any {
	if value := participant.GetInt(field); value > 0 {
		return value
	}
	return nil
}
