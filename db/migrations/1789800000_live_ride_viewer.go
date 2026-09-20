package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// Pola, bez których publiczna strona LIVE musiałaby zgadywać.
//
// Trzy braki, każdy widoczny na stronie jako kłamstwo albo jako kreska:
//
//   - `joined_at` — chwila, w której zawodnik dołączył do jazdy. Bez niej nie
//     da się odróżnić „dopiero wystartował, czekamy na pierwszy fiks" od
//     „jedzie od godziny i właśnie stracił zasięg". Dla obserwującego to
//     różnica między spokojem a telefonem z pytaniem, czy wszystko gra.
//
//   - `auto_paused_seconds` / `manual_paused_seconds` — licznik rozróżnia
//     postój od pauzy wciśniętej palcem, a strona pokazywała dotąd tylko
//     „w ruchu". Czas całkowity minus czas w ruchu to nie to samo co postoje:
//     w tej różnicy siedzą też sekundy poniżej progu auto-pauzy.
//
// Wartości domyślne to zera i puste daty, więc sesje sprzed tej migracji
// zachowują się dokładnie tak jak wcześniej — strona po prostu tych wierszy
// nie pokazuje, zamiast pokazywać w nich zero.
func init() {
	m.Register(func(app core.App) error {
		participants, err := app.FindCollectionByNameOrId("live_ride_participants")
		if err != nil {
			return err
		}
		for _, field := range liveRideViewerParticipantFields() {
			if participants.Fields.GetByName(field.GetName()) != nil {
				continue
			}
			participants.Fields.Add(field)
		}
		return app.Save(participants)
	}, func(app core.App) error {
		participants, err := app.FindCollectionByNameOrId("live_ride_participants")
		if err != nil {
			return err
		}
		for _, field := range liveRideViewerParticipantFields() {
			if existing := participants.Fields.GetByName(field.GetName()); existing != nil {
				participants.Fields.RemoveById(existing.GetId())
			}
		}
		return app.Save(participants)
	})
}

// liveRideViewerParticipantFields jest jednym źródłem prawdy dla migracji
// w obie strony — inaczej wycofanie zostawiłoby kolumnę, o której nikt już
// nie pamięta.
func liveRideViewerParticipantFields() []core.Field {
	return []core.Field{
		&core.DateField{Name: "joined_at"},
		&core.NumberField{Name: "auto_paused_seconds", OnlyInt: true},
		&core.NumberField{Name: "manual_paused_seconds", OnlyInt: true},
	}
}
