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
# where the attachments go (add_parts): barrel tip, under the dust cover, the magazine's base, the slide top
const MOUNTS := {"muzzle": MUZZLE, "under": Vector3(0, 0.043, -0.135), "mag": Vector3(0, -0.045, 0.006),
	"top": Vector3(0, 0.092, -0.035)}

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
	var layers: int = holder.get_child(0).find_children("*", "MeshInstance3D", true, false)[0].layers
	add_parts(holder, parts, MOUNTS, 1.0, layers)


static func add_parts(node: Node3D, parts: Dictionary, at: Dictionary, k: float, layers: int) -> void:
	# the attachments that show, on any gun: at holds the gun's mount spots in node's space ("muzzle",
	# "under" for the laser or light, "mag" for the bottom of the magazine, "top" for the optic's base) and
	# k sizes the parts to the gun. A spot the gun doesn't have leaves that part off; "own_suppressor" means
	# the gun has its own suppressor model (guns.gd shows it instead)
	for n in node.get_children():
		if n.has_meta("attachment"):
			n.free()
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.05, 0.055)
	dark.metallic = 0.6
	dark.roughness = 0.45
	var muzzle: Vector3 = at.get("muzzle", Vector3.ZERO)
	match parts.get("muzzle", "none"):
		"suppressor":
			if not at.get("own_suppressor", false):
				_part(node, _cyl(0.0192 * k, 0.14 * k), muzzle + Vector3(0, 0, -0.068 * k), dark, layers)
		"comp":
			_part(node, _box(Vector3(0.036, 0.034, 0.04) * k), muzzle + Vector3(0, 0, -0.018 * k), dark, layers)
	if at.has("under"):
		var under: Vector3 = at.under
		match parts.get("laser", "none"):
			"laser":
				_part(node, _box(Vector3(0.028, 0.026, 0.06) * k), under, dark, layers)
				var dot := StandardMaterial3D.new()
				dot.albedo_color = Color(1, 0.1, 0.1)
				dot.emission_enabled = true
				dot.emission = Color(1, 0.05, 0.05)
				dot.emission_energy_multiplier = 4.0
				_part(node, _cyl(0.005 * k, 0.004), under + Vector3(0, 0, -0.031 * k), dot, layers)
				# the beam: 1 unit long out the front; player.gd stretches it to whatever it hits
				var ray := StandardMaterial3D.new()
				ray.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				ray.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				ray.albedo_color = Color(1, 0.12, 0.1, 0.6)
				ray.cull_mode = BaseMaterial3D.CULL_DISABLED
				var beam := _part(node, _cyl(0.0014, 1.0, -0.5), under + Vector3(0, 0, -0.033 * k), ray, layers)
				beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				beam.set_meta("beam", true)
			"light":
				_part(node, _cyl(0.017 * k, 0.07 * k), under + Vector3(0, -0.003 * k, -0.005 * k), dark, layers)
	if parts.get("magazine", "none") == "extended" and at.has("mag"):
		_part(node, _box(Vector3(0.026, 0.05, 0.034) * k), at.mag, dark, layers)
	if parts.get("optic", "none") == "reddot" and at.has("top"):
		_red_dot(node, at.top, k, dark, layers)


static func dot_height(k: float) -> float:
	# the red dot's window center above its mount (the sight line when aiming through it)
	return (RED_DOT_BASE + RED_DOT_WINDOW * 0.5 + RED_DOT_FRAME) * k


const RED_DOT_BASE := 0.008 # mount block height
const RED_DOT_WINDOW := 0.026 # window size (square)
const RED_DOT_FRAME := 0.004 # frame thickness
const RED_DOT_LENGTH := 0.032


static func _red_dot(node: Node3D, top: Vector3, k: float, dark: Material, layers: int) -> void:
	# a small open reflex sight: mount, a frame round a square window, tinted glass, and the dot in the middle
	var w := RED_DOT_WINDOW * k
	var f := RED_DOT_FRAME * k
	var b := RED_DOT_BASE * k
	var l := RED_DOT_LENGTH * k
	_part(node, _box(Vector3(w * 0.8, b, l * 1.2)), top + Vector3(0, b * 0.5, 0), dark, layers)
	var mid := top + Vector3(0, b + f + w * 0.5, 0)
	for side in [-1.0, 1.0]:
		_part(node, _box(Vector3(f, w + f * 2.0, l)), mid + Vector3(side * (w + f) * 0.5, 0, 0), dark, layers)
	_part(node, _box(Vector3(w + f * 2.0, f, l)), mid + Vector3(0, (w + f) * 0.5, 0), dark, layers)
	_part(node, _box(Vector3(w + f * 2.0, f, l)), mid - Vector3(0, (w + f) * 0.5, 0), dark, layers)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.55, 0.75, 0.9, 0.12)
	glass.metallic = 0.2
	glass.roughness = 0.05
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(w, w)
	_part(node, q, mid + Vector3(0, 0, -l * 0.4), glass, layers)
	var dot := StandardMaterial3D.new()
	dot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot.albedo_color = Color(1, 0.08, 0.06)
	var s := SphereMesh.new()
	s.radius = 0.0011 * k
	s.height = 0.0022 * k
	s.radial_segments = 8
	s.rings = 4
	var d := _part(node, s, mid + Vector3(0, 0, -l * 0.4), dot, layers)
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _part(node: Node3D, mesh: Mesh, pos: Vector3, mat: Material, layers: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.set_meta("attachment", true)
	mi.layers = layers
	node.add_child(mi)
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
