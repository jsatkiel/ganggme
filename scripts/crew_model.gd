extends Node3D
## A crew member: Quaternius base body + UAL animations, dressed in code:
## all-black hoodie (hood down), dark pants, sneakers, bandana tied around the forehead
## and another hanging out of the back pocket. The bandana color marks the crew.
## Faces -Z like the rest of the game (the source model faces +Z, so it is turned around).

const BODY := preload("res://assets/characters/Superhero_Male_FullBody.gltf")
const HAIR := preload("res://assets/characters/Hair_Buzzed.gltf")
const ANIMS := preload("res://assets/characters/UAL1_Standard.glb")
const OUTFIT_SHADER := preload("res://scripts/outfit.gdshader")
const Pistol := preload("res://scripts/pistol.gd")

# outfit regions painted by bone (see outfit.gdshader)
const HOODIE := 0
const PANTS := 1
const SHOES := 2
const SKIN := 3
const HEAD := 4 # skin too, but hidden in first person
const FOREARM := 5 # hoodie sleeve; with the hands, the only part drawn in first person

static var _anim_lib: AnimationLibrary

var bandana_color := Color(0.75, 0.05, 0.08)
var first_person := false # arms-only view for the player: no head, hair or head bandana, no shadows
var gun: Node3D
var outfit_mats: Array[ShaderMaterial] = []
var muzzle_offset := Vector3.ZERO
var anim: AnimationPlayer
var skeleton: Skeleton3D
var _current := ""


func _ready() -> void:
	var body := BODY.instantiate()
	body.rotation.y = PI
	add_child(body)
	skeleton = body.find_children("*", "Skeleton3D", true, false)[0]

	# buzzed hair, sharing the body's skeleton (not needed in first person)
	var hair_scene := HAIR.instantiate()
	for mi in ([] if first_person else hair_scene.find_children("*", "MeshInstance3D", true, false)):
		var copy: MeshInstance3D = mi.duplicate()
		skeleton.add_child(copy)
		copy.skeleton = NodePath("..")
		copy.material_override = _mat(Color(0.03, 0.025, 0.02), 1.0)
	hair_scene.free()
	for mi in skeleton.find_children("Eyebrows", "MeshInstance3D", false, false):
		mi.material_override = _mat(Color(0.03, 0.025, 0.02), 1.0)

	for mi in skeleton.find_children("*", "MeshInstance3D", false, false):
		if mi.name.begins_with("SuperHero"):
			_dress(mi)

	# animations from the Universal Animation Library (same skeleton and node paths)
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
	if first_person:
		for n in skeleton.find_children("*", "BoneAttachment3D", false, false):
			if n.bone_name != "hand_r": # hood, drawstrings, bandanas: out of view anyway
				n.visible = false
		for mi in skeleton.find_children("*", "MeshInstance3D", false, false):
			if not mi.name.begins_with("SuperHero"):
				mi.visible = false # eyes, eyebrows
		for gi in find_children("*", "GeometryInstance3D", true, false):
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func freeze_pose(anim_name: String, time := 0.0) -> void:
	# holds one frame of an animation (first-person arms)
	_current = anim_name
	anim.play(anim_name, 0.0)
	anim.seek(time, true)
	anim.pause()


func play(name: String, blend := 0.2) -> void:
	if name == _current or not anim.has_animation(name):
		return
	_current = name
	anim.play(name, blend)


func _region_for(bone: String) -> int:
	var b := bone.to_lower()
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


func _dress(mi: MeshInstance3D) -> void:
	var regions := PackedInt32Array()
	regions.resize(128)
	regions.fill(HOODIE)
	if mi.skin:
		for i in mi.skin.get_bind_count():
			var bone_name := String(mi.skin.get_bind_name(i))
			if bone_name.is_empty():
				bone_name = skeleton.get_bone_name(mi.skin.get_bind_bone(i))
			regions[i] = _region_for(bone_name)
	var src_mat := mi.get_active_material(0) as BaseMaterial3D
	var mat := ShaderMaterial.new()
	mat.shader = OUTFIT_SHADER
	mat.set_shader_parameter("regions", regions)
	mat.set_shader_parameter("hide_head", first_person)
	if src_mat:
		mat.set_shader_parameter("skin_tex", src_mat.albedo_texture)
		mat.set_shader_parameter("normal_tex", src_mat.normal_texture)
	mi.material_override = mat
	outfit_mats.append(mat)


func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _attach(bone: String, mesh: Mesh, mat: Material, model_xform: Transform3D) -> void:
	# places a mesh on a bone so it follows the animation; model_xform is where it sits
	# on the character in rest pose, in the source model's own space (+Z = front)
	var idx := skeleton.find_bone(bone)
	if idx < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	skeleton.add_child(att)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	att.add_child(mi)
	var skel_from_model := (skeleton.get_parent() as Node3D).transform * skeleton.transform
	var rest := skeleton.get_bone_global_rest(idx)
	mi.transform = rest.affine_inverse() * skel_from_model.affine_inverse() * model_xform


func _add_accessories() -> void:
	var black := _mat(Color(0.045, 0.045, 0.05), 0.95)
	var band := _mat(bandana_color, 0.85)
	var string_mat := _mat(Color(0.75, 0.75, 0.72))

	# hood down: bunched fabric behind the neck and a drooping hood on the upper back
	var roll := CapsuleMesh.new()
	roll.radius = 0.055
	roll.height = 0.30
	_attach("spine_03", roll, black, Transform3D(Basis(Vector3(0, 0, 1), PI / 2).scaled(Vector3(1, 1, 0.75)), Vector3(0, 1.50, -0.11)))
	var hood := SphereMesh.new()
	hood.radius = 0.13
	hood.height = 0.26
	_attach("spine_03", hood, black, Transform3D(Basis().scaled(Vector3(1.05, 0.85, 0.42)), Vector3(0, 1.41, -0.165)))
	# drawstrings
	var string := CylinderMesh.new()
	string.top_radius = 0.005
	string.bottom_radius = 0.005
	string.height = 0.16
	for x in [-0.035, 0.035]:
		_attach("spine_03", string, string_mat, Transform3D(Basis(), Vector3(x, 1.37, 0.165)))

	# bandana tied around the forehead (just above the eyebrows), knot and tails at the back
	var ring := TorusMesh.new()
	ring.inner_radius = 0.080
	ring.outer_radius = 0.101
	ring.rings = 24
	ring.ring_segments = 8
	var tilt := Basis(Vector3(1, 0, 0), deg_to_rad(-8)) # lower at the front
	_attach("Head", ring, band, Transform3D(tilt.scaled(Vector3(1.0, 1.7, 1.18)), Vector3(0, 1.755, -0.012)))
	var knot := SphereMesh.new()
	knot.radius = 0.024
	knot.height = 0.04
	_attach("Head", knot, band, Transform3D(Basis(), Vector3(0, 1.765, -0.125)))
	var tail := BoxMesh.new()
	tail.size = Vector3(0.03, 0.11, 0.008)
	for side in [-1.0, 1.0]:
		_attach("Head", tail, band, Transform3D(Basis(Vector3(0, 0, 1), side * 0.25), Vector3(side * 0.018, 1.71, -0.13)))

	# pistol in the right hand. In rest pose the arm points out to -X with the palm down and the
	# thumb forward, so the barrel runs along -X and the top of the gun faces +Z.
	var hand := skeleton.find_bone("hand_r")
	if hand >= 0:
		var skel_from_model := (skeleton.get_parent() as Node3D).transform * skeleton.transform
		var hand_pos := skel_from_model * skeleton.get_bone_global_rest(hand).origin
		var gun_basis := Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))
		var grip := hand_pos + Vector3(-0.075, -0.04, -0.005) # handle through the middle of the palm, slide above the web of the hand
		gun = Pistol.make(not first_person)
		_attach_node("hand_r", gun, Transform3D(gun_basis, grip))
		muzzle_offset = grip + gun_basis * Pistol.MUZZLE

	# second bandana hanging out of the right back pocket
	var cloth := BoxMesh.new()
	cloth.size = Vector3(0.085, 0.20, 0.01)
	_attach("pelvis", cloth, band, Transform3D(Basis(Vector3(0, 0, 1), 0.12), Vector3(-0.085, 0.86, -0.16)))
	var tip := PrismMesh.new()
	tip.size = Vector3(0.085, 0.06, 0.01)
	_attach("pelvis", tip, band, Transform3D(Basis(Vector3(0, 0, 1), PI + 0.12), Vector3(-0.073, 0.735, -0.16)))


func _attach_node(bone: String, node: Node3D, model_xform: Transform3D) -> void:
	# like _attach, for a whole model
	var idx := skeleton.find_bone(bone)
	if idx < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	skeleton.add_child(att)
	att.add_child(node)
	var skel_from_model := (skeleton.get_parent() as Node3D).transform * skeleton.transform
	node.transform = skeleton.get_bone_global_rest(idx).affine_inverse() * skel_from_model.affine_inverse() * model_xform
