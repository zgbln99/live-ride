package permissions_test

import (
	"testing"

	"github.com/pocketbase/pocketbase/core"
)

// Migracje Live Ride muszą dać się zastosować od zera.
//
// Ten test istnieje z konkretnego powodu. Migracja synchronizacji dodawała
// samoodniesienie `live_ride_routes.copied_from` z pustym `CollectionId`
// i dopiero po zapisie próbowała je uzupełnić. Walidacja odrzucała już
// pierwszy zapis, więc migracja przerywała się w połowie i NIE POWSTAWAŁA
// żadna z kolekcji: ani przejazdy, ani trasy, ani segmenty.
//
// Na serwerze wyglądało to tak, jakby endpointy synchronizacji nie
// istniały — każdy zwracał 404, mimo że kod HTTP był poprawny i wdrożony.
// Błąd był widoczny wyłącznie w logu startu, którego nikt nie czyta, gdy
// aplikacja „prawie działa".
func TestLiveRideMigrationsApplyFromScratch(t *testing.T) {
	// newRulesTestApp stosuje WSZYSTKIE migracje schematu — jeżeli
	// którakolwiek się wywali, test kończy się tutaj, z nazwą pliku.
	app := newRulesTestApp(t)

	// Każda kolekcja, bez której jakaś trasa HTTP Live Ride odpowie 404.
	for _, name := range []string{
		"live_ride_sessions",
		"live_ride_participants",
		"live_ride_points",
		"live_ride_messages",
		"live_ride_rides",
		"live_ride_routes",
		"live_ride_segments",
		"live_ride_segment_attempts",
	} {
		if _, err := app.FindCollectionByNameOrId(name); err != nil {
			t.Errorf("brak kolekcji %s po migracjach: %v", name, err)
		}
	}
}

// Pola, na których opiera się publiczna strona LIVE i synchronizacja.
//
// Brakujące pole nie wysypuje serwera — cicho zwraca zero albo pustą
// wartość, więc strona pokazuje „0 km" zamiast prawdy. Dlatego sprawdzamy je
// z nazwy, a nie ufamy, że migracja „na pewno przeszła".
func TestLiveRideCollectionsCarryPublicFields(t *testing.T) {
	// newRulesTestApp stosuje WSZYSTKIE migracje schematu — jeżeli
	// którakolwiek się wywali, test kończy się tutaj, z nazwą pliku.
	app := newRulesTestApp(t)

	expected := map[string][]string{
		"live_ride_sessions": {
			"share_token", "join_token", "status", "visibility",
			"expire_on_end", "expires_at", "summary", "route", "trail",
			"meetup_lat", "meetup_lon", "meetup_label",
		},
		"live_ride_participants": {
			"display_name", "latitude", "longitude", "speed_kmh",
			"heart_rate_bpm", "power_watts", "cadence_rpm", "battery_percent",
			"state", "moving_seconds", "max_speed_kmh", "last_seen_at",
			"share_position", "share_speed", "share_heart_rate", "share_power",
			"share_battery",
		},
		// Moc i kadencja szły w telemetrii, ale bez tych pól znikały z historii.
		"live_ride_points": {
			"recorded_at", "latitude", "longitude", "speed_kmh",
			"heart_rate_bpm", "power_watts", "cadence_rpm",
		},
		"live_ride_routes": {
			"client_id", "polyline", "privacy", "share_token",
			"elevation_profile", "climbs", "surfaces", "copied_from",
		},
		"live_ride_rides":    {"client_id", "track_polyline", "privacy", "share_token"},
		"live_ride_segments": {"client_id", "polyline", "privacy", "share_token"},
	}

	for name, fields := range expected {
		collection, err := app.FindCollectionByNameOrId(name)
		if err != nil {
			t.Errorf("brak kolekcji %s: %v", name, err)
			continue
		}
		for _, field := range fields {
			if collection.Fields.GetByName(field) == nil {
				t.Errorf("kolekcja %s nie ma pola %q", name, field)
			}
		}
	}

	// Samoodniesienie musi faktycznie wskazywać na własną kolekcję, a nie
	// zostać zapisane jako puste.
	routes, err := app.FindCollectionByNameOrId("live_ride_routes")
	if err != nil {
		t.Fatal(err)
	}
	relation, ok := routes.Fields.GetByName("copied_from").(*core.RelationField)
	if !ok {
		t.Fatal("copied_from nie jest relacją")
	}
	if relation.CollectionId != routes.Id {
		t.Errorf("copied_from wskazuje na %q, a powinien na %q", relation.CollectionId, routes.Id)
	}
}

// Kolekcje Live Ride nie mają mieć reguł API.
//
// Dostęp idzie wyłącznie przez własne trasy HTTP, które sprawdzają albo
// zalogowanego właściciela, albo nieodgadywalny token. Otwarta reguła
// zrobiłaby z pozycji na żywo listę do przewijania w generycznym API
// PocketBase.
func TestLiveRideCollectionsHaveNoApiRules(t *testing.T) {
	// newRulesTestApp stosuje WSZYSTKIE migracje schematu — jeżeli
	// którakolwiek się wywali, test kończy się tutaj, z nazwą pliku.
	app := newRulesTestApp(t)

	for _, name := range []string{
		"live_ride_sessions",
		"live_ride_participants",
		"live_ride_points",
		"live_ride_messages",
		"live_ride_rides",
		"live_ride_routes",
		"live_ride_segments",
		"live_ride_segment_attempts",
	} {
		collection, err := app.FindCollectionByNameOrId(name)
		if err != nil {
			t.Errorf("brak kolekcji %s: %v", name, err)
			continue
		}
		for label, rule := range map[string]*string{
			"list":   collection.ListRule,
			"view":   collection.ViewRule,
			"create": collection.CreateRule,
			"update": collection.UpdateRule,
			"delete": collection.DeleteRule,
		} {
			if rule != nil {
				t.Errorf("kolekcja %s ma otwartą regułę %s: %q", name, label, *rule)
			}
		}
	}
}

// Konto rowerzysty musi mieć nazwę wyświetlaną i przyjmować e-mail
// oraz nazwę użytkownika jako login.
//
// Aplikacja czyta `record.name` z odpowiedzi logowania i pokazuje tę nazwę
// znajomym na publicznej stronie LIVE. Bez pola nie ma nazwy, a rowerzysta
// oglądałby siebie jako pusty napis obok własnej pozycji.
//
// Logowanie z dwóch pól nie jest kodem — to konfiguracja kolekcji. Gdyby
// ktoś przyciął `identityFields` do samego e-maila, ekran logowania nadal
// przyjmowałby nazwę użytkownika i po prostu odbijałby ją jako złe hasło.
func TestUsersCollectionSupportsAccountScreen(t *testing.T) {
	app := newRulesTestApp(t)

	users, err := app.FindCollectionByNameOrId("users")
	if err != nil {
		t.Fatalf("brak kolekcji users: %v", err)
	}

	if users.Fields.GetByName("name") == nil {
		t.Error("kolekcja users nie ma pola \"name\" (nazwa wyświetlana)")
	}

	identity := map[string]bool{}
	for _, field := range users.PasswordAuth.IdentityFields {
		identity[field] = true
	}
	for _, field := range []string{"email", "username"} {
		if !identity[field] {
			t.Errorf("logowanie nie przyjmuje pola %q jako tożsamości", field)
		}
	}
}
