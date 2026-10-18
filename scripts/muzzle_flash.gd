extends Node3D
## Pistol muzzle flash: Kenney's Particle Pack flames muzzle_03 / muzzle_05 (CC0, assets/fx), one picked at
## random each shot, on two crossed cards along the barrel (-Z), spun and sized a little differently every time
## and gone after a couple of frames.

const TEXTURES := [preload("res://assets/fx/muzzle_03.png"), preload("res://assets/fx/muzzle_05.png")]
const LENGTH := 0.39 # meters along the barrel
const WIDTH := 0.36
const SHOW_TIME := 0.045 # seconds
const TINT := Color(1.0, 0.8, 0.45)

static var _mats: Array[StandardMaterial3D] = []

var _spin: Node3D
var _cards: Array[MeshInstance3D] = []
var _t := 0.0


func _ready() -> void:
	if _mats.is_empty():
		for tex in TEXTURES:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.no_depth_test = false
			m.albedo_texture = tex
			m.albedo_color = TINT
			_mats.append(m)
	var quad := QuadMesh.new()
	quad.size = Vector2(WIDTH, LENGTH)
	quad.center_offset = Vector3(0, LENGTH * 0.5 - 0.01, 0) # the flame's base (bottom of the image) at the muzzle
	_spin = Node3D.new()
	add_child(_spin)
	var along_barrel := Basis(Vector3.RIGHT, -PI / 2) # the image's up (the flame's tip) points down the barrel
	for k in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.basis = Basis(Vector3.FORWARD, k * PI / 2) * along_barrel
		_spin.add_child(mi)
		_cards.append(mi)
	visible = false


func fire() -> void:
	var m := _mats[randi() % _mats.size()]
	for c in _cards:
		c.material_override = m
	_spin.rotation.z = randf() * TAU
	scale = Vector3.ONE * randf_range(0.85, 1.15)
	visible = true
	_t = SHOW_TIME


func _process(delta: float) -> void:
	if visible:
		_t -= delta
		if _t <= 0.0:
			visible = false
