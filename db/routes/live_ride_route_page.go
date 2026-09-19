package routes

import (
	"encoding/xml"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"pocketbase/util"
)

// Publiczna strona trasy.
//
// To druga strona, nie mylić z podglądem LIVE: trasę udostępnia się PRZED
// jazdą, a nie w jej trakcie. Wspólne mają tylko to, że ani jedna, ani druga
// nie wymaga konta.

// liveRideResolveSharedRoute znajduje trasę po tokenie linku.
//
// Prywatna trasa nie istnieje dla nikogo poza właścicielem — nawet gdy ktoś
// zgadnie token, filtr `privacy != 'private'` nie pozwoli jej wydać.
func liveRideResolveSharedRoute(e *core.RequestEvent) (*core.Record, error) {
	token := strings.TrimSpace(e.Request.PathValue("token"))
	if token == "" {
		return nil, apis.NewNotFoundError("Route not found", nil)
	}
	records, err := e.App.FindRecordsByFilter(
		"live_ride_routes",
		"share_token = {:token} && privacy != 'private'",
		"",
		1,
		0,
		dbx.Params{"token": token},
	)
	if err != nil || len(records) == 0 {
		return nil, apis.NewNotFoundError("Route not found", err)
	}
	return records[0], nil
}

// liveRideRouteAuthor zwraca nazwę autora widoczną publicznie.
//
// Nigdy identyfikator konta ani adres e-mail: strona ma powiedzieć, kto
// zaplanował trasę, a nie wydać jego dane.
func liveRideRouteAuthor(e *core.RequestEvent, record *core.Record) string {
	owner := record.GetString("owner")
	if owner == "" {
		return ""
	}
	user, err := e.App.FindRecordById("users", owner)
	if err != nil {
		return ""
	}
	for _, candidate := range []string{user.GetString("name"), user.GetString("username")} {
		if candidate = strings.TrimSpace(candidate); candidate != "" {
			return candidate
		}
	}
	return ""
}

// LiveRidePublicRoutePage serves one shared route to anyone holding the link.
func LiveRidePublicRoutePage(e *core.RequestEvent) error {
	record, err := liveRideResolveSharedRoute(e)
	if err != nil {
		return err
	}
	liveRideNoStore(e, record.GetString("privacy") == "public")

	payload := liveRideRouteJSON(record)
	payload["author"] = liveRideRouteAuthor(e, record)
	// Token widza nie potrzebuje wewnętrznych identyfikatorów właściciela ani
	// tego, jak trasa nazywa się na jego telefonie.
	delete(payload, "id")
	delete(payload, "client_id")
	return e.JSON(http.StatusOK, payload)
}

// LiveRideRouteGPX renders the shared route as a GPX file.
//
// GPX, a nie „otwórz w aplikacji": plik wgra się do Garmina, Wahoo, Komoota i
// czegokolwiek innego, co znajomy już ma. Eksport jest tym, co naprawdę
// działa bez konta.
func LiveRideRouteGPX(e *core.RequestEvent) error {
	record, err := liveRideResolveSharedRoute(e)
	if err != nil {
		return err
	}

	coordinates, _, decodeErr := liveRidePolylineCodec.DecodeCoords(
		[]byte(record.GetString("polyline")),
	)
	if decodeErr != nil || len(coordinates) < 2 {
		return apis.NewBadRequestError("Route has no usable geometry", decodeErr)
	}

	elevations := liveRideElevationsFor(record, coordinates)

	name := strings.TrimSpace(record.GetString("name"))
	if name == "" {
		name = "Live Ride"
	}

	var body strings.Builder
	body.WriteString(xml.Header)
	body.WriteString(`<gpx version="1.1" creator="Live Ride" xmlns="http://www.topografix.com/GPX/1/1">` + "\n")
	body.WriteString("  <metadata><name>" + liveRideEscapeXML(name) + "</name>")
	if description := strings.TrimSpace(record.GetString("description")); description != "" {
		body.WriteString("<desc>" + liveRideEscapeXML(description) + "</desc>")
	}
	body.WriteString("<time>" + time.Now().UTC().Format(time.RFC3339) + "</time></metadata>\n")
	body.WriteString("  <trk><name>" + liveRideEscapeXML(name) + "</name><trkseg>\n")
	for i, coordinate := range coordinates {
		body.WriteString(fmt.Sprintf(`    <trkpt lat="%.6f" lon="%.6f">`, coordinate[0], coordinate[1]))
		if elevations != nil {
			body.WriteString(fmt.Sprintf(`<ele>%.1f</ele>`, elevations[i]))
		}
		body.WriteString("</trkpt>\n")
	}
	body.WriteString("  </trkseg></trk>\n</gpx>\n")

	e.Response.Header().Set("Content-Type", "application/gpx+xml; charset=utf-8")
	e.Response.Header().Set(
		"Content-Disposition",
		`attachment; filename="`+liveRideFileName(name)+`.gpx"`,
	)
	e.Response.Header().Set("Cache-Control", "private, max-age=300")
	_, writeErr := e.Response.Write([]byte(body.String()))
	return writeErr
}

// liveRideElevationsFor rozkłada zapisany profil wysokości na punkty trasy.
//
// Profil jest przerzedzony (kilkaset próbek na kilkaset punktów), więc
// wysokość każdego punktu bierzemy z interpolacji po dystansie. Gdy profilu
// nie ma, plik wychodzi bez `<ele>` — zmyślone zero n.p.m. w GPX-ie psułoby
// każdy program, który go otworzy.
func liveRideElevationsFor(record *core.Record, coordinates [][]float64) []float64 {
	// PocketBase wydaje pole JSON jako surowe bajty, a nie gotowy `[]any`.
	// Rzutowanie na `[]any` cicho zwracało nil i plik wychodził bez wysokości
	// mimo zapisanego profilu.
	var raw []struct {
		D float64 `json:"d"`
		E float64 `json:"e"`
	}
	if err := record.UnmarshalJSONField("elevation_profile", &raw); err != nil {
		return nil
	}
	if len(raw) < 2 {
		return nil
	}

	type sample struct{ distance, elevation float64 }
	samples := make([]sample, 0, len(raw))
	for _, point := range raw {
		samples = append(samples, sample{point.D, point.E})
	}
	if len(samples) < 2 {
		return nil
	}

	cumulative := make([]float64, len(coordinates))
	for i := 1; i < len(coordinates); i++ {
		cumulative[i] = cumulative[i-1] + util.HaversineDistanceMeters(
			coordinates[i-1][0], coordinates[i-1][1],
			coordinates[i][0], coordinates[i][1],
		)
	}

	elevations := make([]float64, len(coordinates))
	cursor := 0
	for i, along := range cumulative {
		for cursor < len(samples)-2 && samples[cursor+1].distance < along {
			cursor++
		}
		left := samples[cursor]
		right := samples[cursor+1]
		span := right.distance - left.distance
		if span <= 0 {
			elevations[i] = left.elevation
			continue
		}
		t := (along - left.distance) / span
		if t < 0 {
			t = 0
		}
		if t > 1 {
			t = 1
		}
		elevations[i] = left.elevation + (right.elevation-left.elevation)*t
	}
	return elevations
}

func liveRideEscapeXML(value string) string {
	var out strings.Builder
	_ = xml.EscapeText(&out, []byte(value))
	return out.String()
}

// liveRideFileName zamienia nazwę trasy na bezpieczną nazwę pliku.
func liveRideFileName(name string) string {
	var out strings.Builder
	for _, r := range name {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
			out.WriteRune(r)
		case r == '-' || r == '_':
			out.WriteRune(r)
		default:
			out.WriteRune('-')
		}
	}
	trimmed := strings.Trim(out.String(), "-")
	for strings.Contains(trimmed, "--") {
		trimmed = strings.ReplaceAll(trimmed, "--", "-")
	}
	if trimmed == "" {
		return "live-ride-trasa"
	}
	if len(trimmed) > 60 {
		trimmed = strings.Trim(trimmed[:60], "-")
	}
	return trimmed
}
