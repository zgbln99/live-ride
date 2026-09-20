package routes

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"

	"github.com/pocketbase/pocketbase/core"
)

// Strumień zdarzeń publicznej strony LIVE.
//
// Odpytywanie co trzy sekundy znaczy, że widz dowiaduje się o skręcie średnio
// półtorej sekundy po tym, jak zawodnik go zrobił — a przy zakładce w tle po
// trzydziestu. Dla dystansu to bez znaczenia, dla manewru i dla „zjechał
// z trasy" to różnica między oglądaniem jazdy a oglądaniem jej nagrania.
//
// Nie ma tu kolejki wiadomości ani brokera. Jest sygnał „ta sesja się
// zmieniła" i przebudowanie migawki w chwili wysyłki, czyli dokładnie ta sama
// zasada, na której stoi Live Activity: LATEST STATE WINS. Widz, którego
// łącze nie nadąża, nie dostaje pięćdziesięciu zaległych stanów — dostaje
// jeden, aktualny.
//
// Polling zostaje jako zapas. Przeglądarka bez EventSource, proxy ucinające
// długie połączenia albo firma z filtrem HTTP nadal widzą wszystko, tylko
// wolniej.

// Ile najwyżej wysyłek na sekundę robimy jednemu widzowi.
//
// Telemetria potrafi przyjść dziesięć razy w ciągu sekundy przy nadrabianiu
// zaległości z tunelu. Widz i tak zobaczy tylko ostatnią.
const liveRideStreamMinInterval = 700 * time.Millisecond

// Co ile wysyłamy komentarz podtrzymujący połączenie.
const liveRideStreamHeartbeat = 20 * time.Second

// Po tym czasie zamykamy strumień i liczymy na to, że przeglądarka wróci.
//
// EventSource wznawia połączenie sama. Zamykanie go co pół godziny pilnuje,
// żeby zapomniana zakładka nie trzymała gniazda przez całą noc.
const liveRideStreamMaxAge = 30 * time.Minute

// liveRideBroker rozsyła sygnały „ta sesja się zmieniła".
type liveRideBroker struct {
	mutex       sync.Mutex
	subscribers map[string]map[chan struct{}]struct{}
}

var liveRideChanges = &liveRideBroker{
	subscribers: make(map[string]map[chan struct{}]struct{}),
}

func (b *liveRideBroker) subscribe(sessionID string) chan struct{} {
	// Bufor jeden: sygnał znaczy „sprawdź stan", a nie „oto zmiana".
	// Dwa sygnały w tej samej chwili to nadal jedno sprawdzenie.
	channel := make(chan struct{}, 1)
	b.mutex.Lock()
	defer b.mutex.Unlock()
	if b.subscribers[sessionID] == nil {
		b.subscribers[sessionID] = make(map[chan struct{}]struct{})
	}
	b.subscribers[sessionID][channel] = struct{}{}
	return channel
}

func (b *liveRideBroker) unsubscribe(sessionID string, channel chan struct{}) {
	b.mutex.Lock()
	defer b.mutex.Unlock()
	if channels, ok := b.subscribers[sessionID]; ok {
		delete(channels, channel)
		if len(channels) == 0 {
			delete(b.subscribers, sessionID)
		}
	}
}

func (b *liveRideBroker) publish(sessionID string) {
	if sessionID == "" {
		return
	}
	b.mutex.Lock()
	defer b.mutex.Unlock()
	for channel := range b.subscribers[sessionID] {
		// Nieblokująco: wolny widz nie ma prawa zatrzymać zapisu telemetrii.
		select {
		case channel <- struct{}{}:
		default:
		}
	}
}

// LiveRideNotifySession budzi widzów tej sesji.
//
// Wołane z haków zapisu w main.go. Czysto powiadamiające — nie czyta bazy
// i nie może się nie udać, więc zapis telemetrii nigdy nie przewróci się
// przez to, że ktoś ogląda.
func LiveRideNotifySession(sessionID string) {
	liveRideChanges.publish(sessionID)
}

// LiveRideViewers mówi, ilu widzów ma teraz otwarty strumień tej sesji.
//
// Do diagnostyki właściciela. Liczymy POŁĄCZENIA, nie ludzi: żaden odcisk
// przeglądarki, cookie ani adres nigdzie nie trafia.
func LiveRideViewers(sessionID string) int {
	liveRideChanges.mutex.Lock()
	defer liveRideChanges.mutex.Unlock()
	return len(liveRideChanges.subscribers[sessionID])
}

// LiveRidePublicStream nadaje migawki przez Server-Sent Events.
func LiveRidePublicStream(e *core.RequestEvent) error {
	access, err := liveRideResolveShare(e)
	if err != nil {
		return err
	}
	session := access.session
	sessionID := session.Id

	flusher, ok := e.Response.(http.Flusher)
	if !ok {
		// Za pośrednikiem, który buforuje odpowiedzi, strumień nie ma sensu.
		// Strona i tak umie odpytywać, więc mówimy to wprost zamiast
		// udawać połączenie, które nigdy nic nie przyśle.
		return e.JSON(http.StatusNotImplemented, map[string]any{
			"message": "Streaming is not available behind this proxy",
		})
	}

	header := e.Response.Header()
	header.Set("Content-Type", "text/event-stream")
	header.Set("Cache-Control", "no-store, max-age=0")
	header.Set("Connection", "keep-alive")
	// Bez tego nginx z domyślną konfiguracją zbuforuje cały strumień
	// i wypuści go dopiero po rozłączeniu.
	header.Set("X-Accel-Buffering", "no")
	if liveRideVisibility(session) != "public" {
		header.Set("X-Robots-Tag", "noindex, nofollow")
	}
	e.Response.WriteHeader(http.StatusOK)

	// Link wygasły albo wyłączony dostaje jedno zdanie i rozłączenie.
	// Trzymanie otwartego strumienia dla kogoś, kto nic nie zobaczy, to
	// gniazdo zajęte bez powodu.
	if access.state != "ok" {
		liveRideStreamSend(e, flusher, "status", map[string]any{"status": access.state})
		return nil
	}

	changes := liveRideChanges.subscribe(sessionID)
	defer liveRideChanges.unsubscribe(sessionID, changes)

	liveRideStreamSend(e, flusher, "snapshot",
		liveRideSnapshotJSON(e.App, session, time.Now().UTC()))

	context := e.Request.Context()
	deadline := time.After(liveRideStreamMaxAge)
	heartbeat := time.NewTicker(liveRideStreamHeartbeat)
	defer heartbeat.Stop()
	lastSent := time.Now()
	var pending bool
	// Bufor na wysyłki wstrzymane limitem tempa — bez niego zmiana, która
	// przyszła sto milisekund po poprzedniej, przepadłaby do następnej.
	throttle := time.NewTicker(liveRideStreamMinInterval)
	defer throttle.Stop()

	for {
		select {
		case <-context.Done():
			return nil
		case <-deadline:
			return nil
		case <-changes:
			if time.Since(lastSent) < liveRideStreamMinInterval {
				pending = true
				continue
			}
			if !liveRideStreamPush(e, flusher, sessionID) {
				return nil
			}
			lastSent = time.Now()
			pending = false
		case <-throttle.C:
			if !pending {
				continue
			}
			if !liveRideStreamPush(e, flusher, sessionID) {
				return nil
			}
			lastSent = time.Now()
			pending = false
		case <-heartbeat.C:
			// Komentarz SSE. Trzyma połączenie przy życiu przez pośredniki,
			// które zamykają bezczynne gniazda po minucie.
			if _, err := fmt.Fprint(e.Response, ": ping\n\n"); err != nil {
				return nil
			}
			flusher.Flush()
		}
	}
}

// liveRideStreamPush odczytuje BIEŻĄCY stan i wysyła go.
//
// Odczyt dzieje się w chwili wysyłki, nie w chwili sygnału — dlatego
// zaległości nie da się nazbierać: dziesięć zmian w sekundę to nadal jedna
// wiadomość z ostatnim stanem.
func liveRideStreamPush(e *core.RequestEvent, flusher http.Flusher, sessionID string) bool {
	session, err := e.App.FindRecordById("live_ride_sessions", sessionID)
	if err != nil {
		return false
	}
	if liveRideShareExpired(session, time.Now().UTC()) ||
		liveRideVisibility(session) == "disabled" {
		liveRideStreamSend(e, flusher, "status", map[string]any{"status": "expired"})
		return false
	}
	return liveRideStreamSend(e, flusher, "snapshot",
		liveRideSnapshotJSON(e.App, session, time.Now().UTC()))
}

// liveRideStreamSend zapisuje jedno zdarzenie SSE.
func liveRideStreamSend(
	e *core.RequestEvent,
	flusher http.Flusher,
	name string,
	payload map[string]any,
) bool {
	body, err := json.Marshal(payload)
	if err != nil {
		return false
	}
	if _, err := fmt.Fprintf(e.Response, "event: %s\ndata: %s\n\n", name, body); err != nil {
		return false
	}
	flusher.Flush()
	return true
}
