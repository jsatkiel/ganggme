extends SceneTree
## Dev: prints the size and materials of every car model in assets/cars2.
const CARS := ["hatchback/hatchback.glb", "si5/si5LOD0.fbx", "carfree02/Car_Free_02.fbx", "van/van.obj"]
func _init() -> void:
	for c in CARS:
		var res = load("res://assets/cars2/" + c)
		var root: Node3D
		if res is PackedScene:
			root = res.instantiate()
		elif res is Mesh:
			root = MeshInstance3D.new(); root.mesh = res
		else:
			print("FAILED ", c); continue
		var box := AABB()
		var first := true
		var mats := {}
		var tris := 0
		for mi in ([root] if root is MeshInstance3D else []) + root.find_children("*", "MeshInstance3D", true, false):
			var t: Transform3D = mi.transform
			var p: Node = mi.get_parent()
			while p and p != root and p is Node3D:
				t = p.transform * t; p = p.get_parent()
			var b: AABB = t * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
			for s in mi.mesh.get_surface_count():
				var m = mi.mesh.surface_get_material(s)
				var n: String = m.resource_name if m else "none"
				var tex := ""
				if m is BaseMaterial3D and m.albedo_texture: tex = "+tex"
				mats[n + tex] = true
				var arr = mi.mesh.surface_get_arrays(s)
				tris += (arr[Mesh.ARRAY_INDEX].size() if arr[Mesh.ARRAY_INDEX] else arr[Mesh.ARRAY_VERTEX].size()) / 3
		print("%s  size=%s  pos=%s  tris=%d\n   mats=%s" % [c, box.size, box.position, tris, mats.keys()])
		root.free()
	quit()
