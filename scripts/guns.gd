extends RefCounted
## The four gun categories for King of the Hood rounds: pistol, shotgun, rifle, SMG. Each round every slot on
## a team carries one (2 of each per team of 8) and the categories rotate between rounds, so in any 4 rounds
## everyone uses all four. The pistol is whatever your loadout class carries; the other three use the numbers
## here. Their models are placeholders built from boxes until the real gun art arrives: same grip spot and the
## same sight height as the Glock (pistol.gd), so the first-person aim lines up without refitting the arms.

const ORDER := ["pistol", "shotgun", "rifle", "smg"]

# damage per bullet (per pellet for the shotgun); falloff: damage multiplier reached by "far" meters, starting
# at "near"; recoil and spread are multipliers on the pistol's feel; auto: hold the trigger to keep firing.
# bot_*: how the bots use it (damage per hit, time between shots in a burst, burst length, pause after a burst,
# hit chance up close, and the range they try to fight at)
const STATS := {
	"pistol": {"name": "PISTOL", "sound_pitch": 1.0,
		"bot_damage": 9.0, "bot_interval": [0.26, 0.4], "bot_burst": [2, 5], "bot_pause": [0.6, 1.1], "bot_accuracy": 0.5, "bot_range": 30.0},
	"shotgun": {"name": "PUMP SHOTGUN", "damage": 13.0, "pellets": 8, "cone": 0.07, "interval": 0.85, "mag": 6, "reserve": 30,
		"reload": 2.6, "recoil": 2.6, "spread": 1.0, "mobility": 0.94, "auto": false, "near": 8.0, "far": 24.0, "falloff": 0.25,
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

# barrel tip in the gun's space (barrel along -Z, top up, grip at the origin), like Pistol.MUZZLE
const MUZZLE := {
	"shotgun": Vector3(0, 0.072, -0.68),
	"rifle": Vector3(0, 0.07, -0.66),
	"smg": Vector3(0, 0.07, -0.36),
}


static func for_slot(slot: int, round_num: int) -> String:
	# slots 0-1 start on the pistol, 2-3 the shotgun, 4-5 the rifle, 6-7 the SMG, and move up one category a round
	return ORDER[(slot / 2 + maxi(round_num - 1, 0)) % ORDER.size()]


static func damage_at(kind: String, base: float, dist: float) -> float:
	var s: Dictionary = STATS[kind]
	if not s.has("near"):
		return base
	var t := clampf((dist - s.near) / maxf(s.far - s.near, 0.01), 0.0, 1.0)
	return base * lerpf(1.0, s.falloff, t)


static func show(holder: Node3D, kind: String, shadows := true) -> void:
	# puts the right gun in the hand: the Glock (child 0, with its attachments) for the pistol, else a placeholder
	var pistol := kind == "pistol"
	for n in holder.get_children():
		if n.has_meta("placeholder"):
			n.visible = n.get_meta("placeholder") == kind
		elif not n.has_meta("muzzle"):
			n.visible = pistol
	if pistol:
		return
	for n in holder.get_children():
		if n.get_meta("placeholder", "") == kind:
			return
	var model := _build(kind, holder.get_child(0).find_children("*", "MeshInstance3D", true, false)[0].layers)
	model.set_meta("placeholder", kind)
	holder.add_child(model)
	if not shadows:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static var _mats := {}


static func _mat(id: String) -> StandardMaterial3D:
	if not _mats.has(id):
		var m := StandardMaterial3D.new()
		match id:
			"metal":
				m.albedo_color = Color(0.07, 0.07, 0.075)
				m.metallic = 0.7
				m.roughness = 0.4
			"polymer":
				m.albedo_color = Color(0.11, 0.11, 0.115)
				m.roughness = 0.75
			"wood":
				m.albedo_color = Color(0.36, 0.2, 0.1)
				m.roughness = 0.6
		_mats[id] = m
	return _mats[id]


static func _build(kind: String, layers: int) -> Node3D:
	# [part, size (x, y, z), center, material]; cylinders run along the barrel. Sights top out at y = 0.102.
	var parts: Array = []
	match kind:
		"shotgun":
			parts = [
				["box", Vector3(0.05, 0.07, 0.26), Vector3(0, 0.055, -0.07), "metal"], # receiver
				["cyl", Vector3(0.016, 0, 0.5), Vector3(0, 0.072, -0.43), "metal"], # barrel
				["cyl", Vector3(0.014, 0, 0.4), Vector3(0, 0.038, -0.38), "metal"], # magazine tube
				["box", Vector3(0.05, 0.045, 0.16), Vector3(0, 0.036, -0.34), "wood"], # pump
				["box", Vector3(0.036, 0.1, 0.05), Vector3(0, -0.035, 0.02), "wood"], # grip
				["box", Vector3(0.042, 0.075, 0.26), Vector3(0, 0.025, 0.17), "wood"], # stock
				["box", Vector3(0.008, 0.012, 0.01), Vector3(0, 0.096, -0.665), "metal"], # bead sight
			]
		"rifle":
			parts = [
				["box", Vector3(0.046, 0.075, 0.32), Vector3(0, 0.05, -0.08), "metal"], # receiver
				["box", Vector3(0.05, 0.055, 0.2), Vector3(0, 0.06, -0.33), "polymer"], # handguard
				["cyl", Vector3(0.011, 0, 0.16), Vector3(0, 0.07, -0.5), "metal"], # barrel
				["box", Vector3(0.012, 0.03, 0.02), Vector3(0, 0.087, -0.42), "metal"], # front sight
				["box", Vector3(0.016, 0.03, 0.03), Vector3(0, 0.087, 0.03), "metal"], # rear sight
				["box", Vector3(0.032, 0.13, 0.06), Vector3(0, -0.03, -0.17), "polymer"], # magazine
				["box", Vector3(0.034, 0.1, 0.045), Vector3(0, -0.035, 0.02), "polymer"], # grip
				["box", Vector3(0.04, 0.07, 0.24), Vector3(0, 0.035, 0.18), "polymer"], # stock
			]
		"smg":
			parts = [
				["box", Vector3(0.044, 0.07, 0.24), Vector3(0, 0.05, -0.08), "metal"], # receiver
				["cyl", Vector3(0.012, 0, 0.14), Vector3(0, 0.07, -0.27), "metal"], # barrel
				["box", Vector3(0.014, 0.025, 0.02), Vector3(0, 0.09, -0.18), "metal"], # front sight
				["box", Vector3(0.016, 0.025, 0.02), Vector3(0, 0.09, 0.02), "metal"], # rear sight
				["box", Vector3(0.03, 0.15, 0.04), Vector3(0, -0.045, -0.12), "polymer"], # magazine
				["box", Vector3(0.034, 0.1, 0.045), Vector3(0, -0.035, 0.02), "polymer"], # grip
				["box", Vector3(0.012, 0.05, 0.18), Vector3(0, 0.04, 0.14), "metal"], # wire stock
			]
	var root := Node3D.new()
	for p in parts:
		var mesh: Mesh
		if p[0] == "cyl":
			var c := CylinderMesh.new()
			c.top_radius = p[1].x
			c.bottom_radius = p[1].x
			c.height = p[1].z
			c.radial_segments = 12
			c.rings = 1
			var st := SurfaceTool.new() # turned to lie along the barrel (-Z)
			st.append_from(c, 0, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3.ZERO))
			mesh = st.commit()
		else:
			var b := BoxMesh.new()
			b.size = p[1]
			mesh = b
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _mat(p[3])
		mi.position = p[2]
		mi.layers = layers
		root.add_child(mi)
	return root
