package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// Miejsce na insighty Ride Intelligence, które zawodnik zgodził się pokazać.
//
// Licznik zawodnika już je liczy: „za siedem kilometrów podjazd", „wrócisz po
// zmroku", „telefon 14%". Do tej pory nie miały gdzie usiąść, więc obserwujący
// widział surowe liczby i musiał sam się domyślać, co z nich wynika.
//
// Pole jest tylko magazynem. O tym, co z niego wychodzi na publiczną stronę,
// decyduje wyłącznie serwer — patrz liveRideSafeInsights w routes. Insighty
// dotyczące zdrowia (strefa tętna, rozjazd tętna i tempa, przypomnienia
// o jedzeniu) nie wyjdą stąd NIGDY, niezależnie od ustawień udostępniania.
func init() {
	m.Register(func(app core.App) error {
		participants, err := app.FindCollectionByNameOrId("live_ride_participants")
		if err != nil {
			return err
		}
		if participants.Fields.GetByName("insights") == nil {
			participants.Fields.Add(&core.JSONField{Name: "insights", MaxSize: 4000})
		}
		return app.Save(participants)
	}, func(app core.App) error {
		participants, err := app.FindCollectionByNameOrId("live_ride_participants")
		if err != nil {
			return err
		}
		if existing := participants.Fields.GetByName("insights"); existing != nil {
			participants.Fields.RemoveById(existing.GetId())
		}
		return app.Save(participants)
	})
}
