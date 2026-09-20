package routes

import (
	"encoding/json"
	"math"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/pocketbase/pocketbase/core"
)

// Testy pogody na trasie.
//
// Samo wyjście do dostawcy nie jest tu sprawdzane — robi to util.FetchPublicURL
// z własnymi testami, a ten pakiet celowo nie wychodzi do sieci. Sprawdzane
// jest to, co naprawdę może pójść źle: KTÓRE punkty wybieramy, KIEDY wolno
// pokazać pogodę i JAK czytamy odpowiedź, w której brakuje pól.

// liveRideWeatherFixture dokłada do zwykłej sesji trasę, żeby dało się pytać
// o punkty przed zawodnikiem.
func liveRideWeatherFixture(t *testing.T) *liveRideFixture {
	t.Helper()
	f := newLiveRideFixture(t)

	routes := core.NewBaseCollection("live_ride_routes")
	routes.Fields.Add(
		&core.TextField{Name: "polyline", Max: 1000000},
		&core.NumberField{Name: "distance_m"},
	)
	if err := f.app.Save(routes); err != nil {
		t.Fatal(err)
	}

	// Prosta linia na wschód: około 100 km w czterech odcinkach, więc punkty
	// „za 20 km" i „za 40 km" na pewno w niej mieszczą.
	coordinates := make([][]float64, 0, 101)
	for i := 0; i <= 100; i++ {
		coordinates = append(coordinates, []float64{52.0, 21.0 + float64(i)*0.0146})
	}
	route := core.NewRecord(routes)
	route.Set("polyline", string(liveRidePolylineCodec.EncodeCoords(nil, coordinates)))
	if err := f.app.Save(route); err != nil {
		t.Fatal(err)
	}

	f.session.Set("route", route.Id)
	if err := f.app.Save(f.session); err != nil {
		t.Fatal(err)
	}
	return f
}

func (f *liveRideFixture) weather(t *testing.T, token string) (int, map[string]any, http.Header) {
	return f.call(t, LiveRideWeather, "/live/"+token+"/weather", "/live/{token}/weather")
}

func liveRideWeatherEvent(t *testing.T, f *liveRideFixture) *core.RequestEvent {
	t.Helper()
	event := &core.RequestEvent{}
	event.App = f.app
	event.Request = httptest.NewRequest(http.MethodGet, "/live/x/weather", nil)
	event.Response = httptest.NewRecorder()
	return event
}

// Bez zgody na pozycję nie ma pogody. Prognoza „na mecie" mówi, gdzie ta meta
// jest, a zawodnik, który ukrył pozycję, właśnie tego nie chciał.
func TestLiveRideWeatherNeedsPositionConsent(t *testing.T) {
	f := liveRideWeatherFixture(t)
	f.addRider(t, "Marek", 3, func(record *core.Record) {
		record.Set("latitude", 52.0)
		record.Set("longitude", 21.0)
		record.Set("share_position", false)
	})

	if samples, ok := liveRideWeatherSamples(liveRideWeatherEvent(t, f), f.session); ok {
		t.Errorf("pogoda wyszła mimo ukrytej pozycji: %v", samples)
	}

	status, body, _ := f.weather(t, f.session.GetString("share_token"))
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	points, _ := body["points"].([]any)
	if len(points) != 0 {
		t.Errorf("points = %v, chciano pustą listę", points)
	}
}

// Zawodnik bez ani jednego fiksa nie ma „tutaj", więc nie ma też „dalej".
func TestLiveRideWeatherNeedsAFix(t *testing.T) {
	f := liveRideWeatherFixture(t)
	rider := core.NewRecord(f.participant)
	rider.Set("session", f.session.Id)
	rider.Set("display_name", "Marek")
	rider.Set("share_position", true)
	if err := f.app.Save(rider); err != nil {
		t.Fatal(err)
	}

	if _, ok := liveRideWeatherSamples(liveRideWeatherEvent(t, f), f.session); ok {
		t.Error("pogoda nie ma prawa powstać, zanim przyjdzie pierwsza pozycja")
	}
}

// Z trasą pytamy o „teraz", punkty przed zawodnikiem i metę.
func TestLiveRideWeatherSamplesRouteAhead(t *testing.T) {
	f := liveRideWeatherFixture(t)
	f.addRider(t, "Marek", 3, func(record *core.Record) {
		record.Set("latitude", 52.0)
		record.Set("longitude", 21.0)
	})

	samples, ok := liveRideWeatherSamples(liveRideWeatherEvent(t, f), f.session)
	if !ok {
		t.Fatal("pogoda powinna być dostępna")
	}
	if len(samples) < 3 {
		t.Fatalf("punktów = %d, chciano co najmniej 3 (teraz, przed, meta): %+v", len(samples), samples)
	}
	if samples[0].Label != "now" || samples[0].AheadM != 0 {
		t.Errorf("pierwszy punkt = %+v, chciano „teraz\"", samples[0])
	}
	if samples[len(samples)-1].Label != "finish" {
		t.Errorf("ostatni punkt = %+v, chciano metę", samples[len(samples)-1])
	}
	if len(samples) > liveRideWeatherMaxPoints {
		t.Errorf("punktów = %d, limit to %d", len(samples), liveRideWeatherMaxPoints)
	}

	// Punkty pośrednie rosną, a odległości są rzeczywiste, nie okrągłe
	// z założenia.
	for i := 1; i < len(samples); i++ {
		if samples[i].AheadM <= samples[i-1].AheadM {
			t.Errorf("punkt %d nie jest dalej niż poprzedni: %+v", i, samples)
		}
	}
	// Kurs jazdy jest tym, co zamienia „wiatr z zachodu" w „wiatr czołowy".
	if samples[0].BearingDeg == nil {
		t.Error("punkt na trasie musi znać kurs jazdy")
	} else if math.Abs(*samples[0].BearingDeg-90) > 2 {
		t.Errorf("kurs = %.1f°, trasa biegnie na wschód", *samples[0].BearingDeg)
	}
}

// Zawodnik prawie na mecie nie dostaje punktów „przed sobą", których nie ma.
func TestLiveRideWeatherNearFinishHasOnlyNow(t *testing.T) {
	f := liveRideWeatherFixture(t)
	f.addRider(t, "Marek", 3, func(record *core.Record) {
		record.Set("latitude", 52.0)
		record.Set("longitude", 21.0+100*0.0146)
	})

	samples, ok := liveRideWeatherSamples(liveRideWeatherEvent(t, f), f.session)
	if !ok {
		t.Fatal("pogoda powinna być dostępna")
	}
	if len(samples) != 1 || samples[0].Label != "now" {
		t.Errorf("punkty = %+v, chciano wyłącznie „teraz\"", samples)
	}
}

// Jazda bez trasy: wiemy tylko, gdzie ktoś jest. „Za 20 km" nie istnieje, bo
// nie wiadomo, w którą stronę.
func TestLiveRideWeatherFreeRideHasNoRoutePoints(t *testing.T) {
	f := newLiveRideFixture(t)
	f.addRider(t, "Marek", 3, nil)

	samples, ok := liveRideWeatherSamples(liveRideWeatherEvent(t, f), f.session)
	if !ok {
		t.Fatal("pogoda w miejscu zawodnika powinna być dostępna")
	}
	if len(samples) != 1 {
		t.Fatalf("punktów = %d, chciano 1", len(samples))
	}
	if samples[0].Label != "now" {
		t.Errorf("label = %q, want now", samples[0].Label)
	}
	if samples[0].BearingDeg != nil {
		t.Error("bez trasy nie znamy kursu i nie wolno go zmyślać")
	}
}

// W grupie pyta się o to, co przed PROWADZĄCYM: jego „dalej" jest tym, o co
// pyta obserwujący.
func TestLiveRideWeatherFollowsTheLeader(t *testing.T) {
	f := liveRideWeatherFixture(t)
	f.addRider(t, "Kuba", 3, func(record *core.Record) {
		record.Set("latitude", 52.0)
		record.Set("longitude", 21.0)
		record.Set("distance_m", 1000.0)
	})
	f.addRider(t, "Marek", 3, func(record *core.Record) {
		record.Set("latitude", 52.0)
		record.Set("longitude", 21.0+50*0.0146)
		record.Set("distance_m", 50000.0)
	})

	samples, ok := liveRideWeatherSamples(liveRideWeatherEvent(t, f), f.session)
	if !ok {
		t.Fatal("pogoda powinna być dostępna")
	}
	if samples[0].AlongM < 40000 {
		t.Errorf("punkt „teraz\" na %.0f m — chciano pozycję prowadzącego", samples[0].AlongM)
	}
}

// Odpowiedź dostawcy bywa niekompletna. Brakujące pole to brak pomiaru,
// nigdy zero procent szansy na deszcz.
func TestLiveRideWeatherDecodeSkipsMissingFields(t *testing.T) {
	body := []byte(`[{
		"hourly": {
			"time": [1789000000, 1789003600],
			"temperature_2m": [17.4, 16.8],
			"precipitation_probability": [40, null],
			"weather_code": [61, 3],
			"wind_speed_10m": [18.2, 14.0],
			"wind_direction_10m": [240, 250]
		},
		"daily": {"sunrise": [1788960000], "sunset": [1789012345]}
	}]`)

	forecasts, err := liveRideWeatherDecode(body, 1)
	if err != nil {
		t.Fatal(err)
	}
	if len(forecasts) != 1 {
		t.Fatalf("prognoz = %d, want 1", len(forecasts))
	}
	hours := forecasts[0].Hours
	if len(hours) != 2 {
		t.Fatalf("godzin = %d, want 2", len(hours))
	}
	if hours[0]["precip_probability"] != 40.0 {
		t.Errorf("precip_probability = %v, want 40", hours[0]["precip_probability"])
	}
	if _, present := hours[1]["precip_probability"]; present {
		t.Error("brak prognozy opadów nie ma prawa zamienić się w zero procent")
	}
	if hours[0]["code"] != 61 {
		t.Errorf("code = %v, want 61", hours[0]["code"])
	}
	if forecasts[0].Sunset == nil {
		t.Error("zachód słońca powinien zostać odczytany")
	}
	// Godziny wychodzą jako RFC3339 w UTC, żeby strona nie musiała zgadywać
	// strefy czasowej dostawcy.
	if at, _ := hours[0]["at"].(string); at != time.Unix(1789000000, 0).UTC().Format(time.RFC3339) {
		t.Errorf("at = %v", hours[0]["at"])
	}
}

// Open-Meteo oddaje obiekt dla jednej współrzędnej i tablicę dla wielu.
func TestLiveRideWeatherDecodeAcceptsSingleObject(t *testing.T) {
	body := []byte(`{"hourly": {"time": [1789000000], "temperature_2m": [12.0]}}`)
	forecasts, err := liveRideWeatherDecode(body, 1)
	if err != nil {
		t.Fatal(err)
	}
	if len(forecasts) != 1 || len(forecasts[0].Hours) != 1 {
		t.Fatalf("prognoza = %+v", forecasts)
	}
	if forecasts[0].Hours[0]["temp_c"] != 12.0 {
		t.Errorf("temp_c = %v, want 12", forecasts[0].Hours[0]["temp_c"])
	}
}

// Wygasły link nie jest furtką do prognozy wzdłuż trasy.
func TestLiveRideWeatherExpiredLinkGivesNothing(t *testing.T) {
	f := liveRideWeatherFixture(t)
	f.addRider(t, "Marek", 3, func(record *core.Record) {
		record.Set("latitude", 52.0)
		record.Set("longitude", 21.0)
	})
	f.session.Set("expires_at", time.Now().UTC().Add(-time.Hour))
	if err := f.app.Save(f.session); err != nil {
		t.Fatal(err)
	}

	_, body, _ := f.weather(t, f.session.GetString("share_token"))
	points, _ := body["points"].([]any)
	if len(points) != 0 {
		t.Errorf("points = %v, chciano pustą listę", points)
	}
	// Odpowiedź nie może też nieść współrzędnych żadną inną drogą.
	encoded, _ := json.Marshal(body)
	if len(encoded) > 200 {
		t.Errorf("odpowiedź dla wygasłego linku jest podejrzanie duża: %s", encoded)
	}
}

// Punkt na trasie i kurs liczą się z geometrii, nie z założeń.
func TestLiveRideRouteGeometryHelpers(t *testing.T) {
	coordinates := [][]float64{
		{52.0, 21.0},
		{52.0, 21.1},
		{52.0, 21.2},
	}
	cumulative := liveRideCumulative(coordinates)
	total := cumulative[len(cumulative)-1]
	if total < 13000 || total > 14000 {
		t.Fatalf("długość = %.0f m, oczekiwano około 13,7 km", total)
	}

	middle := liveRidePointAt(coordinates, cumulative, total/2)
	if math.Abs(middle[1]-21.1) > 0.001 {
		t.Errorf("połowa trasy = %v, chciano długość 21,1", middle)
	}

	// Przed początkiem i za końcem zwracamy końce, a nie liczby spoza trasy.
	if start := liveRidePointAt(coordinates, cumulative, -5); start[1] != 21.0 {
		t.Errorf("przed startem = %v", start)
	}
	if finish := liveRidePointAt(coordinates, cumulative, total*2); finish[1] != 21.2 {
		t.Errorf("za metą = %v", finish)
	}

	if bearing := liveRideBearingAt(coordinates, cumulative, 0); bearing == nil {
		t.Error("kurs na trasie musi być znany")
	} else if math.Abs(*bearing-90) > 1 {
		t.Errorf("kurs = %.1f°, trasa biegnie na wschód", *bearing)
	}

	// Jedna para współrzędnych to nie trasa i nie ma kursu.
	if bearing := liveRideBearingAt([][]float64{{52.0, 21.0}}, []float64{0}, 0); bearing != nil {
		t.Error("pojedynczy punkt nie wyznacza kierunku jazdy")
	}
}
