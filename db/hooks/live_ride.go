package hooks

import (
	"pocketbase/routes"

	"github.com/pocketbase/pocketbase/core"
)

// Budzenie publicznych strumieni LIVE.
//
// Zmiana w bazie jest jedynym momentem, w którym NA PEWNO wiadomo, że widz ma
// co odświeżyć. Alternatywą byłoby odpytywanie bazy raz na sekundę na każde
// otwarte połączenie — czyli przeniesienie pollingu z przeglądarki na serwer
// i pomnożenie go przez liczbę oglądających.
//
// Haki są celowo bezużyteczne poza powiadomieniem: nie czytają bazy, nie mogą
// się nie udać i nie zwracają błędu. Zapis telemetrii już się powiódł, gdy tu
// docieramy, i nie ma prawa przewrócić się przez to, że ktoś ogląda.

// NotifyLiveRideViewers budzi widzów sesji, do której należy rekord.
func NotifyLiveRideViewers() func(*core.RecordEvent) error {
	return func(e *core.RecordEvent) error {
		routes.LiveRideNotifySession(e.Record.GetString("session"))
		return e.Next()
	}
}

// NotifyLiveRideSession budzi widzów sesji, która sama się zmieniła.
func NotifyLiveRideSession() func(*core.RecordEvent) error {
	return func(e *core.RecordEvent) error {
		routes.LiveRideNotifySession(e.Record.Id)
		return e.Next()
	}
}
