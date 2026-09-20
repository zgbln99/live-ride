package routes

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

// Atrapa bazy w testach musi mieć te same kolumny co migracja.
//
// Testowa aplikacja PocketBase startuje bez migracji, więc kolekcje buduje
// ręcznie `newLiveRideFixture`. To wygodne i szybkie, ale ma jedną wadę:
// pole dodane w migracji i zapomniane w atrapie daje ZIELONE testy na
// schemacie, którego nie ma na produkcji — a tam ten sam kod cicho zapisuje
// w próżnię, bo PocketBase ignoruje `Set` na nieistniejące pole.
//
// Ten test nie sprawdza zachowania. Sprawdza, czy obie listy mówią o tej
// samej bazie.

var liveRideFieldName = regexp.MustCompile(`Name:\s*"([a-z0-9_]+)"`)

func liveRideNamesIn(t *testing.T, path string) []string {
	t.Helper()
	source, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("nie udało się przeczytać %s: %v", path, err)
	}
	matches := liveRideFieldName.FindAllStringSubmatch(string(source), -1)
	names := make([]string, 0, len(matches))
	for _, match := range matches {
		names = append(names, match[1])
	}
	return names
}

func TestLiveRideFixtureMatchesMigrations(t *testing.T) {
	fixture, err := os.ReadFile("live_ride_public_test.go")
	if err != nil {
		t.Fatal(err)
	}
	source := string(fixture)

	migrations := []string{
		"../migrations/1789900000_live_ride_computer.go",
		"../migrations/1789910000_live_ride_events.go",
	}

	for _, migration := range migrations {
		names := liveRideNamesIn(t, migration)
		if len(names) < 10 {
			// Gdyby wyrażenie przestało pasować, test cicho przechodziłby na
			// pustej liście i niczego by nie pilnował.
			t.Fatalf("%s: znaleziono tylko %d pól", migration, len(names))
		}
		for _, name := range names {
			if !strings.Contains(source, `Name: "`+name+`"`) {
				t.Errorf(
					"pole %q z %s nie istnieje w atrapie bazy — test przejdzie, "+
						"a na produkcji zapis pójdzie w próżnię",
					name, migration,
				)
			}
		}
	}
}
