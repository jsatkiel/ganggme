extends RefCounted
## The four gun categories for King of the Hood rounds: pistol, shotgun, rifle, SMG. Each round every slot on
## a team carries one (2 of each per team of 8) and the categories rotate between rounds, so in any 4 rounds
## everyone uses all four. The pistol is whatever your loadout class carries; the other three use the numbers
## here and the user's models: RICKY the double-barrel, an AK-47 and a MAC-10, baked by tools/bake_guns.gd with
## the barrel along -Z, top up and the right hand's grip on the origin, like the Glock (pistol.gd).
## The AK and RICKY are held with both hands: SUPPORT is where the left hand takes the front.

const ORDER := ["pistol", "shotgun", "rifle", "smg"]

# damage per bullet (per pellet for the shotgun); falloff: damage multiplier reached by "far" meters, starting
# at "near"; recoil and spread are multipliers on the pistol's feel; auto: hold the trigger to keep firing.
# bot_*: how the bots use it (damage per hit, time between shots in a burst, burst length, pause after a burst,
# hit chance up close, and the range they try to fight at)
const STATS := {
	"pistol": {"name": "PISTOL", "sound_pitch": 1.0,
		"bot_damage": 9.0, "bot_interval": [0.26, 0.4], "bot_burst": [2, 5], "bot_pause": [0.6, 1.1], "bot_accuracy": 0.5, "bot_range": 30.0},
	"shotgun": {"name": "RICKY", "damage": 16.0, "pellets": 8, "cone": 0.07, "interval": 0.3, "mag": 2, "reserve": 24,
		"reload": 2.0, "recoil": 2.6, "spread": 1.0, "mobility": 0.94, "auto": false, "near": 8.0, "far": 24.0, "falloff": 0.25,
		"sound_pitch": 0.62, "volume": 3.0,
		"bot_damage": 30.0, "bot_interval": [0.9, 1.2], "bot_burst": [1, 2], "bot_pause": [0.9, 1.3], "bot_accuracy": 0.75, "bot_range": 9.0},
	"rifle": {"name": "ASSAULT RIFLE", "damage": 28.0, "interval": 0.105, "mag": 30, "reserve": 120,
		"reload": 2.2, "recoil": 0.55, "spread": 0.75, "mobility": 0.9, "auto": true, "near": 60.0, "far": 120.0, "falloff": 0.8,
		"sound_pitch": 0.8, "volume": 1.0,
		"bot_damage": 7.0, "bot_interval": [0.1, 0.13], "bot_burst": [3, 6], "bot_pause": [0.5, 0.9], "bot_accuracy": 0.48, "bot_range": 45.0},
	"smg": {"name": "SMG", "damage": 21.0, "interval": 0.072, "mag": 32, "reserve": 160,
		"reload": 1.8, "recoil": 0.42, "spread": 1.25, "mobility": 1.04, "auto": true, "near": 18.0, "far": 40.0, "falloff": 0.6,
		"sound_pitch": 1.15, "volume": -1.0,
		"bot_damage": 5.5, "bot_interval": [0.07, 0.09], "bot_burst": [4, 9], "bot_pause": [0.5, 0.8], "bot_accuracy": 0.45, "bot_range": 18.0},
}

const MODEL := {
	"shotgun": "res://assets/props/ricky/ricky.res",
	"rifle": "res://assets/props/ak47/ak47.res",
	"smg": "res://assets/props/mac10/mac10.res",
}
# in the gun's space (barrel along -Z, top up, grip at the origin), like the Glock's in pistol.gd:
# barrel tip; top of the sights (the first-person view lines these up when aiming); where the left palm holds
const MUZZLE := {
	"shotgun": Vector3(0, 0.1, -0.575),
	"rifle": Vector3(0, 0.125, -0.67),
	"smg": Vector3(0, 0.1, -0.49),
}
const SIGHT_HEIGHT := {"shotgun": 0.12, "rifle": 0.179, "smg": 0.134}
const SUPPORT := {"shotgun": Vector3(0, 0.055, -0.36), "rifle": Vector3(0, 0.09, -0.39)}


static func for_slot(slot: int, round_num: int) -> String:
	# slots 0-1 start on the pistol, 2-3 the shotgun, 4-5 the rifle, 6-7 the SMG, and move up one category a round
	return ORDER[(slot / 2 + maxi(round_num - 1, 0)) % ORDER.size()]


static func damage_at(kind: String, base: float, dist: float) -> float:
	var s: Dictionary = STATS[kind]
	if not s.has("near"):
		return base
	var t := clampf((dist - s.near) / maxf(s.far - s.near, 0.01), 0.0, 1.0)
	return base * lerpf(1.0, s.falloff, t)


static func sight_height(kind: String) -> float:
	return SIGHT_HEIGHT.get(kind, 0.102) # (0.102: the Glock's, Pistol.SIGHT_HEIGHT)


static func show(holder: Node3D, kind: String, shadows := true) -> void:
	# puts the right gun in the hand: the Glock (child 0, with its attachments) for the pistol, else the long gun
	var pistol := kind == "pistol"
	for n in holder.get_children():
		if n.has_meta("long_gun"):
			n.visible = n.get_meta("long_gun") == kind
		elif not n.has_meta("muzzle"):
			n.visible = pistol
	if pistol:
		return
	for n in holder.get_children():
		if n.get_meta("long_gun", "") == kind:
			return
	var mi := MeshInstance3D.new()
	mi.mesh = load(MODEL[kind])
	mi.material_override = _mat(kind)
	mi.layers = holder.get_child(0).find_children("*", "MeshInstance3D", true, false)[0].layers
	mi.lod_bias = 100.0 # small in view: keep the full mesh
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("long_gun", kind)
	holder.add_child(mi)


static var _mats := {}


static func _mat(kind: String) -> StandardMaterial3D:
	# the FBX files don't carry their textures over: build each material from the texture set (RICKY has none,
	# its vertex colors paint the wooden grip and the metal)
	if not _mats.has(kind):
		var m := StandardMaterial3D.new()
		match kind:
			"smg":
				m.albedo_texture = load("res://assets/props/mac10/Mac10_BaseColor.png")
				m.metallic = 1.0
				m.metallic_texture = load("res://assets/props/mac10/Mac10_Metallic.png")
				m.roughness = 0.5
			"rifle":
				m.albedo_texture = load("res://assets/props/ak47/AK47_BaseColor.png")
				m.metallic = 1.0
				m.metallic_texture = load("res://assets/props/ak47/AK47_Metallic.png")
				m.roughness = 1.0
				m.roughness_texture = load("res://assets/props/ak47/AK47_Roughness.png")
			"shotgun":
				m.vertex_color_use_as_albedo = true
				m.vertex_color_is_srgb = true
				m.metallic = 0.4
				m.roughness = 0.45
		_mats[kind] = m
	return _mats[kind]
