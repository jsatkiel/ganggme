extends RefCounted
## Simplified copies of over-detailed models (a 50k-triangle snow mound, 17k-triangle cardboard boxes,
## 74k-triangle cars) for a laptop GPU. Each source mesh is simplified once and the copy shared.

static var _cache := {}
static var _tri_counts := {}


static func tris(mesh: Mesh) -> int:
	if not _tri_counts.has(mesh):
		var t := 0
		for s in mesh.get_surface_count():
			var a: Array = mesh.surface_get_arrays(s)
			t += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] else a[Mesh.ARRAY_VERTEX].size()) / 3
		_tri_counts[mesh] = t
	return _tri_counts[mesh]


static func lighten(root: Node, budget: Callable, shadows := true) -> void:
	## swaps every mesh under root for its simplified copy; budget(triangles) -> triangles to keep
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh:
			mi.mesh = simplify(mi.mesh, budget.call(tris(mi.mesh)))
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func simplify(mesh: Mesh, target_tris: int) -> Mesh:
	var total := tris(mesh)
	if total <= target_tris:
		return mesh
	var key := "%d:%d" % [mesh.get_instance_id(), target_tris]
	if _cache.has(key):
		return _cache[key]
	var im := ImporterMesh.new()
	var indexed := []
	for s in mesh.get_surface_count():
		var a: Array = mesh.surface_get_arrays(s)
		indexed.append(a[Mesh.ARRAY_INDEX] != null and not a[Mesh.ARRAY_INDEX].is_empty())
		im.add_surface(mesh.surface_get_primitive_type(s), a, [], {}, mesh.surface_get_material(s))
	im.generate_lods(60.0, 25.0, [])
	var out := ArrayMesh.new()
	var keep := float(target_tris) / total
	for s in im.get_surface_count():
		var a := im.get_surface_arrays(s)
		if indexed[s]:
			var full: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			var best := full
			for l in im.get_surface_lod_count(s):
				var idx := im.get_surface_lod_indices(s, l)
				if idx.size() >= full.size() * keep and idx.size() < best.size():
					best = idx
			a[Mesh.ARRAY_INDEX] = best
		out.add_surface_from_arrays(im.get_surface_primitive_type(s), a)
		out.surface_set_material(s, im.get_surface_material(s))
	_cache[key] = out
	return out
