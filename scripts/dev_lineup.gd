extends SceneTree
## Dev: lines up every car in assets/cars2 at real size, all as shipped (no turning), and saves a png.
const CARS := ["hatchback/hatchback.glb", "si5/si5LOD0.fbx", "carfree02/Car_Free_02.fbx", "van/van.obj"]
func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var i := 0
	for c in CARS:
		var res = load("res://assets/cars2/" + c)
		var m: Node3D
		if res is PackedScene: m = res.instantiate()
		else: m = MeshInstance3D.new(); m.mesh = res
		var holder := Node3D.new()
		holder.add_child(m)
		root.add_child(holder)
		var box := _aabb(m)
		var s := 4.5 / box.size.z
		m.scale = Vector3.ONE * s
		m.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * s
		holder.position = Vector3((i - 4) * 3.2, 0, 0)
		var l := Label3D.new(); l.text = "%d %s" % [i, c.get_file()]; l.font_size = 64; l.pixel_size = 0.005; l.position = Vector3(0, 2.4, 0); l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		holder.add_child(l)
		i += 1
	var fl := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(60, 30); fl.mesh = pm; root.add_child(fl)
	var lt := DirectionalLight3D.new(); lt.rotation_degrees = Vector3(-50, 30, 0); root.add_child(lt)
	var we := WorldEnvironment.new(); we.environment = Environment.new(); we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.5, 0.55, 0.6); we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; we.environment.ambient_light_color = Color.WHITE; we.environment.ambient_light_energy = 0.5
	root.add_child(we)
	var cam := Camera3D.new(); root.add_child(cam)
	var a := OS.get_cmdline_user_args()
	cam.look_at_from_position(Vector3(0, 7, 13) if a.size() < 2 else Vector3(0, 7, -13), Vector3(0, 0.5, 0))
	cam.current = true
	for k in 12: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(a[0])
	quit()
func _aabb(n: Node3D) -> AABB:
	var box := AABB(); var first := true
	for mi in ([n] if n is MeshInstance3D else []) + n.find_children("*", "MeshInstance3D", true, false):
		var t: Transform3D = mi.transform if mi != n else Transform3D.IDENTITY
		var p: Node = mi.get_parent()
		while mi != n and p and p != n and p is Node3D:
			t = p.transform * t; p = p.get_parent()
		var b: AABB = t * mi.get_aabb()
		box = b if first else box.merge(b); first = false
	return box
