extends SceneTree
## Dev tool: for each piece in the city pack, prints its bounds and how much wall area faces each way.


func _init() -> void:
	var root: Node3D = load("res://assets/city_pack/city_pack.fbx").instantiate()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var xf := _xf(mi, root)
		var area := {"+X": 0.0, "-X": 0.0, "+Z": 0.0, "-Z": 0.0, "+Y": 0.0, "-Y": 0.0}
		var tris := 0
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var n := idx.size() if idx.size() > 0 else v.size()
			tris += n / 3
			for t in range(0, n, 3):
				var a := xf * v[idx[t] if idx.size() else t]
				var b := xf * v[idx[t + 1] if idx.size() else t + 1]
				var c := xf * v[idx[t + 2] if idx.size() else t + 2]
				var cr := (b - a).cross(c - a) # Godot winding: front face is clockwise, normal = -cross
				var nrm := -cr.normalized()
				var ar := cr.length() / 2.0
				var ab := nrm.abs()
				var i := 0 if ab.x >= ab.y and ab.x >= ab.z else (1 if ab.y >= ab.z else 2)
				area[("+" if nrm[i] > 0 else "-") + "XYZ"[i]] += ar
		var box: AABB = xf * mi.get_aabb()
		var parts := []
		for k in area:
			if area[k] > 0.05:
				parts.append("%s=%.1f" % [k, area[k]])
		print("%s tris=%d pos=%s size=%s  %s" % [mi.name, tris, box.position.snapped(Vector3.ONE * 0.01), box.size.snapped(Vector3.ONE * 0.01), " ".join(parts)])
	root.free()
	quit()


func _xf(n: Node3D, r: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != r:
		t = n.transform * t
		n = n.get_parent()
	return t
