package routes

import (
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// Oś czasu przejazdu.
//
// Migawka odpowiada wyłącznie na pytanie „jak jest teraz". Widz, który wszedł
// kwadrans po starcie, nie miał jak się dowiedzieć, że zawodnik zjechał
// z trasy i po kilometrze wrócił, że stał osiem minut na przejeździe albo że
// właśnie skończył drugi podjazd. To nie są dane, których brakowało w bazie —
// nikt ich nie zapisywał, bo każda kolejna próbka nadpisywała poprzednią.
//
// Zdarzenia powstają z PRZEJŚĆ między stanami, po stronie serwera. Telefon
// niczego nie zgłasza i niczego nie może wstrzyknąć: „POZA TRASĄ" pojawia się
// dokładnie wtedy, gdy pole `nav_off_route` zmieniło się z fałszu na prawdę,
// i dokładnie raz.

// liveRideParticipantState to zdjęcie stanu zawodnika sprzed nowej próbki.
type liveRideParticipantState struct {
	State      string
	OffRoute   bool
	ClimbIndex int
	ClimbLen   float64
	DistanceM  float64
	HasFix     bool
}

// liveRideStateBefore zdejmuje stan zawodnika przed zapisaniem nowej próbki.
func liveRideStateBefore(participant *core.Record) liveRideParticipantState {
	return liveRideParticipantState{
		State:      participant.GetString("state"),
		OffRoute:   participant.GetBool("nav_off_route"),
		ClimbIndex: participant.GetInt("climb_index"),
		ClimbLen:   participant.GetFloat("climb_length_m"),
		DistanceM:  participant.GetFloat("distance_m"),
		HasFix:     !participant.GetDateTime("last_seen_at").IsZero(),
	}
}

// liveRideRecordTransitions dopisuje zdarzenia wynikające z nowej próbki.
//
// Błąd zapisu zdarzenia nie może wywrócić przyjęcia telemetrii: oś czasu jest
// dodatkiem do jazdy, a nie warunkiem jej nadawania. Dlatego funkcja niczego
// nie zwraca — najgorsze, co się stanie, to brakujący wpis na liście.
func liveRideRecordTransitions(
	e *core.RequestEvent,
	session *core.Record,
	participant *core.Record,
	before liveRideParticipantState,
	newest *liveRideTelemetryPoint,
) {
	at := newest.RecordedAt.UTC()
	distance := newest.DistanceM

	if !before.HasFix {
		liveRideAppendEvent(e.App, session, participant, "start", "", distance, at)
	}

	after := participant.GetString("state")
	if after != before.State && before.HasFix {
		switch after {
		case "stopped":
			liveRideAppendEvent(e.App, session, participant, "auto_pause", "", distance, at)
		case "paused":
			liveRideAppendEvent(e.App, session, participant, "pause", "", distance, at)
		case "riding":
			liveRideAppendEvent(e.App, session, participant, "resume", "", distance, at)
		}
	}

	offRoute := participant.GetBool("nav_off_route")
	if offRoute != before.OffRoute {
		if offRoute {
			liveRideAppendEvent(e.App, session, participant, "off_route", "", distance, at)
		} else {
			liveRideAppendEvent(e.App, session, participant, "back_on_route", "", distance, at)
		}
	}

	climbIndex := participant.GetInt("climb_index")
	climbLength := participant.GetFloat("climb_length_m")
	onClimbNow := climbLength > 0
	wasOnClimb := before.ClimbLen > 0
	switch {
	case onClimbNow && (!wasOnClimb || climbIndex != before.ClimbIndex):
		liveRideAppendEvent(
			e.App, session, participant, "climb_start",
			liveRideClimbLabel(participant), distance, at,
		)
	case !onClimbNow && wasOnClimb:
		liveRideAppendEvent(e.App, session, participant, "climb_end", "", distance, at)
	}

	liveRideRecordCheckpoints(e, session, participant, before.DistanceM, distance, at)
}

// liveRideClimbLabel nazywa podjazd tak, jak nazywa go licznik: numerem.
func liveRideClimbLabel(participant *core.Record) string {
	index := participant.GetInt("climb_index")
	total := participant.GetInt("climb_total")
	switch {
	case index > 0 && total > 0:
		return strconv.Itoa(index) + "/" + strconv.Itoa(total)
	case index > 0:
		return strconv.Itoa(index)
	default:
		return ""
	}
}

// liveRideAppendEvent zapisuje jedno zdarzenie z numerem kolejnym w sesji.
//
// Numer bierze się z licznika na sesji, a nie z liczby istniejących wierszy:
// dwa zdarzenia o tej samej sekundzie muszą mieć ustaloną kolejność, bo
// „zjechał z trasy" i „wznowił" w jednej próbce czyta się inaczej niż
// odwrotnie.
func liveRideAppendEvent(
	app core.App,
	session *core.Record,
	participant *core.Record,
	kind string,
	label string,
	distanceM float64,
	at time.Time,
) {
	collection, err := app.FindCollectionByNameOrId("live_ride_events")
	if err != nil {
		return
	}
	next := session.GetInt("event_seq") + 1

	record := core.NewRecord(collection)
	record.Set("session", session.Id)
	if participant != nil {
		record.Set("participant", participant.Id)
	}
	record.Set("at", at.UTC())
	record.Set("kind", kind)
	record.Set("label", strings.TrimSpace(label))
	record.Set("distance_m", distanceM)
	record.Set("seq", next)
	if err := app.Save(record); err != nil {
		return
	}

	session.Set("event_seq", next)
	_ = app.Save(session)
}

// liveRideRecordCheckpoints odnotowuje minięte punkty pośrednie trasy.
//
// Checkpointy to waypointy trasy, a nie osobny byt do utrzymania: zawodnik,
// który ułożył trasę przez Wannsee i Poczdam, już je nazwał. Zdarzenie
// powstaje, gdy przejechany dystans MINIE dystans checkpointu — dlatego
// potrzebny jest dystans sprzed próbki, a nie sam bieżący.
func liveRideRecordCheckpoints(
	e *core.RequestEvent,
	session *core.Record,
	participant *core.Record,
	beforeM float64,
	afterM float64,
	at time.Time,
) {
	if afterM <= beforeM {
		return
	}
	routeID := session.GetString("route")
	if routeID == "" {
		return
	}
	route, err := e.App.FindRecordById("live_ride_routes", routeID)
	if err != nil {
		return
	}
	for _, checkpoint := range liveRideCheckpoints(route) {
		distance, ok := checkpoint["distance_m"].(float64)
		if !ok || distance <= 0 {
			continue
		}
		if distance <= beforeM || distance > afterM {
			continue
		}
		name, _ := checkpoint["name"].(string)
		liveRideAppendEvent(e.App, session, participant, "checkpoint", name, distance, at)
	}
}

// liveRideCheckpoints wyciąga punkty pośrednie z zapisanej trasy.
//
// Pomija pierwszy i ostatni waypoint: start i meta mają na stronie własne
// miejsce, a powtórzone jako „checkpoint 1" wyglądałyby jak dwa różne punkty.
func liveRideCheckpoints(route *core.Record) []map[string]any {
	var waypoints []map[string]any
	if err := route.UnmarshalJSONField("waypoints", &waypoints); err != nil {
		return nil
	}
	if len(waypoints) <= 2 {
		return nil
	}
	result := make([]map[string]any, 0, len(waypoints)-2)
	for _, waypoint := range waypoints[1 : len(waypoints)-1] {
		name := strings.TrimSpace(liveRideString(waypoint["name"]))
		if name == "" {
			// Bezimienny punkt nawigacyjny to szczegół układania trasy,
			// a nie miejsce, o którym warto komukolwiek powiedzieć.
			continue
		}
		entry := map[string]any{"name": name}
		if distance, ok := liveRideFloat(waypoint["distance_m"]); ok {
			entry["distance_m"] = distance
		}
		if lat, ok := liveRideFloat(waypoint["lat"]); ok {
			entry["lat"] = lat
		}
		if lon, ok := liveRideFloat(waypoint["lon"]); ok {
			entry["lon"] = lon
		}
		if kind := strings.TrimSpace(liveRideString(waypoint["kind"])); kind != "" {
			entry["kind"] = kind
		}
		result = append(result, entry)
	}
	return result
}

func liveRideString(value any) string {
	text, _ := value.(string)
	return text
}

func liveRideFloat(value any) (float64, bool) {
	switch typed := value.(type) {
	case float64:
		if math.IsNaN(typed) || math.IsInf(typed, 0) {
			return 0, false
		}
		return typed, true
	case int:
		return float64(typed), true
	default:
		return 0, false
	}
}

// LiveRidePublicEvents wydaje oś czasu posiadaczowi linku.
//
// Osobny adres, a nie część migawki: zdarzeń przybywa kilkanaście na godzinę,
// a migawka chodzi co trzy sekundy. Doklejanie ich tam oznaczałoby wysyłanie
// tej samej listy tysiąc razy.
func LiveRidePublicEvents(e *core.RequestEvent) error {
	access, err := liveRideResolveShare(e)
	if err != nil {
		return err
	}
	liveRideNoStore(e, liveRideVisibility(access.session) == "public")

	if access.state != "ok" {
		return e.JSON(http.StatusOK, map[string]any{
			"status": access.state,
			"events": []any{},
		})
	}

	records, err := e.App.FindRecordsByFilter(
		"live_ride_events",
		"session = {:session}",
		"-seq",
		200,
		0,
		dbx.Params{"session": access.session.Id},
	)
	if err != nil {
		return e.JSON(http.StatusOK, map[string]any{
			"status": "ok",
			"events": []any{},
		})
	}

	events := make([]map[string]any, 0, len(records))
	// Od najnowszego, bo tak się to czyta — i tak też strona je pokazuje.
	for _, record := range records {
		entry := map[string]any{
			"seq":  record.GetInt("seq"),
			"kind": record.GetString("kind"),
			"at":   record.GetDateTime("at").Time().UTC().Format(time.RFC3339),
		}
		if label := record.GetString("label"); label != "" {
			entry["label"] = label
		}
		if distance := record.GetFloat("distance_m"); distance > 0 {
			entry["distance_m"] = distance
		}
		if participant := record.GetString("participant"); participant != "" {
			entry["participant"] = participant
		}
		events = append(events, entry)
	}

	return e.JSON(http.StatusOK, map[string]any{
		"status":      "ok",
		"server_time": time.Now().UTC().Format(time.RFC3339),
		"events":      events,
	})
}
