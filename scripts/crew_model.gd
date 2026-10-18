extends Node3D
## A crew member: the user's Mixamo-rigged male (Fuse body) in the user's hoodie, pants and Jordans with
## buzzed hair, a bandana tied around the forehead and another hanging out of the back pocket. The bandana
## color marks the crew.
## The UAL animations are made for the Quaternius base body, so that body stays as an invisible skeleton
## the animations play on, and the male copies its pose every frame (both stand in a T-pose, see Retarget).
## First person (the player's own arms) still draws the base body: only the forearms and hands show.
## Faces -Z like the rest of the game (the source models face +Z, so they are turned around).

const BODY := preload("res://assets/characters/Superhero_Male_FullBody.gltf")
const ANIMS := preload("res://assets/characters/UAL1_Standard.glb")
const MALE := preload("res://assets/characters/male/male.fbx")
const MALE_SKIN := preload("res://assets/characters/male/FuseModel_Body_Diffuse.png")
const MALE_NORMAL := preload("res://assets/characters/male/FuseModel_Body_Normal.png")
const MALE_OPACITY := preload("res://assets/characters/male/FuseModel_Body_Opacity.png")
const OUTFIT_SHADER := preload("res://scripts/outfit.gdshader")
const MALE_BODY_SHADER := preload("res://scripts/male_body.gdshader")
const Pistol := preload("res://scripts/pistol.gd")
const RigMap := preload("res://scripts/rig_map.gd")
# the user's hoodie, pants and Jordans + the buzzed hair, baked onto the male's skeleton by tools/bake_outfit.gd
const OUTFIT := "res://assets/characters/outfit/"
const GARMENTS := ["hoodie", "pants", "shoe_r", "shoe_l", "hair"]

# outfit regions painted by bone (see outfit.gdshader)
const HOODIE := 0
const PANTS := 1
const SHOES := 2
const SKIN := 3
const HEAD := 4 # skin too, but hidden in first person
const FOREARM := 5 # hoodie sleeve; with the hands, the only part drawn in first person

# locomotion (bots): legs cycle at the real ground speed, the upper body holds the pistol
const LEG_ANIMS := ["Idle", "Walk", "Jog_Fwd", "Sprint"]
const LEG_SPEEDS := [0.0, 1.1, 3.0, 4.8] # m/s each cycle covers, measured from its stride
const CUFF_SHIFT := 1.0 # first person: how far the sleeve's cuff slides onto the wrist (0 = as fitted, 1 = centered)
const MAX_LEG_TURN := deg_to_rad(75.0) # hips swing toward a strafe this far, the chest twists back to the target

static var _anim_lib: AnimationLibrary
static var _lash_mat: ShaderMaterial
static var _male_bodies := {} # first_person -> the male's body mesh, trimmed, with outfit regions in its vertex colors
static var _fp_sleeve: ArrayMesh # first person: the hoodie's right sleeve only
static var _male_mat: ShaderMaterial


class SpineTwist extends SkeletonModifier3D:
	## turns the chest back by `angle` (spread over the three spine bones) after the animation has posed the body,
	## so the hips can face where the legs are going while the gun stays on target
	var angle := 0.0
	var bones: Array[int] = []

	func _process_modification_with_delta(_delta: float) -> void:
		var sk := get_skeleton()
		if sk == null or absf(angle) < 0.001:
			return
		for b in bones:
			var parent := sk.get_bone_global_pose(sk.get_bone_parent(b))
			var axis := (parent.basis.inverse() * Vector3.UP).normalized()
			sk.set_bone_pose_rotation(b, Quaternion(axis, angle / bones.size()) * sk.get_bone_pose_rotation(b))


class Retarget extends SkeletonModifier3D:
	## poses the male like the animated base body: each bone turns by the same amount (in the character's space)
	## that its counterpart turned away from the shared T-pose; the hips also follow the pelvis up and down
	var source: Skeleton3D
	var pairs: Array = [] # [source bone, bone, source rest rotation, rest rotation], parents first
	var src_basis: Quaternion # each skeleton's rotation inside the crew model
	var dst_basis: Quaternion
	var hips := -1
	var src_pelvis := -1
	var hips_rest := Vector3.ZERO
	var pelvis_rest := Vector3.ZERO
	var height_ratio := 1.0
	var src_in_model: Transform3D
	var dst_in_model: Transform3D
	var pin := -1 # first person: this hand is moved onto its counterpart, which holds the gun (the arms differ in length)
	var pin_src := -1
	var thumb := -1
	var thumb_turn := Quaternion.IDENTITY # first person: the male's thumb is bigger and rode up into the slide

	func setup(src: Skeleton3D, dst: Skeleton3D, model: Node3D, pin_hand := false) -> void:
		source = src
		src_in_model = model.global_transform.affine_inverse() * src.global_transform
		dst_in_model = model.global_transform.affine_inverse() * dst.global_transform
		src_basis = src_in_model.basis.get_rotation_quaternion()
		dst_basis = dst_in_model.basis.get_rotation_quaternion()
		for d in dst.get_bone_count():
			var crew := RigMap.to_crew(dst.get_bone_name(d))
			if crew == "" or RigMap.to_mixamo(crew) != dst.get_bone_name(d):
				continue # end bones just ride along
			var s := src.find_bone(crew)
			if s < 0:
				continue
			pairs.append([s, d, src_basis * src.get_bone_global_rest(s).basis.get_rotation_quaternion(),
				dst_basis * dst.get_bone_global_rest(d).basis.get_rotation_quaternion()])
		hips = dst.find_bone(RigMap.to_mixamo("pelvis"))
		src_pelvis = src.find_bone("pelvis")
		hips_rest = dst_in_model * dst.get_bone_global_rest(hips).origin
		pelvis_rest = src_in_model * src.get_bone_global_rest(src_pelvis).origin
		height_ratio = hips_rest.y / pelvis_rest.y
		if pin_hand:
			pin = dst.find_bone(RigMap.to_mixamo("hand_r"))
			pin_src = src.find_bone("hand_r")
			thumb = dst.find_bone(RigMap.to_mixamo("thumb_01_r"))

	func _process_modification_with_delta(_delta: float) -> void:
		var dst := get_skeleton()
		if dst == null or source == null:
			return
		# every bone's new rotation in the character's space is kept here as it is worked out, so a child reads
		# its parent's from this instead of asking the skeleton (which recomputes all its bones after each change)
		var placed := {}
		for p in pairs:
			var moved: Quaternion = src_basis * source.get_bone_global_pose(p[0]).basis.get_rotation_quaternion() * (p[2] as Quaternion).inverse()
			var want: Quaternion = moved * p[3]
			var parent := dst.get_bone_parent(p[1])
			var parent_q: Quaternion = placed[parent] if placed.has(parent) else (dst_basis * dst.get_bone_global_rest(parent).basis.get_rotation_quaternion() if parent >= 0 else dst_basis)
			dst.set_bone_pose_rotation(p[1], (parent_q.inverse() * want).normalized())
			placed[p[1]] = want
		# hips: same rise / drop / sway as the pelvis, scaled to this body's leg length
		var pelvis := src_in_model * source.get_bone_global_pose(src_pelvis).origin
		var world := hips_rest + (pelvis - pelvis_rest) * height_ratio
		var local := dst_in_model.affine_inverse() * world
		var hp := dst.get_bone_parent(hips)
		if hp >= 0:
			local = dst.get_bone_global_rest(hp).affine_inverse() * local # (the male's Hips is the root bone)
		dst.set_bone_pose_position(hips, local)
		if pin >= 0:
			# slide the whole body so the hand lands on the gun (moving just the hand would wring the wrist)
			var target := dst_in_model.affine_inverse() * (src_in_model * source.get_bone_global_pose(pin_src).origin)
			var off := target - dst.get_bone_global_pose(pin).origin
			dst.set_bone_pose_position(hips, local + off)
			if thumb >= 0:
				dst.set_bone_pose_rotation(thumb, dst.get_bone_pose_rotation(thumb) * thumb_turn)


var bandana_color := Color(0.75, 0.05, 0.08)
var first_person := false # arms-only view for the player: no head, hair or head bandana, no shadows
var gun: Node3D
var outfit_mats: Array[ShaderMaterial] = []
var muzzle_offset := Vector3.ZERO
var anim: AnimationPlayer
var skeleton: Skeleton3D # the skeleton that is drawn (the male's; the base body's in first person)
var anim_skeleton: Skeleton3D # the base body's, which the animations play on
var tree: AnimationTree # set up by enable_locomotion()
var twist: SpineTwist
var retarget: Retarget
var _awake := true
var _dead := false # playing the death fall (on the AnimationPlayer, not the tree)
var _body_root: Node3D
var _current := ""
var _leg_yaw := 0.0
var _speed := 0.0
var _aim := 0.0


func _ready() -> void:
	var body := BODY.instantiate()
	body.rotation.y = PI
	add_child(body)
	anim_skeleton = body.find_children("*", "Skeleton3D", true, false)[0]
	skeleton = anim_skeleton
	_body_root = body

	for mi in body.find_children("*", "MeshInstance3D", true, false):
		mi.free() # only its skeleton is needed
	_build_male()

	# animations from the Universal Animation Library (same skeleton and node paths as the base body)
	if _anim_lib == null:
		var src := ANIMS.instantiate()
		var src_player: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
		_anim_lib = src_player.get_animation_library("").duplicate(true)
		for n in ["Idle", "Jog_Fwd", "Walk", "Sprint", "Pistol_Idle", "Pistol_Aim_Neutral", "Crouch_Idle", "Crouch_Fwd"]:
			if _anim_lib.has_animation(n):
				_anim_lib.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		src.free()
	anim = AnimationPlayer.new()
	body.add_child(anim)
	anim.add_animation_library("", _anim_lib)
	play("Pistol_Idle")

	_add_accessories()
	for gi in find_children("*", "GeometryInstance3D", true, false):
		gi.layers = 2 # characters: the wall graffiti decals (layer 1 only) don't paint anyone walking past
	if first_person:
		for n in skeleton.find_children("*", "BoneAttachment3D", false, false):
			n.visible = false # bandanas: out of view anyway (the gun hangs on the animation skeleton)
		for gi in find_children("*", "GeometryInstance3D", true, false):
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_male() -> void:
	var male: Node3D = MALE.instantiate()
	male.rotation.y = PI
	add_child(male)
	_body_root = male
	skeleton = male.find_children("*", "Skeleton3D", true, false)[0]
	for ap in male.find_children("*", "AnimationPlayer", true, false):
		ap.free() # its one-frame bind pose clip; the pose comes from the base body
	for mi: MeshInstance3D in male.find_children("*", "MeshInstance3D", true, false):
		if mi.name == "Body":
			_dress_male(mi)
		elif first_person:
			mi.visible = false # eyes, lashes
		elif mi.name == "Eyes":
			var eyes := StandardMaterial3D.new()
			eyes.albedo_texture = MALE_SKIN
			eyes.roughness = 0.3
			mi.material_override = eyes
		else:
			mi.material_override = _lashes() # eyelashes: cut out by the opacity map
	_wear_garments()
	var rt := Retarget.new()
	retarget = rt
	skeleton.add_child(rt)
	rt.setup(anim_skeleton, skeleton, self, first_person)
	if first_person:
		rt.thumb_turn = Quaternion(Vector3(0.3, 0.0, 1.0).normalized(), deg_to_rad(32.0)) # down onto the grip, a little out from the frame


func _dress_male(mi: MeshInstance3D) -> void:
	# the body skins with up to 8 bones per vertex, more than a shader can read, so each vertex's
	# outfit region is worked out here once (from all of them) and stored in its color
	# third person drops what the clothes cover; first person keeps only the right forearm and hand
	if not _male_bodies.has(first_person):
		var regions := []
		var right_arm := [] # first person: the one arm in view
		for i in mi.skin.get_bind_count():
			var crew := RigMap.to_crew(String(mi.skin.get_bind_name(i)))
			regions.append(_region_for(crew))
			right_arm.append(crew.ends_with("_r") and not crew.begins_with("upperarm") and not crew.begins_with("clavicle") \
				and not crew.begins_with("thigh") and not crew.begins_with("calf") and not crew.begins_with("foot") and not crew.begins_with("ball"))
		var a: Array = mi.mesh.surface_get_arrays(0)
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var wts: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var n: int = a[Mesh.ARRAY_VERTEX].size()
		var per := bones.size() / n
		var cols := PackedColorArray()
		cols.resize(n)
		var show := PackedByteArray() # vertices the clothes don't cover: skin, plus the forearms near the cuffs
		show.resize(n)
		for k in n:
			var c := Color(0, 0, 0, 0)
			var arm := 0.0
			var in_view := 0.0
			for j in per:
				var w := wts[k * per + j]
				if right_arm[bones[k * per + j]]:
					in_view += w
				match regions[bones[k * per + j]]:
					HOODIE: c.r += w
					FOREARM:
						# first person: real skin, so the wrist between cuff and hand shows arm, not black
						if first_person:
							c.a += w
						else:
							c.r += w
						arm += w
					PANTS: c.g += w
					SHOES: c.b += w
					_: c.a += w
			cols[k] = c
			if first_person:
				show[k] = 1 if in_view > 0.5 and arm < 0.75 else 0 # hand and wrist: the forearm under the sleeve would poke through it
			else:
				show[k] = 1 if c.a > 0.05 or arm > 0.3 else 0
		a[Mesh.ARRAY_COLOR] = cols
		_keep_uncovered(a, show, per)
		var body := ArrayMesh.new()
		body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
		_male_bodies[first_person] = body
	if _male_mat == null:
		_male_mat = ShaderMaterial.new()
		_male_mat.shader = MALE_BODY_SHADER
		_male_mat.set_shader_parameter("skin_tex", MALE_SKIN)
		_male_mat.set_shader_parameter("normal_tex", MALE_NORMAL)
	mi.mesh = _male_bodies[first_person]
	mi.material_override = _male_mat


static func _right_sleeve(hoodie: Mesh, skin: Skin) -> ArrayMesh:
	# first person: just the part of the hoodie on the right forearm (the rest is out of view or would block it)
	if _fp_sleeve == null:
		var a: Array = hoodie.surface_get_arrays(0)
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var wts: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var n: int = a[Mesh.ARRAY_VERTEX].size()
		var per := bones.size() / n
		var arm := []
		for i in skin.get_bind_count():
			var crew := RigMap.to_crew(String(skin.get_bind_name(i)))
			arm.append(crew == "lowerarm_r") # (the bit of cuff that follows the hand swings over the knuckles when the wrist bends)
		var show := PackedByteArray()
		show.resize(n)
		for k in n:
			var w := 0.0
			for j in per:
				if arm[bones[k * per + j]]:
					w += wts[k * per + j]
			show[k] = 1 if w > 0.5 else 0
		_shift_cuff(a, show, skin, CUFF_SHIFT)
		_keep_uncovered(a, show, per, 3) # whole triangles only: no loose flap at the cut
		_fp_sleeve = ArrayMesh.new()
		_fp_sleeve.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return _fp_sleeve


static func _shift_cuff(a: Array, show: PackedByteArray, skin: Skin, amount: float) -> void:
	# the sleeve was fitted on an arms-down pose and its cuff sits off to the side of the wrist: slide it toward
	# the forearm's line (amount 1 = cuff centered on it), easing off to nothing at the elbow
	var elbow := Vector3.ZERO
	var wrist := Vector3.ZERO
	var found := 0
	for i in skin.get_bind_count():
		var crew := RigMap.to_crew(String(skin.get_bind_name(i)))
		if crew == "lowerarm_r":
			elbow = skin.get_bind_pose(i).affine_inverse().origin
			found += 1
		elif crew == "hand_r":
			wrist = skin.get_bind_pose(i).affine_inverse().origin
			found += 1
	if found < 2:
		return
	var axis := wrist - elbow
	var length := axis.length()
	axis /= length
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var sum := Vector3.ZERO
	var n := 0
	for k in verts.size():
		if show[k] == 1 and (verts[k] - elbow).dot(axis) / length > 0.85:
			sum += verts[k]
			n += 1
	if n == 0:
		return
	var cuff := sum / n - elbow
	var off := (cuff - axis * cuff.dot(axis)) * amount # how far the cuff sits off the forearm's line
	for k in verts.size():
		verts[k] -= off * clampf((verts[k] - elbow).dot(axis) / length, 0.0, 1.0)
	a[Mesh.ARRAY_VERTEX] = verts


static func _keep_uncovered(a: Array, show: PackedByteArray, per: int, need := 1) -> void:
	# drops the body's triangles that sit entirely under the clothes (torso, legs, feet: never seen, but each
	# one is still skinned and drawn, shadows included) and the vertices only they used
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var remap := PackedInt32Array()
	remap.resize(show.size())
	remap.fill(-1)
	var order := PackedInt32Array()
	var new_idx := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if show[idx[t]] + show[idx[t + 1]] + show[idx[t + 2]] < need: # need = how many of its corners must show
			continue
		for k in 3:
			var v := idx[t + k]
			if remap[v] < 0:
				remap[v] = order.size()
				order.append(v)
			new_idx.append(remap[v])
	var stride := {Mesh.ARRAY_TANGENT: 4, Mesh.ARRAY_BONES: per, Mesh.ARRAY_WEIGHTS: per}
	for type in Mesh.ARRAY_MAX:
		var src = a[type]
		if src == null or type == Mesh.ARRAY_INDEX:
			continue
		var s: int = stride.get(type, 1)
		var out = src.duplicate()
		out.resize(order.size() * s)
		for i in order.size():
			for j in s:
				out[i * s + j] = src[order[i] * s + j]
		a[type] = out
	a[Mesh.ARRAY_INDEX] = new_idx


func _lashes() -> ShaderMaterial:
	if _lash_mat == null:
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform sampler2D opacity : filter_linear_mipmap;
void fragment() {
	ALBEDO = texture(tex, UV).rgb;
	ALPHA = texture(opacity, UV).r;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.8;
}"""
		_lash_mat = ShaderMaterial.new()
		_lash_mat.shader = sh
		_lash_mat.set_shader_parameter("tex", MALE_SKIN)
		_lash_mat.set_shader_parameter("opacity", MALE_OPACITY)
	return _lash_mat


func bone(crew_name: String) -> int:
	## a bone of the drawn skeleton, by its name on the base body ("hand_r", "Head", ...)
	return skeleton.find_bone(_bone_name(crew_name))


func _bone_name(crew_name: String) -> String:
	return crew_name if skeleton == anim_skeleton else RigMap.to_mixamo(crew_name)


func freeze_pose(anim_name: String, time := 0.0) -> void:
	# holds one frame of an animation (first-person arms)
	_current = anim_name
	anim.play(anim_name, 0.0)
	anim.seek(time, true)
	anim.pause()


func play(name: String, blend := 0.2) -> void:
	if tree:
		# with locomotion on, the tree runs everything but the death fall
		var dead := name == "Death01"
		if dead == _dead:
			return
		_dead = dead
		tree.active = _awake and not dead
		anim.active = dead
		_leg_yaw = 0.0
		twist.angle = 0.0
		rotation.y = 0.0
		if dead:
			_current = name
			anim.play(name, 0.0)
		return
	if name == _current or not anim.has_animation(name):
		return
	_current = name
	anim.play(name, blend)


func enable_locomotion() -> void:
	# legs (idle / walk / jog / sprint, by speed) under an upper body that carries or aims the pistol
	var bt := AnimationNodeBlendTree.new()
	var legs := AnimationNodeBlendSpace1D.new()
	for i in LEG_ANIMS.size():
		var a := AnimationNodeAnimation.new()
		a.animation = LEG_ANIMS[i]
		legs.add_blend_point(a, float(i), -1, LEG_ANIMS[i])
	legs.min_space = 0.0
	legs.max_space = float(LEG_ANIMS.size() - 1)
	bt.add_node("legs", legs)
	bt.add_node("legs_speed", AnimationNodeTimeScale.new()) # also negative: backing up plays the cycle in reverse
	bt.connect_node("legs_speed", 0, "legs")
	var carry := AnimationNodeAnimation.new()
	carry.animation = "Pistol_Idle"
	var aimed := AnimationNodeAnimation.new()
	aimed.animation = "Pistol_Aim_Neutral"
	bt.add_node("carry", carry)
	bt.add_node("aimed", aimed)
	bt.add_node("aim", AnimationNodeBlend2.new())
	bt.connect_node("aim", 0, "carry")
	bt.connect_node("aim", 1, "aimed")
	var split := AnimationNodeBlend2.new() # upper body from the pistol pose, legs from the walk cycle
	split.filter_enabled = true
	var hit := AnimationNodeOneShot.new() # flinch when shot, upper body only
	hit.filter_enabled = true
	hit.fadein_time = 0.05
	hit.fadeout_time = 0.15
	var track: NodePath = _anim_lib.get_animation("Idle").track_get_path(0)
	var prefix := String(track).get_slice(":", 0)
	var spine := anim_skeleton.find_bone("spine_01")
	for b in anim_skeleton.get_bone_count():
		var p := b
		while p >= 0 and p != spine:
			p = anim_skeleton.get_bone_parent(p)
		if p == spine:
			var path := NodePath(prefix + ":" + anim_skeleton.get_bone_name(b))
			split.set_filter_path(path, true)
			hit.set_filter_path(path, true)
	bt.add_node("split", split)
	bt.connect_node("split", 0, "legs_speed")
	bt.connect_node("split", 1, "aim")
	var flinch_anim := AnimationNodeAnimation.new()
	flinch_anim.animation = "Hit_Chest"
	bt.add_node("flinch", flinch_anim)
	bt.add_node("hit", hit)
	bt.connect_node("hit", 0, "split")
	bt.connect_node("hit", 1, "flinch")
	bt.connect_node("output", 0, "hit")

	tree = AnimationTree.new()
	anim.get_parent().add_child(tree) # same root the animations' paths start from
	tree.root_node = NodePath("..")
	tree.add_animation_library("", _anim_lib)
	tree.tree_root = bt
	tree.set("parameters/split/blend_amount", 1.0)
	anim.stop()
	anim.active = false
	tree.active = true

	# on the drawn skeleton, after the pose has been copied over
	twist = SpineTwist.new()
	for n in ["spine_01", "spine_02", "spine_03"]:
		var i := bone(n)
		if i >= 0:
			twist.bones.append(i)
	skeleton.add_child(twist)


func set_awake(on: bool) -> void:
	# bots off screen stop animating: no AnimationTree, no pose copy (the pose snaps back when they come into view)
	if on == _awake:
		return
	_awake = on
	if tree:
		tree.active = on and not _dead
	if retarget:
		retarget.active = on
	if twist:
		twist.active = on


func move(local_velocity: Vector3, aiming: bool, delta: float) -> void:
	# local_velocity: the character's movement in its own frame (-Z forward)
	if tree == null or not tree.active:
		return
	var flat := Vector2(local_velocity.x, local_velocity.z)
	var speed := flat.length()
	var yaw := 0.0
	var dir := 1.0
	if speed > 0.4:
		yaw = atan2(-local_velocity.x, -local_velocity.z) # 0 = straight ahead, + = to the left
		if absf(yaw) > PI * 0.6: # mostly backward: face the legs forward and run the cycle in reverse
			dir = -1.0
			yaw = wrapf(yaw + PI, -PI, PI)
		yaw = clampf(yaw, -MAX_LEG_TURN, MAX_LEG_TURN)
	_leg_yaw = lerp_angle(_leg_yaw, yaw, clampf(delta * 8.0, 0.0, 1.0))
	_speed = lerpf(_speed, speed, clampf(delta * 10.0, 0.0, 1.0))
	_aim = move_toward(_aim, 1.0 if aiming else 0.0, delta * 5.0)
	# blend position and playback rate so the feet travel as fast as the ground goes by
	var pos := 0.0
	var native := 1.0
	for i in range(1, LEG_SPEEDS.size()):
		var lo: float = LEG_SPEEDS[i - 1]
		var hi: float = LEG_SPEEDS[i]
		if _speed <= hi or i == LEG_SPEEDS.size() - 1:
			var t := clampf((_speed - lo) / (hi - lo), 0.0, 1.0)
			pos = (i - 1) + t
			native = lerpf(maxf(lo, LEG_SPEEDS[1]), hi, t)
			break
	var rate := clampf(_speed / native, 0.6, 1.6) if _speed > 0.3 else 1.0
	tree.set("parameters/legs/blend_position", pos)
	tree.set("parameters/legs_speed/scale", rate * dir)
	tree.set("parameters/aim/blend_amount", _aim)
	rotation.y = _leg_yaw
	twist.angle = -_leg_yaw


func flinch() -> void:
	if tree and tree.active:
		tree.set("parameters/hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _region_for(bone_name: String) -> int:
	var b := bone_name.to_lower()
	if first_person and b.ends_with("_l") and (b.begins_with("lowerarm") or b.begins_with("hand") or b.contains("index") or b.contains("middle") or b.contains("ring") or b.contains("pinky") or b.contains("thumb")):
		return HEAD # first person is one-handed: hide the left arm like the head
	if b.begins_with("foot") or b.begins_with("ball"):
		return SHOES
	if b.begins_with("thigh") or b.begins_with("calf") or b == "pelvis" or b == "root":
		return PANTS
	if b == "head" or b.begins_with("neck"):
		return HEAD
	if b.begins_with("hand") or b.contains("index") or b.contains("middle") \
			or b.contains("ring") or b.contains("pinky") or b.contains("thumb"):
		return SKIN
	if b.begins_with("lowerarm"):
		return FOREARM
	return HOODIE # spine, clavicles, upper arms


func _dress(mi: MeshInstance3D, skin_tex: Texture2D = null, normal_tex: Texture2D = null) -> void:
	var regions := PackedInt32Array()
	regions.resize(128)
	regions.fill(HOODIE)
	if mi.skin:
		for i in mi.skin.get_bind_count():
			var bone_name := String(mi.skin.get_bind_name(i))
			if bone_name.is_empty():
				bone_name = skeleton.get_bone_name(mi.skin.get_bind_bone(i))
			if skeleton != anim_skeleton:
				bone_name = RigMap.to_crew(bone_name)
			regions[i] = _region_for(bone_name)
	var src_mat := mi.get_active_material(0) as BaseMaterial3D
	var mat := ShaderMaterial.new()
	mat.shader = OUTFIT_SHADER
	mat.set_shader_parameter("regions", regions)
	mat.set_shader_parameter("hide_head", first_person)
	mat.set_shader_parameter("skin_tex", skin_tex if skin_tex else (src_mat.albedo_texture if src_mat else null))
	mat.set_shader_parameter("normal_tex", normal_tex if normal_tex else (src_mat.normal_texture if src_mat else null))
	mi.material_override = mat
	outfit_mats.append(mat)


func _wear_garments() -> void:
	# real clothes over the body; the body keeps its painted outfit underneath (same colors) so any spot
	# where it pokes through still reads as cloth, but no longer puffs out
	var mats := {
		"hoodie": _mat(Color(0.045, 0.045, 0.05), 0.95),
		"pants": _mat(Color(0.10, 0.105, 0.12), 0.9),
		"hair": _mat(Color(0.03, 0.025, 0.02), 1.0),
	}
	for g in ["hoodie", "pants"]:
		(mats[g] as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED # the inside shows dark through the collar and cuffs (no body under there)
	var shoe := StandardMaterial3D.new()
	shoe.vertex_color_use_as_albedo = true # the Jordans' colors are baked into the vertices
	shoe.roughness = 0.6
	for g in (["hoodie"] if first_person else GARMENTS):
		var mi := MeshInstance3D.new()
		mi.name = "Garment_" + g
		mi.mesh = load(OUTFIT + g + ".res")
		mi.skin = load(OUTFIT + g + "_skin.tres")
		if first_person:
			mi.mesh = _right_sleeve(mi.mesh, mi.skin)
		mi.material_override = mats.get(g, shoe)
		skeleton.add_child(mi)
		mi.skeleton = NodePath("..")
	for m in outfit_mats:
		m.set_shader_parameter("hoodie_puff", 0.0)
		m.set_shader_parameter("pants_puff", 0.0)
		m.set_shader_parameter("shoe_puff", 0.0)


func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _skel_from_model(sk: Skeleton3D) -> Transform3D:
	# the skeleton's place inside its source model (the model's own turn-around excluded)
	var xf := sk.transform
	var p := sk.get_parent()
	while p != null and p.get_parent() != self:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func _place(bone_name: String, model_xform: Transform3D, sk: Skeleton3D) -> Array:
	# [bone index, transform under a BoneAttachment3D on it] for something that sits at model_xform on the
	# character in rest pose, in the base body's model space (+Z = front). On the male it moves with the
	# bone's rest position, which differs a little between the two bodies.
	var idx := sk.find_bone(bone_name if sk == anim_skeleton else RigMap.to_mixamo(bone_name))
	if idx < 0:
		return [-1, Transform3D()]
	var xf := model_xform
	if sk != anim_skeleton:
		var q := anim_skeleton.find_bone(bone_name)
		var from := _skel_from_model(anim_skeleton) * anim_skeleton.get_bone_global_rest(q).origin
		var to := _skel_from_model(sk) * sk.get_bone_global_rest(idx).origin
		xf.origin += to - from
	return [idx, sk.get_bone_global_rest(idx).affine_inverse() * _skel_from_model(sk).affine_inverse() * xf]


func _attach(bone_name: String, mesh: Mesh, mat: Material, model_xform: Transform3D) -> void:
	# places a mesh on a bone so it follows the animation
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	_attach_node(bone_name, mi, model_xform)


func _attach_node(bone_name: String, node: Node3D, model_xform: Transform3D, sk: Skeleton3D = null) -> void:
	# on the drawn skeleton unless another is given
	if sk == null:
		sk = skeleton
	var placed := _place(bone_name, model_xform, sk)
	if placed[0] < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = sk.get_bone_name(placed[0])
	sk.add_child(att)
	att.add_child(node)
	node.transform = placed[1]


func _add_accessories() -> void:
	var band := _mat(bandana_color, 0.85)

	# bandana tied around the forehead (just above the eyebrows), knot and tails at the back
	var ring := TorusMesh.new()
	ring.inner_radius = 0.080
	ring.outer_radius = 0.101
	ring.rings = 24
	ring.ring_segments = 8
	var tilt := Basis(Vector3(1, 0, 0), deg_to_rad(-8)) # lower at the front
	# the male's head is a little smaller and its forehead lower than the base body's the sizes were set on
	var s := 0.9 if skeleton != anim_skeleton else 1.0
	var drop := Vector3(0, -0.025, 0.004) if skeleton != anim_skeleton else Vector3.ZERO
	_attach("Head", ring, band, Transform3D(tilt.scaled(Vector3(1.0, 1.7, 1.18) * s), Vector3(0, 1.755, -0.012) + drop))
	var knot := SphereMesh.new()
	knot.radius = 0.024
	knot.height = 0.04
	_attach("Head", knot, band, Transform3D(Basis(), Vector3(0, 1.765, -0.125 * s) + drop))
	var tail := BoxMesh.new()
	tail.size = Vector3(0.03, 0.11, 0.008)
	for side in [-1.0, 1.0]:
		_attach("Head", tail, band, Transform3D(Basis(Vector3(0, 0, 1), side * 0.25), Vector3(side * 0.018, 1.71, -0.13 * s) + drop))

	# pistol in the right hand. In rest pose the arm points out to -X with the palm down and the
	# thumb forward, so the barrel runs along -X and the top of the gun faces +Z.
	var hand := anim_skeleton.find_bone("hand_r")
	if hand >= 0:
		var hand_pos := _skel_from_model(anim_skeleton) * anim_skeleton.get_bone_global_rest(hand).origin
		var gun_basis := Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))
		var grip := hand_pos + Vector3(-0.075, -0.04, -0.005) # handle through the middle of the palm, slide above the web of the hand
		gun = Pistol.make(not first_person)
		# first person: on the animation skeleton, where the player's view code lines the sights up
		_attach_node("hand_r", gun, Transform3D(gun_basis, grip), anim_skeleton if first_person else null)
		muzzle_offset = grip + gun_basis * Pistol.MUZZLE

	# second bandana hanging out of the right back pocket
	var cloth := BoxMesh.new()
	cloth.size = Vector3(0.085, 0.20, 0.01)
	_attach("pelvis", cloth, band, Transform3D(Basis(Vector3(0, 0, 1), 0.12), Vector3(-0.085, 0.86, -0.16)))
	var tip := PrismMesh.new()
	tip.size = Vector3(0.085, 0.06, 0.01)
	_attach("pelvis", tip, band, Transform3D(Basis(Vector3(0, 0, 1), PI + 0.12), Vector3(-0.073, 0.735, -0.16)))
