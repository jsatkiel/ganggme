extends Node3D
## Game setup and team-deathmatch rules: you vs. the bots, first to KILLS_TO_WIN.

const InputSetup = preload("res://scripts/input_setup.gd")
const MapBuilder = preload("res://scripts/map_builder.gd")
const PlayerScript = preload("res://scripts/player.gd")
const BotScript = preload("res://scripts/bot.gd")
const HudScript = preload("res://scripts/hud.gd")

const BOT_COUNT := 6 # opps
const TEAMMATES := 1 # bots on your crew
const KILLS_TO_WIN := 30
const PLAYER_RESPAWN := 3.0
const BOT_RESPAWN := 4.0

var map: Node3D
var player: CharacterBody3D
var hud: CanvasLayer
var bots: Array = []
var kills := 0
var deaths := 0
var match_over := false
var env: Environment


func _ready() -> void:
	randomize()
	InputSetup.setup()
	_build_environment()
	map = MapBuilder.new()
	map.name = "Map"
	add_child(map)
	map.build()

	hud = HudScript.new()
	add_child(hud)

	player = PlayerScript.new()
	player.name = "Player"
	player.game = self
	player.hud = hud
	add_child(player)
	hud.player = player
	var sp := _pick_player_spawn()
	player.respawn(sp, _facing_center(sp))
	player.invuln = 0.0

	for i in TEAMMATES:
		var mate = BotScript.new()
		mate.name = "Mate%d" % i
		mate.display_name = "TWIN" if i == 0 else "TWIN #%d" % (i + 1)
		mate.team = 0
		mate.game = self
		mate.map = map
		add_child(mate)
		mate.global_position = sp + Vector3(1.5 + i, 0, 1.0)
		bots.append(mate)
	for i in BOT_COUNT:
		var bot = BotScript.new()
		bot.name = "Bot%d" % i
		bot.display_name = "OPP #%d" % (i + 1)
		bot.game = self
		bot.map = map
		add_child(bot)
		bot.global_position = map.bot_spawns[i % map.bot_spawns.size()]
		bots.append(bot)

	hud.update_score(kills, deaths, KILLS_TO_WIN)
	hud.center_message("DEFEND THE BLOCK", 3.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var args := OS.get_cmdline_user_args()
	if "--no-ssao" in args: env.ssao_enabled = false
	if "--no-msaa" in args: get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	if "--no-shadows" in args:
		for l in find_children("*", "DirectionalLight3D", true, false): l.shadow_enabled = false
	if "--half-res" in args:
		get_viewport().scaling_3d_scale = 0.6
	if "--screenshot" in args:
		_take_screenshot(args)
	if "--model-test" in args:
		# dev: line up crew models on the street for a close-up (--cam to look at them)
		var i := 0
		for anim_name in ["Pistol_Idle", "Jog_Fwd", "Pistol_Aim_Neutral"]:
			var m := preload("res://scripts/crew_model.gd").new()
			add_child(m)
			m.global_position = Vector3(-1.5 + i * 1.5, 0.05, 40)
			m.rotation.y = PI if i != 1 else PI * 0.5
			m.call_deferred("play", anim_name, 0.0)
			i += 1
		for b in bots:
			b.queue_free()
		bots.clear()
	if "--check-overlaps" in args:
		map.check_overlaps()
		get_tree().quit()
	if "--curb-test" in args:
		# dev: walk the player from the gate road up onto the sidewalk and report the height
		player.global_position = Vector3(2, 0.1, 30)
		player.rotation.y = -PI / 2
		Input.action_press("move_forward")
		await get_tree().create_timer(2.0).timeout
		print("[curb] player at ", player.global_position)
		get_tree().quit()
	if "--debug-bots" in args:
		_debug_bots()


func _debug_bots() -> void:
	while true:
		await get_tree().create_timer(10.0).timeout
		print("[debug] player %s  waypoints=%d" % [player.global_position.round(), map.waypoints.size()])
		for b in bots:
			print("   %s pos=%s alive=%s sees=%s wp=%s has_wp=%s stuck=%.1f" % [b.name, b.global_position.round(), b.alive, b.sees_player, b.waypoint.round(), b.has_waypoint, b.stuck_t])


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	# real overcast sky photo (Poly Haven, CC0): lights the scene and fills the background
	var sm := PanoramaSkyMaterial.new()
	sm.panorama = load("res://assets/sky/farmland_overcast_1k.hdr")
	sm.energy_multiplier = 1.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	env.ssao_enabled = false # too heavy for laptop GPUs (halves the frame rate on a 940MX); a graphics menu can turn it back on
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.74, 0.77)
	env.fog_density = 0.0032
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 0.85
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)


func _process(_delta: float) -> void:
	if match_over and Input.is_action_just_pressed("ui_accept"):
		get_tree().reload_current_scene()


func _facing_center(pos: Vector3) -> float:
	var d := (Vector3(0, 0, 40) if pos.z > 62.0 else Vector3(0, 0, -10)) - pos
	return atan2(-d.x, -d.z)


func enemies_of(team: int) -> Array:
	# who a bot on this team should shoot at
	var out := []
	if team == 1 and player.alive:
		out.append(player)
	for b in bots:
		if b.alive and b.team != team:
			out.append(b)
	return out


func _pick_player_spawn() -> Vector3:
	return _farthest_from(map.player_spawns, enemies_of(0).map(func(b): return b.global_position))


func _pick_bot_spawn(bot: Node) -> Vector3:
	var spots: Array = map.player_spawns if bot.team == 0 else map.bot_spawns + map.player_spawns
	return _farthest_from(spots, enemies_of(bot.team).map(func(e): return e.global_position))


func _farthest_from(spots: Array, threats: Array) -> Vector3:
	if threats.is_empty():
		return spots[randi() % spots.size()]
	var scored := []
	for s in spots:
		var nearest := INF
		for t in threats:
			nearest = minf(nearest, s.distance_to(t))
		scored.append([nearest, s])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	return scored[randi() % mini(3, scored.size())][1]


func on_bot_killed(bot: Node, headshot: bool, attacker: Node = null) -> void:
	if match_over:
		return
	var who: String = "YOU" if attacker == player else (attacker.display_name if attacker and "display_name" in attacker else "?")
	var hs := "   [HEADSHOT]" if headshot else ""
	if bot.team == 0:
		# your teammate went down: a point for the opps
		deaths += 1
		hud.killfeed("%s  dropped  %s%s" % [who, bot.display_name, hs], Color(1, 0.35, 0.3))
		hud.update_score(kills, deaths, KILLS_TO_WIN)
		if deaths >= KILLS_TO_WIN:
			_end_match(false)
			return
		await get_tree().create_timer(BOT_RESPAWN).timeout
		if not match_over and is_instance_valid(bot):
			bot.respawn(_pick_bot_spawn(bot))
		return
	kills += 1
	hud.killfeed("%s  dropped  %s%s" % [who, bot.display_name, hs], Color(1, 0.9, 0.5) if attacker == player else Color(0.55, 0.75, 1.0))
	hud.update_score(kills, deaths, KILLS_TO_WIN)
	if kills >= KILLS_TO_WIN:
		_end_match(true)
		return
	await get_tree().create_timer(BOT_RESPAWN).timeout
	if not match_over and is_instance_valid(bot):
		bot.respawn(_pick_bot_spawn(bot))


func on_player_died(attacker: Node) -> void:
	if match_over:
		return
	deaths += 1
	var who: String = attacker.display_name if attacker and "display_name" in attacker else "the opps"
	hud.killfeed("%s  dropped  YOU" % who, Color(1, 0.35, 0.3))
	hud.update_score(kills, deaths, KILLS_TO_WIN)
	print("[game] player died (%d)" % deaths)
	if deaths >= KILLS_TO_WIN:
		_end_match(false)
		return
	hud.center_message("YOU GOT DROPPED", PLAYER_RESPAWN)
	await get_tree().create_timer(PLAYER_RESPAWN).timeout
	if not match_over:
		var sp := _pick_player_spawn()
		player.respawn(sp, _facing_center(sp))


func _end_match(won: bool) -> void:
	match_over = true
	var msg := "YOU RUN THE BLOCK" if won else "THE OPPS TOOK THE BLOCK"
	hud.center_message("%s\n%d - %d\nPress ENTER / A to run it back" % [msg, kills, deaths])


func _take_screenshot(args: PackedStringArray) -> void:
	# dev helper: godot --path . -- --screenshot out.png
	var idx := args.find("--screenshot")
	var out := args[idx + 1] if idx + 1 < args.size() else "user://shot.png"
	if "--cam" in args:
		# --cam x,y,z,look_x,look_y,look_z
		var v := args[args.find("--cam") + 1].split_floats(",")
		var c := Camera3D.new()
		add_child(c)
		c.global_position = Vector3(v[0], v[1], v[2])
		c.look_at(Vector3(v[3], v[4], v[5]))
		c.make_current()
		hud.visible = false
	if "--ads" in args:
		player.force_ads = true
	if "--fp-side" in args:
		# dev: look at the first-person arms from the side
		await get_tree().create_timer(1.0).timeout
		var sc := Camera3D.new()
		player.camera.add_child(sc)
		sc.near = 0.01
		var gp: Vector3 = player.arms.gun.global_position
		var cb: Basis = player.camera.global_transform.basis
		sc.global_position = gp + cb.x * 0.28 + cb.y * 0.04 + cb.z * 0.02
		sc.look_at(gp)
		sc.make_current()
		hud.visible = false
	if "--overview" in args:
		var cam := Camera3D.new()
		add_child(cam)
		cam.global_position = Vector3(0, 135, 30)
		cam.look_at(Vector3(0, 0, -3))
		cam.make_current()
		hud.visible = false
		env.fog_enabled = false
	await get_tree().create_timer(2.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("[game] screenshot saved to ", out)
	print("[game] draw calls %d, primitives %d, objects %d" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	get_tree().quit()
