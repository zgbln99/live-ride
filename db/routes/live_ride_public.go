package routes

import (
	"math"
	"net/http"
	"strings"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/security"
	"github.com/twpayne/go-polyline"
)

// Publiczna strona LIVE.
//
// Widz nie ma konta, nie ma aplikacji i nie zaloguje się. Jedyne, co ma, to
// link. Dlatego każda decyzja o tym, co widać, zapada TUTAJ, po stronie
// serwera: gdyby filtr prywatności siedział w JavaScripcie strony, dane
// wyłączone przez zawodnika i tak leciałyby po sieci, a „ukrycie" byłoby
// kwestią otwarcia narzędzi deweloperskich.

const (
	// Po tylu sekundach bez telemetrii przestajemy twierdzić, że pozycja jest
	// aktualna. Ostatnia znana zostaje na mapie, ale opisana jako nieświeża.
	liveRideOfflineAfterSeconds = 75

	// Poniżej tej prędkości uznajemy, że zawodnik stoi — o ile sam nie
	// powiedział, w jakim jest stanie.
	liveRideStoppedBelowKmh = 1.5

	// Ile punktów śladu maksymalnie wysyłamy widzowi w jednej odpowiedzi.
	liveRideTrackMaxPoints = 2000

	// Ile wierszy wolno przeczytać, zanim ślad zostanie rozrzedzony.
	liveRideTrackMaxRows = 40000

	// Precyzja polilinii Live Ride. Ta sama, której używa Valhalla i
	// aplikacja — kolekcja `trails` starego Wanderera koduje w 5 i dlatego
	// każda odpowiedź niesie swoją precyzję zamiast liczyć na domyślną.
	liveRidePolylinePrecision = 6
)

var liveRidePolylineCodec = polyline.Codec{Dim: 2, Scale: 1e6}

// Kolekcja `trails` starego Wanderera koduje polilinie w precyzji 5.
var polylinePrecision5 = polyline.Codec{Dim: 2, Scale: 1e5}

// liveRideAccess mówi, czy link nadal działa i dlaczego nie.
type liveRideAccess struct {
	session *core.Record
	// "ok", "expired" albo "disabled".
	state string
}

// liveRideResolveShare zamienia token na sesję i rozstrzyga, czy link żyje.
//
// Nieznany token to 404 — i tylko on. Link wyłączony albo wygasły zwraca
// sesję ze stanem, bo widz ma zobaczyć zdanie po polsku, a nie stronę błędu
// przeglądarki.
func liveRideResolveShare(e *core.RequestEvent) (*liveRideAccess, error) {
	token := strings.TrimSpace(e.Request.PathValue("token"))
	if len(token) < 32 {
		return nil, apis.NewNotFoundError("Live ride not found", nil)
	}

	session, err := e.App.FindFirstRecordByData("live_ride_sessions", "share_token", token)
	if err != nil {
		return nil, apis.NewNotFoundError("Live ride not found", err)
	}

	access := &liveRideAccess{session: session, state: "ok"}
	if session.GetString("visibility") == "disabled" {
		access.state = "disabled"
		return access, nil
	}
	if liveRideShareExpired(session, time.Now().UTC()) {
		access.state = "expired"
	}
	return access, nil
}

// liveRideShareExpired stosuje obie reguły wygasania naraz.
func liveRideShareExpired(session *core.Record, now time.Time) bool {
	if expires := session.GetDateTime("expires_at").Time(); !expires.IsZero() && now.After(expires) {
		return true
	}
	if session.GetBool("expire_on_end") && session.GetString("status") == "ended" {
		return true
	}
	return false
}

// liveRideVisibility normalizuje pole, którego stare sesje nie mają.
func liveRideVisibility(session *core.Record) string {
	switch session.GetString("visibility") {
	case "public":
		return "public"
	case "disabled":
		return "disabled"
	default:
		// Sesje sprzed wprowadzenia pola zachowują się jak „z linku":
		// działają dla każdego, kto ma adres, ale nigdzie ich nie ogłaszamy.
		return "unlisted"
	}
}

// liveRideNoStore wyłącza cache i indeksowanie publicznych odpowiedzi.
//
// Migawka jest z definicji nieświeża sekundę później, a link „unlisted" nie
// ma prawa wylądować w wyszukiwarce przez pośrednika.
func liveRideNoStore(e *core.RequestEvent, indexable bool) {
	e.Response.Header().Set("Cache-Control", "no-store, max-age=0")
	if !indexable {
		e.Response.Header().Set("X-Robots-Tag", "noindex, nofollow")
	}
}

// LiveRidePublicSnapshot jest świadomie bez uwierzytelnienia: posiadanie
// losowego tokenu JEST uprawnieniem. Zwraca wyłącznie to, na co zawodnik się
// zgodził, i nigdy identyfikatorów ani adresów e-mail kont.
func LiveRidePublicSnapshot(e *core.RequestEvent) error {
	access, err := liveRideResolveShare(e)
	if err != nil {
		return err
	}
	session := access.session
	visibility := liveRideVisibility(session)
	liveRideNoStore(e, visibility == "public")

	now := time.Now().UTC()
	if access.state != "ok" {
		// Nic poza tytułem: wygasły link nie jest furtką do pozycji.
		return e.JSON(http.StatusOK, map[string]any{
			"status":      access.state,
			"visibility":  visibility,
			"title":       session.GetString("title"),
			"server_time": now,
			"riders":      []any{},
		})
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

	ended := session.GetString("status") == "ended"
	riders := make([]map[string]any, 0, len(participants))
	for _, participant := range participants {
		riders = append(riders, liveRideRiderJSON(participant, now, ended))
	}

	snapshot := map[string]any{
		"title":       session.GetString("title"),
		"trail_id":    session.GetString("trail"),
		"status":      session.GetString("status"),
		"visibility":  visibility,
		"kind":        session.GetString("kind"),
		"started_at":  session.GetDateTime("started_at"),
		"ended_at":    session.GetDateTime("ended_at"),
		"server_time": now,
		"has_route":   session.GetString("route") != "" || session.GetString("trail") != "",
		"riders":      riders,
	}
	if expires := session.GetDateTime("expires_at").Time(); !expires.IsZero() {
		snapshot["expires_at"] = expires
	}
	if session.GetFloat("meetup_lat") != 0 || session.GetFloat("meetup_lon") != 0 {
		snapshot["meetup"] = map[string]any{
			"latitude":  session.GetFloat("meetup_lat"),
			"longitude": session.GetFloat("meetup_lon"),
			"label":     session.GetString("meetup_label"),
		}
	}
	if ended {
		if summary := session.Get("summary"); summary != nil {
			snapshot["summary"] = summary
		}
	}
	return e.JSON(http.StatusOK, snapshot)
}

// LiveRidePublicTrack wydaje przejechany ślad: raz w całości, potem tylko
// przyrosty.
//
// Bez tego strona musiałaby przy każdym odpytaniu ściągać całą historię
// przejazdu, żeby narysować linię — kilkanaście tysięcy punktów co trzy
// sekundy, przez cały czas trwania jazdy.
func LiveRidePublicTrack(e *core.RequestEvent) error {
	access, err := liveRideResolveShare(e)
	if err != nil {
		return err
	}
	session := access.session
	liveRideNoStore(e, liveRideVisibility(session) == "public")

	now := time.Now().UTC()
	if access.state != "ok" {
		return e.JSON(http.StatusOK, map[string]any{
			"status":      access.state,
			"server_time": now,
			"tracks":      []any{},
		})
	}

	since := time.Time{}
	if raw := strings.TrimSpace(e.Request.URL.Query().Get("since")); raw != "" {
		parsed, parseErr := time.Parse(time.RFC3339Nano, raw)
		if parseErr != nil {
			return apis.NewBadRequestError("Invalid 'since' timestamp", parseErr)
		}
		since = parsed.UTC()
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

	tracks := make([]map[string]any, 0, len(participants))
	for _, participant := range participants {
		// Ślad to ciąg pozycji. Zawodnik, który nie udostępnia pozycji, nie
		// udostępnia też tego, którędy jechał.
		if !liveRideShares(participant, "share_position") {
			continue
		}
		track, err := liveRideTrackFor(e, participant.Id, since)
		if err != nil {
			return err
		}
		if track == nil {
			continue
		}
		track["participant"] = participant.Id
		tracks = append(tracks, track)
	}

	return e.JSON(http.StatusOK, map[string]any{
		"server_time": now,
		"incremental": !since.IsZero(),
		"precision":   liveRidePolylinePrecision,
		"tracks":      tracks,
	})
}

// liveRideTrackFor koduje punkty jednego uczestnika.
func liveRideTrackFor(e *core.RequestEvent, participantID string, since time.Time) (map[string]any, error) {
	filter := "participant={:participant}"
	params := dbx.Params{"participant": participantID}
	if !since.IsZero() {
		filter += " && recorded_at > {:since}"
		params["since"] = since.Format("2006-01-02 15:04:05.000Z")
	}

	records, err := e.App.FindRecordsByFilter(
		"live_ride_points",
		filter,
		"recorded_at",
		liveRideTrackMaxRows,
		0,
		params,
	)
	if err != nil {
		return nil, apis.NewBadRequestError("Failed to read the track", err)
	}
	if len(records) == 0 {
		return nil, nil
	}

	// Rozrzedzanie co n-ty punkt, ale ostatni zawsze zostaje: bez niego
	// linia kończyłaby się kilkadziesiąt metrów za znacznikiem zawodnika.
	stride := 1
	if len(records) > liveRideTrackMaxPoints {
		stride = int(math.Ceil(float64(len(records)) / float64(liveRideTrackMaxPoints)))
	}

	coordinates := make([][]float64, 0, len(records)/stride+2)
	for i, record := range records {
		if i%stride != 0 && i != len(records)-1 {
			continue
		}
		coordinates = append(coordinates, []float64{
			record.GetFloat("latitude"),
			record.GetFloat("longitude"),
		})
	}

	last := records[len(records)-1]
	return map[string]any{
		"polyline":  string(liveRidePolylineCodec.EncodeCoords(nil, coordinates)),
		"points":    len(coordinates),
		"sampled":   stride > 1,
		"from":      records[0].GetDateTime("recorded_at"),
		"until":     last.GetDateTime("recorded_at"),
		"cursor":    last.GetDateTime("recorded_at").Time().UTC().Format(time.RFC3339Nano),
		"precision": liveRidePolylinePrecision,
	}, nil
}

// ----------------------------------------------------------- właściciel

// LiveRideSetShare ustawia widoczność publicznego linku i jego wygasanie.
func LiveRideSetShare(e *core.RequestEvent) error {
	session, err := e.App.FindRecordById("live_ride_sessions", e.Request.PathValue("id"))
	if err != nil {
		return apis.NewNotFoundError("Live ride not found", err)
	}
	if session.GetString("owner") != e.Auth.Id {
		return apis.NewForbiddenError("Only the live ride owner can change sharing", nil)
	}

	var data struct {
		Visibility   *string `json:"visibility"`
		ExpireOnEnd  *bool   `json:"expire_on_end"`
		ExpireInHour *int    `json:"expire_in_hours"`
		Rotate       bool    `json:"rotate_token"`
	}
	if err := e.BindBody(&data); err != nil {
		return apis.NewBadRequestError("Failed to read request data", err)
	}

	if data.Visibility != nil {
		switch strings.ToLower(strings.TrimSpace(*data.Visibility)) {
		case "public":
			session.Set("visibility", "public")
		case "disabled":
			session.Set("visibility", "disabled")
		case "unlisted":
			session.Set("visibility", "unlisted")
		default:
			return apis.NewBadRequestError("visibility must be public, unlisted or disabled", nil)
		}
	}
	if data.ExpireOnEnd != nil {
		session.Set("expire_on_end", *data.ExpireOnEnd)
	}
	if data.ExpireInHour != nil {
		hours := *data.ExpireInHour
		if hours <= 0 {
			session.Set("expires_at", nil)
		} else {
			if hours > 24*365 {
				return apis.NewBadRequestError("expire_in_hours is out of range", nil)
			}
			session.Set("expires_at", time.Now().UTC().Add(time.Duration(hours)*time.Hour))
		}
	}
	if data.Rotate {
		// Nowy token unieważnia każdy rozesłany link — o to właśnie chodzi,
		// gdy zawodnik zorientuje się, że adres trafił nie tam, gdzie chciał.
		session.Set("share_token", security.RandomString(40))
	}

	if err := e.App.Save(session); err != nil {
		return apis.NewBadRequestError("Failed to store sharing settings", err)
	}

	return e.JSON(http.StatusOK, map[string]any{
		"share_token":   session.GetString("share_token"),
		"visibility":    liveRideVisibility(session),
		"expire_on_end": session.GetBool("expire_on_end"),
		"expires_at":    session.GetDateTime("expires_at"),
	})
}

// ------------------------------------------------------------- pomocnicze

// liveRideHasFix mówi, czy od zawodnika przyszła kiedykolwiek pozycja.
//
// Sam zapisany wiersz uczestnika nie wystarcza: powstaje w chwili utworzenia
// jazdy, z zerami w kolumnach współrzędnych.
func liveRideHasFix(participant *core.Record) bool {
	lat := participant.GetFloat("latitude")
	lon := participant.GetFloat("longitude")
	if lat == 0 && lon == 0 {
		return false
	}
	return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
}

// liveRideShares mówi, czy zawodnik zgodził się pokazać dane pole.
func liveRideShares(participant *core.Record, field string) bool {
	// Uczestnik zapisany, zanim te pola istniały, ma wszystkie na false, co
	// ukryłoby go w całości. Traktujemy „nigdy nie ustawione" jak domyślne:
	// pozycja i prędkość widoczne, tętno i moc nie.
	if !liveRideHasPrivacyFields(participant) {
		return field == "share_position" || field == "share_speed"
	}
	return participant.GetBool(field)
}

// liveRideRiderState nazywa to, co widz ma przeczytać nad zawodnikiem.
//
// „Offline" wygrywa ze wszystkim: dopóki nie wiemy, co się dzieje, nie wolno
// twierdzić, że ktoś jedzie, tylko dlatego że ostatnia próbka tak mówiła.
//
// Wyjątkiem jest „waiting": zawodnik, od którego jeszcze NIC nie przyszło, nie
// zgubił sygnału — on go dopiero szuka. Znajomy, który otworzył link sekundę
// po jego wysłaniu, ma przeczytać „oczekiwanie na GPS", a nie „brak
// aktualnych danych", bo to drugie brzmi jak awaria.
func liveRideRiderState(participant *core.Record, now time.Time, sessionEnded bool) (string, float64) {
	lastSeen := participant.GetDateTime("last_seen_at").Time()
	age := math.Inf(1)
	if !lastSeen.IsZero() {
		age = now.Sub(lastSeen.UTC()).Seconds()
		if age < 0 {
			age = 0
		}
	}

	if sessionEnded {
		return "ended", age
	}
	if lastSeen.IsZero() {
		return "waiting", age
	}
	if math.IsInf(age, 1) || age > liveRideOfflineAfterSeconds {
		return "offline", age
	}

	switch participant.GetString("state") {
	case "paused":
		return "paused", age
	case "stopped":
		return "stopped", age
	case "riding":
		return "riding", age
	}

	// Stara aplikacja nie przysyła stanu — wywnioskuj go z prędkości.
	if participant.GetFloat("speed_kmh") < liveRideStoppedBelowKmh {
		return "stopped", age
	}
	return "riding", age
}

// liveRideRiderJSON buduje widok jednego zawodnika dla obserwujących.
//
// Prywatność stosujemy tutaj, na wyjściu, a nie przy zapisie: zawodnik może
// przestawić przełącznik w trakcie jazdy i już następna migawka ma to
// uwzględnić, bez przepisywania wierszy zapisanych wcześniej.
func liveRideRiderJSON(participant *core.Record, now time.Time, sessionEnded bool) map[string]any {
	state, age := liveRideRiderState(participant, now, sessionEnded)
	hasFix := liveRideHasFix(participant)

	// Tożsamość jest niezależna od telemetrii i istnieje od chwili dołączenia.
	// Dzięki temu publiczna strona zna zawodnika, zanim przyjdzie od niego
	// pierwszy fiks — a nie pokazuje pustego miejsca do czasu, aż ruszy.
	rider := map[string]any{
		"id":           participant.Id,
		"display_name": participant.GetString("display_name"),
		"last_seen_at": participant.GetDateTime("last_seen_at"),
		"role":         participant.GetString("role"),
		"state":        state,
		"has_fix":      hasFix,
	}
	if joined := participant.GetDateTime("joined_at").Time(); !joined.IsZero() {
		rider["joined_at"] = joined
	}
	if !math.IsInf(age, 1) {
		rider["age_seconds"] = math.Round(age)
	}

	if liveRideShares(participant, "share_position") {
		// Współrzędne idą tylko wtedy, gdy naprawdę istnieją. Zero jest
		// prawidłową szerokością geograficzną — punkt (0, 0) leży w Zatoce
		// Gwinejskiej — więc wysyłanie zer jako „brak pozycji" oznaczałoby
		// znacznik na Atlantyku u każdego, kto jeszcze nie złapał GPS-a.
		if hasFix {
			rider["latitude"] = participant.GetFloat("latitude")
			rider["longitude"] = participant.GetFloat("longitude")
			rider["altitude_m"] = participant.GetFloat("altitude_m")
			rider["heading_deg"] = participant.GetFloat("heading_deg")
			rider["accuracy_m"] = participant.GetFloat("accuracy_m")
		}
		rider["distance_m"] = participant.GetFloat("distance_m")
		rider["elevation_gain_m"] = participant.GetFloat("elevation_gain_m")
		rider["moving_seconds"] = participant.GetInt("moving_seconds")
		// Postoje osobno od czasu w ruchu: różnica „całkowity minus w ruchu"
		// zawiera też sekundy poniżej progu auto-pauzy i nie jest czasem
		// spędzonym na przystanku.
		if auto := participant.GetInt("auto_paused_seconds"); auto > 0 {
			rider["auto_paused_seconds"] = auto
		}
		if manual := participant.GetInt("manual_paused_seconds"); manual > 0 {
			rider["manual_paused_seconds"] = manual
		}
	}
	if liveRideShares(participant, "share_speed") {
		rider["speed_kmh"] = participant.GetFloat("speed_kmh")
		rider["max_speed_kmh"] = participant.GetFloat("max_speed_kmh")
	}
	if liveRideShares(participant, "share_heart_rate") {
		rider["heart_rate_bpm"] = participant.GetInt("heart_rate_bpm")
	}
	if liveRideShares(participant, "share_power") {
		rider["power_watts"] = participant.GetInt("power_watts")
		rider["cadence_rpm"] = participant.GetInt("cadence_rpm")
	}
	if liveRideShares(participant, "share_battery") {
		rider["battery_percent"] = participant.GetInt("battery_percent")
	}
	return rider
}

// liveRideBuildSummary zamyka jazdę liczbami, które strona pokaże po mecie.
//
// Liczy się je raz, przy zakończeniu, a nie przy każdym wejściu na stronę:
// po jeździe te dane już się nie zmienią.
func liveRideBuildSummary(e *core.RequestEvent, session *core.Record) map[string]any {
	participants, err := e.App.FindRecordsByFilter(
		"live_ride_participants",
		"session={:session}",
		"display_name",
		100,
		0,
		dbx.Params{"session": session.Id},
	)
	if err != nil {
		e.App.Logger().Warn("live ride: failed to read participants for summary", "error", err)
		return nil
	}

	started := session.GetDateTime("started_at").Time()
	ended := session.GetDateTime("ended_at").Time()
	if ended.IsZero() {
		ended = time.Now().UTC()
	}

	riders := make([]map[string]any, 0, len(participants))
	for _, participant := range participants {
		entry := map[string]any{
			"id":           participant.Id,
			"display_name": participant.GetString("display_name"),
		}
		if liveRideShares(participant, "share_position") {
			entry["distance_m"] = participant.GetFloat("distance_m")
			entry["elevation_gain_m"] = participant.GetFloat("elevation_gain_m")
			entry["moving_seconds"] = participant.GetInt("moving_seconds")
		}
		if liveRideShares(participant, "share_speed") {
			entry["max_speed_kmh"] = participant.GetFloat("max_speed_kmh")
			moving := participant.GetInt("moving_seconds")
			if moving > 0 && liveRideShares(participant, "share_position") {
				entry["avg_speed_kmh"] = participant.GetFloat("distance_m") / float64(moving) * 3.6
			}
		}
		if liveRideShares(participant, "share_heart_rate") {
			if average, maximum, ok := liveRideAverageInt(e, participant.Id, "heart_rate_bpm"); ok {
				entry["avg_heart_rate_bpm"] = average
				entry["max_heart_rate_bpm"] = maximum
			}
		}
		if liveRideShares(participant, "share_power") {
			if average, maximum, ok := liveRideAverageInt(e, participant.Id, "power_watts"); ok {
				entry["avg_power_watts"] = average
				entry["max_power_watts"] = maximum
			}
		}
		riders = append(riders, entry)
	}

	elapsed := 0
	if !started.IsZero() {
		elapsed = int(ended.Sub(started).Seconds())
		if elapsed < 0 {
			elapsed = 0
		}
	}

	return map[string]any{
		"started_at":      started.Format(time.RFC3339),
		"ended_at":        ended.Format(time.RFC3339),
		"elapsed_seconds": elapsed,
		"riders":          riders,
	}
}

// liveRideAverageInt liczy średnią i maksimum z niezerowych próbek.
//
// Zera to brak pomiaru (czujnik nie podłączony, pole nieudostępniane), a nie
// „zero uderzeń na minutę" — wliczenie ich zaniżyłoby średnią do fikcji.
func liveRideAverageInt(e *core.RequestEvent, participantID, field string) (int, int, bool) {
	row := struct {
		Average float64 `db:"average"`
		Maximum int     `db:"maximum"`
		Samples int     `db:"samples"`
	}{}

	query := e.App.DB().NewQuery(`
		SELECT AVG(` + field + `) AS average,
		       MAX(` + field + `) AS maximum,
		       COUNT(*) AS samples
		FROM live_ride_points
		WHERE participant = {:participant} AND ` + field + ` > 0
	`).Bind(dbx.Params{"participant": participantID})

	if err := query.One(&row); err != nil || row.Samples == 0 {
		return 0, 0, false
	}
	return int(math.Round(row.Average)), row.Maximum, true
}

// liveRideRouteJSONForViewer opisuje plan przejazdu dla publicznej strony.
func liveRideRouteJSONForViewer(record *core.Record) map[string]any {
	return map[string]any{
		"name":              record.GetString("name"),
		"polyline":          record.GetString("polyline"),
		"precision":         liveRidePolylinePrecision,
		"distance_m":        record.GetFloat("distance_m"),
		"ascent_m":          record.GetFloat("ascent_m"),
		"descent_m":         record.GetFloat("descent_m"),
		"elevation_profile": record.Get("elevation_profile"),
		"climbs":            record.Get("climbs"),
		// Nawierzchnia pochodzi z routingu, nie ze zgadywania po geometrii.
		// Gdy trasa jej nie niesie (import GPX, stary zapis), pole jest puste
		// i strona po prostu nie pokazuje tej sekcji.
		"surfaces": record.Get("surfaces"),
	}
}
