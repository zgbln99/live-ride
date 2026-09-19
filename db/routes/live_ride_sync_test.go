package routes

import (
	"strings"
	"testing"
	"time"
)

func TestNormalizeLiveRidePrivacy(t *testing.T) {
	cases := map[string]string{
		"public":  "public",
		"PUBLIC":  "public",
		" link ":  "link",
		"private": "private",
		"":        "private",
		// Literówka nie może upublicznić cudzego przejazdu.
		"publik":   "private",
		"everyone": "private",
	}
	for input, want := range cases {
		if got := normalizeLiveRidePrivacy(input); got != want {
			t.Errorf("normalizeLiveRidePrivacy(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestValidateLiveRideRide(t *testing.T) {
	valid := liveRideRidePayload{
		ClientID:       "ride_abc",
		Name:           "Poranna jazda",
		StartedAt:      time.Now().UTC(),
		ElapsedSeconds: 3600,
		DistanceM:      42000,
	}
	if err := validateLiveRideRide(valid); err != nil {
		t.Fatalf("valid ride rejected: %v", err)
	}

	cases := []struct {
		name   string
		mutate func(*liveRideRidePayload)
	}{
		{"no client id", func(p *liveRideRidePayload) { p.ClientID = "  " }},
		{"no name", func(p *liveRideRidePayload) { p.Name = "" }},
		{"no start", func(p *liveRideRidePayload) { p.StartedAt = time.Time{} }},
		{"negative distance", func(p *liveRideRidePayload) { p.DistanceM = -1 }},
		{"absurd distance", func(p *liveRideRidePayload) { p.DistanceM = 3_000_000 }},
		{"absurd duration", func(p *liveRideRidePayload) { p.ElapsedSeconds = 30 * 24 * 3600 }},
		{"huge polyline", func(p *liveRideRidePayload) {
			p.TrackPolyline = strings.Repeat("a", liveRideMaxPolylineBytes+1)
		}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			payload := valid
			tc.mutate(&payload)
			if err := validateLiveRideRide(payload); err == nil {
				t.Fatalf("expected %s to be rejected", tc.name)
			}
		})
	}
}

func TestValidateLiveRideRoute(t *testing.T) {
	valid := liveRideRoutePayload{
		ClientID:  "route_abc",
		Name:      "Pętla wokół jeziora",
		Polyline:  "abc123",
		DistanceM: 30000,
	}
	if err := validateLiveRideRoute(valid); err != nil {
		t.Fatalf("valid route rejected: %v", err)
	}

	cases := []struct {
		name   string
		mutate func(*liveRideRoutePayload)
	}{
		{"no client id", func(p *liveRideRoutePayload) { p.ClientID = "" }},
		{"no name", func(p *liveRideRoutePayload) { p.Name = " " }},
		{"no geometry", func(p *liveRideRoutePayload) { p.Polyline = "" }},
		{"huge geometry", func(p *liveRideRoutePayload) {
			p.Polyline = strings.Repeat("x", liveRideMaxPolylineBytes+1)
		}},
		{"negative distance", func(p *liveRideRoutePayload) { p.DistanceM = -5 }},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			payload := valid
			tc.mutate(&payload)
			if err := validateLiveRideRoute(payload); err == nil {
				t.Fatalf("expected %s to be rejected", tc.name)
			}
		})
	}
}

func TestLiveRideUpdatedAtFallsBackToNow(t *testing.T) {
	before := time.Now().UTC().Add(-time.Second)
	got := liveRideUpdatedAt(time.Time{})
	if got.Before(before) {
		t.Fatalf("liveRideUpdatedAt(zero) = %v, want a recent timestamp", got)
	}

	explicit := time.Date(2026, 5, 1, 12, 0, 0, 0, time.UTC)
	if liveRideUpdatedAt(explicit) != explicit {
		t.Fatalf("liveRideUpdatedAt kept a different value")
	}
}
