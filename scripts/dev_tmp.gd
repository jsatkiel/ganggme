extends SceneTree
func _init() -> void:
	var root: Node3D = load("res://assets/props/snowpile/snowpile.fbx").instantiate()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var t: Transform3D = mi.transform
		var p: Node = mi.get_parent()
		while p and p != root: t = p.transform * t; p = p.get_parent()
		var m = mi.mesh.surface_get_material(0)
		print(mi.name, " ", t * mi.get_aabb(), " tex=", m.albedo_texture if m is BaseMaterial3D else null, " surf=", mi.mesh.get_surface_count())
	quit()
