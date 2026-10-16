extends SceneTree
func _init() -> void:
	for id in []:
		_show("res://assets/props/%s/%s.gltf" % [id, id])
	_show("res://assets/props/glock17/Glock17.fbx")
	quit()
func _show(path: String) -> void:
	var scene: PackedScene = load(path)
	if scene == null:
		print("FAILED ", path); return
	var root := scene.instantiate()
	print("=== ", path)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var t: Transform3D = mi.transform
		var p := mi.get_parent()
		while p and p != root:
			t = p.transform * t; p = p.get_parent()
		var mats := []
		for s in mi.mesh.get_surface_count():
			var m = mi.mesh.surface_get_material(s)
			mats.append(m.resource_name if m else "none")
		print("  %s aabb=%s surf=%d mats=%s" % [mi.name, t * mi.get_aabb(), mi.mesh.get_surface_count(), mats])
	root.free()
