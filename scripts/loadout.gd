extends RefCounted
## Loadouts: the guns, attachments, camos and perks you can pick in the pause menu, the four loadouts you
## build from them (one per gun category: rifle, pistol, SMG, shotgun), and the settings, all saved to
## user://loadout.cfg. stats() turns a loadout into the numbers the player actually uses.
## In King of the Hood each round's category picks the loadout (for_kind); the EQUIPPED one is what you
## carry in Team Deathmatch.
## Menu art is optional: drop a PNG in assets/ui/<kind>/<id>.png (see assets/ui/README.txt) and the menu
## shows it instead of its placeholder.

const SAVE := "user://loadout.cfg"
const ART := "res://assets/ui/%s/%s.png"

const Guns = preload("res://scripts/guns.gd")

# the loadouts, in menu order: [gun category (guns.gd), label]
const CATEGORIES := [["rifle", "RIFLE"], ["pistol", "PISTOL"], ["smg", "SMG"], ["shotgun", "SHOTGUN"]]

# every gun, by category. Pistols carry their own numbers (and use the Glock model in hand until their own
# model arrives); the long guns take theirs from guns.gd (STATS[category]). New guns go in here.
# Each gun has its own shot sounds: "sound" up close (your own gun, or anyone near you) and "sound_far"
# for someone else's shots further than NEAR_SOUND_DIST off (shot_sound picks).
const WEAPONS := {
	"drako": {"name": "DRAKO", "category": "rifle", "caliber": "7.62x39", "kind": "Assault rifle",
		"sound": "res://assets/audio/rifle_near.wav", "sound_far": "res://assets/audio/rifle_far.wav"},
	"mak": {"name": "MAK", "category": "smg", "caliber": ".45 ACP", "kind": "Machine pistol",
		"sound": "res://assets/audio/smg_near.wav", "sound_far": "res://assets/audio/smg_far.wav"},
	"ricky": {"name": "RICKY", "category": "shotgun", "caliber": "12 gauge", "kind": "Double-barrel",
		"sound": "res://assets/audio/shotgun_near.wav", "sound_far": "res://assets/audio/shotgun_far.wav"},
	"glock": {"name": "GLIZZY", "category": "pistol", "caliber": "9mm", "kind": "Semi-auto pistol",
		"damage": 34.0, "interval": 0.15, "mag": 15, "reserve": 90, "reload": 1.5, "recoil": 1.0, "spread": 1.0, "mobility": 1.0,
		"sound": "res://assets/audio/pistol_fp.wav", "sound_far": "res://assets/audio/pistol_far.wav", "volume": 1.0}, # (volume: dB on the shot in your own hand)
	"ppq": {"name": "PPQ 9", "category": "pistol", "caliber": "9mm", "kind": "Striker pistol",
		"damage": 32.0, "interval": 0.13, "mag": 17, "reserve": 102, "reload": 1.6, "recoil": 0.9, "spread": 0.9, "mobility": 0.97,
		"sound": "res://assets/audio/ppq.wav", "sound_far": "res://assets/audio/pistol_far.wav"},
	"compact": {"name": ".380 COMPACT", "category": "pistol", "caliber": ".380 ACP", "kind": "Pocket pistol",
		"damage": 26.0, "interval": 0.11, "mag": 13, "reserve": 91, "reload": 1.3, "recoil": 0.7, "spread": 1.15, "mobility": 1.08,
		"sound": "res://assets/audio/compact380.wav", "sound_far": "res://assets/audio/pistol_far.wav"},
	"snub": {"name": ".38 SNUB", "category": "pistol", "caliber": ".38 Special", "kind": "Revolver",
		"damage": 52.0, "interval": 0.36, "mag": 6, "reserve": 48, "reload": 2.3, "recoil": 1.55, "spread": 1.1, "mobility": 1.04,
		"sound": "res://assets/audio/snub38.wav", "sound_far": "res://assets/audio/pistol_far.wav"},
}

# multipliers on the pistol's numbers ("damage", "interval", "mag", "reload", "recoil", "spread", "mobility"),
# plus "volume" (dB on the shot) and "flash" (muzzle flash size, 0 = none)
const ATTACHMENTS := {
	"optic": [
		{"id": "none", "name": "IRON SIGHTS", "desc": "Factory sights."},
		{"id": "reddot", "name": "RED DOT", "desc": "Reflex sight: aim down a red dot instead of the irons. A clearer picture and a little steadier aim.", "spread": 0.95},
	],
	"muzzle": [
		{"id": "none", "name": "NO MUZZLE", "desc": "Factory barrel."},
		{"id": "comp", "name": "COMPENSATOR", "desc": "Vents gas up to fight the kick. Bigger flash.", "recoil": 0.8, "flash": 1.4},
		{"id": "suppressor", "name": "SUPPRESSOR", "desc": "Quiet shots and no flash, at the cost of a little damage.", "damage": 0.9, "volume": -11.0, "flash": 0.0, "mobility": 0.95},
	],
	"magazine": [
		{"id": "none", "name": "STANDARD MAG", "desc": "Factory magazine."},
		{"id": "extended", "name": "EXTENDED MAG", "desc": "50% more rounds. Slower reload, heavier.", "mag": 1.5, "reload": 1.2, "mobility": 0.96},
		{"id": "fastmag", "name": "FAST MAG", "desc": "Taped for quick swaps: reloads 30% faster.", "reload": 0.7},
	],
	"laser": [
		{"id": "none", "name": "NO LASER", "desc": "Nothing under the barrel."},
		{"id": "laser", "name": "LASER SIGHT", "desc": "Visible beam. Tighter hip fire spread, and 25% less hip fire recoil while it's on (T / D-pad left).", "spread": 0.7},
		{"id": "light", "name": "WEAPON LIGHT", "desc": "Steadies the grip: less recoil, a bit slower.", "recoil": 0.9, "mobility": 0.97},
	],
	"trigger": [
		{"id": "none", "name": "STOCK TRIGGER", "desc": "Factory trigger."},
		{"id": "match", "name": "MATCH TRIGGER", "desc": "Light, short pull: fire faster.", "interval": 0.85, "recoil": 1.08},
		{"id": "heavy", "name": "HEAVY TRIGGER", "desc": "Slower to fire but easier to control.", "interval": 1.12, "recoil": 0.85},
	],
}
const SLOTS := ["optic", "muzzle", "magazine", "laser", "trigger"]


static func slots_for(_category: String) -> Array:
	return SLOTS # every gun takes every attachment


static func options(_category: String, slot: String) -> Array:
	return ATTACHMENTS[slot]



# gun color: tint on the Glock's texture, how metallic and how rough it is
const CAMOS := [
	{"id": "factory", "name": "FACTORY", "color": Color(1, 1, 1), "metal": -1.0, "rough": -1.0},
	{"id": "blackout", "name": "BLACKOUT", "color": Color(0.25, 0.25, 0.27), "metal": 0.4, "rough": 0.75},
	{"id": "tan", "name": "DESERT TAN", "color": Color(0.82, 0.68, 0.48), "metal": 0.1, "rough": 0.85},
	{"id": "od", "name": "OD GREEN", "color": Color(0.42, 0.47, 0.3), "metal": 0.1, "rough": 0.85},
	{"id": "blue", "name": "CREW BLUE", "color": Color(0.25, 0.42, 0.95), "metal": 0.3, "rough": 0.5},
	{"id": "red", "name": "CANDY RED", "color": Color(0.9, 0.12, 0.12), "metal": 0.6, "rough": 0.3},
	{"id": "chrome", "name": "CHROME", "color": Color(1.6, 1.6, 1.65), "metal": 1.0, "rough": 0.12},
	{"id": "gold", "name": "GOLD", "color": Color(1.6, 1.15, 0.45), "metal": 1.0, "rough": 0.2},
]

const PERKS := [ # three slots, pick one from each
	[
		{"id": "lightweight", "name": "LIGHTWEIGHT", "desc": "Move 8% faster.", "speed": 1.08},
		{"id": "quickfix", "name": "QUICK FIX", "desc": "Health starts coming back 2 seconds sooner.", "regen": -2.0},
	],
	[
		{"id": "sleight", "name": "SLEIGHT OF HAND", "desc": "Reload 35% faster.", "reload": 0.65},
		{"id": "steady", "name": "STEADY AIM", "desc": "25% tighter hip fire.", "spread": 0.75},
	],
	[
		{"id": "stopping", "name": "STOPPING POWER", "desc": "10% more damage.", "damage": 1.1},
		{"id": "marathon", "name": "MARATHON", "desc": "Sprint 12% faster.", "sprint": 1.12},
	],
]

const NEAR_SOUND_DIST := 20.0 # someone else's shots closer than this (m) use their gun's close-up sound
const CLASS_COUNT := 4 # one loadout per category

static var classes: Array = [] # in CATEGORIES order: [{name, category, weapon, muzzle, magazine, laser, trigger, camo, perks: [id, id, id]}]
static var active := 1 # the equipped loadout (Team Deathmatch); starts on the pistol
static var settings := {"sens": 1.0, "stick": 1.0, "invert": false, "fov": 78.0, "volume": 1.0, "fps": true, "mode": "koth", "map": "projects",
	"big_teams": true} # big_teams: King of the Hood 8 v 8 (off: 4 v 4, easier on a laptop)


static func guns_in(category: String) -> Array:
	return WEAPONS.keys().filter(func(id): return WEAPONS[id].category == category)


static func default_class(i: int) -> Dictionary:
	var cat: String = CATEGORIES[i][0]
	return {"name": CATEGORIES[i][1], "category": cat, "weapon": guns_in(cat)[0], "muzzle": "none", "magazine": "none",
		"optic": "none", "laser": "none", "trigger": "none", "camo": "factory", "perks": [PERKS[0][0].id, PERKS[1][0].id, PERKS[2][0].id]}


static func load_all() -> void:
	if not classes.is_empty():
		return
	var cf := ConfigFile.new()
	var ok := cf.load(SAVE) == OK
	for i in CLASS_COUNT:
		var c := default_class(i)
		var sec: String = "loadout_" + c.category
		if ok:
			for k in ["weapon", "optic", "muzzle", "magazine", "laser", "trigger", "camo", "perks"]:
				c[k] = cf.get_value(sec, k, c[k])
		if not WEAPONS.has(c.weapon) or WEAPONS[c.weapon].category != c.category:
			c.weapon = guns_in(c.category)[0]
		classes.append(c)
	if ok:
		active = clampi(cf.get_value("loadout", "equipped", active), 0, CLASS_COUNT - 1)
		for k in settings.keys():
			settings[k] = cf.get_value("settings", k, settings[k])


static func save_all() -> void:
	var cf := ConfigFile.new()
	for c in classes:
		for k in c.keys():
			cf.set_value("loadout_" + c.category, k, c[k])
	cf.set_value("loadout", "equipped", active)
	for k in settings.keys():
		cf.set_value("settings", k, settings[k])
	cf.save(SAVE)


static func current() -> Dictionary:
	load_all()
	return classes[active]


static func for_kind(category: String) -> Dictionary:
	# the loadout for a gun category (King of the Hood hands out a category each round)
	load_all()
	for c in classes:
		if c.category == category:
			return c
	return classes[active]


static func weapon(id: String) -> Dictionary:
	# a gun's menu info and base numbers: a pistol's own, a long gun's from guns.gd
	var w: Dictionary = WEAPONS.get(id, WEAPONS.glock)
	if w.category == "pistol":
		return w
	var g: Dictionary = Guns.STATS[w.category]
	var out := w.duplicate()
	for k in ["damage", "interval", "mag", "reserve", "reload", "recoil", "spread", "mobility", "auto", "sound_pitch", "volume"]:
		out[k] = g[k]
	for k in ["pellets", "cone"]:
		if g.has(k):
			out[k] = g[k]
	return out


static func shot_sound(id: String, dist: float) -> AudioStream:
	# the sound of a shot from gun id heard dist meters off: its close-up recording near, its far one beyond
	var w: Dictionary = WEAPONS.get(id, WEAPONS.glock)
	var path: String = w.sound if dist < NEAR_SOUND_DIST else w.get("sound_far", w.sound)
	if not _sounds.has(path):
		_sounds[path] = load(path)
	return _sounds[path]


static var _sounds := {}


static func attachment(slot: String, id: String) -> Dictionary:
	for a in ATTACHMENTS[slot]:
		if a.id == id:
			return a
	return ATTACHMENTS[slot][0]


static func camo(id: String) -> Dictionary:
	for c in CAMOS:
		if c.id == id:
			return c
	return CAMOS[0]


static func perk(slot: int, id: String) -> Dictionary:
	for p in PERKS[slot]:
		if p.id == id:
			return p
	return PERKS[slot][0]


static func stats(c: Dictionary) -> Dictionary:
	# the final numbers for a loadout: the gun's, times every attachment's and perk's change
	var w := weapon(c.weapon)
	var pistol: bool = w.category == "pistol"
	var s := {"damage": w.damage, "interval": w.interval, "mag": float(w.mag), "reserve": w.reserve, "reload": w.reload,
		"recoil": w.recoil, "spread": w.spread, "mobility": w.mobility, "volume": w.get("volume", 0.0),
		"flash": 1.0 if pistol else 1.3, "speed": 1.0, "sprint": 1.0, "regen": 0.0, "sound": w.sound, "name": w.name,
		"auto": w.get("auto", false), "pellets": w.get("pellets", 1), "cone": w.get("cone", 0.0),
		"sound_pitch": w.get("sound_pitch", 1.0)}
	var mods: Array = []
	for slot in slots_for(w.category):
		mods.append(attachment(slot, c.get(slot, "none")))
	for i in PERKS.size():
		mods.append(perk(i, c.perks[i] if i < c.perks.size() else ""))
	for m in mods:
		for k in ["damage", "interval", "mag", "reload", "recoil", "spread", "mobility", "speed", "sprint"]:
			if m.has(k):
				s[k] *= m[k]
		if m.has("flash"):
			s.flash *= m.flash
		s.volume += m.get("volume", 0.0)
		s.regen += m.get("regen", 0.0)
	s.mag = roundi(s.mag)
	return s


static func bars(s: Dictionary) -> Array:
	# the six stat bars on the menus, each 0..1: [label, value]
	return [
		["DAMAGE", clampf(s.damage * s.get("pellets", 1) / 60.0, 0.0, 1.0)], # (a shotgun: all its pellets)
		["FIRE RATE", clampf(0.06 / s.interval * 1.6, 0.0, 1.0)],
		["CONTROL", clampf(1.0 - (s.recoil - 0.5) / 1.3, 0.0, 1.0)],
		["ACCURACY", clampf(1.0 - (s.spread - 0.5) / 0.9, 0.0, 1.0)],
		["MOBILITY", clampf((s.mobility * s.speed - 0.85) / 0.3, 0.0, 1.0)],
		["RELOAD", clampf(1.0 - (s.reload - 0.8) / 2.0, 0.0, 1.0)],
	]


static func art(kind: String, id: String) -> Texture2D:
	var p := ART % [kind, id]
	return load(p) if ResourceLoader.exists(p) else null
