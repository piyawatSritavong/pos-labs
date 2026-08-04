package repository

import "testing"

func TestFormatPartCode(t *testing.T) {
	tests := []struct {
		name     string
		sequence int64
		want     string
	}{
		{name: "first", sequence: 1, want: "P0001"},
		{name: "four digits", sequence: 9999, want: "P9999"},
		{name: "grows past four digits", sequence: 10000, want: "P10000"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := formatPartCode(tt.sequence); got != tt.want {
				t.Fatalf("formatPartCode(%d) = %q, want %q", tt.sequence, got, tt.want)
			}
		})
	}
}
