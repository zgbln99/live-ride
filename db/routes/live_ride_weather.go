package routes

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"

	"pocketbase/util"
)

// Pogoda na trasie dla publicznej strony LIVE.
//
// Obserwujący nie potrzebuje temperatury w miejscu, w którym zawodnik JEST —
// tę i tak widzi po oknie. Potrzebuje tej, w którą zawodnik WJEDZIE: „za
// dwadzieścia kilometrów zacznie padać" jest jedyną informacją pogodową,
// która komukolwiek do czegoś służy w trakcie cudzej jazdy.
//
// Dlaczego po stronie serwera, a nie z przeglądarki widza:
//
//   - każdy otwarty link odpytywałby dostawcę osobno, a jedna jazda potrafi
//     mieć kilkunastu obserwujących odświeżających się co kilka sekund,
//   - współrzędne zawodnika szłyby z przeglądarki każdego z nich prosto do
//     zewnętrznej usługi,
//   - prognoza zmienia się co godzinę, więc jedna odpowiedź obsługuje
//     wszystkich obserwujących przez kwadrans.
//
// Serwer zwraca surową serię godzinową, a nie gotowe zdania. Dopasowanie
// godziny do przewidywanego czasu przyjazdu robi strona, bo tylko ona zna
// tempo, którym właśnie liczy ETA — i dzięki temu da się to przetestować bez
// sieci.

const (
	// Ile trzymamy prognozę, zanim zapytamy dostawcę ponownie. Prognoza
	// godzinowa aktualizuje się rzadziej, a limit zapytań jest wspólny dla
	// całego serwera.
	liveRideWeatherTTL = 12 * time.Minute

	// Ile punktów wzdłuż trasy pytamy. Więcej nie mieści się na telefonie
	// ani niczego nie dodaje: znajomy chce wiedzieć „teraz", „za chwilę"
	// i „na mecie".
	liveRideWeatherMaxPoints = 4

	// Jak daleko przed zawodnikiem stawiamy punkty pośrednie.
	liveRideWeatherAheadStepMeters = 20000

	// Prognoza dalej niż na dobę jest zgadywanką, a jazda dłuższa niż doba
	// i tak nie mieści się w jednej sesji LIVE.
	liveRideWeatherForecastHours = 24

	liveRideWeatherMaxBytes int64 = 512 << 10
)

// liveRideWeatherEndpoint pozwala podmienić dostawcę bez przebudowy obrazu —
// i pozwala testom wskazać własny serwer zamiast wychodzić do internetu.
func liveRideWeatherEndpoint() string {
	if custom := strings.TrimSpace(os.Getenv("LIVE_RIDE_WEATHER_URL")); custom != "" {
		return custom
	}
	return "https://api.open-meteo.com/v1/forecast"
}

type liveRideWeatherCacheEntry struct {
	payload   map[string]any
	fetchedAt time.Time
}

var (
	liveRideWeatherMu    sync.Mutex
	liveRideWeatherCache = map[string]liveRideWeatherCacheEntry{}
)

// liveRideWeatherSample to jeden punkt, o który pytamy dostawcę.
type liveRideWeatherSample struct {
	Label      string
	Latitude   float64
	Longitude  float64
	AlongM     float64
	AheadM     float64
	BearingDeg *float64
}

// LiveRideWeather wydaje prognozę wzdłuż pozostałej części trasy.
//
// Bez uwierzytelnienia, tak jak reszta publicznego LIVE: uprawnieniem jest
// posiadanie tokenu. Prywatność rozstrzyga się tutaj, nie na stronie.
func LiveRideWeather(e *core.RequestEvent) error {
	access, err := liveRideResolveShare(e)
	if err != nil {
		return err
	}
	session := access.session
	liveRideNoStore(e, liveRideVisibility(session) == "public")

	now := time.Now().UTC()
	empty := map[string]any{"server_time": now, "points": []any{}}
	if access.state != "ok" {
		return e.JSON(http.StatusOK, empty)
	}

	samples, ok := liveRideWeatherSamples(e, session)
	if !ok || len(samples) == 0 {
		// Zawodnik, który nie udostępnia pozycji, nie udostępnia też tego,
		// w jaką pogodę wjeżdża: prognoza „na mecie" mówiłaby, gdzie ta meta
		// jest. Sekcja po prostu nie powstaje.
		return e.JSON(http.StatusOK, empty)
	}

	payload, err := liveRideWeatherFetch(e, session.Id, samples, now)
	if err != nil {
		// Dostawca pogody nie jest częścią jazdy. Gdy milczy, strona traci
		// jedną sekcję, a nie mapę.
		e.App.Logger().Warn("live ride: weather lookup failed", "error", err)
		return e.JSON(http.StatusOK, empty)
	}
	return e.JSON(http.StatusOK, payload)
}

// liveRideWeatherSamples wybiera punkty, o które warto zapytać.
//
// Drugi zwracany parametr mówi, czy w ogóle wolno pokazać pogodę: pozycja
// zawodnika jest jej warunkiem, bo bez niej nie wiadomo, gdzie on jest ani
// co go czeka.
func liveRideWeatherSamples(e *core.RequestEvent, session *core.Record) ([]liveRideWeatherSample, bool) {
	participants, err := e.App.FindRecordsByFilter(
		"live_ride_participants",
		"session={:session}",
		"display_name",
		100,
		0,
		dbx.Params{"session": session.Id},
	)
	if err != nil {
		return nil, false
	}

	var leader *core.Record
	for _, participant := range participants {
		if !liveRideShares(participant, "share_position") || !liveRideHasFix(participant) {
			continue
		}
		// Prowadzi ten, kto przejechał najwięcej: to jego „przed sobą" jest
		// tym, o co pyta obserwujący grupę.
		if leader == nil || participant.GetFloat("distance_m") > leader.GetFloat("distance_m") {
			leader = participant
		}
	}
	if leader == nil {
		return nil, false
	}

	lat := leader.GetFloat("latitude")
	lon := leader.GetFloat("longitude")

	coordinates := liveRideSessionRouteCoordinates(e, session)
	if len(coordinates) < 2 {
		// Jazda bez trasy: jedyne, co wiemy na pewno, to gdzie zawodnik jest.
		// „Za 20 km" nie istnieje, bo nie wiadomo, w którą stronę.
		return []liveRideWeatherSample{{Label: "now", Latitude: lat, Longitude: lon}}, true
	}

	cumulative := liveRideCumulative(coordinates)
	total := cumulative[len(cumulative)-1]
	along := liveRideAlongRoute(coordinates, cumulative, lat, lon)

	samples := []liveRideWeatherSample{{
		Label:      "now",
		Latitude:   lat,
		Longitude:  lon,
		AlongM:     along,
		BearingDeg: liveRideBearingAt(coordinates, cumulative, along),
	}}

	for ahead := float64(liveRideWeatherAheadStepMeters); ahead < total-along; ahead += liveRideWeatherAheadStepMeters {
		if len(samples) >= liveRideWeatherMaxPoints-1 {
			break
		}
		at := along + ahead
		point := liveRidePointAt(coordinates, cumulative, at)
		samples = append(samples, liveRideWeatherSample{
			Label:      "ahead",
			Latitude:   point[0],
			Longitude:  point[1],
			AlongM:     at,
			AheadM:     ahead,
			BearingDeg: liveRideBearingAt(coordinates, cumulative, at),
		})
	}

	// Meta ma sens tylko wtedy, gdy jest wyraźnie dalej niż ostatni punkt
	// pośredni — inaczej strona pokazałaby dwa razy to samo miejsce.
	last := samples[len(samples)-1]
	if total-last.AlongM > 3000 {
		finish := coordinates[len(coordinates)-1]
		samples = append(samples, liveRideWeatherSample{
			Label:      "finish",
			Latitude:   finish[0],
			Longitude:  finish[1],
			AlongM:     total,
			AheadM:     total - along,
			BearingDeg: liveRideBearingAt(coordinates, cumulative, total),
		})
	}
	return samples, true
}

// liveRideWeatherFetch pyta dostawcę albo oddaje to, co już wiemy.
func liveRideWeatherFetch(
	e *core.RequestEvent,
	sessionID string,
	samples []liveRideWeatherSample,
	now time.Time,
) (map[string]any, error) {
	key := liveRideWeatherCacheKey(sessionID, samples)

	liveRideWeatherMu.Lock()
	entry, cached := liveRideWeatherCache[key]
	liveRideWeatherMu.Unlock()
	if cached && now.Sub(entry.fetchedAt) < liveRideWeatherTTL {
		return entry.payload, nil
	}

	latitudes := make([]string, 0, len(samples))
	longitudes := make([]string, 0, len(samples))
	for _, sample := range samples {
		latitudes = append(latitudes, fmt.Sprintf("%.4f", sample.Latitude))
		longitudes = append(longitudes, fmt.Sprintf("%.4f", sample.Longitude))
	}

	url := fmt.Sprintf(
		"%s?latitude=%s&longitude=%s&hourly=%s&daily=sunrise,sunset&forecast_hours=%d&forecast_days=2&timeformat=unixtime&wind_speed_unit=kmh&timezone=UTC",
		liveRideWeatherEndpoint(),
		strings.Join(latitudes, ","),
		strings.Join(longitudes, ","),
		"temperature_2m,precipitation_probability,weather_code,wind_speed_10m,wind_direction_10m",
		liveRideWeatherForecastHours,
	)

	ctx, cancel := context.WithTimeout(e.Request.Context(), 8*time.Second)
	defer cancel()
	result, err := util.FetchPublicURL(ctx, url, liveRideWeatherMaxBytes)
	if err != nil {
		return nil, err
	}

	forecasts, err := liveRideWeatherDecode(result.Body, len(samples))
	if err != nil {
		return nil, err
	}

	points := make([]map[string]any, 0, len(samples))
	var sunset, sunrise any
	for i, sample := range samples {
		if i >= len(forecasts) {
			break
		}
		forecast := forecasts[i]
		point := map[string]any{
			"label":   sample.Label,
			"along_m": math.Round(sample.AlongM),
			"ahead_m": math.Round(sample.AheadM),
			"hours":   forecast.Hours,
		}
		if sample.BearingDeg != nil {
			point["bearing_deg"] = math.Round(*sample.BearingDeg*10) / 10
		}
		points = append(points, point)
		// Zachód słońca bierzemy z pierwszego punktu: to tam zawodnik jest
		// teraz, a różnica kilkudziesięciu kilometrów to kilka minut.
		if i == 0 {
			sunset = forecast.Sunset
			sunrise = forecast.Sunrise
		}
	}

	payload := map[string]any{
		"server_time": now,
		"points":      points,
	}
	if sunset != nil {
		payload["sunset"] = sunset
	}
	if sunrise != nil {
		payload["sunrise"] = sunrise
	}

	liveRideWeatherMu.Lock()
	liveRideWeatherCache[key] = liveRideWeatherCacheEntry{payload: payload, fetchedAt: now}
	liveRideWeatherPrune(now)
	liveRideWeatherMu.Unlock()

	return payload, nil
}

type liveRideForecast struct {
	Hours   []map[string]any
	Sunset  any
	Sunrise any
}

// liveRideWeatherDecode rozumie obie postaci odpowiedzi Open-Meteo: obiekt dla
// jednej współrzędnej i tablicę dla wielu.
func liveRideWeatherDecode(body []byte, expected int) ([]liveRideForecast, error) {
	var raw []json.RawMessage
	if err := json.Unmarshal(body, &raw); err != nil {
		raw = []json.RawMessage{body}
	}
	if len(raw) == 0 {
		return nil, fmt.Errorf("weather response is empty")
	}

	forecasts := make([]liveRideForecast, 0, expected)
	for _, item := range raw {
		var payload struct {
			Hourly struct {
				Time                     []int64    `json:"time"`
				Temperature              []float64  `json:"temperature_2m"`
				PrecipitationProbability []*float64 `json:"precipitation_probability"`
				WeatherCode              []*float64 `json:"weather_code"`
				WindSpeed                []*float64 `json:"wind_speed_10m"`
				WindDirection            []*float64 `json:"wind_direction_10m"`
			} `json:"hourly"`
			Daily struct {
				Sunrise []int64 `json:"sunrise"`
				Sunset  []int64 `json:"sunset"`
			} `json:"daily"`
		}
		if err := json.Unmarshal(item, &payload); err != nil {
			return nil, err
		}

		hours := make([]map[string]any, 0, len(payload.Hourly.Time))
		for i, stamp := range payload.Hourly.Time {
			hour := map[string]any{"at": time.Unix(stamp, 0).UTC().Format(time.RFC3339)}
			if i < len(payload.Hourly.Temperature) {
				hour["temp_c"] = payload.Hourly.Temperature[i]
			}
			// Każde pole osobno i tylko gdy dostawca je podał: brak prognozy
			// opadów to brak prognozy opadów, a nie zero procent.
			if value := liveRideAtIndex(payload.Hourly.PrecipitationProbability, i); value != nil {
				hour["precip_probability"] = *value
			}
			if value := liveRideAtIndex(payload.Hourly.WeatherCode, i); value != nil {
				hour["code"] = int(*value)
			}
			if value := liveRideAtIndex(payload.Hourly.WindSpeed, i); value != nil {
				hour["wind_kmh"] = *value
			}
			if value := liveRideAtIndex(payload.Hourly.WindDirection, i); value != nil {
				hour["wind_from_deg"] = *value
			}
			hours = append(hours, hour)
		}

		forecast := liveRideForecast{Hours: hours}
		if len(payload.Daily.Sunset) > 0 {
			forecast.Sunset = time.Unix(payload.Daily.Sunset[0], 0).UTC().Format(time.RFC3339)
		}
		if len(payload.Daily.Sunrise) > 0 {
			forecast.Sunrise = time.Unix(payload.Daily.Sunrise[0], 0).UTC().Format(time.RFC3339)
		}
		forecasts = append(forecasts, forecast)
	}
	return forecasts, nil
}

func liveRideAtIndex(values []*float64, index int) *float64 {
	if index >= len(values) {
		return nil
	}
	return values[index]
}

// liveRideWeatherCacheKey zaokrągla współrzędne, żeby zawodnik jadący przez
// miasto nie generował nowego zapytania co sto metrów. Setna część stopnia to
// mniej więcej kilometr — poniżej tego prognoza godzinowa jest identyczna.
func liveRideWeatherCacheKey(sessionID string, samples []liveRideWeatherSample) string {
	var builder strings.Builder
	builder.WriteString(sessionID)
	for _, sample := range samples {
		fmt.Fprintf(&builder, "|%.2f,%.2f", sample.Latitude, sample.Longitude)
	}
	return builder.String()
}

// liveRideWeatherPrune wyrzuca wpisy, które i tak są już nieświeże.
//
// Bez tego mapa rosłaby o jeden wpis na każdą zakończoną jazdę i nigdy nie
// malała — wolno, ale bez końca.
func liveRideWeatherPrune(now time.Time) {
	for key, entry := range liveRideWeatherCache {
		if now.Sub(entry.fetchedAt) > 4*liveRideWeatherTTL {
			delete(liveRideWeatherCache, key)
		}
	}
}

// ------------------------------------------------------ geometria trasy

// liveRideSessionRouteCoordinates zwraca plan przejazdu jako pary [lat, lon].
func liveRideSessionRouteCoordinates(e *core.RequestEvent, session *core.Record) [][]float64 {
	encoded := ""
	precision := liveRidePolylinePrecision
	if routeID := session.GetString("route"); routeID != "" {
		if route, err := e.App.FindRecordById("live_ride_routes", routeID); err == nil {
			encoded = route.GetString("polyline")
		}
	}
	if encoded == "" {
		if trailID := session.GetString("trail"); trailID != "" {
			if trail, err := e.App.FindRecordById("trails", trailID); err == nil {
				encoded = trail.GetString("polyline")
				// Kolekcja `trails` starego Wanderera koduje w precyzji 5.
				precision = 5
			}
		}
	}
	if encoded == "" {
		return nil
	}

	codec := liveRidePolylineCodec
	if precision == 5 {
		codec = polylinePrecision5
	}
	coordinates, _, err := codec.DecodeCoords([]byte(encoded))
	if err != nil {
		return nil
	}
	return coordinates
}

func liveRideCumulative(coordinates [][]float64) []float64 {
	cumulative := make([]float64, len(coordinates))
	for i := 1; i < len(coordinates); i++ {
		cumulative[i] = cumulative[i-1] + util.HaversineDistanceMeters(
			coordinates[i-1][0], coordinates[i-1][1],
			coordinates[i][0], coordinates[i][1],
		)
	}
	return cumulative
}

// liveRideAlongRoute mówi, ile trasy zawodnik ma za sobą.
//
// Najbliższy wierzchołek wystarczy: punkty prognozy stoją co dwadzieścia
// kilometrów, więc błąd rzędu długości jednego odcinka trasy niczego nie
// zmienia. Dokładny rzut na odcinek liczy strona, dla postępu i ETA.
func liveRideAlongRoute(coordinates [][]float64, cumulative []float64, lat, lon float64) float64 {
	best := 0.0
	bestDistance := math.Inf(1)
	for i, point := range coordinates {
		distance := util.HaversineDistanceMeters(point[0], point[1], lat, lon)
		if distance < bestDistance {
			bestDistance = distance
			best = cumulative[i]
		}
	}
	return best
}

// liveRidePointAt zwraca współrzędne w zadanej odległości wzdłuż trasy.
func liveRidePointAt(coordinates [][]float64, cumulative []float64, along float64) []float64 {
	if along <= 0 {
		return coordinates[0]
	}
	for i := 1; i < len(coordinates); i++ {
		if cumulative[i] < along {
			continue
		}
		span := cumulative[i] - cumulative[i-1]
		if span <= 0 {
			return coordinates[i]
		}
		t := (along - cumulative[i-1]) / span
		return []float64{
			coordinates[i-1][0] + (coordinates[i][0]-coordinates[i-1][0])*t,
			coordinates[i-1][1] + (coordinates[i][1]-coordinates[i-1][1])*t,
		}
	}
	return coordinates[len(coordinates)-1]
}

// liveRideBearingAt podaje kurs jazdy w danym miejscu trasy.
//
// To on zamienia „wiatr z zachodu" w „wiatr czołowy 9 km/h" — czyli w jedyną
// postać, w której informacja o wietrze cokolwiek znaczy dla rowerzysty.
func liveRideBearingAt(coordinates [][]float64, cumulative []float64, along float64) *float64 {
	if len(coordinates) < 2 {
		return nil
	}
	index := 0
	for i := 1; i < len(coordinates); i++ {
		if cumulative[i] >= along {
			index = i - 1
			break
		}
		index = i - 1
	}
	if index >= len(coordinates)-1 {
		index = len(coordinates) - 2
	}

	from := coordinates[index]
	to := coordinates[index+1]
	toRad := math.Pi / 180
	lat1 := from[0] * toRad
	lat2 := to[0] * toRad
	dLon := (to[1] - from[1]) * toRad
	y := math.Sin(dLon) * math.Cos(lat2)
	x := math.Cos(lat1)*math.Sin(lat2) - math.Sin(lat1)*math.Cos(lat2)*math.Cos(dLon)
	bearing := math.Mod(math.Atan2(y, x)/toRad+360, 360)
	return &bearing
}
