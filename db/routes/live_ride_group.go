package routes

import (
	"net/http"
	"strings"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
)

// Jazda grupowa i prywatność LIVE.
//
// Grupa to ta sama sesja, do której dołącza się kodem — nie osobny byt.
// Dokładają się do niej trzy rzeczy: ustawienia prywatności każdego
// zawodnika, punkt zbiórki i krótkie wiadomości.

const liveRideMaxMessages = 50

// LiveRideSetPrivacy stores what a rider agrees to share with spectators.
func LiveRideSetPrivacy(e *core.RequestEvent) error {
	session, err := activeLiveRideByID(e, e.Request.PathValue("id"))
	if err != nil {
		return err
	}

	participant, err := e.App.FindFirstRecordByFilter(
		"live_ride_participants",
		"session={:session} && user={:user}",
		dbx.Params{"session": session.Id, "user": e.Auth.Id},
	)
	if err != nil {
		return apis.NewForbiddenError("Join the live ride first", nil)
	}

	var data struct {
		SharePosition  *bool `json:"share_position"`
		ShareSpeed     *bool `json:"share_speed"`
		ShareHeartRate *bool `json:"share_heart_rate"`
		SharePower     *bool `json:"share_power"`
	}
	if err := e.BindBody(&data); err != nil {
		return apis.NewBadRequestError("Failed to read request data", err)
	}

	// Każde pole osobno i tylko to, co przysłano: brak pola w żądaniu znaczy
	// „nie zmieniam", a nie „wyłącz".
	if data.SharePosition != nil {
		participant.Set("share_position", *data.SharePosition)
	}
	if data.ShareSpeed != nil {
		participant.Set("share_speed", *data.ShareSpeed)
	}
	if data.ShareHeartRate != nil {
		participant.Set("share_heart_rate", *data.ShareHeartRate)
	}
	if data.SharePower != nil {
		participant.Set("share_power", *data.SharePower)
	}

	if err := e.App.Save(participant); err != nil {
		return apis.NewBadRequestError("Failed to store privacy settings", err)
	}

	return e.JSON(http.StatusOK, map[string]any{
		"share_position":   participant.GetBool("share_position"),
		"share_speed":      participant.GetBool("share_speed"),
		"share_heart_rate": participant.GetBool("share_heart_rate"),
		"share_power":      participant.GetBool("share_power"),
	})
}

// LiveRideSetMeetup stores the group's meeting point. Only the owner may set it.
func LiveRideSetMeetup(e *core.RequestEvent) error {
	session, err := activeLiveRideByID(e, e.Request.PathValue("id"))
	if err != nil {
		return err
	}
	if session.GetString("owner") != e.Auth.Id {
		return apis.NewForbiddenError("Only the owner can set the meeting point", nil)
	}

	var data struct {
		Latitude  float64 `json:"latitude"`
		Longitude float64 `json:"longitude"`
		Label     string  `json:"label"`
		Clear     bool    `json:"clear"`
	}
	if err := e.BindBody(&data); err != nil {
		return apis.NewBadRequestError("Failed to read request data", err)
	}

	if data.Clear {
		session.Set("meetup_lat", 0)
		session.Set("meetup_lon", 0)
		session.Set("meetup_label", "")
	} else {
		if data.Latitude < -90 || data.Latitude > 90 {
			return apis.NewBadRequestError("latitude must be between -90 and 90", nil)
		}
		if data.Longitude < -180 || data.Longitude > 180 {
			return apis.NewBadRequestError("longitude must be between -180 and 180", nil)
		}
		label := strings.TrimSpace(data.Label)
		if len(label) > 160 {
			label = label[:160]
		}
		session.Set("meetup_lat", data.Latitude)
		session.Set("meetup_lon", data.Longitude)
		session.Set("meetup_label", label)
	}
	session.Set("kind", "group")

	if err := e.App.Save(session); err != nil {
		return apis.NewBadRequestError("Failed to store the meeting point", err)
	}
	return e.JSON(http.StatusOK, map[string]any{
		"latitude":  session.GetFloat("meetup_lat"),
		"longitude": session.GetFloat("meetup_lon"),
		"label":     session.GetString("meetup_label"),
	})
}

// LiveRidePostMessage stores one short message for the group.
func LiveRidePostMessage(e *core.RequestEvent) error {
	session, err := activeLiveRideByID(e, e.Request.PathValue("id"))
	if err != nil {
		return err
	}

	participant, err := e.App.FindFirstRecordByFilter(
		"live_ride_participants",
		"session={:session} && user={:user}",
		dbx.Params{"session": session.Id, "user": e.Auth.Id},
	)
	if err != nil {
		return apis.NewForbiddenError("Join the live ride first", nil)
	}

	var data struct {
		Body string `json:"body"`
	}
	if err := e.BindBody(&data); err != nil {
		return apis.NewBadRequestError("Failed to read request data", err)
	}

	body := strings.TrimSpace(data.Body)
	if body == "" {
		return apis.NewBadRequestError("body is required", nil)
	}
	if len(body) > 280 {
		// Wiadomości czyta się jedną ręką na kierownicy. Obcinamy, zamiast
		// odrzucać, bo odrzucenie kazałoby pisać jeszcze raz.
		body = body[:280]
	}

	collection, err := e.App.FindCollectionByNameOrId("live_ride_messages")
	if err != nil {
		return apis.NewNotFoundError("Live Ride messages collection is missing", err)
	}

	record := core.NewRecord(collection)
	record.Set("session", session.Id)
	record.Set("participant", participant.Id)
	record.Set("body", body)
	record.Set("sent_at", time.Now().UTC())
	if err := e.App.Save(record); err != nil {
		return apis.NewBadRequestError("Failed to store the message", err)
	}

	return e.JSON(http.StatusCreated, map[string]any{
		"id":           record.Id,
		"body":         body,
		"sent_at":      record.GetDateTime("sent_at"),
		"display_name": participant.GetString("display_name"),
	})
}

// LiveRideMessages returns the latest group messages to spectators and riders.
//
// It is reachable with the share token alone, like the snapshot: the people
// following a group ride are exactly the people holding the link.
func LiveRideMessages(e *core.RequestEvent) error {
	token := strings.TrimSpace(e.Request.PathValue("token"))
	if len(token) < 32 {
		return apis.NewNotFoundError("Live ride not found", nil)
	}

	session, err := e.App.FindFirstRecordByData("live_ride_sessions", "share_token", token)
	if err != nil {
		return apis.NewNotFoundError("Live ride not found", err)
	}

	records, err := e.App.FindRecordsByFilter(
		"live_ride_messages",
		"session={:session}",
		"-sent_at",
		liveRideMaxMessages,
		0,
		dbx.Params{"session": session.Id},
	)
	if err != nil {
		return apis.NewBadRequestError("Failed to read messages", err)
	}

	names := map[string]string{}
	items := make([]map[string]any, 0, len(records))
	for _, record := range records {
		participantID := record.GetString("participant")
		name, known := names[participantID]
		if !known {
			if participant, err := e.App.FindRecordById(
				"live_ride_participants",
				participantID,
			); err == nil {
				name = participant.GetString("display_name")
			}
			names[participantID] = name
		}
		items = append(items, map[string]any{
			"id":           record.Id,
			"body":         record.GetString("body"),
			"sent_at":      record.GetDateTime("sent_at"),
			"display_name": name,
		})
	}

	return e.JSON(http.StatusOK, map[string]any{"messages": items})
}
