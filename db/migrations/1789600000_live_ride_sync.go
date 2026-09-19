package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// Synchronizacja Live Ride: przejazdy, trasy, segmenty i prywatność LIVE.
//
// Tak jak poprzednia migracja, wszystkie reguły API kolekcji zostają puste.
// Dostęp idzie wyłącznie przez własne trasy HTTP, które sprawdzają albo
// zalogowanego użytkownika, albo nieodgadywalny token udostępnienia. Gdyby
// reguły były otwarte, cudze trasy i przejazdy dałoby się wyliczyć przez
// generyczne API PocketBase.
func init() {
	m.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId("users")
		if err != nil {
			return err
		}

		// ------------------------------------------------------- przejazdy
		rides := core.NewBaseCollection("live_ride_rides")
		rides.Fields.Add(
			&core.RelationField{Name: "owner", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.TextField{Name: "client_id", Required: true, Max: 64},
			&core.TextField{Name: "name", Required: true, Max: 160},
			&core.DateField{Name: "started_at", Required: true},
			&core.DateField{Name: "ended_at"},
			&core.NumberField{Name: "elapsed_seconds", OnlyInt: true},
			&core.NumberField{Name: "moving_seconds", OnlyInt: true},
			&core.NumberField{Name: "distance_m"},
			&core.NumberField{Name: "ascent_m"},
			&core.NumberField{Name: "descent_m"},
			&core.NumberField{Name: "max_speed_kmh"},
			&core.NumberField{Name: "avg_heart_rate", OnlyInt: true},
			&core.NumberField{Name: "max_heart_rate", OnlyInt: true},
			&core.NumberField{Name: "avg_power", OnlyInt: true},
			&core.NumberField{Name: "normalized_power", OnlyInt: true},
			&core.NumberField{Name: "avg_cadence", OnlyInt: true},
			&core.NumberField{Name: "calories", OnlyInt: true},
			// Ślad trzymany jako zakodowana polilinia: kilkaset kilobajtów
			// punktów w JSON-ie na każdy przejazd zjadłoby bazę bez powodu.
			&core.TextField{Name: "track_polyline", Max: 1000000},
			&core.NumberField{Name: "point_count", OnlyInt: true},
			&core.SelectField{Name: "privacy", Values: []string{"private", "link", "public"}, MaxSelect: 1, Required: true},
			&core.TextField{Name: "share_token", Max: 64},
			&core.DateField{Name: "client_updated_at"},
		)
		rides.Indexes = append(rides.Indexes,
			"CREATE UNIQUE INDEX `idx_live_ride_rides_owner_client` ON `live_ride_rides` (`owner`, `client_id`)",
			"CREATE INDEX `idx_live_ride_rides_owner_started` ON `live_ride_rides` (`owner`, `started_at`)",
			"CREATE UNIQUE INDEX `idx_live_ride_rides_share_token` ON `live_ride_rides` (`share_token`) WHERE `share_token` != ''",
		)
		if err := app.Save(rides); err != nil {
			return err
		}

		// ----------------------------------------------------------- trasy
		routes := core.NewBaseCollection("live_ride_routes")
		routes.Fields.Add(
			&core.RelationField{Name: "owner", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.TextField{Name: "client_id", Required: true, Max: 64},
			&core.TextField{Name: "name", Required: true, Max: 160},
			&core.TextField{Name: "description", Max: 2000},
			&core.JSONField{Name: "tags", MaxSize: 4000},
			&core.NumberField{Name: "distance_m"},
			&core.NumberField{Name: "ascent_m"},
			&core.NumberField{Name: "descent_m"},
			&core.TextField{Name: "polyline", Required: true, Max: 1000000},
			&core.JSONField{Name: "waypoints", MaxSize: 200000},
			&core.JSONField{Name: "preferences", MaxSize: 8000},
			&core.SelectField{Name: "privacy", Values: []string{"private", "link", "public"}, MaxSelect: 1, Required: true},
			&core.TextField{Name: "share_token", Max: 64},
			// Ile razy ktoś skopiował tę trasę do siebie.
			&core.NumberField{Name: "copy_count", OnlyInt: true},
			&core.RelationField{Name: "copied_from", CollectionId: "", MaxSelect: 1},
			&core.DateField{Name: "client_updated_at"},
		)
		routes.Indexes = append(routes.Indexes,
			"CREATE UNIQUE INDEX `idx_live_ride_routes_owner_client` ON `live_ride_routes` (`owner`, `client_id`)",
			"CREATE UNIQUE INDEX `idx_live_ride_routes_share_token` ON `live_ride_routes` (`share_token`) WHERE `share_token` != ''",
			"CREATE INDEX `idx_live_ride_routes_privacy` ON `live_ride_routes` (`privacy`)",
		)
		if err := app.Save(routes); err != nil {
			return err
		}
		// Samoodniesienie da się ustawić dopiero, gdy kolekcja ma już id.
		if field, ok := routes.Fields.GetByName("copied_from").(*core.RelationField); ok {
			field.CollectionId = routes.Id
			if err := app.Save(routes); err != nil {
				return err
			}
		}

		// -------------------------------------------------------- segmenty
		segments := core.NewBaseCollection("live_ride_segments")
		segments.Fields.Add(
			&core.RelationField{Name: "owner", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.TextField{Name: "client_id", Required: true, Max: 64},
			&core.TextField{Name: "name", Required: true, Max: 160},
			&core.NumberField{Name: "distance_m"},
			&core.NumberField{Name: "ascent_m"},
			&core.NumberField{Name: "avg_gradient"},
			&core.TextField{Name: "polyline", Required: true, Max: 500000},
			&core.SelectField{Name: "privacy", Values: []string{"private", "link", "public"}, MaxSelect: 1, Required: true},
			&core.TextField{Name: "share_token", Max: 64},
		)
		segments.Indexes = append(segments.Indexes,
			"CREATE UNIQUE INDEX `idx_live_ride_segments_owner_client` ON `live_ride_segments` (`owner`, `client_id`)",
			"CREATE UNIQUE INDEX `idx_live_ride_segments_share_token` ON `live_ride_segments` (`share_token`) WHERE `share_token` != ''",
		)
		if err := app.Save(segments); err != nil {
			return err
		}

		attempts := core.NewBaseCollection("live_ride_segment_attempts")
		attempts.Fields.Add(
			&core.RelationField{Name: "segment", CollectionId: segments.Id, MaxSelect: 1, Required: true},
			&core.RelationField{Name: "user", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.TextField{Name: "client_id", Required: true, Max: 64},
			&core.DateField{Name: "started_at", Required: true},
			&core.NumberField{Name: "duration_seconds", OnlyInt: true, Required: true},
			&core.NumberField{Name: "avg_speed_kmh"},
			&core.NumberField{Name: "avg_heart_rate", OnlyInt: true},
			&core.NumberField{Name: "avg_power", OnlyInt: true},
		)
		attempts.Indexes = append(attempts.Indexes,
			"CREATE UNIQUE INDEX `idx_live_ride_attempts_user_client` ON `live_ride_segment_attempts` (`user`, `client_id`)",
			// Ranking pyta zawsze o ten sam porządek, więc indeks go obsłuży.
			"CREATE INDEX `idx_live_ride_attempts_segment_duration` ON `live_ride_segment_attempts` (`segment`, `duration_seconds`)",
		)
		if err := app.Save(attempts); err != nil {
			return err
		}

		// ------------------------------------------- prywatność i grupa
		participants, err := app.FindCollectionByNameOrId("live_ride_participants")
		if err != nil {
			return err
		}
		participants.Fields.Add(
			&core.NumberField{Name: "cadence_rpm", OnlyInt: true},
			&core.NumberField{Name: "power_watts", OnlyInt: true},
			// Prywatność per pole: zawodnik decyduje, co widzą obserwujący.
			// Domyślnie wszystko widoczne poza mocą i tętnem — te są
			// osobiste i włącza się je świadomie.
			&core.BoolField{Name: "share_heart_rate"},
			&core.BoolField{Name: "share_power"},
			&core.BoolField{Name: "share_speed"},
			&core.BoolField{Name: "share_position"},
			&core.SelectField{Name: "role", Values: []string{"rider", "leader"}, MaxSelect: 1},
		)
		if err := app.Save(participants); err != nil {
			return err
		}

		sessions, err := app.FindCollectionByNameOrId("live_ride_sessions")
		if err != nil {
			return err
		}
		sessions.Fields.Add(
			&core.SelectField{Name: "kind", Values: []string{"solo", "group"}, MaxSelect: 1},
			&core.NumberField{Name: "meetup_lat"},
			&core.NumberField{Name: "meetup_lon"},
			&core.TextField{Name: "meetup_label", Max: 160},
			&core.DateField{Name: "expires_at"},
		)
		if err := app.Save(sessions); err != nil {
			return err
		}

		messages := core.NewBaseCollection("live_ride_messages")
		messages.Fields.Add(
			&core.RelationField{Name: "session", CollectionId: sessions.Id, MaxSelect: 1, Required: true},
			&core.RelationField{Name: "participant", CollectionId: participants.Id, MaxSelect: 1, Required: true},
			&core.TextField{Name: "body", Required: true, Max: 280},
			&core.DateField{Name: "sent_at", Required: true},
		)
		messages.Indexes = append(messages.Indexes,
			"CREATE INDEX `idx_live_ride_messages_session_sent` ON `live_ride_messages` (`session`, `sent_at`)",
		)
		return app.Save(messages)
	}, func(app core.App) error {
		for _, name := range []string{
			"live_ride_messages",
			"live_ride_segment_attempts",
			"live_ride_segments",
			"live_ride_routes",
			"live_ride_rides",
		} {
			collection, err := app.FindCollectionByNameOrId(name)
			if err != nil {
				continue
			}
			if err := app.Delete(collection); err != nil {
				return err
			}
		}

		for _, spec := range []struct {
			collection string
			fields     []string
		}{
			{"live_ride_participants", []string{
				"cadence_rpm", "power_watts", "share_heart_rate", "share_power",
				"share_speed", "share_position", "role",
			}},
			{"live_ride_sessions", []string{
				"kind", "meetup_lat", "meetup_lon", "meetup_label", "expires_at",
			}},
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
