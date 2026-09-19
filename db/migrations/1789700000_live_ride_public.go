package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// Publiczna strona LIVE dla znajomych.
//
// Poprzednie migracje dały sesję, uczestników i punkty. Tu dochodzi to, bez
// czego publiczny link nie jest produktem, tylko podglądem debugowym:
//
//   - widoczność linku (publiczny / z linku / wyłączony) i jego wygasanie,
//   - stan zawodnika (jedzie / postój / pauza) — inaczej „stoi na światłach"
//     i „zgubił zasięg" wyglądają na stronie identycznie,
//   - podsumowanie zapisane w chwili zakończenia, żeby strona po jeździe nie
//     musiała przeliczać historii przy każdym wejściu,
//   - trasa z biblioteki Live Ride jako plan przejazdu (kolekcja `trails`
//     należy do starego Wanderera i trzyma polilinie w innej precyzji).
//
// Reguły API kolekcji zostają puste, tak jak wcześniej: wszystko idzie przez
// własne trasy HTTP, które sprawdzają token albo zalogowanego właściciela.
func init() {
	m.Register(func(app core.App) error {
		sessions, err := app.FindCollectionByNameOrId("live_ride_sessions")
		if err != nil {
			return err
		}
		routes, err := app.FindCollectionByNameOrId("live_ride_routes")
		if err != nil {
			return err
		}

		sessions.Fields.Add(
			// Puste = „unlisted", czyli stan sesji założonych przed tą
			// migracją: link działa, ale nigdzie go nie ogłaszamy.
			&core.SelectField{
				Name:      "visibility",
				Values:    []string{"public", "unlisted", "disabled"},
				MaxSelect: 1,
			},
			// Link ma przestać działać w chwili zakończenia jazdy.
			&core.BoolField{Name: "expire_on_end"},
			// Migawka policzona raz, przy zakończeniu.
			&core.JSONField{Name: "summary", MaxSize: 20000},
			// Plan przejazdu z biblioteki tras Live Ride.
			&core.RelationField{Name: "route", CollectionId: routes.Id, MaxSelect: 1},
		)
		if err := app.Save(sessions); err != nil {
			return err
		}

		participants, err := app.FindCollectionByNameOrId("live_ride_participants")
		if err != nil {
			return err
		}
		participants.Fields.Add(
			// Puste = „riding": tak zachowywały się sesje sprzed tej zmiany.
			&core.SelectField{
				Name:      "state",
				Values:    []string{"riding", "paused", "stopped"},
				MaxSelect: 1,
			},
			&core.NumberField{Name: "moving_seconds", OnlyInt: true},
			&core.NumberField{Name: "max_speed_kmh"},
			&core.BoolField{Name: "share_battery"},
			// Ostatni punkt, który poszedł do publicznego śladu. Widz dostaje
			// przyrosty po znaczniku czasu, a nie całą historię co 3 sekundy.
			&core.DateField{Name: "track_synced_at"},
		)
		if err := app.Save(participants); err != nil {
			return err
		}

		// Profil wysokości i podjazdy liczy telefon przy budowie trasy.
		// Serwer ich nie przelicza — przyjmuje gotowe, bo inaczej publiczna
		// strona trasy musiałaby pytać o wysokości usługę zewnętrzną przy
		// każdym wejściu, a offline i tak nie ma jak.
		routes.Fields.Add(
			&core.JSONField{Name: "elevation_profile", MaxSize: 100000},
			&core.JSONField{Name: "climbs", MaxSize: 40000},
			&core.JSONField{Name: "surfaces", MaxSize: 8000},
		)
		if err := app.Save(routes); err != nil {
			return err
		}

		// Moc i kadencja szły w telemetrii, ale nie miały gdzie wylądować:
		// zapisywał je tylko bieżący stan uczestnika, więc znikały z historii.
		points, err := app.FindCollectionByNameOrId("live_ride_points")
		if err != nil {
			return err
		}
		points.Fields.Add(
			&core.NumberField{Name: "power_watts", OnlyInt: true},
			&core.NumberField{Name: "cadence_rpm", OnlyInt: true},
		)
		return app.Save(points)
	}, func(app core.App) error {
		for _, spec := range []struct {
			collection string
			fields     []string
		}{
			{"live_ride_sessions", []string{"visibility", "expire_on_end", "summary", "route"}},
			{"live_ride_participants", []string{
				"state", "moving_seconds", "max_speed_kmh", "share_battery", "track_synced_at",
			}},
			{"live_ride_routes", []string{"elevation_profile", "climbs", "surfaces"}},
			{"live_ride_points", []string{"power_watts", "cadence_rpm"}},
		} {
			collection, err := app.FindCollectionByNameOrId(spec.collection)
			if err != nil {
				continue
			}
			for _, field := range spec.fields {
				collection.Fields.RemoveByName(field)
			}
			if err := app.Save(collection); err != nil {
				return err
			}
		}
		return nil
	})
}
