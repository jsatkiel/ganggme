extends SceneTree
## Dev: every car in the catalog as the game builds it, side by side.
const Cars := preload("res://scripts/cars.gd")
func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var rng := RandomNumberGenerator.new()
	var ids: Array = Cars.MODELS.keys()
	for i in ids.size():
		var made: Array = Cars.make(ids[i], rng)
		var n: Node3D = made[0]
		n.rotation.y = PI / 2
		n.position = Vector3((i - ids.size() / 2.0) * 2.8, 0, 0)
		root.add_child(n)
		var l := Label3D.new(); l.text = ids[i]; l.font_size = 64; l.pixel_size = 0.005; l.position = n.position + Vector3(0, 2.3, 0); l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		root.add_child(l)
	var lt := DirectionalLight3D.new(); lt.rotation_degrees = Vector3(-50, 30, 0); root.add_child(lt)
	var we := WorldEnvironment.new(); we.environment = Environment.new(); we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.5, 0.55, 0.6); we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; we.environment.ambient_light_color = Color.WHITE; we.environment.ambient_light_energy = 0.5
	root.add_child(we)
	var cam := Camera3D.new(); root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 4, 12), Vector3(0, 0.6, 0)); cam.current = true
	for k in 12: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
