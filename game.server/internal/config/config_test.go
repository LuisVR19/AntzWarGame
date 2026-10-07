package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDefaultIsValid(t *testing.T) {
	if err := Default().Validate(); err != nil {
		t.Fatal(err)
	}
}

func TestLoadOverridesAndReplacesArmy(t *testing.T) {
	path := filepath.Join(t.TempDir(), "cfg.json")
	data := `{"game": {"tick_rate": 20, "army": [{"name": "Solo", "unit_count": 500, "attack": 5, "defense": 5, "speed": 20, "morale": 70}]},
	          "terrain": {"FOREST": {"movement_modifier": 0.5, "attack_modifier": 0.9, "defense_modifier": 1.4, "visibility_modifier": 0.5}}}`
	if err := os.WriteFile(path, []byte(data), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg, err := Load(path, false)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Game.TickRate != 20 || cfg.Game.EngagementRange != Default().Game.EngagementRange {
		t.Fatalf("override/merge failed: %+v", cfg.Game)
	}
	if len(cfg.Game.Army) != 1 || cfg.Game.Army[0].Name != "Solo" || cfg.Game.Army[0].Experience != 0 {
		t.Fatalf("army must be replaced, not merged: %+v", cfg.Game.Army)
	}
	if cfg.Terrain["FOREST"].Movement != 0.5 || cfg.Terrain["HILL"].Defense != 1.3 {
		t.Fatalf("terrain override failed: %+v", cfg.Terrain)
	}
}

func TestLoadMissingFile(t *testing.T) {
	if _, err := Load("does-not-exist.json", true); err != nil {
		t.Fatalf("optional missing file: %v", err)
	}
	if _, err := Load("does-not-exist.json", false); err == nil {
		t.Fatal("required missing file must fail")
	}
}

func TestLoadRejectsInvalidValues(t *testing.T) {
	path := filepath.Join(t.TempDir(), "cfg.json")
	_ = os.WriteFile(path, []byte(`{"game": {"tick_rate": 0}}`), 0o600)
	if _, err := Load(path, false); err == nil {
		t.Fatal("tick_rate 0 accepted")
	}
}
