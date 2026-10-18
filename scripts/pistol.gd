extends RefCounted
## The handgun everyone carries: Glock 17 (art supplied by the user, assets/props/glock17).
## make() returns a node with the barrel pointing -Z, top up, and the origin where the
## hand holds the grip. MUZZLE is the barrel tip in that node's space.

const MODEL := preload("res://assets/props/glock17/Glock17.fbx")
const TEX := "res://assets/props/glock17/Textures/Glock17_%s.png"
const SCALE := 3.42 # model is 6.5 cm long; sized up to fill the big crew hands
const OFFSET := Vector3(0, 0.026, -0.009) # puts the grip on the origin, same fit as the hand pose expects
const MUZZLE := Vector3(0, 0.083, -0.181)
const SIGHT_HEIGHT := 0.102 # top of the sights above the grip

static var _mat: StandardMaterial3D


static func make(shadows := true) -> Node3D:
	var holder := Node3D.new()
	var gun: Node3D = MODEL.instantiate()
	gun.scale = Vector3.ONE * SCALE
	gun.position = OFFSET
	holder.add_child(gun)
	for mi in gun.find_children("*", "MeshInstance3D", true, false):
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _material()
	return holder


static func dress(holder: Node3D, camo: Dictionary, parts: Dictionary) -> void:
	# loadout look: recolor the gun for its camo and put on the attachments that show
	# (camo: a Loadout.CAMOS entry; parts: slot -> attachment id)
	var m: StandardMaterial3D = _material()
	if camo.get("id", "factory") != "factory":
		m = _material().duplicate()
		m.albedo_color = camo.color
		if camo.metal >= 0.0:
			m.metallic_texture = null
			m.metallic = camo.metal
		if camo.rough >= 0.0:
			m.roughness_texture = null
			m.roughness = camo.rough
	for mi in holder.get_child(0).find_children("*", "MeshInstance3D", true, false): # the gun model, not the flash
		if not mi.has_meta("attachment"):
			mi.material_override = m
	for n in holder.get_children():
		if n.has_meta("attachment"):
			n.free()
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.05, 0.055)
	dark.metallic = 0.6
	dark.roughness = 0.45
	match parts.get("muzzle", "none"):
		"suppressor":
			_part(holder, _cyl(0.0192, 0.14), MUZZLE + Vector3(0, 0, -0.068), dark)
		"comp":
			_part(holder, _box(Vector3(0.036, 0.034, 0.04)), MUZZLE + Vector3(0, 0, -0.018), dark)
	match parts.get("laser", "none"):
		"laser":
			_part(holder, _box(Vector3(0.028, 0.026, 0.06)), Vector3(0, 0.043, -0.135), dark)
			var dot := StandardMaterial3D.new()
			dot.albedo_color = Color(1, 0.1, 0.1)
			dot.emission_enabled = true
			dot.emission = Color(1, 0.05, 0.05)
			dot.emission_energy_multiplier = 4.0
			_part(holder, _cyl(0.005, 0.004), Vector3(0, 0.043, -0.166), dot)
			# the beam: 1 unit long out the front; player.gd stretches it to whatever it hits
			var ray := StandardMaterial3D.new()
			ray.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ray.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ray.albedo_color = Color(1, 0.12, 0.1, 0.6)
			ray.cull_mode = BaseMaterial3D.CULL_DISABLED
			var beam := _part(holder, _cyl(0.0014, 1.0, -0.5), Vector3(0, 0.043, -0.168), ray)
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			beam.set_meta("beam", true)
		"light":
			_part(holder, _cyl(0.017, 0.07), Vector3(0, 0.04, -0.14), dark)
	if parts.get("magazine", "none") == "extended":
		_part(holder, _box(Vector3(0.026, 0.05, 0.034)), Vector3(0, -0.045, 0.006), dark)


static func _part(holder: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.set_meta("attachment", true)
	mi.layers = holder.get_child(0).find_children("*", "MeshInstance3D", true, false)[0].layers if holder.get_child_count() > 0 else 1
	holder.add_child(mi)
	return mi


static func _cyl(radius: float, length: float, shift := 0.0) -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = length
	c.radial_segments = 14
	c.rings = 1
	var st := SurfaceTool.new() # turned to lie along the barrel (-Z)
	st.append_from(c, 0, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, shift)))
	return st.commit()


static func _box(size: Vector3) -> Mesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _material() -> StandardMaterial3D:
	# the FBX doesn't carry its textures over, so build the PBR material from the texture set
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_texture = load(TEX % "BaseColor")
		_mat.metallic = 1.0
		_mat.metallic_texture = load(TEX % "Metalness")
		_mat.roughness = 1.0
		_mat.roughness_texture = load(TEX % "Roughness")
		_mat.normal_enabled = true
		_mat.normal_texture = load(TEX % "Normal")
	return _mat
