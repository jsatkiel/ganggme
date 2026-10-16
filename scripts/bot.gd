extends CharacterBody3D
## AI crew member. team 1 = the opps (hunt you and your teammates), team 0 = your teammate
## (sticks near you and fights the opps). Patrols, picks the nearest enemy it can see, strafes and fires bursts.

const Sfx = preload("res://scripts/sfx.gd")
const Fx = preload("res://scripts/fx.gd")
const CrewModel = preload("res://scripts/crew_model.gd")

const SPEED := 4.2
const STRAFE_SPEED := 2.6
const GRAVITY := 16.0
const MAX_HEALTH := 100.0
const SIGHT_RANGE := 70.0
const DAMAGE := 9.0
const OPP_COLORS := [Color(0.72, 0.05, 0.08), Color(0.62, 0.04, 0.06)] # bandana color, placeholder rival crew: red
const CREW_COLOR := Color(0.1, 0.25, 0.75) # placeholder: your crew wears blue

var game: Node
var map: Node
var display_name := "OPP"
var team := 1
var target: Node3D # enemy currently in sight

var health := MAX_HEALTH
var alive := true
var waypoint := Vector3.ZERO
var has_waypoint := false
var last_known := Vector3.ZERO
var has_last_known := false
var stuck_t := 0.0
var think_t := 0.0
var sees_player := false
var react_t := 0.0
var fire_cd := 0.0
var burst_left := 0
var strafe_dir := 1.0
var strafe_t := 0.0

var model # CrewModel
var muzzle: Node3D
var muzzle_light: OmniLight3D
var col_shape: CollisionShape3D
var shot_audio: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("bots")
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(62) # walk up 15 cm curbs without jumping
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.85
	col_shape = CollisionShape3D.new()
	col_shape.shape = cap
	col_shape.position.y = 0.925
	add_child(col_shape)
	_build_model()
	shot_audio = AudioStreamPlayer3D.new()
	shot_audio.stream = Sfx.gunshot()
	shot_audio.unit_size = 14.0
	shot_audio.volume_db = -3.0
	shot_audio.max_polyphony = 4
	shot_audio.position.y = 1.3
	add_child(shot_audio)


func _build_model() -> void:
	# black hoodie, hood down, bandana on the forehead + one in the back pocket (crew_model.gd)
	model = CrewModel.new()
	model.bandana_color = CREW_COLOR if team == 0 else OPP_COLORS[randi() % OPP_COLORS.size()]
	add_child(model)
	if team == 0:
		# name tag so you can tell your teammate apart at a glance
		var tag := Label3D.new()
		tag.text = "▼ " + display_name
		tag.modulate = Color(0.45, 0.65, 1.0)
		tag.outline_size = 8
		tag.font_size = 40
		tag.pixel_size = 0.004
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.fixed_size = false
		tag.position.y = 2.25
		add_child(tag)
	muzzle = Node3D.new()
	add_child(muzzle)
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color(1.0, 0.75, 0.4)
	muzzle_light.omni_range = 5.0
	muzzle_light.light_energy = 0.0
	muzzle.add_child(muzzle_light)


func _player() -> Node3D:
	return game.player if game else null


func _alive(n: Node3D) -> bool:
	return is_instance_valid(n) and n.alive


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if not alive or (game and game.match_over):
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return

	muzzle_light.light_energy = move_toward(muzzle_light.light_energy, 0.0, 50.0 * delta)
	fire_cd -= delta
	think_t -= delta
	if think_t <= 0.0:
		think_t = 0.15
		_think()

	var p := target
	var move := Vector3.ZERO
	if sees_player and _alive(p):
		var to_p := p.global_position - global_position
		to_p.y = 0
		_face(to_p, delta, 10.0)
		strafe_t -= delta
		if strafe_t <= 0.0:
			strafe_t = randf_range(0.6, 1.6)
			strafe_dir = [-1.0, 1.0, 0.0][randi() % 3]
		var side := to_p.normalized().cross(Vector3.UP)
		move = side * strafe_dir * STRAFE_SPEED
		if to_p.length() > 30.0:
			move += to_p.normalized() * SPEED * 0.7
		react_t -= delta
		if react_t <= 0.0 and fire_cd <= 0.0:
			_fire(p)
	else:
		var goal := Vector3.ZERO
		var have_goal := false
		if has_last_known:
			goal = last_known
			have_goal = true
			if _flat_dist(goal) < 1.5:
				has_last_known = false
		if not have_goal:
			if not has_waypoint or _flat_dist(waypoint) < 1.5 or stuck_t > 1.2:
				_pick_waypoint()
			goal = waypoint
			have_goal = has_waypoint
		if have_goal:
			var dir := goal - global_position
			dir.y = 0
			if dir.length() > 0.1:
				move = dir.normalized() * SPEED
				_face(dir, delta, 6.0)

	velocity.x = move.x
	velocity.z = move.z
	move_and_slide()

	var hspeed := Vector2(velocity.x, velocity.z).length()
	if move.length() > 0.5 and hspeed < 0.6:
		stuck_t += delta
		if has_last_known and stuck_t > 1.2:
			has_last_known = false
	else:
		stuck_t = 0.0
	# animation + keep the muzzle at the gun hand
	if sees_player:
		model.play("Pistol_Aim_Neutral")
	elif hspeed > 0.5:
		model.play("Jog_Fwd")
	else:
		model.play("Pistol_Idle")
	_update_muzzle()


func _update_muzzle() -> void:
	var sk: Skeleton3D = model.skeleton
	if sk == null:
		return
	var hand := sk.find_bone("hand_r")
	if hand < 0:
		return
	var hand_pos := sk.global_transform * sk.get_bone_global_pose(hand).origin
	muzzle.global_position = hand_pos - global_transform.basis.z * 0.22 + Vector3(0, 0.04, 0)


func _flat_dist(v: Vector3) -> float:
	return Vector2(v.x - global_position.x, v.z - global_position.z).length()


func _face(dir: Vector3, delta: float, speed: float) -> void:
	var want := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(speed * delta, 0.0, 1.0))


func _clear_line(from: Vector3, to: Vector3, mask: int) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _think() -> void:
	# look for the closest enemy we can actually see
	var eye := global_position + Vector3(0, 1.6, 0)
	var fwd := -global_transform.basis.z
	var best: Node3D = null
	var best_d := INF
	for e in (game.enemies_of(team) if game else []):
		var aim: Vector3 = e.global_position + Vector3(0, 1.3, 0)
		var dist := eye.distance_to(aim)
		if dist > SIGHT_RANGE or dist >= best_d:
			continue
		var in_view: bool = fwd.dot((aim - eye).normalized()) > 0.25 or dist < 12.0 or (sees_player and e == target)
		if in_view and _clear_line(eye, aim, 1):
			best = e
			best_d = dist
	var can_see := best != null
	if can_see and (not sees_player or best != target):
		react_t = randf_range(0.35, 0.75)
		burst_left = 0
	if not can_see and sees_player and _alive(target):
		last_known = target.global_position
		has_last_known = true
	if can_see:
		target = best
	sees_player = can_see


func _pick_waypoint() -> void:
	stuck_t = 0.0
	var pts: Array = map.waypoints
	if pts.is_empty():
		return
	var p := _player()
	var best := Vector3.ZERO
	var found := false
	var best_score := INF
	for i in 14:
		var w: Vector3 = pts[randi() % pts.size()]
		var d := _flat_dist(w)
		if d < 5.0 or d > 32.0:
			continue
		if not _clear_line(global_position + Vector3(0, 0.9, 0), w + Vector3(0, 0.9, 0), 1 | 2):
			continue
		# lean toward the player so fights actually happen
		var score := randf() * 30.0
		if p:
			score += w.distance_to(p.global_position) * 0.6
		if score < best_score:
			best_score = score
			best = w
			found = true
	if found:
		waypoint = best
		has_waypoint = true
	else:
		has_waypoint = false
		rotation.y += PI * 0.5


func _fire(p: Node3D) -> void:
	if burst_left <= 0:
		burst_left = randi_range(3, 6)
	burst_left -= 1
	fire_cd = randf_range(0.11, 0.16) if burst_left > 0 else randf_range(0.5, 1.0)

	var crouched: bool = p.get("crouching") == true
	var aim_at: Vector3 = p.global_position + Vector3(0, 0.8 if crouched else 1.3, 0)
	var dist := global_position.distance_to(p.global_position)
	var chance := 0.5 - dist * 0.006
	var pv: Vector3 = p.velocity
	if Vector2(pv.x, pv.z).length() > 6.0:
		chance -= 0.15
	if crouched:
		chance -= 0.1
	chance = clampf(chance, 0.06, 0.55)
	var hit := randf() < chance
	var end := aim_at
	if not hit:
		end = aim_at + Vector3(randf_range(-1, 1), randf_range(-0.6, 0.8), randf_range(-1, 1)).normalized() * randf_range(0.6, 1.5)
		end = muzzle.global_position + (end - muzzle.global_position) * 1.8
	Fx.tracer(get_tree().current_scene, muzzle.global_position, end, Color(1.0, 0.6, 0.35))
	muzzle_light.light_energy = 3.0
	shot_audio.pitch_scale = randf_range(0.9, 1.05)
	shot_audio.play()
	if hit:
		p.take_damage(DAMAGE, global_position, self)


func is_headshot(pos: Vector3) -> bool:
	return pos.y > global_position.y + 1.45


func take_damage(amount: float, from_pos: Vector3, attacker: Node = null, headshot := false) -> bool:
	if not alive:
		return false
	health -= amount
	# getting shot: turn toward the shooter
	if not sees_player:
		var dir := from_pos - global_position
		dir.y = 0
		if dir.length() > 0.1:
			rotation.y = atan2(-dir.x, -dir.z)
		last_known = from_pos
		has_last_known = true
	model.scale = Vector3(1.08, 0.95, 1.08)
	create_tween().tween_property(model, "scale", Vector3.ONE, 0.12)
	if health <= 0.0:
		_die(attacker, headshot)
		return true
	return false


func _die(_attacker: Node, headshot: bool) -> void:
	alive = false
	sees_player = false
	col_shape.set_deferred("disabled", true)
	model.play("Death01", 0.1)
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_callback(func(): model.visible = false)
	if game:
		game.on_bot_killed(self, headshot, _attacker)


func respawn(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	health = MAX_HEALTH
	model.rotation = Vector3.ZERO
	model.position = Vector3.ZERO
	model.visible = true
	model.play("Pistol_Idle", 0.0)
	col_shape.set_deferred("disabled", false)
	has_waypoint = false
	has_last_known = false
	sees_player = false
	alive = true
