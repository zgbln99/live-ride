package routes

import (
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
)

// Przebieg jazdy w czasie, a nie tylko jej ostatnia chwila.
//
// Migawka odpowiada na pytanie „jak jest teraz". Ślad odpowiada na „którędy".
// Brakowało trzeciego: „jak było o 14:12" — a to jedyne pytanie, które da się
// zadać o jazdę już zakończoną i jedyne, na które trzeba odpowiedzieć, gdy
// ktoś wszedł na stronę pół godziny za późno.
//
// Ten sam adres obsługuje oba przypadki, bo to ten sam problem: cofnięcie się
// w trwającej transmisji i odtworzenie zakończonej różnią się wyłącznie tym,
// czy koniec przedziału jest w przeszłości.
//
// Prywatność rozstrzyga się dokładnie tak samo jak w migawce — nie „prawie
// tak samo": historia, z której da się odczytać tętno wyłączone
// przełącznikiem, byłaby obejściem tego przełącznika.

// Ile najwyżej próbek wydajemy w jednej odpowiedzi.
//
// Dwie na sekundę wystarczają wizualnie, a przejazd trwa godziny — sześćset
// punktów daje płynny suwak i mieści się w jednym pakiecie na LTE.
const liveRideHistoryMaxSamples = 600

// LiveRideHistory wydaje przebieg jazdy posiadaczowi linku.
func LiveRideHistory(e *core.RequestEvent) error {
	access, err := liveRideResolveShare(e)
	if err != nil {
		return err
	}
	session := access.session
	liveRideNoStore(e, liveRideVisibility(session) == "public")

	now := time.Now().UTC()
	if access.state != "ok" {
		return e.JSON(http.StatusOK, map[string]any{
			"status":  access.state,
			"riders":  []any{},
			"samples": 0,
		})
	}

	from, to, err := liveRideHistoryWindow(e, now)
	if err != nil {
		return err
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

	finish := liveRideRouteFinish(e.App, session)
	riders := make([]map[string]any, 0, len(participants))
	total := 0
	for _, participant := range participants {
		if !liveRideShares(participant, "share_position") {
			continue
		}
		policy := liveRideLocationPolicyFor(participant, finish)
		// Opóźnienie obowiązuje także wstecz: inaczej wystarczyłoby poprosić
		// o historię „do teraz", żeby je ominąć.
		until := to
		if cutoff := policy.cutoff(now); cutoff.Before(until) {
			until = cutoff
		}
		samples, err := liveRideHistoryFor(e, participant, from, until, policy)
		if err != nil {
			return err
		}
		if len(samples) == 0 {
			continue
		}
		total += len(samples)
		riders = append(riders, map[string]any{
			"participant":  participant.Id,
			"display_name": participant.GetString("display_name"),
			"samples":      samples,
		})
	}

	return e.JSON(http.StatusOK, map[string]any{
		"status":      "ok",
		"server_time": now.Format(time.RFC3339),
		"from":        from.Format(time.RFC3339),
		"to":          to.Format(time.RFC3339),
		"samples":     total,
		"riders":      riders,
	})
}

// liveRideHistoryWindow czyta przedział czasu z zapytania.
//
// Bez `from` bierzemy początek jazdy — czyli pełne odtworzenie. To jest
// domyślne zachowanie, bo po mecie nikt nie pyta o ostatnie pięć minut.
func liveRideHistoryWindow(e *core.RequestEvent, now time.Time) (time.Time, time.Time, error) {
	query := e.Request.URL.Query()
	from := time.Time{}
	to := now

	if raw := strings.TrimSpace(query.Get("from")); raw != "" {
		parsed, err := time.Parse(time.RFC3339, raw)
		if err != nil {
			return from, to, apis.NewBadRequestError("Invalid 'from' timestamp", err)
		}
		from = parsed.UTC()
	}
	if raw := strings.TrimSpace(query.Get("to")); raw != "" {
		parsed, err := time.Parse(time.RFC3339, raw)
		if err != nil {
			return from, to, apis.NewBadRequestError("Invalid 'to' timestamp", err)
		}
		to = parsed.UTC()
	}
	// Skrót dla cofania w trwającej jeździe: „ostatnie N minut".
	if raw := strings.TrimSpace(query.Get("minutes")); raw != "" {
		minutes, err := strconv.Atoi(raw)
		if err != nil || minutes <= 0 || minutes > 720 {
			return from, to, apis.NewBadRequestError("Invalid 'minutes' window", nil)
		}
		from = to.Add(-time.Duration(minutes) * time.Minute)
	}
	if !from.IsZero() && !to.After(from) {
		return from, to, apis.NewBadRequestError("'to' must be after 'from'", nil)
	}
	return from, to, nil
}

// liveRideHistoryFor składa próbki jednego zawodnika.
func liveRideHistoryFor(
	e *core.RequestEvent,
	participant *core.Record,
	from time.Time,
	to time.Time,
	policy liveRideLocationPolicy,
) ([]map[string]any, error) {
	filter := "participant={:participant} && recorded_at <= {:to}"
	params := dbx.Params{
		"participant": participant.Id,
		"to":          to.Format("2006-01-02 15:04:05.000Z"),
	}
	if !from.IsZero() {
		filter += " && recorded_at >= {:from}"
		params["from"] = from.Format("2006-01-02 15:04:05.000Z")
	}

	records, err := e.App.FindRecordsByFilter(
		"live_ride_points", filter, "recorded_at", liveRideTrackMaxRows, 0, params,
	)
	if err != nil {
		return nil, apis.NewBadRequestError("Failed to read the ride history", err)
	}
	if len(records) == 0 {
		return nil, nil
	}

	stride := 1
	if len(records) > liveRideHistoryMaxSamples {
		stride = int(math.Ceil(float64(len(records)) / float64(liveRideHistoryMaxSamples)))
	}

	// Te same przełączniki co w migawce, czytane raz.
	sharesSpeed := liveRideShares(participant, "share_speed")
	sharesHeartRate := liveRideShares(participant, "share_heart_rate")
	sharesPower := liveRideShares(participant, "share_power")

	samples := make([]map[string]any, 0, len(records)/stride+2)
	for i, record := range records {
		if i%stride != 0 && i != len(records)-1 {
			continue
		}
		latitude := record.GetFloat("latitude")
		longitude := record.GetFloat("longitude")
		if policy.hides(latitude, longitude) {
			continue
		}
		latitude, longitude = policy.blur(latitude, longitude)

		sample := map[string]any{
			"at":  record.GetDateTime("recorded_at").Time().UTC().Format(time.RFC3339),
			"lat": latitude,
			"lon": longitude,
		}
		// Każda wielkość osobno i tylko wtedy, gdy wolno. Pole nieobecne
		// znaczy „nie udostępnione", a nie „zero" — strona rysuje wtedy
		// przerwę, nie płaską linię na dnie wykresu.
		if !policy.Coarse {
			if altitude := record.GetFloat("altitude_m"); altitude != 0 {
				sample["altitude_m"] = altitude
			}
		}
		if distance := record.GetFloat("distance_m"); distance > 0 {
			sample["distance_m"] = distance
		}
		if sharesSpeed {
			sample["speed_kmh"] = record.GetFloat("speed_kmh")
		}
		if sharesHeartRate {
			if bpm := record.GetInt("heart_rate_bpm"); bpm > 0 {
				sample["heart_rate_bpm"] = bpm
			}
		}
		if sharesPower {
			if watts := record.GetInt("power_watts"); watts > 0 {
				sample["power_watts"] = watts
			}
			if rpm := record.GetInt("cadence_rpm"); rpm > 0 {
				sample["cadence_rpm"] = rpm
			}
		}
		samples = append(samples, sample)
	}
	return samples, nil
}
