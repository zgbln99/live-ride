package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// Oś czasu przejazdu i wersjonowanie trasy.
//
// Dwie rzeczy, których publiczny LIVE nie umiał powiedzieć. Pierwsza: „co się
// wydarzyło". Migawka odpowiada tylko na pytanie „jak jest teraz", więc widz,
// który wszedł kwadrans później, nie wiedział, że zawodnik zjechał z trasy
// i wrócił. Druga: „czy geometria się zmieniła". Bez numeru wersji strona
// musiałaby pobierać całą trasę co kilka sekund, żeby to sprawdzić — albo,
// jak dotąd, nie sprawdzać tego wcale i pokazywać nieaktualny plan.
func init() {
	m.Register(func(app core.App) error {
		sessions, err := app.FindCollectionByNameOrId("live_ride_sessions")
		if err != nil {
			return err
		}
		for _, field := range liveRideSessionRouteFields() {
			if sessions.Fields.GetByName(field.GetName()) != nil {
				continue
			}
			sessions.Fields.Add(field)
		}
		if err := app.Save(sessions); err != nil {
			return err
		}

		participants, err := app.FindCollectionByNameOrId("live_ride_participants")
		if err != nil {
			return err
		}

		if _, err := app.FindCollectionByNameOrId("live_ride_events"); err == nil {
			return nil
		}

		events := core.NewBaseCollection("live_ride_events")
		events.Fields.Add(
			&core.RelationField{Name: "session", CollectionId: sessions.Id, MaxSelect: 1, Required: true},
			&core.RelationField{Name: "participant", CollectionId: participants.Id, MaxSelect: 1},
			&core.DateField{Name: "at", Required: true},
			// Zamknięta lista, żeby telefon nie mógł wpisać dowolnego tekstu,
			// który potem wyląduje na publicznej stronie.
			&core.SelectField{Name: "kind", MaxSelect: 1, Required: true, Values: []string{
				"start",
				"stop",
				"resume",
				"pause",
				"auto_pause",
				"climb_start",
				"climb_end",
				"off_route",
				"back_on_route",
				"reroute",
				"checkpoint",
				"finish",
				"sos",
			}},
			// Podpis zdarzenia: nazwa podjazdu, nazwa checkpointu. Nigdy
			// dowolne zdanie — kind decyduje, jak strona je nazwie.
			&core.TextField{Name: "label", Max: 120},
			&core.NumberField{Name: "distance_m"},
			&core.NumberField{Name: "value"},
			// Numer w obrębie sesji: kolejność zdarzeń nie może zależeć od
			// tego, które z dwóch o tej samej sekundzie zapisało się pierwsze.
			&core.NumberField{Name: "seq", OnlyInt: true},
		)
		events.Indexes = append(events.Indexes,
			"CREATE INDEX `idx_live_ride_events_session_at` ON `live_ride_events` (`session`, `at`)",
			"CREATE UNIQUE INDEX `idx_live_ride_events_session_seq` ON `live_ride_events` (`session`, `seq`)",
		)
		return app.Save(events)
	}, func(app core.App) error {
		if events, err := app.FindCollectionByNameOrId("live_ride_events"); err == nil {
			if err := app.Delete(events); err != nil {
				return err
			}
		}
		sessions, err := app.FindCollectionByNameOrId("live_ride_sessions")
		if err != nil {
			return err
		}
		for _, field := range liveRideSessionRouteFields() {
			if existing := sessions.Fields.GetByName(field.GetName()); existing != nil {
				sessions.Fields.RemoveById(existing.GetId())
			}
		}
		return app.Save(sessions)
	})
}

// liveRideSessionRouteFields — jedno źródło prawdy dla migracji w obie strony.
func liveRideSessionRouteFields() []core.Field {
	return []core.Field{
		// Rośnie o jeden przy każdej podmianie geometrii. Widz porównuje
		// liczbę, a nie kilometr polilinii.
		&core.NumberField{Name: "route_revision", OnlyInt: true},
		&core.DateField{Name: "route_updated_at"},
		// Najwyższy dotąd przyznany numer zdarzenia w tej sesji.
		&core.NumberField{Name: "event_seq", OnlyInt: true},
	}
}
