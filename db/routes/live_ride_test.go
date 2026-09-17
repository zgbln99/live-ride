package routes

import (
	"testing"
	"time"
)

func TestNormalizeLiveRideJoinToken(t *testing.T) {
	got := normalizeLiveRideJoinToken("  aB3x-9z  ")
	if got != "AB3X-9Z" {
		t.Fatalf("normalizeLiveRideJoinToken() = %q, want %q", got, "AB3X-9Z")
	}
}

func TestValidateLiveRidePoint(t *testing.T) {
	valid := liveRideTelemetryPoint{
		RecordedAt:   time.Now().UTC(),
		Latitude:     52.2297,
		Longitude:    21.0122,
		SpeedKmh:     31.5,
		AccuracyM:    6,
		HeartRateBpm: 158,
	}
	if err := validateLiveRidePoint(valid); err != nil {
		t.Fatalf("valid sample rejected: %v", err)
	}

	cases := []struct {
		name   string
		mutate func(*liveRideTelemetryPoint)
	}{
		{"missing timestamp", func(p *liveRideTelemetryPoint) { p.RecordedAt = time.Time{} }},
		{"latitude", func(p *liveRideTelemetryPoint) { p.Latitude = 91 }},
		{"longitude", func(p *liveRideTelemetryPoint) { p.Longitude = 181 }},
		{"speed", func(p *liveRideTelemetryPoint) { p.SpeedKmh = 201 }},
		{"accuracy", func(p *liveRideTelemetryPoint) { p.AccuracyM = 5001 }},
		{"heart rate", func(p *liveRideTelemetryPoint) { p.HeartRateBpm = 261 }},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			point := valid
			tc.mutate(&point)
			if err := validateLiveRidePoint(point); err == nil {
				t.Fatal("invalid sample was accepted")
			}
		})
	}
}
