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
