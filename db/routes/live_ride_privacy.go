package routes

import (
	"math"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// Prywatność lokalizacji — trzy osobne decyzje, wszystkie po stronie serwera.
//
// Każdą z nich dałoby się „załatwić" w przeglądarce w pięć minut i każda
// byłaby wtedy warta dokładnie tyle, co komentarz w kodzie: dane i tak
// poleciałyby po sieci, a ukrycie polegałoby na tym, że widz ich nie kliknie.
// Dlatego filtr siedzi tutaj, a publiczne API po prostu nie zna odpowiedzi.
//
//  1. UKRYTY START/META — pozycje w promieniu wokół domu nie wychodzą wcale.
//  2. OPÓŹNIENIE — widz dostaje pozycję sprzed N sekund, a nagranie przejazdu
//     zostaje nietknięte.
//  3. PRZYBLIŻONA POZYCJA — współrzędne zaokrąglone do kratki, nie do piksela.

// Do ilu miejsc po przecinku zaokrąglamy przybliżoną pozycję.
//
// Trzy miejsca to około 110 metrów w pionie i mniej w poziomie na naszych
// szerokościach — dość, by widać było, że ktoś jedzie doliną, i za mało, by
// wskazać, przed którym domem stoi.
const liveRideCoarseDecimals = 3

// liveRideLocationPolicy to komplet ustawień lokalizacyjnych zawodnika.
type liveRideLocationPolicy struct {
	DelaySeconds int
	Coarse       bool
	HideStartM   float64
	HideFinishM  float64

	startLat, startLon   float64
	finishLat, finishLon float64
	hasStart, hasFinish  bool
}

// active mówi, czy cokolwiek w ogóle trzeba filtrować.
func (p liveRideLocationPolicy) active() bool {
	return p.DelaySeconds > 0 || p.Coarse ||
		(p.HideStartM > 0 && p.hasStart) ||
		(p.HideFinishM > 0 && p.hasFinish)
}

// liveRideLocationPolicyFor składa ustawienia zawodnika z metą trasy.
//
// Metę bierzemy z ostatniego punktu planu, bo tylko on jest znany PRZED
// dojechaniem. Gdyby brać ostatnią pozycję, promień ukrycia wędrowałby razem
// z zawodnikiem i nie ukrywał niczego.
func liveRideLocationPolicyFor(
	participant *core.Record,
	finish *liveRideGeoPoint,
) liveRideLocationPolicy {
	policy := liveRideLocationPolicy{
		DelaySeconds: participant.GetInt("location_delay_seconds"),
		Coarse:       participant.GetBool("location_coarse"),
		HideStartM:   participant.GetFloat("hide_start_m"),
		HideFinishM:  participant.GetFloat("hide_finish_m"),
		startLat:     participant.GetFloat("start_lat"),
		startLon:     participant.GetFloat("start_lon"),
	}
	policy.hasStart = policy.startLat != 0 || policy.startLon != 0
	if finish != nil {
		policy.finishLat = finish.Lat
		policy.finishLon = finish.Lon
		policy.hasFinish = true
	}
	// Opóźnienie ponad kwadrans zamienia „live" w coś innego i nie ma po co
	// go obsługiwać; ujemne nie znaczy nic.
	if policy.DelaySeconds < 0 {
		policy.DelaySeconds = 0
	}
	if policy.DelaySeconds > 900 {
		policy.DelaySeconds = 900
	}
	return policy
}

// hides mówi, czy tej pozycji nie wolno pokazać wcale.
func (p liveRideLocationPolicy) hides(lat, lon float64) bool {
	if p.HideStartM > 0 && p.hasStart &&
		liveRideHaversine(lat, lon, p.startLat, p.startLon) <= p.HideStartM {
		return true
	}
	if p.HideFinishM > 0 && p.hasFinish &&
		liveRideHaversine(lat, lon, p.finishLat, p.finishLon) <= p.HideFinishM {
		return true
	}
	return false
}

// blur zaokrągla współrzędne, gdy zawodnik wybrał pozycję przybliżoną.
func (p liveRideLocationPolicy) blur(lat, lon float64) (float64, float64) {
	if !p.Coarse {
		return lat, lon
	}
	factor := math.Pow(10, liveRideCoarseDecimals)
	return math.Round(lat*factor) / factor, math.Round(lon*factor) / factor
}

// cutoff to najpóźniejsza chwila, którą wolno pokazać widzowi.
func (p liveRideLocationPolicy) cutoff(now time.Time) time.Time {
	if p.DelaySeconds <= 0 {
		return now
	}
	return now.Add(-time.Duration(p.DelaySeconds) * time.Second)
}

// liveRideGeoPoint to para współrzędnych bez żadnej dodatkowej semantyki.
type liveRideGeoPoint struct {
	Lat float64
	Lon float64
}

// liveRideRouteFinish zwraca koniec planu albo nil, gdy planu nie ma.
func liveRideRouteFinish(app core.App, session *core.Record) *liveRideGeoPoint {
	routeID := session.GetString("route")
	if routeID == "" {
		return nil
	}
	route, err := app.FindRecordById("live_ride_routes", routeID)
	if err != nil {
		return nil
	}
	encoded := route.GetString("polyline")
	if encoded == "" {
		return nil
	}
	coordinates, _, err := liveRidePolylineCodec.DecodeCoords([]byte(encoded))
	if err != nil || len(coordinates) == 0 {
		return nil
	}
	last := coordinates[len(coordinates)-1]
	if len(last) < 2 {
		return nil
	}
	return &liveRideGeoPoint{Lat: last[0], Lon: last[1]}
}

// liveRideDelayedPosition znajduje najnowszą pozycję nie nowszą niż próg.
//
// Zwraca nil, gdy żadna próbka nie jest jeszcze dość stara — czyli przez
// pierwsze N sekund transmisji. Wtedy widz nie dostaje pozycji w ogóle,
// i o to właśnie chodzi: opóźnienie, które na starcie pokazuje bieżący punkt,
// nie jest opóźnieniem.
func liveRideDelayedPosition(
	app core.App,
	participantID string,
	cutoff time.Time,
) *core.Record {
	records, err := app.FindRecordsByFilter(
		"live_ride_points",
		"participant = {:participant} && recorded_at <= {:cutoff}",
		"-recorded_at",
		1,
		0,
		dbx.Params{
			"participant": participantID,
			"cutoff":      cutoff.UTC().Format("2006-01-02 15:04:05.000Z"),
		},
	)
	if err != nil || len(records) == 0 {
		return nil
	}
	return records[0]
}

const liveRideEarthRadiusMeters = 6371008.8

// liveRideHaversine liczy odległość dwóch punktów po powierzchni Ziemi.
func liveRideHaversine(lat1, lon1, lat2, lon2 float64) float64 {
	toRad := math.Pi / 180
	dLat := (lat2 - lat1) * toRad
	dLon := (lon2 - lon1) * toRad
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*toRad)*math.Cos(lat2*toRad)*math.Sin(dLon/2)*math.Sin(dLon/2)
	return 2 * liveRideEarthRadiusMeters * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}
