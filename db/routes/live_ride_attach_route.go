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

// Doczepianie aktywnej trasy do trwającej sesji LIVE.
//
// Dotąd trasę wskazywało się przy tworzeniu sesji jednym polem
// `route_client_id`, a serwer szukał jej wśród tras JUŻ ZSYNCHRONIZOWANYCH.
// To działa dokładnie w jednym przypadku: trasa została wcześniej wysłana na
// serwer. W każdym innym — trasa właśnie powstała w kreatorze, przyszła
// z pliku GPX, została skopiowana z cudzego linku, albo synchronizacja jeszcze
// nie zdążyła — wyszukiwanie nie znajdowało nic, sesja zostawała bez trasy
// i publiczna strona pokazywała sam znacznik zawodnika. Bez żadnego błędu,
// bo z punktu widzenia serwera nic złego się nie stało.
//
// Ta trasa HTTP przyjmuje trasę w całości, więc nie zależy od tego, czy
// cokolwiek wcześniej się zsynchronizowało. Obsługuje też sytuacje, których
// tamto pole z założenia nie umiało: wybranie trasy PO uruchomieniu LIVE,
// zmianę trasy w trakcie jazdy i przeliczenie trasy po zjechaniu z niej.
//
// Publiczny link się nie zmienia. Widz, który go już otworzył, dostaje nową
// geometrię przy najbliższym odświeżeniu.

// liveRideAttachedRoute to trasa przysłana razem z żądaniem doczepienia.
//
// Świadomie ten sam kształt co w synchronizacji: telefon składa ładunek raz
// i używa go w obu miejscach, więc nie ma dwóch definicji tego, czym jest
// trasa, które mogłyby się rozjechać.
type liveRideAttachedRoute struct {
	ClientID         string  `json:"client_id"`
	Name             string  `json:"name"`
	DistanceM        float64 `json:"distance_m"`
	AscentM          float64 `json:"ascent_m"`
	DescentM         float64 `json:"descent_m"`
	Polyline         string  `json:"polyline"`
	ElevationProfile []any   `json:"elevation_profile"`
	Climbs           []any   `json:"climbs"`
	Surfaces         []any   `json:"surfaces"`
}

// LiveRideAttachRoute ustawia albo podmienia trasę aktywnej sesji.
func LiveRideAttachRoute(e *core.RequestEvent) error {
	session, err := e.App.FindRecordById("live_ride_sessions", e.Request.PathValue("id"))
	if err != nil {
		return apis.NewNotFoundError("Live ride not found", err)
	}
	if session.GetString("owner") != e.Auth.Id {
		return apis.NewForbiddenError("Only the live ride owner can set its route", nil)
	}

	var data struct {
		// Trasa już zsynchronizowana — wystarczy jej client_id.
		RouteClientID string `json:"route_client_id"`
		// Trasa, której serwer jeszcze nie zna — cała, w jednym kawałku.
		Route *liveRideAttachedRoute `json:"route"`
		// Jawne odpięcie: jazda bez planu po zakończeniu nawigacji.
		Detach bool `json:"detach"`
	}
	if err := e.BindBody(&data); err != nil {
		return apis.NewBadRequestError("Failed to read request data", err)
	}

	previousRoute := session.GetString("route")

	if data.Detach {
		if previousRoute == "" {
			return e.JSON(http.StatusOK, map[string]any{
				"has_route": false,
				"revision":  session.GetInt("route_revision"),
			})
		}
		session.Set("route", "")
		liveRideBumpRouteRevision(session)
		if err := e.App.Save(session); err != nil {
			return apis.NewBadRequestError("Failed to detach the route", err)
		}
		return e.JSON(http.StatusOK, map[string]any{
			"has_route": false,
			"revision":  session.GetInt("route_revision"),
		})
	}

	routeID, changed, err := liveRideResolveAttachedRoute(e, data.RouteClientID, data.Route)
	if err != nil {
		return err
	}
	if routeID == "" {
		return apis.NewBadRequestError("Provide route_client_id or a route payload", nil)
	}

	// Numer wersji rośnie tylko wtedy, gdy geometria naprawdę się zmieniła.
	//
	// Telefon ponawia doczepianie co tyknięcie licznika jako siatkę
	// bezpieczeństwa na nieudane pierwsze żądanie. Gdyby każde z nich
	// podbijało wersję, strona pobierałaby całą trasę co kilka sekund —
	// czyli dokładnie to, czego wersjonowanie ma unikać.
	if previousRoute != routeID || changed {
		session.Set("route", routeID)
		liveRideBumpRouteRevision(session)
		if err := e.App.Save(session); err != nil {
			return apis.NewBadRequestError("Failed to attach the route", err)
		}
		// Podmiana trasy w trakcie jazdy to zdarzenie, o którym widz ma
		// prawo wiedzieć: inaczej mapa po cichu zmienia kształt i wygląda
		// to jak błąd strony.
		if previousRoute != "" {
			liveRideAppendEvent(
				e.App, session, nil, "reroute", "",
				0, time.Now().UTC(),
			)
		}
	}

	return e.JSON(http.StatusOK, map[string]any{
		"has_route": true,
		"route_id":  routeID,
		"revision":  session.GetInt("route_revision"),
	})
}

// liveRideBumpRouteRevision podbija numer wersji trasy sesji.
func liveRideBumpRouteRevision(session *core.Record) {
	session.Set("route_revision", session.GetInt("route_revision")+1)
	session.Set("route_updated_at", time.Now().UTC())
}

// liveRideResolveAttachedRoute znajduje trasę albo ją zapisuje.
//
// Kolejność ma znaczenie: jeżeli telefon przysłał geometrię, zapisujemy ją,
// bo może być NOWSZA niż to, co leży na serwerze — dokładnie tak wygląda
// przeliczenie trasy w trakcie jazdy. Samo `client_id` to ścieżka dla trasy,
// która już tam jest i się nie zmieniła.
func liveRideResolveAttachedRoute(
	e *core.RequestEvent,
	clientID string,
	payload *liveRideAttachedRoute,
) (string, bool, error) {
	collection, err := e.App.FindCollectionByNameOrId("live_ride_routes")
	if err != nil {
		return "", false, apis.NewNotFoundError("Live Ride routes collection is missing", err)
	}

	if payload != nil && strings.TrimSpace(payload.Polyline) != "" {
		id := strings.TrimSpace(payload.ClientID)
		if id == "" {
			id = strings.TrimSpace(clientID)
		}
		if id == "" {
			// Trasa bez własnego identyfikatora nadal musi dać się zapisać:
			// zdarza się przy imporcie GPX, który nie ma żadnego id.
			id = "live_" + security.RandomString(16)
		}
		record, err := liveRideRouteByClientID(e, collection, e.Auth.Id, id)
		if err != nil {
			return "", false, err
		}
		changed := record == nil || record.GetString("polyline") != payload.Polyline
		if record == nil {
			record = core.NewRecord(collection)
			record.Set("owner", e.Auth.Id)
			record.Set("client_id", id)
			// Trasa doczepiona do publicznego LIVE jest widoczna spod tokenu
			// tej jazdy i tylko spod niego. Własnego linku nie dostaje —
			// udostępnienie trasy to osobna decyzja, której nikt tu nie podjął.
			record.Set("privacy", "private")
		}

		record.Set("name", strings.TrimSpace(payload.Name))
		record.Set("distance_m", payload.DistanceM)
		record.Set("ascent_m", payload.AscentM)
		record.Set("descent_m", payload.DescentM)
		record.Set("polyline", payload.Polyline)
		record.Set("elevation_profile", payload.ElevationProfile)
		record.Set("climbs", payload.Climbs)
		record.Set("surfaces", payload.Surfaces)
		record.Set("client_updated_at", time.Now().UTC())

		if err := e.App.Save(record); err != nil {
			return "", false, apis.NewBadRequestError("Failed to store the route", err)
		}
		return record.Id, changed, nil
	}

	if strings.TrimSpace(clientID) == "" {
		return "", false, nil
	}
	record, err := liveRideRouteByClientID(e, collection, e.Auth.Id, strings.TrimSpace(clientID))
	if err != nil {
		return "", false, err
	}
	if record == nil {
		return "", false, apis.NewNotFoundError("Route not found for this account", nil)
	}
	return record.Id, false, nil
}

// liveRideRouteByClientID szuka trasy TEGO właściciela.
//
// Filtrowanie po właścicielu nie jest ostrożnością na zapas: bez niego
// identyfikator z cudzego telefonu przypinałby cudzą trasę do własnego
// publicznego linku.
func liveRideRouteByClientID(
	e *core.RequestEvent,
	collection *core.Collection,
	ownerID string,
	clientID string,
) (*core.Record, error) {
	records, err := e.App.FindRecordsByFilter(
		collection.Name,
		"owner = {:owner} && client_id = {:client}",
		"",
		1,
		0,
		dbx.Params{"owner": ownerID, "client": clientID},
	)
	if err != nil {
		return nil, apis.NewBadRequestError("Failed to look up the route", err)
	}
	if len(records) == 0 {
		return nil, nil
	}
	return records[0], nil
}
