package routes

import (
	"testing"

	"github.com/pocketbase/pocketbase/core"
)

// Insighty są najniebezpieczniejszą rzeczą, jaką publikuje LIVE.
//
// Surowe pole to liczba: „148". Insight to zdanie, które tę liczbę tłumaczy
// — a zdania o ciele („tętno trzyma się wyżej przy tym samym tempie")
// zostają na telefonie niezależnie od tego, co zawodnik pozaznaczał.
// Każdy test poniżej pilnuje dokładnie jednej granicy.

func insightsOf(rider map[string]any) []any {
	raw, ok := rider["insights"].([]any)
	if !ok {
		return nil
	}
	return raw
}

func insightKinds(rider map[string]any) []string {
	out := []string{}
	for _, entry := range insightsOf(rider) {
		item, ok := entry.(map[string]any)
		if !ok {
			continue
		}
		if kind, ok := item["kind"].(string); ok {
			out = append(out, kind)
		}
	}
	return out
}

func hasKind(kinds []string, want string) bool {
	for _, kind := range kinds {
		if kind == want {
			return true
		}
	}
	return false
}

func TestLiveRideInsightsDropMedicalOnWrite(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 3, nil)

	liveRideApplyInsights(rider, []liveRideInsightPayload{
		{Kind: "zone", Title: "STREFA 4", Body: "Próg, 171 bpm"},
		{Kind: "effort", Title: "WYSIŁEK", Body: "Tętno trzyma się wyżej (12%)."},
		{Kind: "fuel", Title: "JEDZENIE", Body: "Pora coś zjeść."},
		{Kind: "climb", Title: "PODJAZD", Body: "Za 3,2 km podjazd."},
	})

	var stored []liveRideInsightPayload
	if err := rider.UnmarshalJSONField("insights", &stored); err != nil {
		t.Fatal(err)
	}
	// Nie tylko „nie wyszło" — nie zostało nawet ZAPISANE. Czego nie ma
	// w bazie, tego nie wycieknie żaden przyszły endpoint.
	if len(stored) != 1 || stored[0].Kind != "climb" {
		t.Fatalf("zapisano %+v, oczekiwano tylko podjazdu", stored)
	}
}

func TestLiveRideInsightsDropUnknownKinds(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 3, nil)

	liveRideApplyInsights(rider, []liveRideInsightPayload{
		{Kind: "medical_diagnosis", Body: "cokolwiek"},
		{Kind: "", Body: "bez rodzaju"},
		{Kind: "weather", Body: ""},
	})

	var stored []liveRideInsightPayload
	if err := rider.UnmarshalJSONField("insights", &stored); err != nil {
		t.Fatal(err)
	}
	if len(stored) != 0 {
		t.Fatalf("zapisano %+v, oczekiwano pustej listy", stored)
	}
}

func TestLiveRideInsightsRespectShareSwitches(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 3, func(r *core.Record) {
		r.Set("share_position", false)
		r.Set("share_speed", true)
		r.Set("share_power", false)
	})
	liveRideApplyInsights(rider, []liveRideInsightPayload{
		{Kind: "climb", Body: "Za 3,2 km podjazd."},
		{Kind: "eta", Body: "Meta około 15:40."},
		{Kind: "pace", Body: "Jedziesz 8 min szybciej niż zwykle."},
		{Kind: "power", Body: "225 W znorm., IF 0.90."},
		{Kind: "weather", Body: "Deszcz prawdopodobny (70%)."},
	})
	if err := f.app.Save(rider); err != nil {
		t.Fatal(err)
	}

	_, body, _ := f.snapshot(t, f.session.GetString("share_token"))
	kinds := insightKinds(riders(body)[0])

	// Insight o podjeździe to informacja o POZYCJI wyrażona zdaniem.
	// Wyłączona pozycja musi go zdjąć razem ze współrzędnymi.
	for _, forbidden := range []string{"climb", "eta", "power"} {
		if hasKind(kinds, forbidden) {
			t.Errorf("insight %q wyszedł mimo wyłączonego przełącznika: %v", forbidden, kinds)
		}
	}
	for _, expected := range []string{"pace", "weather"} {
		if !hasKind(kinds, expected) {
			t.Errorf("insight %q powinien wyjść: %v", expected, kinds)
		}
	}
}

func TestLiveRideInsightsPassWhenShared(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 3, func(r *core.Record) {
		r.Set("share_position", true)
		r.Set("share_power", true)
		r.Set("share_battery", true)
	})
	liveRideApplyInsights(rider, []liveRideInsightPayload{
		{Kind: "climb", Title: "PODJAZD", Body: "Za 3,2 km podjazd.", Priority: "notable"},
		{Kind: "battery", Title: "BATERIA", Body: "Telefon 14%."},
	})
	if err := f.app.Save(rider); err != nil {
		t.Fatal(err)
	}

	_, body, _ := f.snapshot(t, f.session.GetString("share_token"))
	entries := insightsOf(riders(body)[0])
	if len(entries) != 2 {
		t.Fatalf("wyszło %d insightów, oczekiwano 2: %v", len(entries), entries)
	}
	first, _ := entries[0].(map[string]any)
	// Zdanie idzie GOTOWE, dokładnie tak, jak przeczytał je zawodnik.
	if first["body"] != "Za 3,2 km podjazd." {
		t.Errorf("body = %v", first["body"])
	}
	if first["title"] != "PODJAZD" || first["priority"] != "notable" {
		t.Errorf("title/priority = %v / %v", first["title"], first["priority"])
	}
}

func TestLiveRideInsightsAreCapped(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 3, nil)

	many := make([]liveRideInsightPayload, 0, 20)
	for i := 0; i < 20; i++ {
		many = append(many, liveRideInsightPayload{Kind: "weather", Body: "x"})
	}
	liveRideApplyInsights(rider, many)

	var stored []liveRideInsightPayload
	if err := rider.UnmarshalJSONField("insights", &stored); err != nil {
		t.Fatal(err)
	}
	if len(stored) != liveRideMaxInsights {
		t.Fatalf("zapisano %d, oczekiwano %d", len(stored), liveRideMaxInsights)
	}
}

func TestLiveRideInsightsClearedWhenEmpty(t *testing.T) {
	f := newLiveRideFixture(t)
	rider := f.addRider(t, "Marek", 3, func(r *core.Record) {
		r.Set("share_position", true)
	})
	liveRideApplyInsights(rider, []liveRideInsightPayload{
		{Kind: "climb", Body: "Za 3,2 km podjazd."},
	})
	// Skończony podjazd musi zdjąć zdanie o podjeździe. Inaczej widz zostaje
	// z komunikatem sprzed godziny.
	liveRideApplyInsights(rider, nil)
	if err := f.app.Save(rider); err != nil {
		t.Fatal(err)
	}

	_, body, _ := f.snapshot(t, f.session.GetString("share_token"))
	if entries := insightsOf(riders(body)[0]); len(entries) != 0 {
		t.Fatalf("insighty zostały po wyczyszczeniu: %v", entries)
	}
}
