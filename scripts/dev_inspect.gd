extends SceneTree
## Dev tool: prints the structure of imported models (run with --script).


func _init() -> void:
	for path in ["res://assets/characters/Superhero_Male_FullBody.gltf", "res://assets/characters/UAL1_Standard.glb", "res://assets/characters/Hair_Buzzed.gltf", "res://assets/nature/tree_oak_dark.glb"]:
		var scene: PackedScene = load(path)
		if scene == null:
			print("FAILED ", path)
			continue
		var root := scene.instantiate()
		print("=== ", path)
		_dump(root, 0)
		var ap := root.find_children("*", "AnimationPlayer", true, false)
		for p in ap:
			var names: PackedStringArray = p.get_animation_list()
			print("  animations (%d): %s" % [names.size(), ", ".join(names)])
			if names.size() > 0:
				var a: Animation = p.get_animation(names[0])
				for t in mini(a.get_track_count(), 3):
					print("  track: ", a.track_get_path(t))
		for sk in root.find_children("*", "Skeleton3D", true, false):
			var bones := []
			for b in sk.get_bone_count():
				bones.append(sk.get_bone_name(b))
			print("  skeleton %s bones (%d): %s" % [root.get_path_to(sk), bones.size(), ", ".join(bones)])
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var aabb: AABB = mi.get_aabb()
			print("  mesh %s aabb=%s surfaces=%d skin=%s" % [root.get_path_to(mi), aabb, mi.mesh.get_surface_count(), mi.skin != null])
		root.free()
	quit()


func _dump(n: Node, depth: int) -> void:
	if depth > 4:
		return
	print("  ".repeat(depth + 1), n.name, " <", n.get_class(), ">")
	for c in n.get_children():
		_dump(c, depth + 1)
