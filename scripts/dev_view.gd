extends SceneTree
## Dev: renders one model with axis markers to a png. godot --path . --script res://scripts/dev_view.gd -- <res path> <out.png> <dist>
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var root := Node3D.new()
	get_root().add_child(root)
	var m: Node3D = load(a[0]).instantiate()
	root.add_child(m)
	var d := float(a[2]) if a.size() > 2 else 0.5
	for ax in [[Vector3.RIGHT, Color.RED], [Vector3.UP, Color.GREEN], [Vector3.BACK, Color.BLUE]]:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new(); b.size = Vector3.ONE * d * 0.02 + ax[0].abs() * d * 0.4
		mi.mesh = b
		var mat := StandardMaterial3D.new(); mat.albedo_color = ax[1]; mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = mat
		mi.position = ax[0] * d * 0.2
		root.add_child(mi)
	var l := DirectionalLight3D.new(); l.rotation_degrees = Vector3(-50, 30, 0); root.add_child(l)
	var we := WorldEnvironment.new(); we.environment = Environment.new(); we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.5, 0.55, 0.6); we.environment.ambient_light_color = Color.WHITE; we.environment.ambient_light_energy = 0.6
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root.add_child(we)
	var c := Camera3D.new(); root.add_child(c)
	c.position = Vector3(d * 0.6, d * 0.5, d * 1.2); c.look_at_from_position(c.position, Vector3.ZERO)
	c.current = true
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(a[1])
	quit()
