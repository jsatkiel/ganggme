extends Node3D
## Map 2 (working name: Brownstone Block): one city block of a residential street in summer, from the user's
## reference photos. A two-lane street with cars parked both sides, a row of brownstone and red-brick
## rowhouses on each side with stone stoops, black iron railings and areaway fences, street trees,
## lamp posts and utility poles. Cross streets close off both ends.
## The street runs along X (block from x -75 to 75), its center line on z = 0.
##
## Only loaded when this map is picked (main.gd loads one map script, so the other map's art never loads).
## Collision layers as in map_builder.gd: 1 = world (blocks bullets), 2 = iron fences and railings
## (block movement, bullets pass through).

const Cars := preload("res://scripts/cars.gd")
const LiteMesh := preload("res://scripts/lite_mesh.gd")
const HYDRANT := preload("res://assets/props/fire_hydrant/fire_hydrant.gltf")
const TRASH_CAN := preload("res://assets/props/metal_trash_can/metal_trash_can.gltf")
const TRASHBAG := preload("res://assets/props/trashbag/trashbag.gltf")
const KIT := "res://assets/citykit/%s.gltf"
const TREE_VARIANTS := 4

const ROAD_Y := -0.15 # the street sits one curb below the sidewalks
const HALF_BLOCK := 75.0 # the rows run x -75 .. 75 (25 houses a side)
const CURB := 5.0 # |z| of the curbs: a 10 m street, a parking lane and a travel lane each way
const FACE := 12.5 # |z| of the house fronts: 3.6 m of sidewalk, then the stoops and areaways
const HOUSE_W := 6.0 # three 2 m kit bays
const HOUSE_D := 14.0
const GARDEN_H := 1.8 # the half-sunk garden floor under the parlor floor; the stoop climbs it
const FLOOR_H := 3.0 # kit pieces are 3 m tall
const STOOP_W := 1.9
const STOOP_RUN := 3.9 # how far a stoop comes out from the house front
const CROSS_IN := 79.0 # |x| of the cross streets' near curbs
const CROSS_OUT := 89.0 # ...and far curbs
const BOUND_Z := 20.0 # how far up a cross street you can walk

var rng := RandomNumberGenerator.new()
var player_spawns: Array[Vector3] = []
var bot_spawns: Array[Vector3] = []
# King of the Hood: the circle in the middle of the block, on the street (parking left open round it), and the
# two sides starting at opposite ends of the block, 62 m from it
var koth_hill := Vector3(0, ROAD_Y, 0)
var koth_bases: Array[Vector3] = [Vector3(-62, 0.05, 0), Vector3(62, 0.05, 0)]
var waypoints: Array[Vector3] = []
var grass_tiles: Array = [] # (none here; main.gd's quality steps look for it)

var _blocked: Array = [] # [center: Vector2, half_size: Vector2, yaw: float]
var _boxes := {} # material -> Array[Transform3D] of a unit cube: drawn as one MultiMesh per material
var _kit := {} # "piece|variant" -> Array[Transform3D]
var _kit_cache := {}
var _stoops := {} # stone material -> Array[Transform3D]
var _rails: Array[Transform3D] = []
var _fences: Array[Transform3D] = []
var _trees := {} # variant -> Array[Transform3D]
var _bushes: Array[Transform3D] = []
var _world: StaticBody3D
var _iron_body: StaticBody3D
var _unit := BoxMesh.new()

var m_road: StandardMaterial3D
var m_sidewalk: StandardMaterial3D
var m_curb: StandardMaterial3D
var m_brick: StandardMaterial3D
var m_brick_dark: StandardMaterial3D
var m_brown: StandardMaterial3D
var m_brown_dark: StandardMaterial3D
var m_brown_trim: StandardMaterial3D
var m_brown_trim_dark: StandardMaterial3D
var m_lime: StandardMaterial3D
var m_iron: StandardMaterial3D
var m_glass: StandardMaterial3D
var m_wood: StandardMaterial3D
var m_soil: StandardMaterial3D
var m_pole: StandardMaterial3D
var m_yellow: StandardMaterial3D
var m_paint: StandardMaterial3D
var m_roof: StandardMaterial3D
var m_wire: StandardMaterial3D
var m_bark: StandardMaterial3D
var m_leaves: StandardMaterial3D
var _no_shadow := {} # materials whose boxes are too small to bother casting shadows


func build() -> void:
	rng.seed = 2207
	_world = _body(1)
	_iron_body = _body(2)
	_materials()
	_ground()
	_rows()
	_hydrants()
	_street_trees()
	_poles_and_lamps()
	_parked_cars()
	_clutter()
	_bounds()
	_flush()
	# Team Deathmatch: your crew starts and comes back at the west end, the opps at the east end
	player_spawns = [Vector3(-66, 0.2, 0), Vector3(-60, 0.2, 6.6), Vector3(-60, 0.2, -6.6), Vector3(-46, 0.2, 0)]
	bot_spawns = [Vector3(66, 0.2, 0), Vector3(60, 0.2, 6.6), Vector3(60, 0.2, -6.6), Vector3(46, 0.2, 0), Vector3(66, 0.2, 3), Vector3(66, 0.2, -3)]
	for x in range(-72, 73, 6):
		for z in [-6.6, -2.0, 2.0, 6.6]:
			if not _is_blocked(Vector2(x, z), 1.0):
				waypoints.append(Vector3(x, 0.2, z))


func tune_environment(env: Environment, sun: DirectionalLight3D) -> void:
	# summer: a brighter, partly cloudy sky and a warmer, stronger sun than the winter projects
	# (a plain sky: the sky photos have hills on the horizon that would show over the city)
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color(0.32, 0.5, 0.78)
	sky.sky_horizon_color = Color(0.72, 0.78, 0.86)
	sky.ground_horizon_color = Color(0.72, 0.78, 0.86)
	sky.ground_bottom_color = Color(0.3, 0.29, 0.28)
	sky.sun_angle_max = 20.0
	env.sky.sky_material = sky
	env.ambient_light_energy = 1.7 # this sky is dimmer than the photo: keep the shady side of the street readable
	env.fog_light_color = Color(0.75, 0.8, 0.86)
	env.fog_density = 0.0022
	env.adjustment_saturation = 1.0
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.rotation_degrees = Vector3(-52, -62, 0) # across the street, so one side's fronts catch the light


func spawn_facing(pos: Vector3) -> float:
	# look down the block toward its middle
	var d := Vector3(0, 0, pos.z) - pos
	if d.length() < 1.0:
		d = Vector3(1, 0, 0)
	return atan2(-d.x, -d.z)


# ---------------------------------------------------------------- materials

func _pbr(id: String, per_meter: float, tint := Color.WHITE, ext := "jpg", one := false) -> StandardMaterial3D:
	# Poly Haven / user-picked photo textures (assets/textures), mapped in world space like map_builder.gd's
	var base := "res://assets/textures/" + (id if one else id + "_%s_1k." + ext)
	var m := StandardMaterial3D.new()
	if one:
		m.albedo_texture = load(base % "diff")
		m.normal_texture = load(base % "nor")
		m.roughness_texture = load(base % "rough")
	else:
		m.albedo_texture = load(base % "diff")
		m.normal_texture = load(base % "nor_gl")
		m.roughness_texture = load(base % "rough")
	m.albedo_color = tint
	m.normal_enabled = true
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * per_meter
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _flat(c: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _materials() -> void:
	m_road = _pbr("road_cracked_%s.png", 0.11, Color(0.6, 0.6, 0.61), "", true)
	m_road.uv1_scale = Vector3(0.11, 0.11, 0.275) # 9 x 3.6 m tile: one lane across
	m_sidewalk = _pbr("sidewalk02_%s.png", 0.5, Color(0.95, 0.94, 0.92), "", true)
	m_curb = _pbr("curb_%s.jpg", 0.6, Color(0.85, 0.84, 0.82), "", true)
	m_brick = _pbr("red_brick_03", 0.5, Color(0.92, 0.8, 0.75))
	m_brick_dark = _pbr("red_brick_03", 0.5, Color(0.62, 0.5, 0.47))
	# brownstone: smooth chocolate-brown sandstone (concrete photo texture, tinted)
	m_brown = _pbr("brushed_concrete_04", 0.4, Color(0.6, 0.4, 0.3))
	m_brown_dark = _pbr("brushed_concrete_04", 0.4, Color(0.44, 0.3, 0.24))
	m_brown_trim = _pbr("brushed_concrete_04", 0.6, Color(0.72, 0.52, 0.4))
	m_brown_trim_dark = _pbr("brushed_concrete_04", 0.6, Color(0.55, 0.39, 0.31))
	m_lime = _pbr("brushed_concrete_04", 0.4, Color(0.9, 0.87, 0.8)) # limestone stoops and bases of the brick houses
	m_iron = _flat(Color(0.035, 0.035, 0.04), 0.45, 0.5)
	m_glass = _flat(Color(0.1, 0.12, 0.15), 0.12, 0.4)
	m_wood = _flat(Color(0.2, 0.11, 0.06), 0.55)
	m_soil = _flat(Color(0.16, 0.11, 0.08), 1.0)
	m_pole = _pbr("bark_brown_02", 0.9, Color(0.45, 0.4, 0.36))
	m_yellow = _flat(Color(0.95, 0.75, 0.05))
	m_paint = _flat(Color(0.95, 0.95, 0.92))
	m_roof = _flat(Color(0.2, 0.2, 0.21), 0.95)
	m_wire = _flat(Color(0.02, 0.02, 0.02), 0.6)
	m_bark = _pbr("bark_brown_02", 0.9, Color(0.55, 0.52, 0.5))
	m_bark.uv1_world_triplanar = false
	m_leaves = StandardMaterial3D.new()
	m_leaves.albedo_texture = _leaf_texture()
	m_leaves.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m_leaves.alpha_scissor_threshold = 0.5
	m_leaves.cull_mode = BaseMaterial3D.CULL_DISABLED
	m_leaves.vertex_color_use_as_albedo = true
	m_leaves.roughness = 0.85
	m_leaves.backlight_enabled = true # sun through the leaves
	m_leaves.backlight = Color(0.25, 0.32, 0.12)
	for m in [m_iron, m_glass, m_wood, m_yellow, m_paint, m_wire, m_soil]:
		_no_shadow[m] = true


# ---------------------------------------------------------------- helpers

func _body(layer: int) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	b.collision_mask = 0
	add_child(b)
	return b


func _box(mat: Material, center: Vector3, size: Vector3, basis := Basis(), layer := 1) -> void:
	# a box drawn in its material's MultiMesh; layer 0 = no collision, 1 = world, 2 = iron (bullets pass)
	if not _boxes.has(mat):
		_boxes[mat] = [] as Array[Transform3D]
	_boxes[mat].append(Transform3D(basis * Basis.from_scale(size), center))
	if layer > 0:
		_box_shape(size, Transform3D(basis, center), layer)


func _box_shape(size: Vector3, xf: Transform3D, layer := 1) -> void:
	var bs := BoxShape3D.new()
	bs.size = size
	_shape(bs, xf, layer)


func _shape(shape: Shape3D, xf: Transform3D, layer := 1) -> Shape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	(_world if layer == 1 else _iron_body).add_child(cs)
	return shape


func _seg(st: SurfaceTool, a: Vector3, b: Vector3, w: float, h := -1.0) -> void:
	# a square bar from a to b, merged into st
	var d := b - a
	var z := d.normalized()
	var up := Vector3.UP if absf(z.y) < 0.99 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	st.append_from(_unit, 0, Transform3D(Basis(x * w, y * (h if h > 0.0 else w), z * d.length()), (a + b) / 2.0))


func _solid(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	st.append_from(_unit, 0, Transform3D(Basis.from_scale(size), center))


func _ball(st: SurfaceTool, at: Vector3, r: float) -> void:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 6
	s.rings = 3
	st.append_from(s, 0, Transform3D(Basis(), at))


func _spike(st: SurfaceTool, at: Vector3, r: float, h: float) -> void:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 4
	c.rings = 1
	st.append_from(c, 0, Transform3D(Basis(), at + Vector3(0, h / 2.0, 0)))


func _multi(mesh: Mesh, xforms: Array, mat: Material = null, shadows := true) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _block(center: Vector2, size: Vector2, yaw := 0.0) -> void:
	_blocked.append([center, size / 2.0, yaw])


func _is_blocked(p: Vector2, margin: float, list = null) -> bool:
	for b in (list if list != null else _blocked):
		var d: Vector2 = p - b[0]
		var half: Vector2 = b[1]
		var y: float = b[2]
		var lx := d.x * cos(y) - d.y * sin(y)
		var lz := d.x * sin(y) + d.y * cos(y)
		if absf(lx) < half.x + margin and absf(lz) < half.y + margin:
			return true
	return false


func check_overlaps() -> int:
	return 0 # (dev check for the projects map's layout; nothing to check here)


func _invisible_wall(pos: Vector3, size: Vector3) -> void:
	var s := BoxShape3D.new()
	s.size = size
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.position = pos
	var b := StaticBody3D.new() # its own body on layer 1 like map_builder.gd's
	b.add_child(cs)
	add_child(b)


# ---------------------------------------------------------------- ground

func _ground() -> void:
	# asphalt everywhere one curb down, sidewalk slabs on top with curb strips along their street edges
	_box(m_road, Vector3(0, ROAD_Y - 0.5, 0), Vector3(240, 1, 160))
	for s: float in [-1.0, 1.0]:
		# along the block (runs on under the house fronts)
		_slab(Vector2(-CROSS_IN, s * CURB), Vector2(CROSS_IN, s * (FACE + 2.0)))
		_curb_strip(Vector3(0, 0, s * (CURB + 0.12)), Vector2(CROSS_IN * 2.0, 0.24))
		# the corners and on up each cross street, both ends
		for e: float in [-1.0, 1.0]:
			_slab(Vector2(e * (HALF_BLOCK - 3.5), s * CURB), Vector2(e * CROSS_IN, s * 70.0))
			_curb_strip(Vector3(e * (CROSS_IN - 0.12), 0, s * (CURB + 32.5)), Vector2(0.24, 65.0))
	for e: float in [-1.0, 1.0]:
		# far side of each cross street
		_slab(Vector2(e * CROSS_OUT, -70), Vector2(e * (CROSS_OUT + 9.0), 70))
		_curb_strip(Vector3(e * (CROSS_OUT + 0.12), 0, 0), Vector2(0.24, 140.0))
		# crosswalk across the block's street where it meets the cross street
		for i in 8:
			var z := -CURB + 0.6 + i * 1.25
			_box(m_paint, Vector3(e * (CROSS_IN - 1.6), ROAD_Y + 0.006, z), Vector3(2.6, 0.012, 0.6), Basis(), 0)
		# cross street center line
		for z0: float in [-0.12, 0.12]:
			_box(m_yellow, Vector3(e * (CROSS_IN + CROSS_OUT) / 2.0 + z0, ROAD_Y + 0.006, 0), Vector3(0.1, 0.012, 140), Basis(), 0)
	# the block's double yellow center line, stopping at the crosswalks
	for z0: float in [-0.12, 0.12]:
		_box(m_yellow, Vector3(0, ROAD_Y + 0.006, z0), Vector3((CROSS_IN - 3.2) * 2.0, 0.012, 0.1), Basis(), 0)


func _slab(a: Vector2, b: Vector2) -> void:
	# sidewalk-level slab between corners a and b (top at y 0)
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var c := (lo + hi) / 2.0
	var size := hi - lo
	_box(m_sidewalk, Vector3(c.x, (ROAD_Y - 0.2) / 2.0, c.y), Vector3(size.x, -ROAD_Y + 0.2, size.y))


func _curb_strip(center: Vector3, size: Vector2) -> void:
	_box(m_curb, center + Vector3(0, -0.005, 0), Vector3(size.x, 0.02, size.y), Basis(), 0)


# ---------------------------------------------------------------- rowhouses

func _rows() -> void:
	# the block: 25 houses each side facing the street
	for s: float in [-1.0, 1.0]:
		_row(Transform3D(Basis(Vector3.UP, 0.0 if s < 0.0 else PI), Vector3(0, 0, s * FACE)), 25)
	# across each cross street, and the near side of each cross street past the corner houses
	for e: float in [-1.0, 1.0]:
		var face_x := e * (CROSS_OUT + 7.5)
		_row(Transform3D(Basis(Vector3.UP, -e * PI / 2.0), Vector3(face_x, 0, 0)), 17)
		for s: float in [-1.0, 1.0]:
			var near_x := e * (CROSS_IN - 7.5)
			_row(Transform3D(Basis(Vector3.UP, e * PI / 2.0), Vector3(near_x, 0, s * (FACE + HOUSE_D + 0.5 + 12.0))), 4)


func _row(xf: Transform3D, count: int) -> void:
	# a row of attached houses in xf's frame: along local +X, fronts facing local +Z at z = 0.
	# Houses come in runs of 2-4 built alike (same stone, same height), stoops paired up two by two.
	var i := 0
	var variants := ["brown", "brown_dark", "brick", "brick_dark"]
	var last := ""
	while i < count:
		var run := mini(rng.randi_range(2, 4), count - i)
		var v: String = variants[rng.randi() % variants.size()]
		while v == last:
			v = variants[rng.randi() % variants.size()]
		last = v
		var up := rng.randi_range(1, 2) # floors above the parlor floor: 3 or 4 stories in all
		for k in run:
			var cx := (i - (count - 1) / 2.0) * HOUSE_W
			_house(xf, cx, v, up, i % 2 == 0)
			i += 1


func _house(xf: Transform3D, cx: float, v: String, up: int, stoop_right: bool) -> void:
	var brown := v.begins_with("brown")
	var wall: Material = {"brown": m_brown, "brown_dark": m_brown_dark, "brick": m_brick, "brick_dark": m_brick_dark}[v]
	var trim: Material = (m_brown_trim if v == "brown" else m_brown_trim_dark) if brown else m_lime
	var base: Material = wall if brown else m_lime
	var b := xf.basis
	var at := func(p: Vector3) -> Vector3: return xf * p
	var top := GARDEN_H + FLOOR_H * (up + 1)
	var h := top + 0.9
	var door_x := cx + (2.0 if stoop_right else -2.0)
	# the body of the house (side walls show above lower neighbors), and its roof
	_box(wall, at.call(Vector3(cx, h / 2.0, -0.2 - HOUSE_D / 2.0)), Vector3(HOUSE_W, h, HOUSE_D), b, 0)
	_box(m_roof, at.call(Vector3(cx, h + 0.05, -0.2 - HOUSE_D / 2.0)), Vector3(HOUSE_W, 0.1, HOUSE_D), b, 0)
	_box_shape(Vector3(HOUSE_W, h, HOUSE_D), Transform3D(b, at.call(Vector3(cx, h / 2.0, -HOUSE_D / 2.0))))
	# garden floor: plain stone base with two small barred windows beside the stoop, and a ledge on top
	_box(base, at.call(Vector3(cx, GARDEN_H / 2.0, -0.12)), Vector3(HOUSE_W, GARDEN_H, 0.44), b, 0)
	_box(trim, at.call(Vector3(cx, GARDEN_H - 0.06, 0.12)), Vector3(HOUSE_W, 0.14, 0.24), b, 0)
	for bay: int in [-1, 0, 1]:
		var bx: float = cx + bay * 2.0
		if absf(bx - door_x) < 0.1:
			continue
		_box(m_glass, at.call(Vector3(bx, 0.95, 0.11)), Vector3(1.0, 0.8, 0.02), b, 0)
		_box(trim, at.call(Vector3(bx, 0.5, 0.14)), Vector3(1.2, 0.08, 0.1), b, 0)
		for k in 6:
			_box(m_iron, at.call(Vector3(bx - 0.45 + k * 0.18, 0.95, 0.15)), Vector3(0.02, 0.84, 0.02), b, 0)
	# parlor floor and the floors above: tall windows in kit bays; the stoop bay gets the front door
	var kit_v := v
	for f in up + 1:
		var y := GARDEN_H + f * FLOOR_H
		for bay: int in [-1, 0, 1]:
			var bx: float = cx + bay * 2.0
			var piece := "Brick_Window_Trim"
			if f == 0 and absf(bx - door_x) < 0.1:
				piece = "Brick_Plain_3"
				_door(xf, bx, y, trim)
			elif f == up and up == 2:
				piece = "Brick_Window_Trim_Single" # shorter top-floor windows
			_kit_piece(piece, kit_v, xf * Transform3D(Basis(), Vector3(bx, y, 0)))
	# cornice across the top
	for bay: int in [-1, 0, 1]:
		_kit_piece("Cornice_Trim_Center", "brown" if brown else "brick", xf * Transform3D(Basis(), Vector3(cx + bay * 2.0, top, 0)))
	# the stoop, its railings, and the areaway fence across the rest of the front
	var stone: Material = trim if brown else m_lime
	if not _stoops.has(stone):
		_stoops[stone] = [] as Array[Transform3D]
	var sxf := xf * Transform3D(Basis(), Vector3(door_x, 0, 0))
	_stoops[stone].append(sxf)
	_rails.append(sxf)
	_stoop_collision(sxf)
	var fence_a := cx - HOUSE_W / 2.0 if stoop_right else door_x + STOOP_W / 2.0
	var fence_b := door_x - STOOP_W / 2.0 if stoop_right else cx + HOUSE_W / 2.0
	var fxf := xf * Transform3D(Basis(), Vector3((fence_a + fence_b) / 2.0, 0, STOOP_RUN - 0.05))
	_fences.append(fxf)
	_box_shape(Vector3(fence_b - fence_a, 1.5, 0.12), fxf * Transform3D(Basis(), Vector3(0, 0.75, 0)), 2)
	var mid: Vector3 = at.call(Vector3((fence_a + fence_b) / 2.0, 0, 2.0))
	_block(Vector2(mid.x, mid.z), Vector2(fence_b - fence_a, 4.0), b.get_euler().y)
	var sm: Vector3 = at.call(Vector3(door_x, 0, 2.0))
	_block(Vector2(sm.x, sm.z), Vector2(STOOP_W, 4.0), b.get_euler().y)
	# areaway: a planted bed, or the house's trash cans
	var yard_c := (fence_a + fence_b) / 2.0
	if rng.randf() < 0.65:
		_box(m_soil, at.call(Vector3(yard_c, 0.06, 2.0)), Vector3(fence_b - fence_a - 0.2, 0.12, 3.4), b, 0)
		for k in rng.randi_range(1, 3):
			var p: Vector3 = at.call(Vector3(yard_c + rng.randf_range(-1.4, 1.4), 0.1, rng.randf_range(0.9, 3.0)))
			_bushes.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.25)), p))
	else:
		for k in rng.randi_range(1, 3):
			var p: Vector3 = at.call(Vector3(yard_c - 1.2 + k * 0.7, 0, 3.2))
			_prop(TRASH_CAN, p, rng.randf() * TAU, 1.0, "rust", Vector3(0.5, 0, 0))


func _door(xf: Transform3D, x: float, y: float, trim: Material) -> void:
	# the front door at the top of the stoop: dark wood double door under a glass transom, in a stone surround
	var b := xf.basis
	var at := func(p: Vector3) -> Vector3: return xf * p
	_box(m_wood, at.call(Vector3(x, y + 1.18, 0.06)), Vector3(1.24, 2.36, 0.08), b, 0)
	_box(m_iron, at.call(Vector3(x, y + 1.18, 0.105)), Vector3(0.025, 2.3, 0.02), b, 0) # the split between the leaves
	for side in [-1.0, 1.0]:
		_box(m_glass, at.call(Vector3(x + side * 0.31, y + 1.62, 0.105)), Vector3(0.36, 0.8, 0.02), b, 0)
		_box(trim, at.call(Vector3(x + side * 0.78, y + 1.4, 0.12)), Vector3(0.26, 2.8, 0.22), b, 0) # pilasters
	_box(m_glass, at.call(Vector3(x, y + 2.58, 0.08)), Vector3(1.24, 0.38, 0.03), b, 0) # transom
	_box(trim, at.call(Vector3(x, y + 2.9, 0.18)), Vector3(1.9, 0.26, 0.36), b, 0) # hood
	_box(trim, at.call(Vector3(x, y + 3.06, 0.22)), Vector3(2.0, 0.08, 0.44), b, 0)


func _kit_piece(piece: String, variant: String, xf: Transform3D) -> void:
	var key := piece + "|" + variant
	if not _kit.has(key):
		_kit[key] = [] as Array[Transform3D]
	_kit[key].append(xf)


func _kit_mesh(key: String) -> Mesh:
	# a Downtown City MegaKit piece (Quaternius, CC0) without its inside-the-room surfaces, glass made opaque,
	# and its brick swapped for this house's stone or brick
	if _kit_cache.has(key):
		return _kit_cache[key]
	var piece := key.get_slice("|", 0)
	var v := key.get_slice("|", 1)
	var scene: Node = load(KIT % piece).instantiate()
	var src: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh: ArrayMesh = src.mesh.duplicate()
	scene.free()
	for s in range(mesh.get_surface_count() - 1, -1, -1):
		var m := mesh.surface_get_material(s)
		var mname := m.resource_name if m else ""
		if mname in ["MI_InteriorWall", "MI_FakeInterior"]:
			mesh.surface_remove(s)
		elif mname == "MI_Glass":
			mesh.surface_set_material(s, m_glass)
		elif mname.begins_with("MI_RedBrick"):
			match v:
				"brown": mesh.surface_set_material(s, m_brown)
				"brown_dark": mesh.surface_set_material(s, m_brown_dark)
				"brick_dark":
					var d: StandardMaterial3D = m.duplicate()
					d.albedo_color = Color(0.68, 0.56, 0.53)
					mesh.surface_set_material(s, d)
		elif mname == "MI_Trim" and v.begins_with("brown"):
			mesh.surface_set_material(s, m_brown_trim if v == "brown" else m_brown_trim_dark)
	_kit_cache[key] = mesh
	return mesh


func _stoop_mesh() -> Mesh:
	# stone stoop in its own frame: centered on x, against the house front (z 0), out along +z.
	# A landing at the parlor floor, then 8 steps (20 cm rise, 30 cm tread) down to the sidewalk.
	var st := SurfaceTool.new()
	_solid(st, Vector3(0, GARDEN_H / 2.0, 0.85), Vector3(STOOP_W, GARDEN_H, 1.3))
	for k in range(1, 9):
		var y := GARDEN_H - 0.2 * k
		var front := 1.5 + 0.3 * k
		_solid(st, Vector3(0, y / 2.0, (0.2 + front) / 2.0), Vector3(STOOP_W, y, front - 0.2))
		_solid(st, Vector3(0, y - 0.02, front - 0.13), Vector3(STOOP_W + 0.04, 0.04, 0.3)) # nosing
	_solid(st, Vector3(0, GARDEN_H - 0.02, 0.85), Vector3(STOOP_W + 0.04, 0.04, 1.34))
	return st.commit()


func _rail_mesh() -> Mesh:
	# the stoop's black iron railings, both sides: a rail down the steps and along the landing, thin
	# balusters, and at the bottom a heavy newel post with a ball on top and a scroll curling out of the rail
	var st := SurfaceTool.new()
	for side in [-1.0, 1.0]:
		var x: float = side * (STOOP_W / 2.0 - 0.06)
		var top_a := Vector3(x, 0.2 + 0.95, 3.85) # down the steps: from the bottom step...
		var top_b := Vector3(x, GARDEN_H + 0.95, 1.5) # ...to the landing
		var low_a := Vector3(x, 0.32, 3.85)
		var low_b := Vector3(x, GARDEN_H + 0.12, 1.5)
		_seg(st, top_a, top_b, 0.05, 0.04)
		_seg(st, low_a, low_b, 0.03)
		var land_top := Vector3(x, GARDEN_H + 0.95, 0.15)
		_seg(st, top_b, land_top, 0.05, 0.04)
		_seg(st, low_b, Vector3(x, GARDEN_H + 0.12, 0.15), 0.03)
		for k in 22:
			var t := (k + 0.5) / 22.0
			var lo := low_a.lerp(low_b, t)
			_seg(st, lo, lo + Vector3(0, 0.83, 0), 0.018)
			if k % 3 == 1: # little twists between every few balusters
				_ball(st, lo + Vector3(0, 0.45, 0), 0.025)
		for k in 10:
			var z := 1.45 - k * 0.13
			_seg(st, Vector3(x, GARDEN_H + 0.12, z), Vector3(x, GARDEN_H + 0.95, z), 0.018)
		_seg(st, Vector3(x, GARDEN_H, 0.15), Vector3(x, GARDEN_H + 1.0, 0.15), 0.06) # post at the door
		# newel post and scroll
		_seg(st, Vector3(x, 0.2, 3.92), Vector3(x, 1.32, 3.92), 0.09)
		_seg(st, Vector3(x, 1.3, 3.92), Vector3(x, 1.36, 3.92), 0.13)
		_ball(st, Vector3(x, 1.43, 3.92), 0.07)
		var prev := top_a
		for k in 9:
			var a := k * 0.7
			var r := 0.22 * (1.0 - k / 10.0)
			var p := Vector3(x, 0.2 + 0.72 + cos(a) * r, 3.92 + 0.05 + sin(a) * r * 0.8)
			_seg(st, prev, p, 0.035)
			prev = p
	return st.commit()


func _fence_mesh() -> Mesh:
	# areaway fence across the front of a house beside its stoop: pickets with spear points between two rails,
	# posts at both ends (the stoop's width leaves the same 4.05 m on every house)
	var st := SurfaceTool.new()
	var half := (HOUSE_W - STOOP_W - 0.05) / 2.0
	_seg(st, Vector3(-half, 0.12, 0), Vector3(half, 0.12, 0), 0.04)
	_seg(st, Vector3(-half, 0.9, 0), Vector3(half, 0.9, 0), 0.045)
	var n := int(half * 2.0 / 0.12)
	for k in n + 1:
		var x := -half + k * (half * 2.0 / n)
		_seg(st, Vector3(x, 0.02, 0), Vector3(x, 1.02, 0), 0.016)
		_spike(st, Vector3(x, 1.02, 0), 0.022, 0.07)
	for x in [-half, half]:
		_seg(st, Vector3(x, 0.0, 0), Vector3(x, 1.12, 0), 0.07)
		_ball(st, Vector3(x, 1.16, 0), 0.05)
	return st.commit()


func _stoop_collision(sxf: Transform3D) -> void:
	# a ramp you can walk up and down (the steps themselves would catch your feet) and the landing
	var hw := STOOP_W / 2.0
	var pts := PackedVector3Array()
	for x in [-hw, hw]:
		pts.append_array([Vector3(x, 0, 0.0), Vector3(x, 0, STOOP_RUN + 0.05), Vector3(x, GARDEN_H, 1.5), Vector3(x, GARDEN_H, 0.0)])
	var cps := ConvexPolygonShape3D.new()
	cps.points = pts
	_shape(cps, sxf, 1)
	# the railings keep you on the steps
	for side in [-1.0, 1.0]:
		var x: float = side * (hw - 0.06)
		var a := Vector3(x, 1.15, STOOP_RUN)
		var c := Vector3(x, GARDEN_H + 0.95, 1.5)
		var d := c - a
		var basis := Basis(Vector3.RIGHT, atan2(d.y, -d.z)) # the box's long side down the steps
		_box_shape(Vector3(0.1, 1.0, d.length()), sxf * Transform3D(basis, (a + c) / 2.0 - Vector3(0, 0.45, 0)), 2)
		_box_shape(Vector3(0.1, 1.0, 1.4), sxf * Transform3D(Basis(), Vector3(x, GARDEN_H + 0.5, 0.8)), 2)


# ---------------------------------------------------------------- street furniture

func _street_trees() -> void:
	# street trees in sidewalk pits, a few spots left bare
	for s: float in [-1.0, 1.0]:
		var x := -HALF_BLOCK + rng.randf_range(3.0, 7.0)
		while x < HALF_BLOCK - 3.0:
			if rng.randf() < 0.85:
				_tree(Vector3(x, 0, s * (CURB + 1.0)))
			x += rng.randf_range(9.0, 13.0)


func _tree(p: Vector3) -> void:
	var v := rng.randi() % TREE_VARIANTS
	if not _trees.has(v):
		_trees[v] = [] as Array[Transform3D]
	_trees[v].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.15)), p))
	_box(m_soil, p + Vector3(0, 0.005, 0), Vector3(1.3, 0.02, 1.3), Basis(), 0) # tree pit
	for k in 4: # low iron guard round the pit
		var a := k * PI / 2.0
		var o := Vector3(cos(a), 0, sin(a)) * 0.65
		_box(m_iron, p + o + Vector3(0, 0.22, 0), Vector3(0.03 if k % 2 == 0 else 1.3, 0.03, 1.3 if k % 2 == 0 else 0.03), Basis(), 0)
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.2
	trunk.height = 3.0
	_shape(trunk, Transform3D(Basis(), p + Vector3(0, 1.5, 0)), 1)
	_block(Vector2(p.x, p.z), Vector2(1.3, 1.3))


func _poles_and_lamps() -> void:
	# wooden utility poles down one side with wires between them; black lamp posts down the other
	var poles: Array[Vector3] = []
	for x in [-70.0, -42.0, -14.0, 14.0, 42.0, 70.0]:
		var p := Vector3(x + rng.randf_range(-1.5, 1.5), 0, CURB + 0.45)
		while _is_blocked(Vector2(p.x, p.z), 0.6):
			p.x += 1.0
		poles.append(p)
		_box(m_pole, p + Vector3(0, 4.75, 0), Vector3(0.28, 9.5, 0.28), Basis(), 1)
		_box(m_pole, p + Vector3(0, 8.6, 0), Vector3(0.12, 0.14, 2.4), Basis(), 0) # crossarm
		for z in [-1.0, 0.0, 1.0]:
			_box(m_glass, p + Vector3(0, 8.75, z), Vector3(0.08, 0.16, 0.08), Basis(), 0) # insulators
		if poles.size() == 3:
			_box(m_roof, p + Vector3(-0.3, 7.3, 0), Vector3(0.5, 0.9, 0.5), Basis(), 0) # transformer
		_block(Vector2(p.x, p.z), Vector2(0.6, 0.6))
	for i in poles.size() - 1:
		for z in [-1.0, 0.0, 1.0]:
			var a := poles[i] + Vector3(0, 8.82, z)
			var c := poles[i + 1] + Vector3(0, 8.82, z)
			var mid := (a + c) / 2.0 - Vector3(0, 0.35, 0) # a little sag
			for seg in [[a, mid], [mid, c]]:
				var d: Vector3 = seg[1] - seg[0]
				_box(m_wire, (seg[0] + seg[1]) / 2.0, Vector3(d.length(), 0.025, 0.025), Basis(Vector3.BACK, atan2(d.y, d.x)), 0)
	for x in [-60.0, -35.0, -10.0, 15.0, 40.0, 65.0]:
		var p := Vector3(x + rng.randf_range(-1.5, 1.5), 0, -(CURB + 0.45))
		while _is_blocked(Vector2(p.x, p.z), 0.6):
			p.x += 1.0
		_lamp(p)


func _lamp(p: Vector3) -> void:
	# cast-iron post with a lantern
	_box(m_iron, p + Vector3(0, 0.3, 0), Vector3(0.32, 0.6, 0.32), Basis(), 1)
	_box(m_iron, p + Vector3(0, 2.4, 0), Vector3(0.11, 4.2, 0.11), Basis(), 1)
	_box(m_iron, p + Vector3(0, 4.55, 0), Vector3(0.36, 0.08, 0.36), Basis(), 0)
	_box(m_glass, p + Vector3(0, 4.85, 0), Vector3(0.3, 0.5, 0.3), Basis(), 0)
	_box(m_iron, p + Vector3(0, 5.16, 0), Vector3(0.42, 0.1, 0.42), Basis(), 0)
	_box(m_iron, p + Vector3(0, 5.3, 0), Vector3(0.12, 0.2, 0.12), Basis(), 0)
	_block(Vector2(p.x, p.z), Vector2(0.6, 0.6))


const HYDRANTS := {1.0: [-48.0, 4.0, 52.0], -1.0: [-24.0, 30.0]} # x of the hydrants on each side


func _hydrants() -> void:
	for s: float in [-1.0, 1.0]:
		for x: float in HYDRANTS[s]:
			_prop(HYDRANT, Vector3(x, 0.0, s * (CURB + 0.35)), -s * PI / 2.0, 1.0, "aged", Vector3(-0.3, 0, 0))
			_block(Vector2(x, s * (CURB + 0.35)), Vector2(1.2, 1.2))


func _parked_cars() -> void:
	# every curb lined with the cars from the projects map, bumper to bumper with only a few open spots
	# (always the one by a hydrant, and the street round the King of the Hood circle)
	for s: float in [-1.0, 1.0]:
		var hyd: Array = HYDRANTS[s]
		_car_row(Vector3(0, 0, s * CURB), Vector3(0, 0, -s), s < 0.0, -HALF_BLOCK + 3.5, HALF_BLOCK - 2.0,
			func(a: float, b: float) -> bool: return (a < 7.0 and b > -7.0) or hyd.any(func(h: float) -> bool: return h > a - 1.5 and h < b + 1.5))


var _last_car := ""
var _free02 := 0


func _car_row(curb: Vector3, inward: Vector3, flip: bool, from: float, to: float, keep_clear: Callable) -> void:
	# cars parked along one curb of the block (curb: a point on the curb line, inward: toward the road) from
	# x = from to x = to; keep_clear(start, end) says where a car may not go. flip: noses the other way
	var along := Vector3(1, 0, 0)
	var d := from
	while d < to:
		var pool: Array = Cars.MODELS.keys().filter(func(k): return k != _last_car and (k != "carfree02" or _free02 < 3))
		var id: String = pool[rng.randi() % pool.size()]
		var length: float = Cars.MODELS[id].length
		if d + length > to:
			break # no room before the end
		if keep_clear.call(d, d + length) or rng.randf() < 0.05:
			d += 6.3 # an open spot
			continue
		if id == "carfree02":
			_free02 += 1
		_last_car = id
		var made: Array = Cars.make(id, rng)
		var size: Vector3 = made[1]
		var root := Node3D.new()
		var center := curb * Vector3(1, 0, 1) + along * (d + size.x / 2.0) + inward * (0.3 + size.z / 2.0)
		root.position = center + Vector3(0, ROAD_Y, 0)
		root.rotation.y = atan2(-along.z, along.x) + (PI if flip else 0.0) # nose with the traffic on that side
		root.add_child(made[0])
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = made[2]
		body.add_child(cs)
		root.add_child(body)
		add_child(root)
		_block(Vector2(center.x, center.z), Vector2(size.x + 0.3, size.z + 0.35))
		d += size.x + rng.randf_range(0.7, 1.4)


func _clutter() -> void:
	# trash bags out at the curb for pickup, here and there
	for i in 7:
		var s := -1.0 if i % 2 == 0 else 1.0
		var p := Vector2(rng.randf_range(-HALF_BLOCK + 5.0, HALF_BLOCK - 5.0), s * (CURB + 0.7))
		if _is_blocked(p, 0.8):
			continue
		for k in rng.randi_range(2, 4):
			var o := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.3, 0.3))
			_prop(TRASHBAG, Vector3(p.x, 0, p.y) + o, rng.randf() * TAU, rng.randf_range(0.9, 1.2))
		_block(p, Vector2(1.6, 1.0))


func _bounds() -> void:
	# up the cross streets only as far as the corners; the backs of the rows are solid house
	for e: float in [-1.0, 1.0]:
		for s: float in [-1.0, 1.0]:
			_invisible_wall(Vector3(e * (CROSS_IN + CROSS_OUT) / 2.0, 15, s * BOUND_Z), Vector3(CROSS_OUT - CROSS_IN + 16.0, 30, 1))
		_invisible_wall(Vector3(e * (CROSS_OUT + 6.0), 15, 0), Vector3(1, 30, BOUND_Z * 2.0))


func _prop(scene: PackedScene, pos: Vector3, yaw: float, scale := 1.0, keep := "", offset := Vector3.ZERO) -> Node3D:
	# a model from the projects map's props (keep: only meshes whose name has this, offset recenters it).
	# These ship as film-quality scans: a sixth of their triangles reads the same at play distance
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	root.scale = Vector3.ONE * scale
	add_child(root)
	var model: Node3D = scene.instantiate()
	model.position = offset
	root.add_child(model)
	if keep != "":
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			if not mi.name.contains(keep):
				mi.visible = false
	LiteMesh.lighten(model, func(t: int) -> int: return clampi(t / 6, 800, 3000), false)
	return root


# ---------------------------------------------------------------- summer trees
# grown here like the projects map's bare winter trees (tapered bark tubes), with leaf clusters on the
# outer branches: cards of a leaf texture painted at load

func _leaf_texture() -> ImageTexture:
	# a clump of small leaves, alpha cut, in a few greens (tinted further per card by vertex color)
	var r := RandomNumberGenerator.new()
	r.seed = 515
	var n := 256
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.3, 0.1, 0.0))
	for i in 420:
		var c := Vector2(r.randf_range(0.1, 0.9), r.randf_range(0.1, 0.9)) * n
		if c.distance_to(Vector2(n, n) / 2.0) > n * 0.44:
			continue
		var a := r.randf() * TAU
		var len := r.randf_range(9.0, 15.0)
		var wid := len * 0.45
		var shade := r.randf_range(0.65, 1.15)
		var dir := Vector2(cos(a), sin(a))
		for y in range(int(c.y - len), int(c.y + len) + 1):
			for x in range(int(c.x - len), int(c.x + len) + 1):
				if x < 0 or y < 0 or x >= n or y >= n:
					continue
				var d := Vector2(x, y) - c
				var u := d.dot(dir) / len
				var w := d.dot(Vector2(-dir.y, dir.x)) / wid
				if u * u + w * w <= 1.0:
					var lit := shade * (1.0 - 0.12 * (u + 1.0)) # a little darker toward the tip
					img.set_pixel(x, y, Color(0.32 * lit, 0.47 * lit, 0.16 * lit, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _tree_mesh(variant: int) -> ArrayMesh:
	# a street tree: a clear trunk to about 3 m, limbs reaching up and out, leaves at their ends
	var r := RandomNumberGenerator.new()
	r.seed = 4400 + variant * 53
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tips: Array[Vector3] = []
	var top := Vector3(r.randf_range(-0.15, 0.15), r.randf_range(2.8, 3.4), r.randf_range(-0.15, 0.15))
	_tube(bark, Vector3.ZERO, top, 0.2, 0.16)
	var limbs := r.randi_range(3, 4)
	for k in limbs:
		var a := TAU * (k + r.randf_range(-0.2, 0.2)) / limbs
		var d := Vector3(cos(a) * 0.6, 1.0, sin(a) * 0.6).normalized()
		_grow(bark, r, top, d, r.randf_range(2.4, 3.2), 0.12, 0, tips)
	var mesh := bark.commit()
	mesh.surface_set_material(0, m_bark)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, top.y + 3.2, 0)
	for t in tips:
		for i in 7:
			var p := t + Vector3(r.randf_range(-1, 1), r.randf_range(-0.6, 0.9), r.randf_range(-1, 1)) * 1.1
			_leaf_card(leaves, r, p, r.randf_range(1.3, 2.0), (p - center).normalized())
	leaves.commit(mesh)
	mesh.surface_set_material(1, m_leaves)
	return mesh


func _bush_mesh() -> ArrayMesh:
	# a shrub for the areaway beds, from the same leaf cards
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 26:
		var a := r.randf() * TAU
		var p := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.0, 0.45) + Vector3(0, r.randf_range(0.2, 0.6), 0)
		_leaf_card(st, r, p, r.randf_range(0.5, 0.8), (p - Vector3(0, 0.1, 0)).normalized())
	var mesh := st.commit()
	mesh.surface_set_material(0, m_leaves)
	return mesh


func _leaf_card(st: SurfaceTool, r: RandomNumberGenerator, p: Vector3, size: float, out: Vector3) -> void:
	# one square of the leaf texture at p, turned at random; normals point out of the crown so it shades as a whole
	var b := Basis.from_euler(Vector3(r.randf() * TAU, r.randf() * TAU, r.randf() * TAU))
	var u := b.x * size / 2.0
	var v := b.y * size / 2.0
	var g := r.randf_range(0.8, 1.15)
	var col := Color(g, g * r.randf_range(0.95, 1.05), g * 0.9)
	var n := (out + Vector3(0, 0.5, 0)).normalized()
	var corners := [[p - u - v, Vector2(0, 1)], [p + u - v, Vector2(1, 1)], [p + u + v, Vector2(1, 0)], [p - u + v, Vector2(0, 0)]]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(corners[k][1])
		st.add_vertex(corners[k][0])


func _grow(st: SurfaceTool, r: RandomNumberGenerator, start: Vector3, dir: Vector3, length: float, radius: float, depth: int, tips: Array[Vector3]) -> void:
	# a limb in two bends; the first two levels fork twice, the last ones end in leaves
	var segments := 2
	var pos := start
	var d := dir
	for i in segments:
		var nd := (d + Vector3(r.randf_range(-1, 1), r.randf_range(-0.2, 0.4), r.randf_range(-1, 1)) * 0.25).normalized()
		var end := pos + nd * (length / segments)
		var r0 := radius * (1.0 - 0.4 * float(i) / segments)
		var r1 := radius * (1.0 - 0.4 * float(i + 1) / segments)
		_tube(st, pos, end, r0, r1)
		if depth < 2:
			for k in 2:
				var side := nd.cross(Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1))).normalized()
				var bd := (nd * 0.7 + side * r.randf_range(0.5, 0.9)).normalized()
				bd.y = absf(bd.y) * 0.6 + 0.3
				_grow(st, r, end, bd.normalized(), length * r.randf_range(0.55, 0.7), r1 * 0.6, depth + 1, tips)
		elif i == segments - 1:
			tips.append(end)
		pos = end
		d = nd


func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float) -> void:
	# tapered bark tube from a to b (as in map_builder.gd)
	var sides := 7 if ra > 0.05 else 4
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u)
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		var n0 := u * cos(a0) + v * sin(a0)
		var n1 := u * cos(a1) + v * sin(a1)
		for q in [[a + n0 * ra, n0], [b + n0 * rb, n0], [b + n1 * rb, n1], [a + n0 * ra, n0], [b + n1 * rb, n1], [a + n1 * ra, n1]]:
			st.set_normal(q[1])
			st.add_vertex(q[0])


# ---------------------------------------------------------------- draw everything collected above

func _flush() -> void:
	for mat in _boxes:
		_multi(_unit, _boxes[mat], mat, not _no_shadow.has(mat))
	for key in _kit:
		_multi(_kit_mesh(key), _kit[key], null, false) # (the house bodies cast the shadows)
	var stoop := _stoop_mesh()
	for mat in _stoops:
		_multi(stoop, _stoops[mat], mat)
	_multi(_rail_mesh(), _rails, m_iron, false)
	_multi(_fence_mesh(), _fences, m_iron, false)
	for v in _trees:
		_multi(_tree_mesh(v), _trees[v], null, false) # leaf cards casting shadows cost a third of the frame...
	# ...so each crown casts its shade from a plain flattened ball instead (shadow only, never drawn)
	var crown := SphereMesh.new()
	crown.radial_segments = 10
	crown.rings = 5
	var shade: Array[Transform3D] = []
	for v in _trees:
		for xf: Transform3D in _trees[v]:
			shade.append(xf * Transform3D(Basis.from_scale(Vector3(3.3, 1.9, 3.3)), Vector3(0, 6.3, 0)))
	_multi(crown, shade, m_soil)
	(get_child(get_child_count() - 1) as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_multi(_bush_mesh(), _bushes, null, false)
