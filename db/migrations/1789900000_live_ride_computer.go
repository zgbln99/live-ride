package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// Pola, przez których brak publiczny LIVE był trackerem GPS, a nie
// odzwierciedleniem licznika.
//
// Zawodnik widzi na kierownicy nawigację, aktualny podjazd i nachylenie.
// Obserwujący widział dystans i prędkość, bo tylko tyle mieściło się
// w wierszu uczestnika. Nie było żadnego błędu do znalezienia — po prostu
// nie istniała kolumna, w której te dane mogłyby usiąść.
//
// Wszystko jest opcjonalne i domyślnie puste, więc sesje sprzed tej migracji
// zachowują się dokładnie tak jak wcześniej: strona po prostu nie pokazuje
// sekcji, dla których nie ma danych.
func init() {
	m.Register(func(app core.App) error {
		participants, err := app.FindCollectionByNameOrId("live_ride_participants")
		if err != nil {
			return err
		}
		for _, field := range liveRideComputerFields() {
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
		for _, field := range liveRideComputerFields() {
			if existing := participants.Fields.GetByName(field.GetName()); existing != nil {
				participants.Fields.RemoveById(existing.GetId())
			}
		}
		return app.Save(participants)
	})
}

// liveRideComputerFields — jedno źródło prawdy dla migracji w obie strony.
func liveRideComputerFields() []core.Field {
	return []core.Field{
		// Czas zegarowy od startu. Nie da się go policzyć z `started_at`
		// sesji, gdy zawodnik dołączył do grupy później.
		&core.NumberField{Name: "elapsed_seconds", OnlyInt: true},

		// Nachylenie w miejscu, w którym zawodnik właśnie jest.
		&core.NumberField{Name: "gradient_percent"},

		// --- stan nawigacji ---------------------------------------------
		//
		// Instrukcja przychodzi GOTOWA i po polsku. Strona jej nie składa
		// i nie tłumaczy: obserwujący ma przeczytać dokładnie to zdanie,
		// które zawodnik ma przed oczami.
		&core.TextField{Name: "nav_instruction", Max: 200},
		&core.TextField{Name: "nav_street", Max: 160},
		&core.NumberField{Name: "nav_maneuver_type", OnlyInt: true},
		&core.NumberField{Name: "nav_distance_m"},
		&core.NumberField{Name: "nav_remaining_m"},
		&core.NumberField{Name: "nav_eta_seconds", OnlyInt: true},
		&core.BoolField{Name: "nav_off_route"},
		&core.NumberField{Name: "nav_off_route_m"},

		// --- aktualny podjazd -------------------------------------------
		//
		// Liczy go telefon, tym samym kodem, który rysuje ClimbPro. Serwer
		// nie ma jak go odtworzyć z samej pozycji, a strona tym bardziej:
		// wymagałoby to przeliczania profilu wysokości przy każdym wejściu.
		&core.NumberField{Name: "climb_index", OnlyInt: true},
		&core.NumberField{Name: "climb_total", OnlyInt: true},
		&core.NumberField{Name: "climb_done_m"},
		&core.NumberField{Name: "climb_length_m"},
		&core.NumberField{Name: "climb_gain_m"},
		&core.NumberField{Name: "climb_remaining_gain_m"},
		&core.NumberField{Name: "climb_avg_gradient"},
		&core.NumberField{Name: "climb_max_gradient"},
		&core.TextField{Name: "climb_category", Max: 16},

		// --- kolejność próbek -------------------------------------------
		//
		// Telemetria jedzie po LTE, gdzie pakiety potrafią się wyprzedzić.
		// Bez numeru starsza próbka nadpisuje nowszą i publiczna strona
		// cofa zawodnika o dwa kilometry, żeby za chwilę go przywrócić.
		&core.NumberField{Name: "telemetry_seq", OnlyInt: true},

		// --- pomiary z czujników zamiast z GPS ---------------------------
		&core.NumberField{Name: "sensor_speed_kmh"},
		&core.NumberField{Name: "sensor_distance_m"},

		// --- skąd pochodzi dana ------------------------------------------
		//
		// „HR 143" znaczy co innego z opaski WHOOP, a co innego z zegarka
		// liczonego z ruchu nadgarstka. Diagnostyka właściciela pokazuje
		// źródło; publiczna strona używa go tylko jako podpisu.
		&core.TextField{Name: "hr_source", Max: 40},
		&core.TextField{Name: "power_source", Max: 40},
		&core.TextField{Name: "cadence_source", Max: 40},
		&core.TextField{Name: "speed_source", Max: 40},

		// --- świeżość każdej danej z osobna ------------------------------
		//
		// Jeden `last_seen_at` na całego zawodnika kłamał: pas HR potrafi
		// odpaść, gdy GPS nadaje co sekundę, a strona dalej pokazywała
		// tętno sprzed czterech minut jako bieżące.
		&core.DateField{Name: "gps_updated_at"},
		&core.DateField{Name: "hr_updated_at"},
		&core.DateField{Name: "power_updated_at"},
		&core.DateField{Name: "cadence_updated_at"},
		&core.DateField{Name: "nav_updated_at"},

		// --- średnie i maksima z jazdy -----------------------------------
		&core.NumberField{Name: "avg_heart_rate_bpm", OnlyInt: true},
		&core.NumberField{Name: "max_heart_rate_bpm", OnlyInt: true},
		&core.NumberField{Name: "avg_power_watts", OnlyInt: true},
		&core.NumberField{Name: "max_power_watts", OnlyInt: true},
		&core.NumberField{Name: "avg_cadence_rpm", OnlyInt: true},

		// --- baterie ------------------------------------------------------
		//
		// Nie jedna. Telefon na 61% i pas HR na 4% to dwie różne wiadomości,
		// a druga tłumaczy, dlaczego za kwadrans zniknie tętno.
		&core.NumberField{Name: "hr_battery_percent", OnlyInt: true},
		&core.NumberField{Name: "power_battery_percent", OnlyInt: true},
		&core.NumberField{Name: "cadence_battery_percent", OnlyInt: true},
		&core.NumberField{Name: "speed_battery_percent", OnlyInt: true},

		// --- prywatność lokalizacji --------------------------------------
		//
		// Filtry, których nie wolno zostawić przeglądarce: pierwsza osoba,
		// która otworzy narzędzia deweloperskie, i tak zobaczyłaby to, co
		// serwer wysłał. Wysyłamy więc mniej.
		&core.NumberField{Name: "location_delay_seconds", OnlyInt: true},
		&core.BoolField{Name: "location_coarse"},
		&core.NumberField{Name: "hide_start_m", OnlyInt: true},
		&core.NumberField{Name: "hide_finish_m", OnlyInt: true},

		// Pierwszy fiks zawodnika — punkt odniesienia dla ukrytego startu.
		// Nigdy nie opuszcza serwera.
		&core.NumberField{Name: "start_lat"},
		&core.NumberField{Name: "start_lon"},
	}
}
