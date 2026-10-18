extends Node3D
## Game setup and the rules for both modes: team deathmatch (you vs. the bots, first to KILLS_TO_WIN) and
## King of the Hood (8 v 8, hold the green circle in the middle of the lot for HOLD_TIME, best of 7 rounds).
## In King of the Hood each team carries 2 pistols, 2 shotguns, 2 rifles and 2 SMGs, and every slot moves on to
## the next gun each round (guns.gd), so in any 4 rounds everyone uses all four.

const InputSetup = preload("res://scripts/input_setup.gd")
const MapBuilder = preload("res://scripts/map_builder.gd")
const PlayerScript = preload("res://scripts/player.gd")
const BotScript = preload("res://scripts/bot.gd")
const HudScript = preload("res://scripts/hud.gd")
const PauseMenu = preload("res://scripts/pause_menu.gd")
const Loadout = preload("res://scripts/loadout.gd")
const Guns = preload("res://scripts/guns.gd")
const MODES := {"koth": "KING OF THE HOOD", "tdm": "TEAM DEATHMATCH"}

const BOT_COUNT := 6 # opps
const TEAMMATES := 1 # bots on your crew
const KILLS_TO_WIN := 30
const PLAYER_RESPAWN := 3.0
const BOT_RESPAWN := 4.0
# King of the Hood
# per side: 8 v 8, or 4 v 4 with BIG TEAMS off in the settings (the laptop dropped to 2 FPS at 8 v 8 before the
# bots got cheaper; the 4 v 4 switch is there if it still can't keep up). Each team's 8 slots hold 2 of each gun,
# so at 4 v 4 that's one of each.
var koth_team := 8
const ROUNDS_TO_WIN := 4 # best of 7
const HOLD_TIME := 5.0 # seconds on the circle in a row, with none of the other team on it
const HILL := Vector3(0, 0.0, -7) # the grass island in the very middle of the parking lot
const HILL_RADIUS := 4.5
const CREW_BASE := Vector3(0, 0.2, 48) # both 55 m from the circle, on opposite sides (south by the gate, north)
const OPP_BASE := Vector3(0, 0.2, -62)
const ROUND_BREAK := 4.0

# auto quality: frame cost swings with the view (the 940MX holds 60 looking down the street but not
# across a lawn full of cut-out grass), so ease detail off when frames run long and bring it back after
const QUALITY_LEVELS := [
	# grass draw range factor, 3D render scale, sun shadow distance, mesh detail threshold (how many pixels of
	# error a model may show before it switches to its simplified version; Godot's default is 1)
	[1.0, 0.75, 80.0, 4.0],
	[0.7, 0.75, 70.0, 8.0],
	[0.5, 0.65, 55.0, 12.0],
	[0.35, 0.55, 40.0, 20.0],
]
const SLOW_MS := 17.0 # frames averaging longer than this miss 60 FPS
const FAST_MS := 10.5 # under this there's room to bring detail back

var map: Node3D
var player: CharacterBody3D
var hud: CanvasLayer
var bots: Array = []
var kills := 0
var deaths := 0
var match_over := false
var mode: String = "koth"
var round_num := 0
var round_wins := [0, 0] # [your crew, opps]
var round_live := false
var hold_team := -1 # who is alone on the circle right now (-1: nobody, or both)
var hold_t := 0.0
var hill_node: Node3D
var _hill_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _hill_light: OmniLight3D
var env: Environment
var sun: DirectionalLight3D
var auto_quality := true
var quality := 0
var _frame_ms := 0.0
var _slow_t := 0.0
var _fast_t := 0.0


func _ready() -> void:
	randomize()
	InputSetup.setup()
	Loadout.load_all()
	mode = Loadout.settings.get("mode", "koth")
	if not MODES.has(mode):
		mode = "koth"
	var koth := mode == "koth"
	koth_team = 8 if Loadout.settings.get("big_teams", true) else 4
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
	var sp: Vector3 = _base_slots(0)[0] if koth else _pick_player_spawn()
	player.respawn(sp, _facing_center(sp))
	player.invuln = 0.0

	for i in (koth_team - 1 if koth else TEAMMATES):
		var mate = BotScript.new()
		mate.name = "Mate%d" % i
		mate.display_name = "TWIN" if i == 0 else "TWIN #%d" % (i + 1)
		mate.team = 0
		mate.slot = _slot_for(i + 1)
		mate.game = self
		mate.map = map
		add_child(mate)
		mate.global_position = _base_slots(0)[i + 1] if koth else sp + Vector3(1.5 + i, 0, 1.0)
		bots.append(mate)
	for i in (koth_team if koth else BOT_COUNT):
		var bot = BotScript.new()
		bot.name = "Bot%d" % i
		bot.display_name = "OPP #%d" % (i + 1)
		bot.slot = _slot_for(i)
		bot.game = self
		bot.map = map
		add_child(bot)
		bot.global_position = _base_slots(1)[i] if koth else map.bot_spawns[i % map.bot_spawns.size()]
		bots.append(bot)
	if koth:
		for b in bots:
			b.rotation.y = _facing_center(b.global_position)
		_build_hill()

	var menu := PauseMenu.new() # Esc / Start: pause, loadout, settings
	menu.game = self
	menu.player = player
	add_child(menu)

	if koth:
		hud.show_hill(true)
		_start_round()
	else:
		hud.update_score(kills, deaths, KILLS_TO_WIN)
		hud.center_message("DEFEND THE BLOCK", 3.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var args := OS.get_cmdline_user_args()
	# dev runs that set their own quality (or take screenshots) keep it fixed
	auto_quality = not ("--fixed-quality" in args or "--screenshot" in args or "--half-res" in args or "--no-shadows" in args)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	get_viewport().mesh_lod_threshold = QUALITY_LEVELS[0][3]
	if "--no-ssao" in args: env.ssao_enabled = false
	if "--no-msaa" in args: get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	if "--no-shadows" in args:
		for l in find_children("*", "DirectionalLight3D", true, false): l.shadow_enabled = false
	if "--half-res" in args:
		get_viewport().scaling_3d_scale = 0.6
	if "--gun" in args:
		# dev: start holding this gun (pistol, shotgun, rifle, smg)
		player.gun_kind = args[args.find("--gun") + 1]
		player.respawn(player.global_position, player.rotation.y)
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
	if "--perf-log" in args:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # it runs unattended: leave the mouse free
		_perf_log()


func _perf_log() -> void:
	# dev: what the frame costs and what is piling up, every 5 s (godot --path . -- --perf-log)
	var vp := get_viewport().get_viewport_rid()
	var t := 0
	while true:
		await get_tree().create_timer(5.0).timeout
		t += 5
		print("[perf] %3ds fps %3d  gpu %5.1fms cpu %5.1fms  proc %4.1fms phys %4.1fms  draws %4d objs %4d prims %7d  nodes %5d orphans %d  mem %.0fMB vmem %.0fMB  detail -%d" % [
			t, Engine.get_frames_per_second(),
			RenderingServer.viewport_get_measured_render_time_gpu(vp), RenderingServer.viewport_get_measured_render_time_cpu(vp),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			quality])


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
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 0.85
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	# 2 cascades out to 80 m: every caster is drawn once per cascade, and 4 out to 140 m tripled the
	# draw calls, which a laptop CPU/GPU (940MX) can't keep up with
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)


func _process(delta: float) -> void:
	if match_over and Input.is_action_just_pressed("ui_accept"):
		get_tree().reload_current_scene()
	if auto_quality:
		_auto_quality(delta)
	if mode == "koth" and hill_node:
		_koth_tick(delta)


# ---------------------------------------------------------------- King of the Hood

func _base_slots(team: int) -> Array:
	# the spots a side starts in: a tight group, rows of 4, at its end of the map
	var c: Vector3 = CREW_BASE if team == 0 else OPP_BASE
	var out := []
	for i in koth_team:
		var p := c + Vector3((i % 4 - 1.5) * 1.8, 0, (floori(i / 4.0) - 0.5) * 1.8)
		if map._is_blocked(Vector2(p.x, p.z), 0.5):
			p = c + Vector3(0, 0, (floori(i / 4.0) - 0.5) * 1.8)
		out.append(p)
	return out


func _build_hill() -> void:
	# the glowing green circle on the grass island in the middle of the lot
	hill_node = Node3D.new()
	hill_node.name = "Hill"
	add_child(hill_node)
	hill_node.global_position = HILL + Vector3(0, 0.035, 0)
	_hill_mat = StandardMaterial3D.new()
	_hill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hill_mat.albedo_color = Color(0.2, 1.0, 0.35, 0.22)
	_hill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var disc := CylinderMesh.new()
	disc.top_radius = HILL_RADIUS
	disc.bottom_radius = HILL_RADIUS
	disc.height = 0.02
	disc.radial_segments = 48
	var dmi := MeshInstance3D.new()
	dmi.mesh = disc
	dmi.material_override = _hill_mat
	dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hill_node.add_child(dmi)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(0.25, 1.0, 0.4)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(0.2, 1.0, 0.35)
	_ring_mat.emission_energy_multiplier = 3.0
	var ring := TorusMesh.new()
	ring.inner_radius = HILL_RADIUS - 0.14
	ring.outer_radius = HILL_RADIUS
	ring.rings = 64
	ring.ring_segments = 8
	var rmi := MeshInstance3D.new()
	rmi.mesh = ring
	rmi.material_override = _ring_mat
	rmi.scale = Vector3(1, 0.5, 1)
	rmi.position.y = 0.03
	rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hill_node.add_child(rmi)
	_hill_light = OmniLight3D.new()
	_hill_light.light_color = Color(0.3, 1.0, 0.4)
	_hill_light.omni_range = HILL_RADIUS + 3.0
	_hill_light.light_energy = 1.5
	_hill_light.position.y = 1.2
	hill_node.add_child(_hill_light)


func hill_target() -> Vector3:
	# where the bots should be heading (Vector3.INF: no circle in this mode)
	return HILL if mode == "koth" else Vector3.INF


func _on_hill(n: Node3D) -> bool:
	var d := Vector2(n.global_position.x - HILL.x, n.global_position.z - HILL.z)
	return d.length() < HILL_RADIUS and absf(n.global_position.y - HILL.y) < 2.5


func _koth_tick(delta: float) -> void:
	var on := [0, 0]
	if round_live and not match_over:
		if player.alive and _on_hill(player):
			on[0] += 1
		for b in bots:
			if b.alive and _on_hill(b):
				on[b.team] += 1
	var holder := -1
	if on[0] > 0 and on[1] == 0:
		holder = 0
	elif on[1] > 0 and on[0] == 0:
		holder = 1
	if holder != hold_team: # someone stepped off, or the other side stepped on: the count starts over
		hold_team = holder
		hold_t = 0.0
	if holder >= 0:
		hold_t += delta
	var contested: bool = on[0] > 0 and on[1] > 0
	# the circle breathes, faster and brighter while someone is taking it
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.5 + 0.5 * sin(t * (9.0 if holder >= 0 else (14.0 if contested else 2.5)))
	_hill_mat.albedo_color.a = 0.16 + 0.14 * pulse + (0.12 if holder >= 0 else 0.0)
	_ring_mat.emission_energy_multiplier = 2.2 + 2.0 * pulse
	_hill_light.light_energy = 1.0 + 1.2 * pulse
	hud.update_hill(hold_team, hold_t / HOLD_TIME, contested, player.alive and _on_hill(player))
	if round_live and holder >= 0 and hold_t >= HOLD_TIME:
		_round_won(holder)


func _slot_for(i: int) -> int:
	# which of the 8 gun slots the i-th member of a team fills: at 4 v 4, one of each gun (slots 0, 2, 4, 6)
	return i if koth_team >= 8 else i * 2


func _start_round() -> void:
	round_num += 1
	hold_team = -1
	hold_t = 0.0
	var crew := _base_slots(0)
	var opps := _base_slots(1)
	# hand out this round's guns: each slot moves on to the next category
	player.gun_kind = Guns.for_slot(_slot_for(0), round_num)
	for b in bots:
		b.set_gun(Guns.for_slot(b.slot, round_num))
	player.respawn(crew[0], _facing_center(crew[0]))
	print("[game] round %d: you %s, crew %s, opps %s" % [round_num, player.gun_kind,
		bots.filter(func(b): return b.team == 0).map(func(b): return b.gun_kind),
		bots.filter(func(b): return b.team == 1).map(func(b): return b.gun_kind)])
	var ci := 1
	var oi := 0
	for b in bots:
		var p: Vector3
		if b.team == 0:
			p = crew[ci % crew.size()]
			ci += 1
		else:
			p = opps[oi % opps.size()]
			oi += 1
		b.respawn(p)
		b.rotation.y = _facing_center(p)
	hud.update_rounds(round_num, round_wins[0], round_wins[1], ROUNDS_TO_WIN)
	hud.center_message("ROUND %d
TAKE THE CIRCLE
YOU'VE GOT THE %s" % [round_num, Guns.STATS[player.gun_kind].name if player.gun_kind != "pistol" else "PISTOL"], 3.0)
	round_live = true


func _round_won(team: int) -> void:
	round_live = false
	hold_team = -1
	hold_t = 0.0
	round_wins[team] += 1
	hud.update_rounds(round_num, round_wins[0], round_wins[1], ROUNDS_TO_WIN)
	if round_wins[team] >= ROUNDS_TO_WIN:
		_end_match(team == 0)
		return
	hud.center_message(("YOUR CREW TOOK THE HOOD" if team == 0 else "THE OPPS TOOK THE HOOD") + "
%d - %d" % [round_wins[0], round_wins[1]], ROUND_BREAK)
	await get_tree().create_timer(ROUND_BREAK).timeout
	if not match_over:
		_start_round()


func _auto_quality(delta: float) -> void:
	# measured work per frame, GPU or CPU, whichever is the bottleneck (not the frame rate, which
	# vsync caps at 60 and so can't show how much room is left)
	var vp := get_viewport().get_viewport_rid()
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(vp) \
		+ (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	var ms := maxf(RenderingServer.viewport_get_measured_render_time_gpu(vp), cpu)
	if ms <= 0.0:
		return # no measurement yet
	_frame_ms = lerpf(_frame_ms, ms, clampf(delta * 6.0, 0.0, 1.0))
	_slow_t = _slow_t + delta if _frame_ms > SLOW_MS else 0.0
	_fast_t = _fast_t + delta if _frame_ms < FAST_MS else 0.0
	if _slow_t > 1.0 and quality < QUALITY_LEVELS.size() - 1:
		_set_quality(quality + 1)
	elif _fast_t > 8.0 and quality > 0:
		_set_quality(quality - 1)


func _set_quality(level: int) -> void:
	quality = level
	_slow_t = 0.0
	_fast_t = 0.0
	var q: Array = QUALITY_LEVELS[level]
	for t in map.grass_tiles:
		t[0].visibility_range_end = t[1] * q[0]
	get_viewport().scaling_3d_scale = q[1]
	sun.directional_shadow_max_distance = q[2]
	get_viewport().mesh_lod_threshold = q[3]
	hud.quality = level
	print("[game] detail level %d (frame %.1f ms)" % [level, _frame_ms])


func _facing_center(pos: Vector3) -> float:
	if mode == "koth":
		var h := HILL - pos
		return atan2(-h.x, -h.z)
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
	if mode == "koth":
		return _base_slots(0)[randi() % koth_team]
	return _farthest_from(map.player_spawns, enemies_of(0).map(func(b): return b.global_position))


func _pick_bot_spawn(bot: Node) -> Vector3:
	if mode == "koth":
		return _base_slots(bot.team)[randi() % koth_team]
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
	if mode == "koth":
		# kills don't score here, the circle does: back to your side's end after the wait
		hud.killfeed("%s  dropped  %s%s" % [who, bot.display_name, hs], Color(1, 0.9, 0.5) if attacker == player else (Color(1, 0.35, 0.3) if bot.team == 0 else Color(0.55, 0.75, 1.0)))
		await get_tree().create_timer(BOT_RESPAWN).timeout
		if not match_over and is_instance_valid(bot) and not bot.alive:
			var bp := _pick_bot_spawn(bot)
			bot.respawn(bp)
			bot.rotation.y = _facing_center(bp)
		return
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
	if mode == "koth":
		hud.center_message("YOU GOT DROPPED", PLAYER_RESPAWN)
		await get_tree().create_timer(PLAYER_RESPAWN).timeout
		if not match_over and not player.alive:
			var ksp := _pick_player_spawn()
			player.respawn(ksp, _facing_center(ksp))
		return
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
	round_live = false
	if mode == "koth":
		var km := "YOU RUN THE HOOD" if won else "THE OPPS RUN THE HOOD"
		hud.center_message("%s
%d - %d
Press ENTER / A to run it back" % [km, round_wins[0], round_wins[1]])
		return
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
		sc.global_position = gp + cb.x * (-0.28 if "--fp-left" in args else 0.28) + cb.y * 0.04 + cb.z * 0.02 # --fp-left: from the thumb side
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
