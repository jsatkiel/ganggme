extends RefCounted
## Bullet tracers, impact marks and dust puffs.

const MAX_DECALS := 80

static var _decals: Array = []
static var _decal_mat: StandardMaterial3D
static var _decal_mesh: BoxMesh
static var _puff_mesh: SphereMesh
static var _puff_mats := {} # color -> material, shared (each puff fades with its own transparency)


static func up_for(dir: Vector3) -> Vector3:
	return Vector3.RIGHT if absf(dir.normalized().y) > 0.98 else Vector3.UP


static func tracer(root: Node, from: Vector3, to: Vector3, col := Color(1.0, 0.85, 0.45)) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.018, 0.018, length)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = (from + to) * 0.5
	mi.look_at(to, up_for(to - from))
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.08)
	tw.tween_callback(mi.queue_free)


static func impact(root: Node, pos: Vector3, normal: Vector3, puff_col := Color(0.55, 0.52, 0.48)) -> void:
	if _decal_mat == null:
		_decal_mat = StandardMaterial3D.new()
		_decal_mat.albedo_color = Color(0.06, 0.05, 0.05)
		_decal_mat.roughness = 1.0
	if _decal_mesh == null:
		_decal_mesh = BoxMesh.new()
		_decal_mesh.size = Vector3(0.08, 0.08, 0.01)
	var mark := MeshInstance3D.new()
	mark.mesh = _decal_mesh
	mark.material_override = _decal_mat
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mark)
	mark.global_position = pos + normal * 0.006
	mark.look_at(pos + normal * 2.0, up_for(normal))
	_decals.append(mark)
	while _decals.size() > MAX_DECALS:
		var old = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	puff(root, pos + normal * 0.05, puff_col)


static func puff(root: Node, pos: Vector3, col: Color) -> void:
	if _puff_mesh == null:
		_puff_mesh = SphereMesh.new()
		_puff_mesh.radius = 0.07
		_puff_mesh.height = 0.14
		_puff_mesh.radial_segments = 8
		_puff_mesh.rings = 4
	if not _puff_mats.has(col):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = col
		_puff_mats[col] = m
	var mi := MeshInstance3D.new()
	mi.mesh = _puff_mesh
	mi.material_override = _puff_mats[col]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 3.0, 0.3)
	tw.tween_property(mi, "transparency", 1.0, 0.3)
	tw.chain().tween_callback(mi.queue_free)
