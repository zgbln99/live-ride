package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// Live Ride intentionally keeps all collection API rules nil. The feature is
// exposed only through custom routes which enforce either normal user auth or
// the unguessable spectator share token. This prevents live locations from
// becoming enumerable through PocketBase's generic record API.
func init() {
	m.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId("users")
		if err != nil {
			return err
		}
		trails, err := app.FindCollectionByNameOrId("trails")
		if err != nil {
			return err
		}

		sessions := core.NewBaseCollection("live_ride_sessions")
		sessions.Fields.Add(
			&core.RelationField{Name: "owner", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.RelationField{Name: "trail", CollectionId: trails.Id, MaxSelect: 1},
			&core.TextField{Name: "title", Required: true, Max: 160},
			&core.TextField{Name: "share_token", Required: true, Min: 32, Max: 64},
			&core.TextField{Name: "join_token", Required: true, Min: 8, Max: 32},
			&core.SelectField{Name: "status", Values: []string{"active", "ended"}, MaxSelect: 1, Required: true},
			&core.DateField{Name: "started_at", Required: true},
			&core.DateField{Name: "ended_at"},
		)
		sessions.Indexes = append(sessions.Indexes,
			"CREATE UNIQUE INDEX `idx_live_ride_sessions_share_token` ON `live_ride_sessions` (`share_token`)",
			"CREATE UNIQUE INDEX `idx_live_ride_sessions_join_token` ON `live_ride_sessions` (`join_token`)",
			"CREATE INDEX `idx_live_ride_sessions_owner_status` ON `live_ride_sessions` (`owner`, `status`)",
		)
		if err := app.Save(sessions); err != nil {
			return err
		}

		participants := core.NewBaseCollection("live_ride_participants")
		participants.Fields.Add(
			&core.RelationField{Name: "session", CollectionId: sessions.Id, MaxSelect: 1, Required: true},
			&core.RelationField{Name: "user", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.TextField{Name: "display_name", Required: true, Max: 80},
			&core.NumberField{Name: "latitude"},
			&core.NumberField{Name: "longitude"},
			&core.NumberField{Name: "speed_kmh"},
			&core.NumberField{Name: "altitude_m"},
			&core.NumberField{Name: "heading_deg"},
			&core.NumberField{Name: "accuracy_m"},
			&core.NumberField{Name: "heart_rate_bpm", OnlyInt: true},
			&core.NumberField{Name: "distance_m"},
			&core.NumberField{Name: "elevation_gain_m"},
			&core.NumberField{Name: "battery_percent", OnlyInt: true},
			&core.DateField{Name: "last_seen_at"},
		)
		participants.Indexes = append(participants.Indexes,
			"CREATE UNIQUE INDEX `idx_live_ride_participants_session_user` ON `live_ride_participants` (`session`, `user`)",
			"CREATE INDEX `idx_live_ride_participants_session` ON `live_ride_participants` (`session`)",
		)
		if err := app.Save(participants); err != nil {
			return err
		}

		points := core.NewBaseCollection("live_ride_points")
		points.Fields.Add(
			&core.RelationField{Name: "session", CollectionId: sessions.Id, MaxSelect: 1, Required: true},
			&core.RelationField{Name: "participant", CollectionId: participants.Id, MaxSelect: 1, Required: true},
			&core.DateField{Name: "recorded_at", Required: true},
			&core.NumberField{Name: "latitude", Required: true},
			&core.NumberField{Name: "longitude", Required: true},
			&core.NumberField{Name: "speed_kmh"},
			&core.NumberField{Name: "altitude_m"},
			&core.NumberField{Name: "heading_deg"},
			&core.NumberField{Name: "accuracy_m"},
			&core.NumberField{Name: "heart_rate_bpm", OnlyInt: true},
			&core.NumberField{Name: "distance_m"},
			&core.NumberField{Name: "elevation_gain_m"},
		)
		points.Indexes = append(points.Indexes,
			"CREATE UNIQUE INDEX `idx_live_ride_points_participant_recorded_at` ON `live_ride_points` (`participant`, `recorded_at`)",
			"CREATE INDEX `idx_live_ride_points_session_recorded_at` ON `live_ride_points` (`session`, `recorded_at`)",
		)
		return app.Save(points)
	}, func(app core.App) error {
		for _, name := range []string{"live_ride_points", "live_ride_participants", "live_ride_sessions"} {
			collection, err := app.FindCollectionByNameOrId(name)
			if err != nil {
				continue
			}
			if err := app.Delete(collection); err != nil {
				return err
			}
		}
		return nil
	})
}
