extends SceneTree
## Dev tool: turns the user's long-gun models (assets/props/mac10, ak47, ricky) into one static mesh each,
## fitted the way guns.gd holds them: barrel along -Z, top up, the spot the right hand grips on the origin (the
## sight heights, muzzles and left-hand spots measured off these go in guns.gd). The MAC-10 comes rigged; its
## parts are baked in their posed places. One mesh, one draw call per gun. RICKY came without textures, so its
## grip is painted wood and the rest gun metal in the vertex colors.
## Needs a window (skinned parts pose on the renderer):  godot --path . -s tools/bake_guns.gd
## Add --views to also save side/top renders with a 5 cm grid to user:// for checking the fit.
## Name guns after the script to bake only those (godot --path . -s tools/bake_guns.gd -- mac10).

# key: [source, turn about Y (degrees), scale, offset after turning and scaling]
const GUNS := {
	"mac10": ["res://assets/props/mac10/Mac10.fbx", 180.0, 0.66, Vector3(0, -0.011, 0)],
	"ak47": ["res://assets/props/ak47/AK47.fbx", 180.0, 1.07, Vector3(0, 0.083, -0.116)],
	"ricky": ["res://assets/props/ricky/DoubleBarrel.fbx", 90.0, 0.325, Vector3(0, 0.08, -0.28)],
}
# an attachment modeled onto the gun, cut off into a mesh of its own (the game shows or hides it): key ->
# [its mesh name, the cut: every triangle ahead of this z goes to it]. The MAC-10's suppressor starts 15.5 cm out.
const SPLIT := {"mac10": ["mac10_suppressor", -0.155]}


func _rel(n: Node, root: Node) -> Transform3D:
	var t := Transform3D()
	while n != root:
		t = n.transform * t
		n = n.get_parent()
	return t


func _init() -> void:
	var views := "--views" in OS.get_cmdline_user_args() or "--views" in OS.get_cmdline_args()
	var cam: Camera3D
	if views:
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.55, 0.62, 0.7)
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color.WHITE
		get_root().add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-40, 30, 0)
		get_root().add_child(sun)
		cam = Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		get_root().add_child(cam)
	await process_frame
	var only := Array(OS.get_cmdline_user_args()).filter(func(a): return GUNS.has(a))
	for key in GUNS:
		if not only.is_empty() and not key in only:
			continue
		var g: Array = GUNS[key]
		var src: Node3D = load(g[0]).instantiate()
		get_root().add_child(src)
		await process_frame
		await process_frame
		var fit := Transform3D(Basis(Vector3.UP, deg_to_rad(g[1])).scaled(Vector3.ONE * g[2]), g[3])
		var st := SurfaceTool.new()
		for mi: MeshInstance3D in src.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = mi.bake_mesh_from_current_skeleton_pose() if mi.skin else mi.mesh
			for i in m.get_surface_count():
				st.append_from(m, i, fit * _rel(mi, src))
		src.queue_free()
		st.generate_tangents()
		var mesh := st.commit()
		if SPLIT.has(key):
			var cut := _split_front(mesh, SPLIT[key][1])
			mesh = cut[0]
			var part: ArrayMesh = cut[1]
			part.resource_name = SPLIT[key][0]
			var pp: String = g[0].get_base_dir() + "/" + SPLIT[key][0] + ".res"
			ResourceSaver.save(part, pp)
			print("%s -> %s  from %s to %s" % [SPLIT[key][0], pp, part.get_aabb().position, part.get_aabb().end])
		if key == "ricky":
			mesh = _paint_grip(mesh)
		mesh.resource_name = key
		var path: String = g[0].get_base_dir() + "/" + key + ".res"
		ResourceSaver.save(mesh, path)
		var a := mesh.get_aabb()
		print("%s -> %s  from %s to %s" % [key, path, a.position, a.end])
		if views:
			await _views(key, mesh, cam)
	quit()


func _split_front(mesh: ArrayMesh, z: float) -> Array:
	# [the mesh behind z, the mesh ahead of it], whole triangles by where their middle is
	var a := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var back := PackedInt32Array()
	var front := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var mid := (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
		var to := front if mid.z < z else back
		to.append_array([idx[t], idx[t + 1], idx[t + 2]])
	var out := []
	for part in [back, front]:
		# keep only the vertices this half uses, so its bounds fit it
		var remap := {}
		var used := PackedInt32Array()
		var new_idx := PackedInt32Array()
		for v in part:
			if not remap.has(v):
				remap[v] = used.size()
				used.append(v)
			new_idx.append(remap[v])
		var pa := []
		pa.resize(Mesh.ARRAY_MAX)
		for k in Mesh.ARRAY_MAX:
			if a[k] == null or k == Mesh.ARRAY_INDEX:
				continue
			var src = a[k]
			var per: int = src.size() / verts.size()
			var dst = src.duplicate()
			dst.resize(used.size() * per)
			for j in used.size():
				for c in per:
					dst[j * per + c] = src[used[j] * per + c]
			pa[k] = dst
		pa[Mesh.ARRAY_INDEX] = new_idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pa)
		out.append(m)
	return out


func _paint_grip(mesh: ArrayMesh) -> ArrayMesh:
	# the curved grip, behind and below the action, is wood; the rest gun metal
	var a := mesh.surface_get_arrays(0)
	var cols := PackedColorArray()
	for v: Vector3 in a[Mesh.ARRAY_VERTEX]:
		cols.append(Color(0.36, 0.2, 0.1) if v.y < 0.035 and v.z > -0.07 else Color(0.13, 0.13, 0.14))
	a[Mesh.ARRAY_COLOR] = cols
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return out


func _views(key: String, mesh: Mesh, cam: Camera3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	get_root().add_child(mi)
	var grid := MeshInstance3D.new() # 5 cm lines in the side plane, the origin and the sight line in red
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for i in range(-20, 21):
		var c := Color(1, 0, 0) if i == 0 else Color(0, 0, 0, 0.5)
		for p in [[Vector3(0.2, i * 0.05, -1), Vector3(0.2, i * 0.05, 1)], [Vector3(0.2, -1, i * 0.05), Vector3(0.2, 1, i * 0.05)]]:
			im.surface_set_color(c)
			im.surface_add_vertex(p[0])
			im.surface_add_vertex(p[1])
	im.surface_set_color(Color(1, 1, 0))
	im.surface_add_vertex(Vector3(0.2, 0.102, -1))
	im.surface_add_vertex(Vector3(0.2, 0.102, 1))
	im.surface_end()
	grid.mesh = im
	get_root().add_child(grid)
	var a := mesh.get_aabb()
	var c := a.get_center()
	cam.size = maxf(a.size.z, a.size.y) * 1.15
	cam.near = 0.001
	cam.far = 10.0
	cam.look_at_from_position(Vector3(2, c.y, c.z), Vector3(0, c.y, c.z), Vector3.UP)
	for f in 3:
		await process_frame
	get_root().get_texture().get_image().save_png("user://gun_%s_side.png" % key)
	grid.visible = false
	cam.size = maxf(a.size.z, a.size.x) * 1.15
	cam.look_at_from_position(Vector3(c.x, 2, c.z), Vector3(c.x, 0, c.z), Vector3.FORWARD)
	for f in 3:
		await process_frame
	get_root().get_texture().get_image().save_png("user://gun_%s_top.png" % key)
	mi.queue_free()
	grid.queue_free()
