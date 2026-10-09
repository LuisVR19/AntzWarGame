package game

import (
	"errors"
	"fmt"
	"math"
	"strings"

	"gameserver/internal/combat"
	"gameserver/internal/player"
)

// Formation is how a division arranges its soldiers. Attack, Defense* and
// Speed are multipliers; the defense used depends on the side a blow lands
// on (see Exposure). Same model and values as the client's formations.json.
type Formation struct {
	Name         string  `json:"name"`
	Attack       float64 `json:"attack"`
	DefenseFront float64 `json:"defense_front"`
	DefenseFlank float64 `json:"defense_flank"`
	DefenseRear  float64 `json:"defense_rear"`
	Speed        float64 `json:"speed"`
	// Frontage: soldiers that can fight at once (the rest is a reserve).
	Frontage int `json:"frontage"`
	// TurnRate: degrees per second it turns towards its enemy in combat.
	TurnRate float64 `json:"turn_rate"`
	// BonusVs multiplies the attack against another formation.
	BonusVs map[string]float64 `json:"bonus_vs,omitempty"`
}

// Defense returns the defense multiplier for a blow on side.
func (f Formation) Defense(side Exposure) float64 {
	switch side {
	case ExposureFlank:
		return f.DefenseFlank
	case ExposureRear:
		return f.DefenseRear
	}
	return f.DefenseFront
}

// AttackVs returns the attack multiplier against enemy formation.
func (f Formation) AttackVs(enemy string) float64 {
	if b, ok := f.BonusVs[enemy]; ok {
		return f.Attack * b
	}
	return f.Attack
}

// Ranged is the ranged attack of a unit type.
type Ranged struct {
	Range  float64 `json:"range"` // world units
	Attack float64 `json:"attack"`
}

// UnitType holds the base stats of a kind of division (ant). An army
// template may override any of them.
type UnitType struct {
	Name       string  `json:"name"`
	Attack     float64 `json:"attack"`
	Defense    float64 `json:"defense"`
	Speed      float64 `json:"speed"`
	Morale     float64 `json:"morale"`
	Experience float64 `json:"experience"`
	Ranged     *Ranged `json:"ranged,omitempty"`
}

// Exposure is the side of a division hit by a blow.
type Exposure string

const (
	ExposureFront Exposure = "front"
	ExposureFlank Exposure = "flank"
	ExposureRear  Exposure = "rear"

	frontArc = math.Pi / 3     // up to 60 degrees from the facing
	rearArc  = math.Pi * 2 / 3 // from 120 degrees
)

// Formation and unit type identifiers used by the defaults.
const (
	FormationLine       = "LINE"
	FormationShieldWall = "SHIELD_WALL"
	FormationWedge      = "WEDGE"
	FormationSquare     = "SQUARE"
	FormationColumn     = "COLUMN"

	UnitWorker  = "WORKER"
	UnitSoldier = "SOLDIER"
	UnitArcher  = "ARCHER"
	UnitTank    = "TANK"
	UnitScout   = "SCOUT"
)

// DefaultFormations mirrors game.client/data/definitions/formations.json.
func DefaultFormations() map[string]Formation {
	return map[string]Formation{
		FormationLine: {Name: "Línea", Attack: 1.0, DefenseFront: 1.0, DefenseFlank: 0.75, DefenseRear: 0.55,
			Speed: 1.0, Frontage: 2000, TurnRate: 60},
		FormationShieldWall: {Name: "Muro de escudos", Attack: 0.75, DefenseFront: 1.7, DefenseFlank: 0.6, DefenseRear: 0.45,
			Speed: 0.6, Frontage: 1800, TurnRate: 20},
		FormationWedge: {Name: "Cuña", Attack: 1.35, DefenseFront: 0.85, DefenseFlank: 0.6, DefenseRear: 0.5,
			Speed: 1.1, Frontage: 1000, TurnRate: 45, BonusVs: map[string]float64{FormationShieldWall: 1.4, FormationLine: 1.15}},
		FormationSquare: {Name: "Erizo", Attack: 0.7, DefenseFront: 1.25, DefenseFlank: 1.25, DefenseRear: 1.25,
			Speed: 0.45, Frontage: 1600, TurnRate: 360, BonusVs: map[string]float64{FormationWedge: 0.8}},
		FormationColumn: {Name: "Columna", Attack: 0.7, DefenseFront: 0.75, DefenseFlank: 0.5, DefenseRear: 0.5,
			Speed: 1.35, Frontage: 600, TurnRate: 90},
	}
}

// DefaultUnitTypes mirrors game.client/data/definitions/unit_types.json.
func DefaultUnitTypes() map[string]UnitType {
	return map[string]UnitType{
		UnitWorker:  {Name: "Obrera", Attack: 10, Defense: 12, Speed: 30, Morale: 80, Experience: 10},
		UnitSoldier: {Name: "Soldado", Attack: 16, Defense: 8, Speed: 45, Morale: 85, Experience: 20},
		UnitArcher: {Name: "Arquera", Attack: 5, Defense: 6, Speed: 35, Morale: 75, Experience: 10,
			Ranged: &Ranged{Range: 220, Attack: 11}},
		UnitTank:  {Name: "Acorazada", Attack: 11, Defense: 22, Speed: 20, Morale: 95, Experience: 15},
		UnitScout: {Name: "Exploradora", Attack: 9, Defense: 7, Speed: 70, Morale: 70, Experience: 10},
	}
}

// FormationRules tunes formation changes.
type FormationRules struct {
	Default string `json:"default"`
	// ChangeSeconds: time a division spends reorganizing after a change.
	ChangeSeconds float64 `json:"change_seconds"`
	// ReformPenalty multiplies attack and defense while reorganizing.
	ReformPenalty float64 `json:"reform_penalty"`
	// ReformSpeedFactor multiplies speed while reorganizing.
	ReformSpeedFactor float64 `json:"reform_speed_factor"`
}

// DefaultFormationRules returns the default formation tuning.
func DefaultFormationRules() FormationRules {
	return FormationRules{Default: FormationLine, ChangeSeconds: 3, ReformPenalty: 0.75, ReformSpeedFactor: 0.5}
}

func (r Rules) validateFormations() error {
	if len(r.Formations) == 0 {
		return errors.New("rules: formations must not be empty")
	}
	for id, f := range r.Formations {
		if f.Attack <= 0 || f.DefenseFront <= 0 || f.DefenseFlank <= 0 || f.DefenseRear <= 0 || f.Speed <= 0 || f.Frontage <= 0 || f.TurnRate <= 0 {
			return fmt.Errorf("rules: formation %q has invalid values", id)
		}
	}
	fr := r.FormationRules
	switch {
	case !r.hasFormation(fr.Default):
		return fmt.Errorf("rules: default formation %q does not exist", fr.Default)
	case fr.ChangeSeconds < 0 || fr.ReformPenalty <= 0 || fr.ReformSpeedFactor <= 0:
		return errors.New("rules: formation_rules values must be > 0")
	}
	for id, u := range r.UnitTypes {
		if u.Ranged != nil && (u.Ranged.Range <= 0 || u.Ranged.Attack <= 0) {
			return fmt.Errorf("rules: unit type %q has an invalid ranged attack", id)
		}
	}
	return nil
}

func (r Rules) hasFormation(id string) bool {
	_, ok := r.Formations[id]
	return ok
}

func (r Rules) formation(id string) Formation {
	if f, ok := r.Formations[id]; ok {
		return f
	}
	return r.Formations[r.FormationRules.Default]
}

// Resolved returns the template with its type's stats filled in where the
// template leaves them at zero, and the formation and type normalized.
func (r Rules) Resolved(t DivisionTemplate) DivisionTemplate {
	t.Type = strings.ToUpper(t.Type)
	t.Formation = strings.ToUpper(t.Formation)
	if t.Formation == "" {
		t.Formation = r.FormationRules.Default
	}
	u, ok := r.UnitTypes[t.Type]
	if !ok {
		if t.Type == "" {
			t.Type = UnitWorker
		}
		return t
	}
	fill := func(v *float64, base float64) {
		if *v == 0 {
			*v = base
		}
	}
	fill(&t.Attack, u.Attack)
	fill(&t.Defense, u.Defense)
	fill(&t.Speed, u.Speed)
	fill(&t.Morale, u.Morale)
	fill(&t.Experience, u.Experience)
	return t
}

// exposureOf returns the side of a division facing `facing` (radians) hit
// by a blow coming from direction (vector from the division to the enemy).
func exposureOf(facing float64, from Position) Exposure {
	if from.X*from.X+from.Y*from.Y < 1e-4 {
		return ExposureFront
	}
	diff := math.Abs(angleDiff(facing, math.Atan2(from.Y, from.X)))
	switch {
	case diff <= frontArc:
		return ExposureFront
	case diff >= rearArc:
		return ExposureRear
	}
	return ExposureFlank
}

// angleDiff returns to-from wrapped to [-pi, pi].
func angleDiff(from, to float64) float64 {
	d := math.Mod(to-from, 2*math.Pi)
	switch {
	case d > math.Pi:
		d -= 2 * math.Pi
	case d < -math.Pi:
		d += 2 * math.Pi
	}
	return d
}

func wrapAngle(a float64) float64 { return angleDiff(0, a) }

// exposure returns the side of d hit by enemy.
func (g *Game) exposure(d, enemy *Division) Exposure {
	return exposureOf(d.Facing, enemy.Position.Sub(d.Position))
}

// initialFacing points a side's divisions towards the enemy base.
func initialFacing(side player.Side) float64 {
	if side == 1 {
		return math.Pi
	}
	return 0
}

// ranged returns the ranged attack of d's type (nil = melee only).
func (g *Game) ranged(d *Division) *Ranged {
	return g.Rules.UnitTypes[d.UnitType].Ranged
}

// SetFormation validates a formation change and queues it for the next
// tick. It does not go through the chain of command: the division's own
// officers reorganize it. The division then spends ChangeSeconds
// reorganizing (slower and weaker).
func (g *Game) SetFormation(pid player.ID, id DivisionID, formation string) error {
	formation = strings.ToUpper(formation)
	if err := g.validateFormation(pid, id, formation); err != nil {
		return err
	}
	g.pendingFormations = append(g.pendingFormations, pendingFormation{division: id, formation: formation})
	return nil
}

type pendingFormation struct {
	division  DivisionID
	formation string
}

func (g *Game) validateFormation(pid player.ID, id DivisionID, formation string) error {
	if g.Status != StatusRunning {
		return newErr(CodeGameNotRunning, "game is %s", g.Status)
	}
	d, ok := g.divisions[id]
	switch {
	case !ok:
		return newErr(CodeDivisionNotFound, "division %s does not exist", id)
	case d.PlayerID != pid:
		return newErr(CodeNotOwner, "division %s belongs to another player", id)
	case !d.Alive():
		return newErr(CodeDivisionDestroyed, "division %s is destroyed", id)
	case d.Routed:
		return newErr(CodeDivisionRouted, "division %s is routed and cannot change formation", id)
	case !g.Rules.hasFormation(formation):
		return newErr(CodeInvalidFormation, "unknown formation %q", formation)
	case d.Formation == formation:
		return newErr(CodeSameFormation, "division %s is already in formation %s", id, formation)
	}
	return nil
}

// applyFormations applies the changes validated since the previous tick
// (step 1, with the orders).
func (g *Game) applyFormations() {
	for _, c := range g.pendingFormations {
		d := g.divisions[c.division]
		if d == nil || g.validateFormation(d.PlayerID, d.ID, c.formation) != nil {
			continue
		}
		d.Formation = c.formation
		d.reformTicks = max(int(math.Round(g.Rules.FormationRules.ChangeSeconds*float64(g.Rules.TickRate))), 1)
		g.log.Info("formation changed", "game_id", g.ID, "division_id", d.ID, "formation", d.Formation)
		g.refreshState(d, "formation_changed", true)
	}
	g.pendingFormations = g.pendingFormations[:0]
}

// updateFacing counts down reorganizations and turns engaged divisions
// towards their main opponent at their formation's turn rate.
func (g *Game) updateFacing() {
	for _, d := range g.divisionOrder {
		if !d.Alive() {
			continue
		}
		if d.reformTicks > 0 {
			d.reformTicks--
			if d.reformTicks == 0 {
				g.refreshState(d, "formation_ready", true)
			}
		}
		if d.State == StateRetreating {
			continue
		}
		opp := g.primaryOpponent(d)
		if opp == nil {
			continue
		}
		target := math.Atan2(opp.Position.Y-d.Position.Y, opp.Position.X-d.Position.X)
		maxTurn := g.Rules.formation(d.Formation).TurnRate * math.Pi / 180 * g.Rules.DT()
		d.Facing = wrapAngle(d.Facing + clamp(angleDiff(d.Facing, target), -maxTurn, maxTurn))
	}
}

// primaryOpponent is the opponent of d's oldest active battle.
func (g *Game) primaryOpponent(d *Division) *Division {
	for _, b := range g.battles {
		if b.Active && b.Involves(d.ID) {
			return g.divisions[b.opponent(d.ID)]
		}
	}
	return nil
}

// updateVolleys makes ranged divisions shoot once per combat round at an
// enemy in range, when they are not marching, retreating or in melee.
func (g *Game) updateVolleys() {
	for _, d := range g.divisionOrder {
		r := g.ranged(d)
		if !d.Alive() || r == nil {
			continue
		}
		if d.volleyCooldown > 0 {
			d.volleyCooldown--
			continue
		}
		if d.Routed || d.State == StateRetreating || d.movedTick > 0 || g.engaged(d.ID) {
			continue
		}
		t := g.volleyTarget(d, r.Range)
		if t == nil {
			continue
		}
		d.Facing = math.Atan2(t.Position.Y-d.Position.Y, t.Position.X-d.Position.X)
		g.volley(d, t, r)
		d.volleyCooldown = g.Rules.CombatRoundTicks
	}
}

// volleyTarget is the attack target if it is in range, otherwise the
// closest enemy in range.
func (g *Game) volleyTarget(d *Division, reach float64) *Division {
	if d.orderType() == OrderAttack {
		if t := g.divisions[d.CurrentOrder.TargetDivisionID]; t != nil && t.Alive() && d.Position.Dist(t.Position) <= reach {
			return t
		}
	}
	var best *Division
	bestDist := reach
	for _, o := range g.divisionOrder {
		if o.Alive() && o.PlayerID != d.PlayerID {
			if dist := d.Position.Dist(o.Position); dist <= bestDist {
				best, bestDist = o, dist
			}
		}
	}
	return best
}

func (g *Game) volley(d, t *Division, r *Ranged) {
	shooter := g.combatant(d, t)
	shooter.Attack = r.Attack
	shooter.Stance = combat.StanceHolding
	victim := g.combatant(t, d)
	side := g.exposure(t, d)
	res := g.engine.ResolveVolley(shooter, victim)
	g.applySide(t, res)
	d.Experience = clamp(d.Experience+g.Rules.Combat.ExperiencePerRound*0.5, 0, 100)
	g.emit(Volley{At: g.CurrentTick, ShooterID: d.ID, TargetID: t.ID, Losses: res.Losses, UnitCount: t.UnitCount,
		Exposure: side, From: d.Position, To: t.Position})
	switch {
	case t.UnitCount <= g.Rules.DestroyedUnitThreshold:
		g.destroy(t, "")
	case !t.Routed && t.Morale <= g.Rules.RoutMoraleThreshold:
		g.rout(t)
	}
}
