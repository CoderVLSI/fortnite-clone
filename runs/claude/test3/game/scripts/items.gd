## Item, weapon, rarity and ammo data for the match.
class_name Items
extends RefCounted

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const RARITY_COLORS := [Color(0.72, 0.74, 0.76), Color(0.35, 0.8, 0.25), Color(0.25, 0.6, 1.0), Color(0.72, 0.35, 0.95), Color(1.0, 0.75, 0.2)]
const AMMO_TYPES := ["light", "medium", "heavy", "shells", "rockets"]
const AMMO_COLORS := {"light": Color(0.95, 0.85, 0.5), "medium": Color(0.9, 0.6, 0.3), "heavy": Color(0.6, 0.75, 0.95), "shells": Color(0.9, 0.3, 0.25), "rockets": Color(0.55, 0.7, 0.35)}
const AMMO_PICKUP := {"light": 24, "medium": 30, "heavy": 8, "shells": 8, "rockets": 3}
const SLOTS := 5
const MAT_NAMES := {"wood": "Wood", "brick": "Brick", "metal": "Metal"}
const MAT_COLORS := {"wood": Color(0.85, 0.6, 0.3), "brick": Color(0.88, 0.42, 0.32), "metal": Color(0.62, 0.7, 0.82)}

## kind: weapon | throwable | heal | shield
## Weapons: damage per hit, shots per second, magazine, reload seconds, spread in degrees, effective range in metres.
const DEFS := {
	"pistol": {"name": "Pistol", "kind": "weapon", "asset": "pistol", "ammo": "light", "damage": 24.0, "rate": 6.0, "mag": 16, "reload": 1.5, "spread": 1.6, "range": 60.0, "pellets": 1, "auto": false, "bloom": 0.35},
	"shotgun": {"name": "Pump Shotgun", "kind": "weapon", "asset": "shotgun", "ammo": "shells", "damage": 10.0, "rate": 0.95, "mag": 5, "reload": 4.2, "spread": 5.5, "range": 28.0, "pellets": 9, "auto": false},
	"assault_rifle": {"name": "Assault Rifle", "kind": "weapon", "asset": "assault_rifle", "ammo": "medium", "damage": 30.0, "rate": 5.5, "mag": 30, "reload": 2.3, "spread": 1.3, "range": 110.0, "pellets": 1, "auto": true, "bloom": 0.2},
	"sniper_rifle": {"name": "Bolt Sniper", "kind": "weapon", "asset": "sniper_rifle", "ammo": "heavy", "damage": 105.0, "rate": 0.4, "mag": 1, "reload": 2.6, "spread": 0.15, "range": 320.0, "pellets": 1, "auto": false},
	"rocket_launcher": {"name": "Rocket Launcher", "kind": "weapon", "asset": "rocket_launcher", "ammo": "rockets", "damage": 110.0, "rate": 0.75, "mag": 1, "reload": 3.2, "spread": 0.4, "range": 140.0, "pellets": 1, "auto": false, "rocket": true, "radius": 5.5},
	"grenade": {"name": "Grenade", "kind": "throwable", "asset": "grenade", "stack": 6, "damage": 100.0, "radius": 5.5},
	"medkit": {"name": "Med Kit", "kind": "heal", "asset": "medkit", "stack": 3, "amount": 100.0, "use_time": 6.0, "cap": 100.0},
	"shield_potion": {"name": "Big Shield", "kind": "shield", "asset": "shield_potion", "stack": 3, "amount": 50.0, "use_time": 4.0, "cap": 100.0},
	"small_shield": {"name": "Small Shield", "kind": "shield", "asset": "small_shield", "stack": 6, "amount": 25.0, "use_time": 2.0, "cap": 50.0},
	"healing_drink": {"name": "Healing Drink", "kind": "heal", "asset": "healing_drink", "stack": 2, "amount": 50.0, "use_time": 2.5, "cap": 100.0},
	"launch_pad": {"name": "Launch Pad", "kind": "launcher", "asset": "launch_pad", "stack": 1},
}
const WEAPON_IDS := ["pistol", "shotgun", "assault_rifle", "sniper_rifle", "rocket_launcher"]


static func make(id: String, rarity := 0, count := 1) -> Dictionary:
	var d: Dictionary = DEFS[id]
	var fixed := {"shield_potion": 2, "medkit": 1, "small_shield": 1, "healing_drink": 2, "launch_pad": 3}
	var it := {"id": id, "rarity": rarity if d.kind == "weapon" else int(fixed.get(id, 0)), "count": count}
	if d.kind == "weapon":
		it["loaded"] = d.mag
	return it


static func def(it: Dictionary) -> Dictionary:
	return DEFS[it.id]


## Each rarity step adds 6 % damage and makes reloads 5 % faster.
static func damage(it: Dictionary) -> float:
	return DEFS[it.id].damage * (1.0 + 0.06 * it.rarity)


static func reload_time(it: Dictionary) -> float:
	return DEFS[it.id].reload * (1.0 - 0.05 * it.rarity)


static func label(it: Dictionary) -> String:
	var d: Dictionary = DEFS[it.id]
	return ("%s %s" % [RARITY_NAMES[it.rarity], d.name]) if d.kind == "weapon" else d.name


static func roll_rarity(rng: RandomNumberGenerator, bonus := 0.0) -> int:
	var r := rng.randf() - bonus
	if r < 0.03: return 4
	if r < 0.11: return 3
	if r < 0.28: return 2
	if r < 0.58: return 1
	return 0


static func roll_weapon(rng: RandomNumberGenerator, bonus := 0.0) -> Dictionary:
	var weights := {"pistol": 26, "shotgun": 24, "assault_rifle": 28, "sniper_rifle": 13, "rocket_launcher": 9}
	var total := 0
	for k in weights: total += weights[k]
	var pick := rng.randi() % total
	for k in weights:
		pick -= weights[k]
		if pick < 0:
			return make(k, roll_rarity(rng, bonus))
	return make("pistol")


static func roll_floor(rng: RandomNumberGenerator) -> Dictionary:
	## What lies on a floor loot spot.
	var r := rng.randf()
	if r < 0.50: return roll_weapon(rng)
	if r < 0.59: return make("medkit")
	if r < 0.67: return make("shield_potion")
	if r < 0.75: return make("small_shield", 0, 2)
	if r < 0.80: return make("healing_drink")
	if r < 0.86: return make("grenade", 0, 2)
	if r < 0.89: return make("launch_pad")
	return {"ammo": AMMO_TYPES[rng.randi() % 5]}
