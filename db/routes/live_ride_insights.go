package routes

import (
	"strings"

	"github.com/pocketbase/pocketbase/core"
)

// liveRideInsightPayload to jedna rzecz, którą licznik powiedział zawodnikowi.
//
// Zdanie przychodzi GOTOWE i po polsku, dokładnie tak jak instrukcja
// nawigacji: obserwujący ma przeczytać to samo, co rowerzysta ma przed
// oczami, a nie jego tłumaczenie z angielskiego.
type liveRideInsightPayload struct {
	Kind     string `json:"kind"`
	Title    string `json:"title"`
	Body     string `json:"body"`
	Priority string `json:"priority"`
}

// Ile insightów w ogóle bierzemy pod uwagę.
//
// Panel widza mieści trzy. Przyjmowanie stu byłoby zaproszeniem do wpisania
// powieści w pole JSON i utrzymywania jej w każdej odpowiedzi.
const liveRideMaxInsights = 6

// liveRideMedicalInsightKinds NIGDY nie opuszczają telefonu na publiczną
// stronę — ani przy włączonym udostępnianiu tętna, ani przy żadnym innym
// ustawieniu.
//
// Strefa tętna, rozjazd tętna i tempa oraz przypomnienia o jedzeniu i piciu
// mówią o CIELE zawodnika, a nie o jeździe. Obserwujący nie ma powodu
// wiedzieć, że komuś rośnie tętno przy tym samym tempie, i nie da się takiej
// informacji cofnąć po tym, jak raz wyjdzie na publiczny link.
var liveRideMedicalInsightKinds = map[string]bool{
	"zone":   true,
	"effort": true,
	"fuel":   true,
}

// liveRideInsightGate mówi, które ustawienie udostępniania otwiera który
// rodzaj insightu. Pusty ciąg znaczy „bezpieczny bez warunków".
//
// Reguła jest ta sama co przy surowych polach: insight o podjeździe jest
// informacją o POZYCJI, tyle że zdaniem zamiast liczbą, więc dzieli
// ustawienie z pozycją. Inaczej wyłączenie pozycji chowałoby współrzędne,
// a zdanie „za 7 km podjazd na Przełęcz Sokolą" zostawiało na stronie.
var liveRideInsightGate = map[string]string{
	"climb":   "share_position",
	"eta":     "share_position",
	"plan":    "share_position",
	"gps":     "share_position",
	"pace":    "share_speed",
	"power":   "share_power",
	"battery": "share_battery",
	"weather": "",
	"wind":    "",
}

// liveRideApplyInsights zapisuje insighty albo je czyści.
//
// Czyszczenie jest tak samo ważne jak zapis: skończony podjazd musi zdjąć
// zdanie o podjeździe, inaczej widz zostaje z komunikatem sprzed godziny.
func liveRideApplyInsights(
	participant *core.Record,
	insights []liveRideInsightPayload,
) {
	clean := make([]liveRideInsightPayload, 0, liveRideMaxInsights)
	for _, insight := range insights {
		if len(clean) >= liveRideMaxInsights {
			break
		}
		kind := strings.TrimSpace(strings.ToLower(insight.Kind))
		body := strings.TrimSpace(insight.Body)
		if kind == "" || body == "" {
			continue
		}
		// Insight medyczny odrzucamy już przy zapisie, a nie dopiero przy
		// odczycie. Czego nie ma w bazie, tego nie wycieknie żaden przyszły
		// endpoint, o którym dziś nie wiemy.
		if liveRideMedicalInsightKinds[kind] {
			continue
		}
		if _, known := liveRideInsightGate[kind]; !known {
			continue
		}
		clean = append(clean, liveRideInsightPayload{
			Kind:     kind,
			Title:    strings.TrimSpace(insight.Title),
			Body:     body,
			Priority: strings.TrimSpace(strings.ToLower(insight.Priority)),
		})
	}
	participant.Set("insights", clean)
}

// liveRideSafeInsights wybiera to, co wolno pokazać obserwującym.
//
// Filtr jest TUTAJ, a nie w JavaScripcie na stronie: strona dostaje wyłącznie
// to, co przeszło przez ten kod, więc wyłączony przełącznik znaczy „dane nie
// wyszły z serwera", a nie „strona ich nie narysowała".
func liveRideSafeInsights(participant *core.Record) []map[string]any {
	var stored []liveRideInsightPayload
	if err := participant.UnmarshalJSONField("insights", &stored); err != nil {
		return nil
	}

	out := make([]map[string]any, 0, len(stored))
	for _, insight := range stored {
		if liveRideMedicalInsightKinds[insight.Kind] {
			continue
		}
		gate, known := liveRideInsightGate[insight.Kind]
		if !known {
			continue
		}
		if gate != "" && !liveRideShares(participant, gate) {
			continue
		}
		entry := map[string]any{"kind": insight.Kind, "body": insight.Body}
		if insight.Title != "" {
			entry["title"] = insight.Title
		}
		if insight.Priority != "" {
			entry["priority"] = insight.Priority
		}
		out = append(out, entry)
	}
	if len(out) == 0 {
		return nil
	}
	return out
}
