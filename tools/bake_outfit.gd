extends SceneTree
## Dev tool: fits the user's hoodie, pants and Jordans (unrigged models in assets/characters/outfit_src)
## onto the crew body and bakes them as skinned meshes that follow its skeleton, so they move with every
## animation. Each garment gets the skin weights of the body surface under it; the body is first posed to
## match the garment (the hoodie is modeled arms-down, the body's rest pose is a T-pose), and that pose
## becomes the garment's bind pose. Heavy sources are simplified (the Jordan alone was 228k triangles).
##
## Run after changing a source:  godot --headless --path . -s tools/bake_outfit.gd
## Writes assets/characters/outfit/<name>.res (mesh) + <name>_skin.tres, read by scripts/crew_model.gd.

const SRC := "res://assets/characters/outfit_src/"
const OUT := "res://assets/characters/outfit/"
const BODY := "res://assets/characters/male/male.fbx" # the user's Mixamo-rigged male
const BODY_MESHES := ["Body"]
const OLD_BODY := "res://assets/characters/Superhero_Male_FullBody.gltf" # the buzzed hair was made for this head
const HAIR := "res://assets/characters/Hair_Buzzed.gltf"
const RigMap := preload("res://scripts/rig_map.gd")
const CELL := 0.04 # body lookup grid, meters

var sk: Skeleton3D
var sk_inv: Transform3D # world -> skeleton space
var body_pos := PackedVector3Array() # posed body vertices, skeleton space
var body_infl: Array = [] # per body vertex: {bone index: weight}
var body_dom := PackedStringArray() # dominant bone per body vertex, named as on the crew animation skeleton (rig_map.gd)
var foot_box := {} # side -> AABB of the body's foot (world), for fitting the shoes


func _initialize() -> void:
	var body: Node3D = load(BODY).instantiate()
	root.add_child(body)
	await process_frame
	sk = body.find_children("*", "Skeleton3D", true, false)[0]
	sk_inv = sk.global_transform.affine_inverse()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	# --- hoodie: arms-down source, about 10x real size; hood down
	var hoodie := _load_parts("hoodie.fbx", ["Base", "Hood_off"])
	# the body of the hoodie runs 9.12 - 16.34 in source units: scale so the hem sits at 0.86 m and the collar at 1.56 m
	var hb := _bounds(hoodie.v)
	var s := 0.70 / 7.22
	var hoodie_xf := Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(0, 0.86 - hb.position.y * s, 0))
	hoodie.v = _xform(hoodie.v, hoodie_xf)
	hoodie.v = _xform(hoodie.v, Transform3D(Basis(), Vector3(0, 0, _torso_z_offset(hoodie.v))))
	for k in hoodie.v.size(): # a little room over the pants' waistband
		hoodie.v[k] += hoodie.n[k] * 0.01
	_simplify(hoodie, 6000)
	_pose_rest()
	for side in ["r", "l"]:
		_aim_limb("upperarm_" + side, "hand_" + side, _cuff_center(hoodie.v, side))
	_bake("hoodie", hoodie, func(b: String) -> bool: return not (b.begins_with("thigh") or b.begins_with("calf") or b.begins_with("foot") or b.begins_with("ball") or b == "Head"))

	# --- pants: already life size and standing
	var pants := _load_parts("pants.fbx", [])
	# tuck the waist (it rises above the hoodie's hem) in toward the body so it stays under the hoodie
	var pb := _bounds(pants.v)
	var axis := Vector2(pb.get_center().x, pb.get_center().z)
	for k in pants.v.size():
		var p: Vector3 = pants.v[k]
		var t := clampf((p.y - 0.80) / 0.1, 0.0, 1.0)
		var xz := axis + (Vector2(p.x, p.z) - axis) * lerpf(1.0, 0.9, t)
		pants.v[k] = Vector3(xz.x, p.y, xz.y)
	_simplify(pants, 3500)
	_pose_rest()
	for side in ["r", "l"]:
		_aim_limb("thigh_" + side, "foot_" + side, _hem_center(pants.v, side))
	_bake("pants", pants, func(b: String) -> bool: return b == "pelvis" or b == "root" or b == "spine_01" or b.begins_with("thigh") or b.begins_with("calf"))

	# --- Jordans: one right shoe, about 2x real size; mirrored for the left
	_pose_rest()
	_measure_feet()
	for side in ["r", "l"]:
		var shoe := _load_parts("jordan2.fbx", [])
		_simplify(shoe, 2500)
		if side == "l":
			_mirror_x(shoe)
		shoe.v = _xform(shoe.v, _shoe_fit(_bounds(shoe.v), foot_box[side]))
		_bake("shoe_" + side, shoe, func(b: String) -> bool: return b == "foot_" + side or b == "ball_" + side)

	# --- buzzed hair from the old base body (the male's head is bald): stretched from that head onto this one
	_pose_rest()
	var hair := _load_parts(HAIR, [])
	var from_head := _head_box(_old_body_verts(), 1.5205)
	var to_head := _head_box(_body_rest_verts(), _rest_y("neck_01"))
	for k in hair.v.size():
		var p: Vector3 = (hair.v[k] - from_head.position) / from_head.size * to_head.size + to_head.position
		hair.v[k] = p + hair.n[k] * 0.003
	_bake("hair", hair, func(b: String) -> bool: return b == "Head" or b == "neck_01")
	quit()


func _old_body_verts() -> PackedVector3Array:
	var scene: Node3D = load(OLD_BODY).instantiate()
	root.add_child(scene)
	var out := PackedVector3Array()
	for mi: MeshInstance3D in scene.find_children("SuperHero*", "MeshInstance3D", true, false):
		out.append_array(_xform(mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], _world(mi)))
	scene.free()
	return out


func _body_rest_verts() -> PackedVector3Array:
	var out := PackedVector3Array()
	for mi: MeshInstance3D in _body_meshes():
		out.append_array(_xform(mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], _world(mi)))
	return out


func _rest_y(crew_bone: String) -> float:
	return (sk.global_transform * sk.get_bone_global_rest(sk.find_bone(RigMap.to_mixamo(crew_bone)))).origin.y


func _head_box(v: PackedVector3Array, neck_y: float) -> AABB:
	# the head: everything well above the neck joint (the arms stay below it in a T-pose)
	var b := AABB()
	var first := true
	for p in v:
		if p.y > neck_y + 0.06 and absf(p.x) < 0.15:
			b = AABB(p, Vector3.ZERO) if first else b.expand(p)
			first = false
	return b


# ---------------------------------------------------------------- loading + fitting

func _load_parts(file: String, only: Array) -> Dictionary:
	# merges the source's meshes into one surface (world positions), keeping uv + vertex colors
	var scene: Node3D = load(file if file.begins_with("res://") else SRC + file).instantiate()
	root.add_child(scene)
	var out := {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if not only.is_empty() and not only.has(String(mi.name)):
			continue
		var xf := _world(mi)
		for surf in mi.mesh.get_surface_count():
			var a: Array = mi.mesh.surface_get_arrays(surf)
			var base: int = out.v.size()
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			for k in verts.size():
				out.v.append(xf * verts[k])
				out.n.append((xf.basis * norms[k]).normalized())
			var uv = a[Mesh.ARRAY_TEX_UV]
			out.uv.append_array(uv if uv else PackedVector2Array(range(verts.size()).map(func(_k): return Vector2.ZERO)))
			var col = a[Mesh.ARRAY_COLOR]
			for k in verts.size():
				out.c.append(col[k] if col and col.size() == verts.size() else Color.WHITE)
			var idx = a[Mesh.ARRAY_INDEX]
			if idx == null or idx.is_empty():
				idx = PackedInt32Array(range(verts.size()))
			for k in idx:
				out.i.append(base + k)
	scene.free()
	return out


func _world(n: Node3D) -> Transform3D:
	# global transform without being inside the tree's processing (parents multiplied by hand)
	var xf := n.transform
	var p := n.get_parent()
	while p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func _bounds(v: PackedVector3Array) -> AABB:
	var b := AABB(v[0], Vector3.ZERO)
	for p in v:
		b = b.expand(p)
	return b


func _xform(v: PackedVector3Array, xf: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(v.size())
	for k in v.size():
		out[k] = xf * v[k]
	return out


func _torso_z_offset(v: PackedVector3Array) -> float:
	# centers the hoodie's chest slice on the body's chest slice (front to back)
	var lo := INF
	var hi := -INF
	for p in v:
		if absf(p.x) < 0.1 and p.y > 1.15 and p.y < 1.3:
			lo = minf(lo, p.z)
			hi = maxf(hi, p.z)
	var blo := INF
	var bhi := -INF
	for mi in _body_meshes():
		for p: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var w := _world(mi) * p
			if absf(w.x) < 0.1 and w.y > 1.15 and w.y < 1.3:
				blo = minf(blo, w.z)
				bhi = maxf(bhi, w.z)
	return (blo + bhi) / 2.0 - (lo + hi) / 2.0


func _cuff_center(v: PackedVector3Array, side: String) -> Vector3:
	# the right sleeve reaches out to -X (the body's right hand is at -X)
	var sgn := -1.0 if side == "r" else 1.0
	var far := 0.0
	for p in v:
		far = maxf(far, p.x * sgn)
	var sum := Vector3.ZERO
	var n := 0
	for p in v:
		if p.x * sgn > far - 0.05:
			sum += p
			n += 1
	return sum / n


func _hem_center(v: PackedVector3Array, side: String) -> Vector3:
	var sgn := -1.0 if side == "r" else 1.0
	var b := _bounds(v)
	var sum := Vector3.ZERO
	var n := 0
	for p in v:
		if p.y < b.position.y + 0.06 and p.x * sgn > 0.0:
			sum += p
			n += 1
	return sum / n


func _measure_feet() -> void:
	var boxes := {}
	_ensure_body()
	for k in body_pos.size():
		var d := body_dom[k]
		for side in ["r", "l"]:
			if d == "foot_" + side or d == "ball_" + side:
				var w := sk.global_transform * body_pos[k]
				boxes[side] = AABB(w, Vector3.ZERO) if not boxes.has(side) else (boxes[side] as AABB).expand(w)
	foot_box = boxes


func _shoe_fit(shoe: AABB, foot: AABB) -> Transform3D:
	# uniform scale so the shoe is a bit longer than the foot, sole on the ground, heel just behind the heel
	var s := foot.size.z * 1.14 / shoe.size.z
	var pos := Vector3(
		foot.get_center().x - shoe.get_center().x * s,
		maxf(foot.position.y, 0.0) - 0.005 - shoe.position.y * s,
		foot.position.z - foot.size.z * 0.07 - shoe.position.z * s)
	return Transform3D(Basis().scaled(Vector3.ONE * s), pos)


func _mirror_x(g: Dictionary) -> void:
	for k in g.v.size():
		g.v[k].x = -g.v[k].x
		g.n[k].x = -g.n[k].x
	for t in range(0, g.i.size(), 3): # mirroring flips the winding
		var tmp: int = g.i[t + 1]
		g.i[t + 1] = g.i[t + 2]
		g.i[t + 2] = tmp


func _simplify(g: Dictionary, target_tris: int) -> void:
	if g.i.size() / 3 <= target_tris:
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = g.v
	arrays[Mesh.ARRAY_NORMAL] = g.n
	arrays[Mesh.ARRAY_TEX_UV] = g.uv
	arrays[Mesh.ARRAY_COLOR] = g.c
	arrays[Mesh.ARRAY_INDEX] = g.i
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	im.generate_lods(60.0, 25.0, [])
	var best: PackedInt32Array = g.i
	for l in im.get_surface_lod_count(0):
		var idx := im.get_surface_lod_indices(0, l)
		if idx.size() / 3 >= target_tris and idx.size() < best.size():
			best = idx
	# keep only the vertices the simplified triangles use
	var remap := {}
	var out := {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
	for k in best:
		if not remap.has(k):
			remap[k] = out.v.size()
			out.v.append(g.v[k])
			out.n.append(g.n[k])
			out.uv.append(g.uv[k])
			out.c.append(g.c[k])
		out.i.append(remap[k])
	print("[outfit] simplified %d -> %d triangles" % [g.i.size() / 3, out.i.size() / 3])
	g.merge(out, true)


# ---------------------------------------------------------------- posing the body

func _pose_rest() -> void:
	for b in sk.get_bone_count():
		sk.set_bone_pose(b, sk.get_bone_rest(b))
	body_pos.clear()


func _global_pose(b: int) -> Transform3D:
	var xf := sk.get_bone_pose(b)
	var p := sk.get_bone_parent(b)
	while p >= 0:
		xf = sk.get_bone_pose(p) * xf
		p = sk.get_bone_parent(p)
	return xf


func _aim_limb(bone: String, tip: String, target_world: Vector3) -> void:
	# swings a limb at its root so its tip points at the target (sleeve cuff / pant hem)
	var b := sk.find_bone(RigMap.to_mixamo(bone))
	var t := sk.find_bone(RigMap.to_mixamo(tip))
	var g := _global_pose(b)
	var target := sk_inv * target_world
	var from := (_global_pose(t).origin - g.origin).normalized()
	var to := (target - g.origin).normalized()
	var rot := Basis(Quaternion(from, to))
	var parent := _global_pose(sk.get_bone_parent(b))
	var new_global := Basis(rot * g.basis)
	sk.set_bone_pose_rotation(b, (parent.basis.inverse() * new_global).orthonormalized().get_rotation_quaternion())
	body_pos.clear()


func _body_meshes() -> Array:
	var out := []
	for n in BODY_MESHES:
		out.append_array(sk.get_parent().find_children(n, "MeshInstance3D", true, false))
	return out


func _ensure_body() -> void:
	# the body skinned into the current pose (skeleton space), with each vertex's bone weights
	if not body_pos.is_empty():
		return
	body_infl.clear()
	body_dom.clear()
	var pose := []
	for b in sk.get_bone_count():
		pose.append(_global_pose(b))
	for mi: MeshInstance3D in _body_meshes():
		var skin := mi.skin
		var bind_bone := []
		for i in skin.get_bind_count():
			var bn := skin.get_bind_name(i)
			bind_bone.append(sk.find_bone(bn) if bn != &"" else skin.get_bind_bone(i))
		for surf in mi.mesh.get_surface_count():
			var a: Array = mi.mesh.surface_get_arrays(surf)
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
			var wts: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / verts.size()
			for k in verts.size():
				var p := Vector3.ZERO
				var infl := {}
				var best_w := -1.0
				var best_b := 0
				for j in per:
					var w: float = wts[k * per + j]
					if w <= 0.0:
						continue
					var bi: int = bones[k * per + j]
					var bone: int = bind_bone[bi]
					p += w * ((pose[bone] as Transform3D) * skin.get_bind_pose(bi) * verts[k])
					infl[bone] = infl.get(bone, 0.0) + w
					if w > best_w:
						best_w = w
						best_b = bone
				body_pos.append(p)
				body_infl.append(infl)
				body_dom.append(RigMap.to_crew(sk.get_bone_name(best_b)))


# ---------------------------------------------------------------- weight transfer + save

func _bake(name: String, g: Dictionary, allowed: Callable) -> void:
	_ensure_body()
	var pose := []
	for b in sk.get_bone_count():
		pose.append(_global_pose(b))
	# grid of the allowed body vertices
	var grid := {}
	for k in body_pos.size():
		if allowed.call(body_dom[k]):
			var key := Vector3i((body_pos[k] / CELL).floor())
			if not grid.has(key):
				grid[key] = []
			grid[key].append(k)
	var verts := _xform(g.v, sk_inv)
	var norms := PackedVector3Array()
	for n: Vector3 in g.n:
		norms.append((sk_inv.basis * n).normalized())
	var bind_of := {} # skeleton bone -> bind index
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for v in verts:
		# the 4 nearest allowed body vertices, searching outward ring by ring
		var c := Vector3i((v / CELL).floor())
		var near := []
		var r := 0
		while near.size() < 4 and r < 12:
			for x in range(-r, r + 1):
				for y in range(-r, r + 1):
					for z in range(-r, r + 1):
						if maxi(absi(x), maxi(absi(y), absi(z))) != r:
							continue
						for k in grid.get(c + Vector3i(x, y, z), []):
							near.append([v.distance_squared_to(body_pos[k]), k])
			r += 1
		near.sort()
		var acc := {}
		for e in near.slice(0, 4):
			var wd := 1.0 / (sqrt(e[0]) + 0.005)
			for bone in body_infl[e[1]]:
				if allowed.call(RigMap.to_crew(sk.get_bone_name(bone))):
					acc[bone] = acc.get(bone, 0.0) + wd * body_infl[e[1]][bone]
		var top := acc.keys()
		top.sort_custom(func(a, b): return acc[a] > acc[b])
		top = top.slice(0, 4)
		var total := 0.0
		for bone in top:
			total += acc[bone]
		for j in 4:
			if j < top.size():
				if not bind_of.has(top[j]):
					bind_of[top[j]] = bind_of.size()
				bones.append(bind_of[top[j]])
				weights.append(acc[top[j]] / total)
			else:
				bones.append(0)
				weights.append(0.0)
	var skin := Skin.new()
	for bone in bind_of:
		# bind pose = where the bone was when the garment was fitted
		skin.add_named_bind(sk.get_bone_name(bone), (pose[bone] as Transform3D).affine_inverse())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = g.uv
	arrays[Mesh.ARRAY_COLOR] = g.c
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = g.i
	# with distance detail levels: a bot across the map draws a fraction of the triangles
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	im.generate_lods(60.0, 25.0, [])
	var mesh := im.get_mesh()
	ResourceSaver.save(mesh, OUT + name + ".res")
	ResourceSaver.save(skin, OUT + name + "_skin.tres")
	print("[outfit] %s: %d triangles, %d bones" % [name, g.i.size() / 3, bind_of.size()])
