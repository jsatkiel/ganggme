extends RefCounted
## Parked-car catalog: the car models the user picked (assets/cars2), each fitted to real size,
## turned so it runs down local +X (the game's car direction, nose = +X), set on the ground and painted.
## Every model ships in different units and with different material setups, so each entry says
## how long the car really is and how to paint it.

const DIR := "res://assets/cars2/"
const LiteMesh := preload("res://scripts/lite_mesh.gd")
const OPP_PAINTS := [
	Color(0.05, 0.05, 0.055), Color(0.55, 0.56, 0.58), Color(0.8, 0.8, 0.78), Color(0.32, 0.05, 0.06),
	Color(0.08, 0.12, 0.26), Color(0.16, 0.22, 0.17), Color(0.3, 0.28, 0.25), Color(0.4, 0.33, 0.24),
]
const CITY_COLORS := ["Black", "Blue", "Brown", "IceBlue", "OliveGreen", "Red", "White"]

# file, real length (m), paint: "body:<material>" recolors that material, "city" swaps the color
# texture, "keep" leaves the model's own look. tex: texture set to apply to every surface.
const MODELS := {
	"hatchback": {"file": "hatchback/hatchback.glb", "length": 4.25, "paint": "body:carpaint"},
	"si5": {"file": "si5/si5LOD0.fbx", "length": 4.5, "paint": "body:Car Paint", "hide": "logos"},
	"citycar": {"file": "citycar03/CityCar03.fbx", "length": 5.2, "paint": "city"},
	"carfree02": {"file": "carfree02/Car_Free_02.fbx", "length": 4.9, "paint": "keep", "tex": "carfree02"},
	"van": {"file": "van/van.obj", "length": 5.4, "paint": "keep"},
}

static var _fit := {} # model -> [scale, offset, size] measured once
static var _scenes := {}
static var _tex_mats := {}
static var _shapes := {} # model -> collision hull hugging the body (so bullet holes land on the paint)


static func make(id: String, rng: RandomNumberGenerator) -> Array:
	# returns [node, size (length, height, width), collision shape]; node faces +X with its footprint centered on the origin
	var spec: Dictionary = MODELS[id]
	var model := _instance(id)
	# some of these are showroom models (one is 74k triangles with its tires): cut each part to a sixth,
	# at most 6000, which still reads as the same car
	LiteMesh.lighten(model, func(t: int) -> int: return clampi(t / 6, 600, 6000) if t > 2000 else t)
	if spec.has("hide"):
		for mi in model.find_children("*" + spec.hide + "*", "MeshInstance3D", true, false):
			mi.queue_free()
	if spec.has("tex"):
		var m := _tex_material(spec.tex)
		for mi in _meshes(model):
			mi.material_override = m
	_paint(model, spec.paint, rng)
	if not _fit.has(id):
		_fit[id] = _measure(model, spec.length)
	var f: Array = _fit[id]
	model.scale = Vector3.ONE * f[0]
	model.position = f[1]
	var turn := Node3D.new()
	turn.rotation.y = PI / 2 # model nose +Z -> game nose +X
	turn.add_child(model)
	var root := Node3D.new()
	root.add_child(turn)
	if not _shapes.has(id):
		_shapes[id] = _hull(model, turn)
	return [root, f[2], _shapes[id]]


static func _instance(id: String) -> Node3D:
	if not _scenes.has(id):
		_scenes[id] = load(DIR + MODELS[id].file)
	var res = _scenes[id]
	if res is PackedScene:
		return res.instantiate()
	var mi := MeshInstance3D.new() # .obj files load as a bare mesh
	mi.mesh = res
	var holder := Node3D.new()
	holder.add_child(mi)
	return holder


static func _meshes(n: Node) -> Array:
	return n.find_children("*", "MeshInstance3D", true, false).filter(func(m): return not m.is_queued_for_deletion())


static func _measure(model: Node3D, length: float) -> Array:
	var box := AABB()
	var first := true
	for mi in _meshes(model):
		var t: Transform3D = mi.transform
		var p: Node = mi.get_parent()
		while p and p != model and p is Node3D:
			t = p.transform * t
			p = p.get_parent()
		var b: AABB = t * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var s := length / box.size.z
	var offset := -Vector3(box.get_center().x, box.position.y, box.get_center().z) * s
	return [s, offset, Vector3(box.size.z, box.size.y, box.size.x) * s]


static func _paint(model: Node3D, how: String, rng: RandomNumberGenerator) -> void:
	if how.begins_with("body:"):
		var target := how.substr(5)
		var color: Color = OPP_PAINTS[rng.randi() % OPP_PAINTS.size()]
		for mi in _meshes(model):
			for s in mi.mesh.get_surface_count():
				var src: Material = mi.mesh.surface_get_material(s)
				if src is BaseMaterial3D and src.resource_name == target:
					var m: BaseMaterial3D = src.duplicate()
					m.albedo_color = color
					m.metallic = 0.3
					m.roughness = rng.randf_range(0.3, 0.6) # some shiny, some faded
					m.clearcoat_enabled = true
					m.clearcoat = 0.5
					mi.set_surface_override_material(s, m)
	elif how == "parts":
		var paint: Color = OPP_PAINTS[rng.randi() % OPP_PAINTS.size()]
		for mi in _meshes(model):
			for s in mi.mesh.get_surface_count():
				var src: Material = mi.mesh.surface_get_material(s)
				if src == null:
					continue
				var m := StandardMaterial3D.new()
				match src.resource_name:
					"Red":
						m.albedo_color = paint
						m.metallic = 0.3
						m.roughness = rng.randf_range(0.3, 0.6)
						m.clearcoat_enabled = true
					"Glass":
						m.albedo_color = Color(0.04, 0.05, 0.06)
						m.metallic = 0.5
						m.roughness = 0.08
					"Tires":
						m.albedo_color = Color(0.03, 0.03, 0.03)
						m.roughness = 0.9
					"Silver":
						m.albedo_color = Color(0.6, 0.6, 0.62)
						m.metallic = 0.9
						m.roughness = 0.3
					_:
						m.albedo_color = Color(0.08, 0.08, 0.085) # trim, grille
						m.roughness = 0.7
				mi.set_surface_override_material(s, m)
	elif how == "city":
		var tex: Texture2D = load(DIR + "citycar03/Textures/RCA1_Color_%s.png" % CITY_COLORS[rng.randi() % CITY_COLORS.size()])
		for mi in _meshes(model):
			for s in mi.mesh.get_surface_count():
				var src: Material = mi.mesh.surface_get_material(s)
				if src is BaseMaterial3D and src.resource_name == "RCA1":
					var m: BaseMaterial3D = src.duplicate()
					m.albedo_texture = tex
					m.albedo_color = Color(0.62, 0.6, 0.58) # sun-faded, dusty: the palette colors are toy-bright
					m.roughness = 0.7
					mi.set_surface_override_material(s, m)


static func _tex_material(set_name: String) -> StandardMaterial3D:
	# models whose textures didn't come through on import
	if _tex_mats.has(set_name):
		return _tex_mats[set_name]
	var m := StandardMaterial3D.new()
	if set_name == "redcar":
		var t := DIR + "redcar/textures/bake_LP_%s.png"
		m.albedo_texture = load(t % "albedo")
		m.metallic = 1.0
		m.metallic_texture = load(t % "metalness")
		m.roughness = 1.0
		m.roughness_texture = load(t % "roughness")
		m.normal_enabled = true
		m.normal_texture = load(t % "normal")
	else:
		m.albedo_texture = load(DIR + "carfree02/Car_Free_02_Texture.png")
		m.roughness = 0.6
	_tex_mats[set_name] = m
	return m


static func _hull(model: Node3D, turn: Node3D) -> ConvexPolygonShape3D:
	# convex hull of the car's own vertices in the returned node's space, thinned to a few thousand points
	var pts := PackedVector3Array()
	for mi in _meshes(model):
		var t: Transform3D = mi.transform
		var p: Node = mi.get_parent()
		while p and p != model and p is Node3D:
			t = p.transform * t
			p = p.get_parent()
		t = turn.transform * model.transform * t
		for s in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			var step := maxi(1, verts.size() / 600)
			for i in range(0, verts.size(), step):
				pts.append(t * verts[i])
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	return shape
