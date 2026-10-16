extends SceneTree
## Dev tool: prints size, origin offset and materials of city kit pieces (run with --script).


func _init() -> void:
	var dir := DirAccess.open("res://assets/citykit")
	for f in dir.get_files():
		if not f.ends_with(".gltf"):
			continue
		var filt: Array = Array(OS.get_cmdline_user_args())
		if not filt.is_empty() and not filt.any(func(s): return f.begins_with(s)):
			continue
		var root: Node3D = load("res://assets/citykit/" + f).instantiate()
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		var box := AABB()
		var first := true
		var mats := []
		for mi: MeshInstance3D in meshes:
			var xf := _global(mi, root)
			var a: AABB = xf * mi.get_aabb()
			box = a if first else box.merge(a)
			first = false
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				mats.append(m.resource_name if m else "null")
		print("%s meshes=%d pos=%s size=%s mats=%s" % [f.get_basename(), meshes.size(), box.position.snapped(Vector3.ONE * 0.01), box.size.snapped(Vector3.ONE * 0.01), mats])
		root.free()
	quit()


func _global(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != root:
		t = n.transform * t
		n = n.get_parent()
	return t
