extends CharacterBody3D
## First-person player: COD-style movement (sprint, slide, crouch, jump) and the crew pistol.

const Sfx = preload("res://scripts/sfx.gd")
const Fx = preload("res://scripts/fx.gd")
const Pistol = preload("res://scripts/pistol.gd")
const MuzzleFlash = preload("res://scripts/muzzle_flash.gd")
const CrewModel = preload("res://scripts/crew_model.gd")
const Loadout = preload("res://scripts/loadout.gd")
const CREW_COLOR := Color(0.1, 0.25, 0.75) # placeholder: your crew wears blue

# movement
const WALK_SPEED := 5.5
const SPRINT_SPEED := 8.5
const CROUCH_SPEED := 2.8
const ADS_SPEED := 3.4
const JUMP_VELOCITY := 5.4
const GRAVITY := 16.0
const SLIDE_SPEED := 12.5
const SLIDE_TIME := 0.75
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const MOUSE_SENS := 0.0022
const STICK_SENS := 3.4

# health
const MAX_HEALTH := 100.0
const REGEN_DELAY := 4.0
const REGEN_RATE := 40.0

# pistol
const MAG_SIZE := 15
const START_RESERVE := 90
const FIRE_INTERVAL := 0.15
const RELOAD_TIME := 1.5
const DAMAGE := 34.0
const HEADSHOT_MULT := 2.0
const HIP_FOV := 78.0
const ADS_FOV := 42.0
const WEAPON_HIP := Vector3(0.22, -0.13, -0.04)
const HIP_AIM_DIST := 15.0 # hip fire: the barrel points at the crosshair this far out (where the bullets go)
const ADS_DISTANCE := 0.5 # how far in front of the eye the sights sit when aiming
const FOREARM_RISE := 12.0 # degrees the forearm climbs from below the screen up to the hand (the wrist bends this much)
const WEAPON_ADS := Vector3(0.0, 0.0, 0.06)

var game: Node
var hud: CanvasLayer

var head: Node3D
var camera: Camera3D
var weapon: Node3D
var arms # CrewModel, first-person arms
var muzzle: Node3D
var flash # MuzzleFlash
var col_shape: CollisionShape3D
var capsule: CapsuleShape3D
var shot_audio: AudioStreamPlayer
var tick_audio: AudioStreamPlayer
var hurt_audio: AudioStreamPlayer

var pitch := 0.0
var recoil_left := 0.0
var recoil_side := 0.0 # sideways kick still to recover
var gun_bounce_rot := Vector3.ZERO # this shot's random bounce of the gun model, dying away
var gun_bounce_pos := Vector3.ZERO
var _gun_pos := WEAPON_HIP # the gun's smoothed pose, before the bounce
var _gun_rot := Vector3.ZERO
var health := MAX_HEALTH
var since_damage := 99.0
var alive := true
var invuln := 0.0

var ammo := MAG_SIZE
var reserve := START_RESERVE
# the equipped class (Loadout.stats), set by apply_loadout on every spawn
var weapon_name := "GLOCK 17"
var mag_size := MAG_SIZE
var reserve_max := START_RESERVE
var fire_interval := FIRE_INTERVAL
var reload_time := RELOAD_TIME
var damage := DAMAGE
var recoil_mult := 1.0
var spread_mult := 1.0
var speed_mult := 1.0
var sprint_mult := 1.0
var regen_bonus := 0.0
var flash_size := 1.0
var hip_fov := HIP_FOV
var laser_on := true # T / D-pad left switches the laser sight's beam on and off
var laser_beam: MeshInstance3D # set when the laser sight is equipped
var laser_dot: MeshInstance3D
var fire_cd := 0.0
var reloading := false
var reload_t := 0.0
var ads := 0.0
var bloom := 0.0
var current_spread := 0.0
var kick := 0.0
var fire_queued := 0.0 # single fire: a trigger pull waits this long for the gun to be ready
var elbow_bend := 0.0 # radians the elbow is folded by the last shot, springing back
var _elbow := -1 # forearm bone of the first-person arms, and its fitted pose
var _elbow_rest := Quaternion.IDENTITY
var _elbow_axis := Vector3.RIGHT # the elbow's hinge, in the upper arm's space

var sprinting := false
var crouching := false
var sliding := false
var slide_t := 0.0
var slide_dir := Vector3.ZERO
var bob_t := 0.0
var force_ads := false # dev: --ads screenshots


func _ready() -> void:
	add_to_group("player")
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(62) # walk up 15 cm curbs without jumping
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = STAND_HEIGHT
	col_shape = CollisionShape3D.new()
	col_shape.shape = capsule
	col_shape.position.y = STAND_HEIGHT / 2.0
	add_child(col_shape)

	head = Node3D.new()
	head.position.y = STAND_HEIGHT - 0.18
	add_child(head)
	camera = Camera3D.new()
	camera.fov = hip_fov
	camera.near = 0.03
	camera.far = 600.0
	head.add_child(camera)
	camera.make_current()
	_build_weapon()

	shot_audio = _audio(preload("res://assets/audio/pistol_fp.wav"), -4.0, 8)
	tick_audio = _audio(Sfx.hit_tick(), -14.0, 4)
	hurt_audio = _audio(Sfx.hurt(), -2.0, 2)


func invert_sign() -> float:
	return -1.0 if Loadout.settings.invert else 1.0


func apply_settings() -> void:
	hip_fov = Loadout.settings.fov
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(Loadout.settings.volume, 0.001)))
	if hud:
		hud.fps_label.visible = Loadout.settings.fps


func apply_loadout() -> void:
	# the active class from the pause menu: the pistol's numbers, attachments, perks and camo
	var c := Loadout.current()
	var s := Loadout.stats(c)
	weapon_name = s.name
	mag_size = s.mag
	reserve_max = s.reserve
	fire_interval = s.interval
	reload_time = s.reload
	damage = s.damage
	recoil_mult = s.recoil
	spread_mult = s.spread
	speed_mult = s.mobility * s.speed
	sprint_mult = s.sprint
	regen_bonus = s.regen
	flash_size = s.flash
	if ResourceLoader.exists(s.sound):
		shot_audio.stream = load(s.sound)
	shot_audio.volume_db = -4.0 + s.volume
	var parts := {}
	for slot in Loadout.SLOTS:
		parts[slot] = c[slot]
	if arms and arms.gun:
		Pistol.dress(arms.gun, Loadout.camo(c.camo), parts)
		laser_beam = null
		for n in arms.gun.get_children():
			if n.has_meta("beam"):
				laser_beam = n
	apply_settings()


func _audio(stream: AudioStream, db: float, poly: int) -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.stream = stream
	a.volume_db = db
	a.max_polyphony = poly
	add_child(a)
	return a


func _build_weapon() -> void:
	# first-person view: the same rigged crew body the bots use (real hands, black hoodie sleeves),
	# frozen in its two-hand pistol aim with the head hidden, then fitted so the Glock's sights
	# sit dead center when aiming down sights
	weapon = Node3D.new()
	weapon.position = WEAPON_HIP
	camera.add_child(weapon)
	arms = CrewModel.new()
	arms.first_person = true
	arms.bandana_color = CREW_COLOR
	weapon.add_child(arms)
	arms.play("Pistol_Aim_Neutral", 0.0)
	_fit_arms.call_deferred()

	muzzle = Node3D.new()
	muzzle.position = Pistol.MUZZLE
	arms.gun.add_child(muzzle) # (no tracers: the user cut them)
	flash = MuzzleFlash.new()
	muzzle.add_child(flash)


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and alive:
		var sens: float = MOUSE_SENS * Loadout.settings.sens * lerpf(1.0, 0.6, ads)
		rotate_y(-event.relative.x * sens)
		pitch = clampf(pitch - event.relative.y * sens * invert_sign(), deg_to_rad(-88), deg_to_rad(88))


func _process(_delta: float) -> void:
	_update_laser()


func _update_laser() -> void:
	# stretch the beam out to whatever it points at and put the red dot there
	var on := laser_beam != null and is_instance_valid(laser_beam) and laser_on and alive
	if laser_beam and is_instance_valid(laser_beam):
		laser_beam.visible = on
	if laser_dot == null:
		laser_dot = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.025
		sm.height = 0.05
		laser_dot.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1, 0.15, 0.1)
		laser_dot.material_override = m
		laser_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		laser_dot.top_level = true
		add_child(laser_dot)
	laser_dot.visible = false
	if not on:
		return
	var from := laser_beam.global_position
	var dir := -laser_beam.global_basis.z.normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 90.0, 1 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var d := 90.0
	if not hit.is_empty():
		d = from.distance_to(hit.position)
		laser_dot.global_position = hit.position - dir * 0.02
		laser_dot.visible = true
	laser_beam.scale.z = d / maxf(laser_beam.get_parent().global_basis.z.length(), 0.001)


func _physics_process(delta: float) -> void:
	if not alive:
		velocity.x = move_toward(velocity.x, 0, 20 * delta)
		velocity.z = move_toward(velocity.z, 0, 20 * delta)
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	invuln = maxf(invuln - delta, 0.0)
	_look(delta)
	_move(delta)
	_weapon_update(delta)
	_regen(delta)


func _look(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length() > 0.0:
		look *= look.length() # response curve: fine aim near center, fast turns at full tilt
		var s: float = STICK_SENS * Loadout.settings.stick * lerpf(1.0, 0.5, ads) * delta
		rotate_y(-look.x * s)
		pitch = clampf(pitch - look.y * s * 0.75 * invert_sign(), deg_to_rad(-88), deg_to_rad(88))
	# recoil recovery: pull back down (and part of the way back across) from the kick
	if recoil_left > 0.0:
		var r := minf(recoil_left, 3.0 * delta)
		pitch -= r
		recoil_left -= r
	if recoil_side != 0.0:
		var s2 := signf(recoil_side) * minf(absf(recoil_side), 2.0 * delta)
		rotate_y(-s2)
		recoil_side -= s2
	head.rotation.x = pitch


func _move(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := transform.basis * Vector3(input.x, 0, input.y)
	var on_floor := is_on_floor()

	if Input.is_action_just_pressed("sprint"):
		if crouching and not sliding:
			crouching = false # sprint stands you up out of a crouch
		if input.y < -0.3:
			sprinting = true
	if input.y > -0.3 or Input.is_action_pressed("aim") or Input.is_action_pressed("fire") or crouching:
		sprinting = false

	if Input.is_action_just_pressed("crouch"):
		if sprinting and on_floor:
			sliding = true
			slide_t = SLIDE_TIME
			var hv := Vector3(velocity.x, 0, velocity.z)
			slide_dir = hv.normalized() if hv.length() > 0.5 else -transform.basis.z
			sprinting = false
			crouching = true
		elif not sliding:
			crouching = not crouching

	if Input.is_action_just_pressed("jump") and on_floor:
		if crouching and not sliding:
			crouching = false
		else:
			velocity.y = JUMP_VELOCITY
			sliding = false
			crouching = false

	if not on_floor:
		velocity.y -= GRAVITY * delta

	if sliding:
		slide_t -= delta
		var spd := lerpf(CROUCH_SPEED, SLIDE_SPEED, clampf(slide_t / SLIDE_TIME, 0.0, 1.0))
		velocity.x = slide_dir.x * spd
		velocity.z = slide_dir.z * spd
		if slide_t <= 0.0:
			sliding = false
	else:
		var speed := WALK_SPEED * speed_mult
		if sprinting:
			speed = SPRINT_SPEED * speed_mult * sprint_mult
		elif crouching:
			speed = CROUCH_SPEED
		if ads > 0.5:
			speed = minf(speed, ADS_SPEED)
		var accel := 14.0 if on_floor else 3.0
		var hv := Vector3(velocity.x, 0, velocity.z).lerp(wish * speed, clampf(accel * delta, 0.0, 1.0))
		velocity.x = hv.x
		velocity.z = hv.z

	move_and_slide()

	# crouch height + head bob
	var target_h := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	capsule.height = move_toward(capsule.height, target_h, 6.0 * delta)
	col_shape.position.y = capsule.height / 2.0
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var bob := 0.0
	if on_floor and hspeed > 1.0 and not sliding:
		bob_t += delta * hspeed * 1.7
		bob = sin(bob_t * 2.0) * 0.035 * (1.0 - ads)
	head.position.y = capsule.height - 0.18 + bob
	camera.rotation.z = lerpf(camera.rotation.z, (0.06 if sliding else 0.0), 10.0 * delta)


func _weapon_update(delta: float) -> void:
	fire_cd -= delta
	bloom = move_toward(bloom, 0.0, 0.25 * delta)
	kick = move_toward(kick, 0.0, 8.0 * delta)

	var want_ads := (Input.is_action_pressed("aim") or force_ads) and not sprinting and not reloading and not sliding
	ads = move_toward(ads, 1.0 if want_ads else 0.0, delta * 6.0)
	camera.fov = lerpf(hip_fov, ADS_FOV, ads)

	if reloading:
		reload_t -= delta
		if reload_t <= 0.0:
			var take := mini(mag_size - ammo, reserve)
			ammo += take
			reserve -= take
			reloading = false
			_update_ammo_hud()
	elif Input.is_action_just_pressed("reload") and ammo < mag_size and reserve > 0:
		_start_reload()

	if Input.is_action_just_pressed("laser") and laser_beam:
		laser_on = not laser_on

	# single fire: one shot per trigger pull (a pull just before the gun is ready still counts)
	if Input.is_action_just_pressed("fire"):
		fire_queued = 0.2
	fire_queued -= delta
	if fire_queued > 0.0 and fire_cd <= 0.0 and not reloading and not sprinting:
		fire_queued = 0.0
		if ammo > 0:
			_shoot()
		elif reserve > 0:
			_start_reload()

	# spread: bigger when moving / jumping, tight when aiming
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var hip := 0.03 + clampf(hspeed / SPRINT_SPEED, 0.0, 1.0) * 0.035 + bloom
	if not is_on_floor():
		hip += 0.05
	if crouching:
		hip *= 0.75
	current_spread = lerpf(hip * spread_mult, 0.002 + bloom * 0.15, ads)
	if hud:
		hud.set_spread(current_spread, ads)

	# weapon pose
	var hspeed_n := clampf(hspeed / SPRINT_SPEED, 0.0, 1.0)
	var target := WEAPON_HIP.lerp(WEAPON_ADS, ads)
	target += Vector3(sin(bob_t) * 0.012, absf(cos(bob_t)) * 0.01, 0) * hspeed_n * (1.0 - ads)
	target.z += kick * 0.05
	# point the barrel at the crosshair: tip it in toward the screen center from its spot at the lower right
	var hip_rot := Vector3(atan2(-WEAPON_HIP.y, HIP_AIM_DIST), atan2(WEAPON_HIP.x, HIP_AIM_DIST), 0.0)
	var rot := hip_rot * (1.0 - ads)
	if sprinting:
		target += Vector3(-0.05, -0.06, 0.05)
		rot = Vector3(-0.3, 0.6, 0.2)
	if reloading:
		var p := 1.0 - absf((reload_t / reload_time) * 2.0 - 1.0)
		target.y -= 0.12 * p
		rot.x -= 0.6 * p
		rot.z += 0.5 * p
	rot.x += kick * 0.06
	_gun_pos = _gun_pos.lerp(target, clampf(18.0 * delta, 0.0, 1.0))
	_gun_rot = _gun_rot.lerp(rot, clampf(12.0 * delta, 0.0, 1.0))
	# this shot's bounce goes on top of the smoothed pose, so it snaps, then dies away
	gun_bounce_rot = gun_bounce_rot.lerp(Vector3.ZERO, clampf(16.0 * delta, 0.0, 1.0))
	gun_bounce_pos = gun_bounce_pos.lerp(Vector3.ZERO, clampf(16.0 * delta, 0.0, 1.0))
	weapon.position = _gun_pos + gun_bounce_pos
	weapon.rotation = _gun_rot + gun_bounce_rot
	# the elbow folds with the kick and springs back out
	elbow_bend = lerpf(elbow_bend, 0.0, clampf(11.0 * delta, 0.0, 1.0))
	if _elbow >= 0:
		arms.anim_skeleton.set_bone_pose_rotation(_elbow, Quaternion(_elbow_axis, elbow_bend) * _elbow_rest)


func _start_reload() -> void:
	reloading = true
	reload_t = reload_time
	sprinting = false
	_update_ammo_hud()


func _shoot() -> void:
	fire_cd = fire_interval
	ammo -= 1
	var basis_cam := camera.global_transform.basis
	var forward := -basis_cam.z
	var off := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * tan(current_spread)
	var dir := (forward + basis_cam.x * off.x + basis_cam.y * off.y).normalized()
	var from := camera.global_position
	var to := from + dir * 400.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var root := get_tree().current_scene
	if hit:
		var col: Object = hit.collider
		if col.get("team") == 0:
			pass # your teammate: no friendly fire
		elif col.has_method("take_damage"):
			var headshot: bool = col.has_method("is_headshot") and col.is_headshot(hit.position)
			var killed: bool = col.take_damage(damage * (HEADSHOT_MULT if headshot else 1.0), global_position, self, headshot)
			Fx.puff(root, hit.position, Color(0.6, 0.1, 0.1))
			tick_audio.play()
			if hud:
				hud.show_hitmarker(headshot, killed)
		else:
			Fx.impact(root, hit.position, hit.normal)

	# recoil: every shot throws the aim a different way, mostly up with a random left/right jolt; most of it
	# recovers, the rest stacks up, so a quick string of shots climbs and wanders like a real pistol
	# aimed: 0.78, moving or not; from the hip: 1.8 standing still, up to 1.5x that on the move (full at walking pace or in the air)
	var moving := 1.0 if not is_on_floor() else clampf(Vector2(velocity.x, velocity.z).length() / WALK_SPEED, 0.0, 1.0)
	var steady := lerpf(1.8 * lerpf(1.0, 1.5, moving), 0.78, ads) * recoil_mult
	if laser_beam and laser_on:
		steady *= lerpf(0.75, 1.0, ads) # the laser only helps from the hip
	var up := deg_to_rad(randf_range(1.1, 2.0)) * steady
	var side := deg_to_rad(randf_range(-1.1, 1.1)) * steady
	pitch = clampf(pitch + up, deg_to_rad(-88), deg_to_rad(88))
	rotate_y(side)
	recoil_left += up * 0.7
	recoil_side += side * 0.5
	# the gun itself bounces: a random tilt, twist and shove each shot, settling fast; from the hip it jumps
	# harder still and the elbow folds with it
	var violent := steady * lerpf(1.4, 1.0, ads)
	kick = 1.0
	if flash_size > 0.0:
		flash.fire(lerpf(1.0, 2.0, ads) * flash_size)
	gun_bounce_rot = Vector3(randf_range(0.10, 0.20), randf_range(-0.09, 0.09), randf_range(-0.16, 0.16)) * violent
	gun_bounce_pos = Vector3(randf_range(-0.014, 0.014), randf_range(0.004, 0.014), randf_range(0.0, 0.02)) * violent
	elbow_bend = deg_to_rad(randf_range(7.0, 11.0)) * violent * lerpf(1.0, 0.35, ads)
	if hud:
		hud.kick_crosshair(Vector2(rad_to_deg(side), -rad_to_deg(up)) * 9.0, violent)
	bloom = minf(bloom + 0.01, 0.06)
	shot_audio.pitch_scale = randf_range(0.94, 1.06)
	shot_audio.play()
	_update_ammo_hud()
	if ammo == 0 and reserve > 0:
		_start_reload()


func _regen(delta: float) -> void:
	since_damage += delta
	if since_damage > REGEN_DELAY + regen_bonus and health < MAX_HEALTH:
		health = minf(MAX_HEALTH, health + REGEN_RATE * delta)
		if hud:
			hud.update_health(health)


func _update_ammo_hud() -> void:
	if hud:
		hud.update_ammo(ammo, reserve, reloading, weapon_name)


func take_damage(amount: float, from_pos: Vector3, attacker: Node = null, _headshot := false) -> bool:
	if not alive or invuln > 0.0:
		return false
	health -= amount
	since_damage = 0.0
	hurt_audio.play()
	if hud:
		hud.update_health(health)
		hud.show_damage(from_pos)
	if health <= 0.0:
		_die(attacker)
		return true
	return false


func is_headshot(pos: Vector3) -> bool:
	return pos.y > global_position.y + capsule.height - 0.3


func _die(attacker: Node) -> void:
	alive = false
	health = 0.0
	weapon.visible = false
	sliding = false
	crouching = false
	reloading = false
	var tw := create_tween()
	tw.tween_property(head, "position:y", 0.4, 0.5)
	tw.parallel().tween_property(camera, "rotation:z", 0.6, 0.5)
	if game:
		game.on_player_died(attacker)


func respawn(pos: Vector3, facing: float) -> void:
	apply_loadout() # a new class picked in the pause menu goes on here
	global_position = pos
	rotation.y = facing
	velocity = Vector3.ZERO
	pitch = 0.0
	recoil_left = 0.0
	recoil_side = 0.0
	elbow_bend = 0.0
	fire_queued = 0.0
	health = MAX_HEALTH
	since_damage = 99.0
	ammo = mag_size
	reserve = reserve_max
	reloading = false
	crouching = false
	sliding = false
	capsule.height = STAND_HEIGHT
	head.position.y = STAND_HEIGHT - 0.18
	camera.rotation.z = 0.0
	weapon.visible = true
	invuln = 1.5
	alive = true
	if hud:
		hud.update_health(health)
	_update_ammo_hud()


func _fit_arms() -> void:
	await get_tree().create_timer(0.3).timeout # let the aim animation settle
	arms.freeze_pose("Pistol_Aim_Neutral", arms.anim.current_animation_position)
	await get_tree().process_frame
	_straighten_wrist()
	await get_tree().process_frame
	var keep := weapon.transform
	weapon.transform = Transform3D.IDENTITY
	arms.transform = Transform3D.IDENTITY
	_align_gun()
	# the forearm should rise from below the screen to the hand (like holding a real pistol out),
	# not point back at the eye: tip the rig up around the hand and bend the wrist back down to keep the gun level
	var sk: Skeleton3D = arms.anim_skeleton # the skeleton the pose is set on (the drawn arms copy it)
	var hand := sk.find_bone("hand_r")
	var to_cam := weapon.global_transform.affine_inverse() * sk.global_transform
	var hand_c: Vector3 = to_cam * sk.get_bone_global_pose(hand).origin
	var elbow_c: Vector3 = to_cam * sk.get_bone_global_pose(sk.get_bone_parent(hand)).origin
	var f := hand_c - elbow_c
	var tilt := deg_to_rad(FOREARM_RISE) - atan2(f.y, -f.z)
	arms.transform = Transform3D(Basis.IDENTITY, hand_c) * Transform3D(Basis(Vector3.RIGHT, tilt)) * Transform3D(Basis.IDENTITY, -hand_c) * arms.transform
	var axis: Vector3 = (sk.global_transform.basis.inverse() * weapon.global_transform.basis * Vector3.RIGHT).normalized()
	var parent_pose: Transform3D = sk.get_bone_global_pose(sk.get_bone_parent(hand))
	var new_global: Basis = Basis(axis, -tilt) * sk.get_bone_global_pose(hand).basis
	sk.set_bone_pose_rotation(hand, (parent_pose.basis.inverse() * new_global).orthonormalized().get_rotation_quaternion())
	await get_tree().process_frame
	_align_gun()
	weapon.transform = keep
	# remember the fitted elbow, and its hinge: across the upper arm and forearm (turning about it folds the arm)
	var fore := sk.get_bone_parent(hand)
	var upper := sk.get_bone_parent(fore)
	var u := sk.get_bone_global_pose(fore).origin - sk.get_bone_global_pose(upper).origin
	var fv := sk.get_bone_global_pose(hand).origin - sk.get_bone_global_pose(fore).origin
	_elbow_axis = (sk.get_bone_global_pose(upper).basis.inverse() * u.cross(fv)).normalized()
	_elbow_rest = sk.get_bone_pose_rotation(fore)
	_elbow = fore


func _straighten_wrist() -> void:
	# the aim pose cocks the hand off to the side of the forearm; swing it back in line (keeping its roll, so
	# the gun stays upright) before the rig is fitted to the screen
	var sk: Skeleton3D = arms.anim_skeleton
	var hand := sk.find_bone("hand_r")
	var fore := sk.get_bone_parent(hand)
	var knuckle := sk.find_bone("middle_01_r")
	if hand < 0 or knuckle < 0:
		return
	var hand_g := sk.get_bone_global_pose(hand)
	var fore_g := sk.get_bone_global_pose(fore)
	var along_forearm := (hand_g.origin - fore_g.origin).normalized()
	var along_hand := (sk.get_bone_global_pose(knuckle).origin - hand_g.origin).normalized()
	var new_global := Basis(Quaternion(along_hand, along_forearm)) * hand_g.basis
	sk.set_bone_pose_rotation(hand, (fore_g.basis.inverse() * new_global).orthonormalized().get_rotation_quaternion())


func _align_gun() -> void:
	# turn the rig so the barrel points straight ahead and the gun sits upright, sights centered.
	# The gun is read straight off the posed skeleton (the bone attachment may not have caught up yet)
	var sk: Skeleton3D = arms.anim_skeleton # the skeleton the pose is set on (the drawn arms copy it)
	var hand_world: Transform3D = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hand_r"))
	var g: Transform3D = weapon.global_transform.affine_inverse() * hand_world * arms.gun.transform
	var rot := Basis(Quaternion(-g.basis.z.normalized(), Vector3.FORWARD))
	var up: Vector3 = (rot * g.basis).y.normalized()
	rot = Basis(Vector3.BACK, atan2(up.x, up.y)) * rot
	var g2: Transform3D = Transform3D(rot) * g
	var sight: Vector3 = g2.origin + g2.basis.y.normalized() * Pistol.SIGHT_HEIGHT
	arms.transform = Transform3D(rot, Vector3(-sight.x, -sight.y, -ADS_DISTANCE - sight.z)) * arms.transform
