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
	ElapsedSeconds      int `json:"elapsed_seconds"`

	// Nachylenie w miejscu, w którym zawodnik właśnie jest.
	GradientPercent float64 `json:"gradient_percent"`

	// Stan nawigacji, tak jak widzi go zawodnik. Instrukcja przychodzi
	// GOTOWA i po polsku — ani serwer, ani strona jej nie składają, żeby
	// obserwujący czytał dokładnie to samo zdanie co rowerzysta.
	Nav *liveRideNavPayload `json:"nav"`

	// Aktualny podjazd, policzony tym samym kodem co ClimbPro na kierownicy.
	Climb *liveRideClimbPayload `json:"climb"`

	// Insighty Ride Intelligence, gotowymi zdaniami. Serwer decyduje, które
	// z nich w ogóle zapisze i które pokaże — patrz live_ride_insights.go.
	Insights []liveRideInsightPayload `json:"insights"`

	// Numer próbki, rosnący w obrębie jednej sesji.
	//
	// Telemetria jedzie po LTE i pakiety potrafią się wyprzedzić. Bez tego
	// numeru próbka sprzed dwóch minut, która dotarła jako ostatnia,
	// nadpisywała stan zawodnika i publiczna strona cofała go o dwa
	// kilometry, żeby za chwilę przywrócić. Zero znaczy „telefon nie
	// numeruje" i zachowuje się jak dotąd.
	Seq int `json:"seq"`

	// Prędkość i dystans z czujnika koła, gdy jest. Nie zastępują GPS-owych,
	// bo to dwa różne pomiary i widz ma prawo wiedzieć, który ogląda.
	SensorSpeedKmh  float64 `json:"sensor_speed_kmh"`
	SensorDistanceM float64 `json:"sensor_distance_m"`

	// Skąd pochodzi która dana i jak dawno przyszła.
	Sources   *liveRideSourcesPayload   `json:"sources"`
	Batteries *liveRideBatteriesPayload `json:"batteries"`
	Freshness *liveRideFreshnessPayload `json:"freshness"`
	Averages  *liveRideAveragesPayload  `json:"averages"`
}

// liveRideSourcesPayload mówi, z czego wzięła się każda liczba.
//
// „HR 143" z opaski WHOOP i „HR 143" liczone z ruchu nadgarstka to nie ta
// sama informacja. Diagnostyka właściciela pokazuje źródło wprost.
type liveRideSourcesPayload struct {
	HeartRate string `json:"heart_rate"`
	Power     string `json:"power"`
	Cadence   string `json:"cadence"`
	Speed     string `json:"speed"`
}

// liveRideBatteriesPayload to baterie telefonu i czujników.
type liveRideBatteriesPayload struct {
	Phone   int `json:"phone"`
	HR      int `json:"heart_rate"`
	Power   int `json:"power"`
	Cadence int `json:"cadence"`
	Speed   int `json:"speed"`
}

// liveRideFreshnessPayload to wiek każdej danej w sekundach.
//
// Liczony przez telefon, bo tylko on wie, kiedy pas HR ostatnio się odezwał.
// Serwer zamienia go na znacznik czasu, żeby strona nie musiała ufać zegarowi
// przeglądarki.
type liveRideFreshnessPayload struct {
	GPSAgeSeconds     float64 `json:"gps_age_seconds"`
	HRAgeSeconds      float64 `json:"hr_age_seconds"`
	PowerAgeSeconds   float64 `json:"power_age_seconds"`
	CadenceAgeSeconds float64 `json:"cadence_age_seconds"`
	NavAgeSeconds     float64 `json:"nav_age_seconds"`
}

// liveRideAveragesPayload to średnie i maksima liczone przez licznik.
type liveRideAveragesPayload struct {
	AvgHeartRate int `json:"avg_heart_rate_bpm"`
	MaxHeartRate int `json:"max_heart_rate_bpm"`
	AvgPower     int `json:"avg_power_watts"`
	MaxPower     int `json:"max_power_watts"`
	AvgCadence   int `json:"avg_cadence_rpm"`
}

// liveRideNavPayload to stan nawigacji jednej próbki.
type liveRideNavPayload struct {
	Instruction  string  `json:"instruction"`
	Street       string  `json:"street"`
	ManeuverType int     `json:"maneuver_type"`
	DistanceM    float64 `json:"distance_m"`
	RemainingM   float64 `json:"remaining_m"`
	EtaSeconds   int     `json:"eta_seconds"`
	OffRoute     bool    `json:"off_route"`
	OffRouteM    float64 `json:"off_route_m"`
}

// liveRideClimbPayload to aktualny podjazd.
type liveRideClimbPayload struct {
	Index          int     `json:"index"`
	Total          int     `json:"total"`
	DoneM          float64 `json:"done_m"`
	LengthM        float64 `json:"length_m"`
	GainM          float64 `json:"gain_m"`
	RemainingGainM float64 `json:"remaining_gain_m"`
	AvgGradient    float64 `json:"avg_gradient"`
	MaxGradient    float64 `json:"max_gradient"`
	Category       string  `json:"category"`
}

// liveRideApplyNav zapisuje stan nawigacji albo go czyści.
//
// Czyszczenie jest tak samo ważne jak zapis: zakończona nawigacja musi zdjąć
// manewr z publicznej strony, bo inaczej widz zostaje ze strzałką w lewo,
// której zawodnik od dawna nie ma przed sobą.
func liveRideApplyNav(participant *core.Record, nav *liveRideNavPayload) {
	if nav == nil {
		participant.Set("nav_instruction", "")
		participant.Set("nav_street", "")
		participant.Set("nav_maneuver_type", 0)
		participant.Set("nav_distance_m", 0)
		participant.Set("nav_remaining_m", 0)
		participant.Set("nav_eta_seconds", 0)
		participant.Set("nav_off_route", false)
		participant.Set("nav_off_route_m", 0)
		return
	}
	participant.Set("nav_instruction", strings.TrimSpace(nav.Instruction))
	participant.Set("nav_street", strings.TrimSpace(nav.Street))
	participant.Set("nav_maneuver_type", nav.ManeuverType)
	participant.Set("nav_distance_m", nav.DistanceM)
	participant.Set("nav_remaining_m", nav.RemainingM)
	participant.Set("nav_eta_seconds", nav.EtaSeconds)
	participant.Set("nav_off_route", nav.OffRoute)
	participant.Set("nav_off_route_m", nav.OffRouteM)
}

// liveRideApplyClimb zapisuje aktualny podjazd albo go czyści po szczycie.
func liveRideApplyClimb(participant *core.Record, climb *liveRideClimbPayload) {
	if climb == nil || climb.LengthM <= 0 {
		participant.Set("climb_index", 0)
		participant.Set("climb_total", 0)
		participant.Set("climb_done_m", 0)
		participant.Set("climb_length_m", 0)
		participant.Set("climb_gain_m", 0)
		participant.Set("climb_remaining_gain_m", 0)
		participant.Set("climb_avg_gradient", 0)
		participant.Set("climb_max_gradient", 0)
		participant.Set("climb_category", "")
		return
	}
	participant.Set("climb_index", climb.Index)
	participant.Set("climb_total", climb.Total)
	participant.Set("climb_done_m", climb.DoneM)
	participant.Set("climb_length_m", climb.LengthM)
	participant.Set("climb_gain_m", climb.GainM)
	participant.Set("climb_remaining_gain_m", climb.RemainingGainM)
	participant.Set("climb_avg_gradient", climb.AvgGradient)
	participant.Set("climb_max_gradient", climb.MaxGradient)
	participant.Set("climb_category", strings.TrimSpace(climb.Category))
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
		session.Set("route_revision", 1)
		session.Set("route_updated_at", time.Now().UTC())
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

	// Stan zawodnika zapisuje wyłącznie próbka NOWSZA niż ostatnio przyjęta.
	//
	// Punkty historii zapisały się wyżej niezależnie od tego — spóźniona
	// paczka z tunelu ma prawo uzupełnić ślad. Nie ma natomiast prawa
	// przestawić „gdzie on jest teraz" na dwa kilometry wstecz.
	if newest != nil && liveRideStaleSample(participant, newest) {
		return e.JSON(http.StatusAccepted, map[string]any{
			"accepted": accepted,
			"received": len(data.Points),
			"seq":      participant.GetInt("telemetry_seq"),
			"stale":    true,
		})
	}

	if newest != nil {
		before := liveRideStateBefore(participant)
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
		if newest.ElapsedSeconds > 0 {
			participant.Set("elapsed_seconds", newest.ElapsedSeconds)
		}
		participant.Set("gradient_percent", newest.GradientPercent)
		liveRideApplyNav(participant, newest.Nav)
		liveRideApplyClimb(participant, newest.Climb)
		liveRideApplyInsights(participant, newest.Insights)
		// Rekord prędkości nigdy nie maleje w trakcie jazdy — telefon, który
		// po restarcie przysłał niższą wartość, nie może skasować maksimum.
		if newest.MaxSpeedKmh > participant.GetFloat("max_speed_kmh") {
			participant.Set("max_speed_kmh", newest.MaxSpeedKmh)
		}
		if newest.BatteryPercent > 0 && newest.BatteryPercent <= 100 {
			participant.Set("battery_percent", newest.BatteryPercent)
		}
		liveRideApplySensors(participant, newest)
		liveRideApplyFreshness(participant, newest)
		liveRideApplyAverages(participant, newest)
		liveRideRememberStart(participant, newest)
		if newest.Seq > 0 {
			participant.Set("telemetry_seq", newest.Seq)
		}
		if err := e.App.Save(participant); err != nil {
			return err
		}
		// Oś czasu powstaje z PRZEJŚĆ między stanami, a nie z tego, co
		// telefon zechce zgłosić. Dzięki temu „zjechał z trasy" pojawia się
		// dokładnie raz, w tej samej chwili, w której zmienił się stan,
		// i nie da się jej wstrzyknąć z zewnątrz.
		liveRideRecordTransitions(e, session, participant, before, newest)
	}

	return e.JSON(http.StatusAccepted, map[string]any{
		"accepted": accepted,
		"received": len(data.Points),
		"seq":      participant.GetInt("telemetry_seq"),
	})
}

// liveRideStaleSample mówi, czy ta paczka jest starsza od już przyjętej.
//
// Numer wygrywa z czasem, bo tylko on jest nadany przez jedno urządzenie
// w jednej kolejności. Gdy telefon nie numeruje (stara wersja aplikacji),
// zostaje znacznik czasu ostatniej próbki.
func liveRideStaleSample(participant *core.Record, newest *liveRideTelemetryPoint) bool {
	if newest.Seq > 0 {
		return newest.Seq <= participant.GetInt("telemetry_seq")
	}
	// Telefon bez numeracji (starsza wersja aplikacji) rozstrzyga czasem.
	last := participant.GetDateTime("last_seen_at").Time()
	return !last.IsZero() && !newest.RecordedAt.UTC().After(last.UTC())
}

// liveRideApplySensors zapisuje pomiary z czujników i ich źródła.
func liveRideApplySensors(participant *core.Record, newest *liveRideTelemetryPoint) {
	if newest.SensorSpeedKmh > 0 {
		participant.Set("sensor_speed_kmh", newest.SensorSpeedKmh)
	}
	if newest.SensorDistanceM > 0 {
		participant.Set("sensor_distance_m", newest.SensorDistanceM)
	}
	if sources := newest.Sources; sources != nil {
		participant.Set("hr_source", liveRideSourceName(sources.HeartRate))
		participant.Set("power_source", liveRideSourceName(sources.Power))
		participant.Set("cadence_source", liveRideSourceName(sources.Cadence))
		participant.Set("speed_source", liveRideSourceName(sources.Speed))
	}
	if batteries := newest.Batteries; batteries != nil {
		liveRideSetBattery(participant, "battery_percent", batteries.Phone)
		liveRideSetBattery(participant, "hr_battery_percent", batteries.HR)
		liveRideSetBattery(participant, "power_battery_percent", batteries.Power)
		liveRideSetBattery(participant, "cadence_battery_percent", batteries.Cadence)
		liveRideSetBattery(participant, "speed_battery_percent", batteries.Speed)
	}
}

// liveRideSetBattery zapisuje procent tylko wtedy, gdy jest procentem.
//
// Zero z pola „nie wiem" wyglądałoby na rozładowany czujnik, czyli na awarię,
// której nie ma.
func liveRideSetBattery(participant *core.Record, field string, value int) {
	if value > 0 && value <= 100 {
		participant.Set(field, value)
	}
}

// liveRideSourceName przycina nazwę źródła do tego, co zmieści się w polu.
func liveRideSourceName(value string) string {
	name := strings.TrimSpace(value)
	if len(name) > 40 {
		return name[:40]
	}
	return name
}

// liveRideApplyFreshness zamienia wiek danych na znaczniki czasu.
//
// Telefon liczy wiek, bo tylko on wie, kiedy pas HR ostatnio się odezwał.
// Serwer zapisuje moment, bo tylko wtedy strona nie musi ufać zegarowi
// przeglądarki ani zgadywać opóźnienia sieci.
func liveRideApplyFreshness(participant *core.Record, newest *liveRideTelemetryPoint) {
	recorded := newest.RecordedAt.UTC()
	freshness := newest.Freshness
	if freshness == nil {
		// Bez rozbicia świeżości jedyne, co wiemy na pewno, to moment fiksu.
		participant.Set("gps_updated_at", recorded)
		return
	}
	liveRideSetFreshness(participant, "gps_updated_at", recorded, freshness.GPSAgeSeconds)
	liveRideSetFreshness(participant, "hr_updated_at", recorded, freshness.HRAgeSeconds)
	liveRideSetFreshness(participant, "power_updated_at", recorded, freshness.PowerAgeSeconds)
	liveRideSetFreshness(participant, "cadence_updated_at", recorded, freshness.CadenceAgeSeconds)
	liveRideSetFreshness(participant, "nav_updated_at", recorded, freshness.NavAgeSeconds)
}

// liveRideSetFreshness cofa znacznik o wiek danej.
//
// Ujemny wiek znaczy „nie mam tej danej wcale" i wtedy pole zostaje puste:
// brak czujnika to nie to samo co czujnik milczący od godziny.
func liveRideSetFreshness(
	participant *core.Record,
	field string,
	recorded time.Time,
	ageSeconds float64,
) {
	if ageSeconds < 0 {
		participant.Set(field, nil)
		return
	}
	participant.Set(field, recorded.Add(-time.Duration(ageSeconds*float64(time.Second))))
}

// liveRideApplyAverages zapisuje średnie i maksima z licznika.
func liveRideApplyAverages(participant *core.Record, newest *liveRideTelemetryPoint) {
	averages := newest.Averages
	if averages == nil {
		return
	}
	if averages.AvgHeartRate > 0 {
		participant.Set("avg_heart_rate_bpm", averages.AvgHeartRate)
	}
	if averages.MaxHeartRate > participant.GetInt("max_heart_rate_bpm") {
		participant.Set("max_heart_rate_bpm", averages.MaxHeartRate)
	}
	if averages.AvgPower > 0 {
		participant.Set("avg_power_watts", averages.AvgPower)
	}
	if averages.MaxPower > participant.GetInt("max_power_watts") {
		participant.Set("max_power_watts", averages.MaxPower)
	}
	if averages.AvgCadence > 0 {
		participant.Set("avg_cadence_rpm", averages.AvgCadence)
	}
}

// liveRideRememberStart zapamiętuje pierwszy fiks zawodnika.
//
// Potrzebny wyłącznie po to, żeby dało się UKRYĆ okolicę startu. Sam nigdy
// nie opuszcza serwera — gdyby opuszczał, ukrywanie nie miałoby sensu.
func liveRideRememberStart(participant *core.Record, newest *liveRideTelemetryPoint) {
	if participant.GetFloat("start_lat") != 0 || participant.GetFloat("start_lon") != 0 {
		return
	}
	if newest.Latitude == 0 && newest.Longitude == 0 {
		return
	}
	participant.Set("start_lat", newest.Latitude)
	participant.Set("start_lon", newest.Longitude)
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
		liveRideAppendEvent(e.App, session, nil, "finish", "", 0, time.Now().UTC())
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
			payload := liveRideRouteJSONForViewer(route)
			// Numer wersji jedzie razem z geometrią, żeby strona mogła
			// porównać go z migawką i nie pobierać trasy, która się nie
			// zmieniła.
			payload["revision"] = session.GetInt("route_revision")
			if updated := session.GetDateTime("route_updated_at").Time(); !updated.IsZero() {
				payload["updated_at"] = updated.UTC().Format(time.RFC3339)
			}
			return e.JSON(http.StatusOK, payload)
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
