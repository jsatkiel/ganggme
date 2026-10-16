extends Node3D
## Map 1 (placeholder name): a gated South Side housing project in winter.
## Red-brick mid-rise towers, 3-story walk-ups, black iron fencing, a guard booth
## at the gate, parking lots, bare trees and dirty snow.
## Layout traced from an aerial photo: two angled towers in a V around a central
## parking lot, ringed by long 3-story walk-ups, gate at the bottom center.
## North is -Z. The gate / street is on the south side (+Z).
##
## Collision layers: 1 = world (blocks bullets), 2 = iron fences (block movement,
## bullets pass through), 3 (value 4) = characters.

const FLOOR_H := 3.1
const ROAD_Y := -0.15 # the street, gate road and parking lot sit one curb (15 cm) below the sidewalks and lawns
const CAR_MODELS := [
	preload("res://assets/cars/sedan.glb"), preload("res://assets/cars/sedan-sports.glb"), preload("res://assets/cars/suv.glb"),
	preload("res://assets/cars/suv-luxury.glb"), preload("res://assets/cars/hatchback-sports.glb"), preload("res://assets/cars/van.glb"),
	preload("res://assets/cars/sedan.glb"), preload("res://assets/cars/suv.glb"),
]
const CAR_PAINT := preload("res://scripts/car_paint.gdshader")
const Cars := preload("res://scripts/cars.gd")
const COVERED_CAR := preload("res://assets/props/covered_car/covered_car.gltf")
const DUMPSTER := preload("res://assets/props/dumpster/dumpster.glb")
const TRASHBAG := preload("res://assets/props/trashbag/trashbag.gltf")
const TRASH_CAN := preload("res://assets/props/metal_trash_can/metal_trash_can.gltf")
const TIRE := preload("res://assets/props/old_tyre/old_tyre.gltf")
const HYDRANT := preload("res://assets/props/fire_hydrant/fire_hydrant.gltf")
const BOX := preload("res://assets/props/cardboard_box_01/cardboard_box_01.gltf")
const CAR_COLORS := [
	Color(0.45, 0.06, 0.07), Color(0.62, 0.63, 0.65), Color(0.07, 0.07, 0.08),
	Color(0.85, 0.85, 0.83), Color(0.1, 0.14, 0.3), Color(0.2, 0.28, 0.22), Color(0.35, 0.33, 0.3),
]
const TAGS := ["SOUTHSIDE", "BLOCK", "R.I.P.", "64TH ST", "KEEP OUT", "NO LACKIN", "TWIN", "LONG LIVE"]
const TAG_COLORS := [
	Color(0.9, 0.15, 0.2), Color(0.2, 0.55, 1.0), Color(1.0, 0.85, 0.1), Color(0.95, 0.95, 0.95), Color(0.4, 0.9, 0.3),
]

var rng := RandomNumberGenerator.new()
var player_spawns: Array[Vector3] = []
var bot_spawns: Array[Vector3] = []
var waypoints: Array[Vector3] = []

var _blocked: Array = [] # [center: Vector2, half_size: Vector2, yaw: float]
var _boards: Array[Transform3D] = []
var _pickets: Array[Transform3D] = []
var _posts: Array[Transform3D] = []
var _car_mats := {}

var m_concrete: StandardMaterial3D
var m_sidewalk: StandardMaterial3D
var m_curb: StandardMaterial3D
var m_asphalt: StandardMaterial3D
var m_road: StandardMaterial3D
var m_ground: StandardMaterial3D
var m_snow: StandardMaterial3D
var m_iron: StandardMaterial3D
var m_glass: StandardMaterial3D
var m_frame: StandardMaterial3D
var m_board: StandardMaterial3D
var m_bark: StandardMaterial3D
var m_yellow: StandardMaterial3D
var m_orange: StandardMaterial3D
var m_paint: StandardMaterial3D
var m_dumpster: StandardMaterial3D
var m_tire: StandardMaterial3D
var m_bag: StandardMaterial3D
var m_lawn: StandardMaterial3D
var m_leaves: StandardMaterial3D


func build() -> void:
	rng.seed = 6300
	_make_materials()
	_ground_and_roads()
	_buildings()
	_entrance()
	_fences()
	_parking()
	_props()
	_snow_piles()
	if not OS.get_cmdline_user_args().has("--no-grass"):
		_grass()
	_backdrop()
	_bounds()
	_flush_multimeshes()
	_spawns_and_waypoints()


# ---------------------------------------------------------------- materials

func _mat(c: Color, grime := 0.0, scale := 0.3, rough := 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if grime > 0.0:
		m.albedo_texture = _noise_tex(grime)
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * scale
	return m


func _noise_tex(grime: float) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = 0.03
	n.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = n
	var g := Gradient.new()
	g.set_color(0, Color(1.0 - grime, 1.0 - grime, 1.0 - grime))
	g.set_color(1, Color.WHITE)
	tex.color_ramp = g
	return tex


func _brick_mat(base: Color) -> StandardMaterial3D:
	var w := 128
	var h := 128
	var bw := 32
	var bh := 16
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var mortar := Color(0.6, 0.57, 0.53)
	for row in range(h / bh):
		var off := bw / 2 if row % 2 == 1 else 0
		for col in range(-1, w / bw + 1):
			var shade := rng.randf_range(0.8, 1.1)
			var bc := Color(base.r * shade, base.g * shade, base.b * shade)
			for y in range(row * bh, row * bh + bh):
				for x in range(col * bw + off, col * bw + off + bw):
					if x < 0 or x >= w:
						continue
					var lx := x - (col * bw + off)
					var ly := y - row * bh
					var c := mortar if (lx < 2 or ly < 2) else bc
					var g := rng.randf_range(0.92, 1.0)
					img.set_pixel(x, y, Color(c.r * g, c.g * g, c.b * g))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.9
	m.roughness = 1.0
	return m


func _pbr(id: String, repeats_per_meter: float, tint := Color.WHITE) -> StandardMaterial3D:
	# Poly Haven photo texture (CC0) mapped in world space so it tiles evenly across every box
	var base := "res://assets/textures/%s_%s_1k.jpg"
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(base % [id, "diff"])
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(base % [id, "nor_gl"])
	m.roughness_texture = load(base % [id, "rough"])
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * repeats_per_meter
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _pbr_set(diff: String, nor: String, rough: String, scale: Vector3, tint := Color.WHITE) -> StandardMaterial3D:
	# a texture set the user picked (assets/textures), world-mapped like _pbr
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/" + diff)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load("res://assets/textures/" + nor)
	m.roughness_texture = load("res://assets/textures/" + rough)
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _make_materials() -> void:
	m_concrete = _pbr("concrete_floor_02", 0.35, Color(0.95, 0.94, 0.92))
	m_sidewalk = _pbr_set("sidewalk02_diff.png", "sidewalk02_nor.png", "sidewalk02_rough.png", Vector3(0.5, 0.5, 0.5))
	m_asphalt = _pbr("asphalt_01", 0.22, Color(0.8, 0.8, 0.8))
	m_road = _pbr_set("road_cracked_diff.png", "road_cracked_nor.png", "road_cracked_rough.png", Vector3(0.11, 0.11, 0.275), Color(0.55, 0.55, 0.56)) # 9 x 3.6 m tile, dark
	m_curb = _pbr_set("curb_diff.jpg", "curb_nor.jpg", "curb_rough.jpg", Vector3(0.6, 0.6, 0.6), Color(0.85, 0.84, 0.82))
	m_ground = _pbr_set("snow_diff.png", "snow_nor.png", "snow_rough.png", Vector3(0.2, 0.2, 0.2), Color(0.8, 0.81, 0.84)) # snow-covered lawns
	m_snow = _pbr_set("snow_diff.png", "snow_nor.png", "snow_rough.png", Vector3(0.35, 0.35, 0.35), Color(0.62, 0.6, 0.58)) # piles: shoveled, dirty
	m_iron = _mat(Color(0.06, 0.06, 0.07), 0.0, 1.0, 0.5)
	m_glass = _mat(Color(0.13, 0.16, 0.2), 0.0, 1.0, 0.15)
	m_glass.metallic = 0.4
	m_frame = _mat(Color(0.82, 0.8, 0.75))
	m_board = _mat(Color(0.6, 0.48, 0.32), 0.3, 0.5)
	m_bark = _pbr("bark_brown_02", 0.9, Color(0.62, 0.6, 0.58))
	m_bark.uv1_world_triplanar = false
	m_bark.cull_mode = BaseMaterial3D.CULL_DISABLED
	m_yellow = _mat(Color(0.95, 0.75, 0.05))
	m_orange = _mat(Color(1.0, 0.45, 0.05))
	m_paint = _mat(Color(0.95, 0.95, 0.92))
	m_dumpster = _mat(Color(0.12, 0.25, 0.16), 0.4, 0.4)
	m_tire = _mat(Color(0.05, 0.05, 0.05))
	m_bag = _mat(Color(0.03, 0.03, 0.03), 0.0, 1.0, 0.35)
	m_lawn = _pbr_set("snow_diff.png", "snow_nor.png", "snow_rough.png", Vector3(0.2, 0.2, 0.2), Color(0.76, 0.77, 0.8)) # snowy strips by the doors, a touch more trampled
	m_leaves = _mat(Color(0.16, 0.24, 0.12), 0.0, 1.0, 0.9)


# ---------------------------------------------------------------- helpers

func add_box(pos: Vector3, size: Vector3, mat: Material, collide := true, yaw := 0.0, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	(parent if parent else self).add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
	return mi


func add_cyl(pos: Vector3, r_top: float, r_bot: float, height: float, mat: Material, collide := false, basis := Basis(), parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = height
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	(parent if parent else self).add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = maxf(r_top, r_bot)
		shape.height = height
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
	return mi


func _invisible_wall(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


func _tag(pos: Vector3, yaw: float, text: String, size := 1.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 140
	l.pixel_size = 0.006 * size
	l.modulate = TAG_COLORS[rng.randi() % TAG_COLORS.size()]
	l.outline_modulate = Color(0.05, 0.05, 0.05)
	l.outline_size = 22
	l.position = pos
	l.rotation = Vector3(0, yaw, rng.randf_range(-0.15, 0.15))
	l.shaded = true
	l.double_sided = false
	add_child(l)


# ---------------------------------------------------------------- layout
# Traced from the user's layout drawing. North is up (-Z), the gate is at the bottom (+Z).

# diamond-shaped parking lot: its edges run right up to the tower aprons (top) and the wing walkways (bottom),
# with the bottom point opening into the street
const LOT := [
	Vector2(0, -37.8), Vector2(31.3, -5.4), Vector2(5, 16.7),
	Vector2(-5, 16.7), Vector2(-31.3, -5.4),
]
# the two long angled 3-story wings: [center, length, depth, yaw in degrees]
# everything is mirrored left/right across the street (x = 0)
const LEFT_WING := [Vector2(-42, 2), 54.0, 13.0, -40.0]
const RIGHT_WING := [Vector2(42, 2), 54.0, 13.0, 40.0]


func _ground_and_roads() -> void:
	# Asphalt everywhere one curb down; the lawns/sidewalk level is a ground slab with the street,
	# the gate road and the parking lot cut out of it, so every road edge is a real 15 cm curb.
	add_box(Vector3(0, ROAD_Y - 0.5, 0), Vector3(320, 1, 320), m_road)
	var roads := PackedVector2Array(LOT)
	for cut in [_rect_pts(-5, 5, 4, 72.5), _rect_pts(-8, 8, 58, 72.5)]: # gate road up into the lot, wide apron at the gate
		roads = Geometry2D.merge_polygons(roads, cut)[0]
	var north := Geometry2D.clip_polygons(_rect_pts(-160, 160, -160, 71), roads)
	for poly in north:
		if not Geometry2D.is_polygon_clockwise(poly) or north.size() == 1:
			_ground_slab(poly)
	_ground_slab(_rect_pts(-160, 160, 85, 160)) # across the street
	# sidewalks along the street outside the gate (open where the gate road crosses)
	for side: float in [-1.0, 1.0]:
		add_box(Vector3(side * 51.5, 0.03, 69), Vector3(87, 0.06, 4), m_sidewalk, false)
	add_box(Vector3(0, 0.03, 87), Vector3(190, 0.06, 4), m_sidewalk, false)
	for x in range(-90, 91, 6): # center line dashes
		add_box(Vector3(x, ROAD_Y + 0.005, 78), Vector3(3, 0.01, 0.18), m_yellow, false)
	# two-way street from the gate straight up into the parking lot
	for x in [-0.15, 0.15]: # double yellow center line
		add_box(Vector3(x, ROAD_Y + 0.006, 41.5), Vector3(0.1, 0.01, 49), m_yellow, false)
	for x in [-4.6, 4.6]: # white edge lines
		add_box(Vector3(x, ROAD_Y + 0.006, 41.5), Vector3(0.12, 0.01, 49), m_paint, false)
	# along the lot side of each wing: green grass strip leading to the doors, then the walkway
	for w in [LEFT_WING, RIGHT_WING]:
		# building face is 6.5 out, its concrete apron ends at 8.5: grass to 10, walkway 10 - 12.5
		_band(w, 0.0, w[1], 8.5, 10.0, m_lawn, 0.03)
		_band(w, 0.0, w[1], 10.0, 12.5, m_sidewalk, 0.04)
		_band(w, 0.0, 2.4, 8.5, 10.0, m_sidewalk, 0.04) # short path across the grass to the door
	# straight walkways in front of the two bottom buildings, running to the street
	# Walkway network near the street, built from shapes cut to fit so every corner meets flush.
	# Left-side points; the right side is the mirror image.
	for s: float in [-1.0, 1.0]:
		# wing walkway continues from the wing's end straight to the street sidewalk
		_sidewalk_poly(s, [Vector2(-14.89, 11.70), Vector2(-13.28, 9.78), Vector2(-7.5, 14.63), Vector2(-7.5, 17.90)], LEFT_WING[3])
		# sidewalk along the street, from the lot edge down to the gate (top edge follows the lot edge)
		_sidewalk_poly(s, [Vector2(-7.5, 14.63), Vector2(-5.0, 16.7), Vector2(-5.0, 58.0), Vector2(-7.5, 58.0)])
		# walkway in front of the bottom building, ending exactly at the street sidewalk
		_sidewalk_poly(s, [Vector2(-68.0, 30.25), Vector2(-7.5, 30.25), Vector2(-7.5, 32.75), Vector2(-68.0, 32.75)])


func _sidewalk_poly(s: float, pts: Array, yaw_deg := 0.0) -> void:
	# flat sidewalk shape at the same height as the wing walkways; s = -1 left side, 1 mirrored to the right.
	# yaw_deg (left-side value) is the direction the piece runs, used to fit its keep-clear box.
	var poly := PackedVector2Array()
	for p: Vector2 in pts:
		poly.append(Vector2(p.x * -s, p.y))
	_flat_poly(poly, 0.055, m_sidewalk)
	# keep props off it: tightest box in the piece's own direction
	var y := deg_to_rad(yaw_deg * -s)
	var u := Vector2(cos(y), -sin(y))
	var n := Vector2(sin(y), cos(y))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		var l := Vector2(p.dot(u), p.dot(n))
		lo = Vector2(minf(lo.x, l.x), minf(lo.y, l.y))
		hi = Vector2(maxf(hi.x, l.x), maxf(hi.y, l.y))
	var mid := (lo + hi) / 2.0
	_keep_clear(u * mid.x + n * mid.y, hi - lo, y)


func _band(w: Array, along: float, length: float, off_a: float, off_b: float, mat: Material, y: float) -> void:
	# flat strip on the lot side of a wing, between off_a and off_b meters out from its center line
	var c: Vector2 = w[0]
	var yaw := deg_to_rad(w[3])
	var unit := Vector2(cos(yaw), -sin(yaw))
	var lot_side := -Vector2(sin(yaw), cos(yaw))
	var mid := c + unit * along + lot_side * ((off_a + off_b) / 2.0)
	var size := Vector2(length, off_b - off_a)
	add_box(Vector3(mid.x, y, mid.y), Vector3(size.x, 0.03, size.y), mat, false, yaw)
	_keep_clear(mid, size, yaw)


func _buildings() -> void:
	# the two 8-story towers, leaning in toward each other at the top of the lot
	_building(-21, -29, 36, 14, 8, true, 46)
	_building(21, -29, 36, 14, 8, true, -46)
	# 3-story walk-ups
	_building(-36, -60, 46, 13, 3, false, 0) # top left
	_building(36, -60, 46, 13, 3, false, 0) # top right
	_building(LEFT_WING[0].x, LEFT_WING[0].y, LEFT_WING[1], LEFT_WING[2], 3, false, LEFT_WING[3]) # left wing
	_building(RIGHT_WING[0].x, RIGHT_WING[0].y, RIGHT_WING[1], RIGHT_WING[2], 3, false, RIGHT_WING[3]) # right wing
	_building(-42, 44, 52, 14, 3, false, 0) # bottom left (by the gate)
	_building(42, 44, 52, 14, 3, false, 0) # bottom right (by the gate)


func _wing(a: Vector2, b: Vector2, width: float) -> void:
	# 3-story building running from point a to point b
	var d := b - a
	var mid := (a + b) / 2.0
	_building(mid.x, mid.y, d.length(), width, 3, false, rad_to_deg(atan2(-d.y, d.x)))


func _walkway(a: Vector2, b: Vector2, width := 2.5) -> void:
	var d := b - a
	var mid := (a + b) / 2.0
	# extend a little past each end so joined segments overlap cleanly
	add_box(Vector3(mid.x, 0.04, mid.y), Vector3(d.length() + width * 0.5, 0.04, width), m_sidewalk, false, atan2(-d.y, d.x))
	_keep_clear(mid, Vector2(d.length() + width * 0.5, width), atan2(-d.y, d.x))


func _flat_poly(pts: PackedVector2Array, y: float, mat: Material) -> void:
	# flat convex shape on the ground (lawns, the diamond lot); both sides so winding never matters
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, pts.size() - 1):
		for tri in [[pts[0], pts[i], pts[i + 1]], [pts[0], pts[i + 1], pts[i]]]:
			for p: Vector2 in tri:
				st.set_normal(Vector3.UP)
				st.set_uv(p * 0.1)
				st.add_vertex(Vector3(p.x, y, p.y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


func _building(cx: float, cz: float, sx: float, sz: float, floors: int, tower: bool, yaw_deg := 0.0) -> void:
	# walls tiled from the Downtown City MegaKit (Quaternius, CC0): 2 m wide, 3 m tall pieces, stretched a
	# little so each face holds a whole, odd number of them (a door piece lands dead center) and floors are FLOOR_H.
	var by := deg_to_rad(yaw_deg)
	var c := Vector3(cx, 0, cz)
	var h := floors * FLOOR_H + 0.6
	var root := Node3D.new()
	root.position = c
	root.rotation.y = by
	add_child(root)
	_block(Vector2(cx, cz), Vector2(sx, sz), by)
	_bldg.append([Vector2(cx, cz), Vector2(sx + 3.9, sz + 3.9) / 2.0, by]) # footprint incl. concrete apron
	add_box(Vector3(0, h + 0.2, 0), Vector3(sx + 0.3, 0.4, sz + 0.3), m_concrete, false, 0.0, root) # roof cap
	add_box(Vector3(0, 0.125, 0), Vector3(sx + 0.1, 0.25, sz + 0.1), m_concrete, false, 0.0, root) # base course, under the ground-floor sills
	if tower:
		for f in range(1, floors):
			add_box(Vector3(0, f * FLOOR_H, 0), Vector3(sx + 0.14, 0.26, sz + 0.14), m_concrete, false, 0.0, root)
	add_box(c + Vector3(0, 0.03, 0), Vector3(sx + 4, 0.06, sz + 4), m_sidewalk, false, by) # apron
	# the kit pieces don't cast shadows (too heavy on a laptop GPU); this plain box does it for them
	var shadow := add_box(Vector3(0, h / 2.0, 0), Vector3(sx - 0.1, h, sz - 0.1), m_concrete, false, 0.0, root)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY

	# random details come from a seed shared with the mirror-image building, and are laid out in that
	# building's frame (faces 2/3 swap, columns run backwards) so the pair stays an exact mirror
	var r := RandomNumberGenerator.new()
	r.seed = int(absf(cx) * 1000.0 + cz * 7.0)
	var flip := cx > 0.0
	var ys := FLOOR_H / 3.0
	var pieces := {} # kit piece -> Array[Transform3D] (building-local)
	var shell := PackedVector3Array() # collision triangles on the wall faces, open where the windows are
	for fc in 4:
		var face: int = [0, 1, 3, 2][fc] if flip else fc
		var along := sx if face < 2 else sz
		var depth := sz if face < 2 else sx
		var basis := Basis(Vector3.UP, [0.0, PI, PI / 2, -PI / 2][face])
		var n := 2 * roundi((along / 2.0 - 1.0) / 2.0) + 1
		var w := along / n
		var xs := w / 2.0
		var openings: Array[float] = [] # centers of the window openings on this face
		for f in floors:
			for ic in n:
				var i := n - 1 - ic if flip else ic
				var o := -along / 2.0 + w * (i + 0.5)
				var at := Transform3D(basis, basis * Vector3(o, f * FLOOR_H, depth / 2.0))
				var xf := at * Transform3D(Basis.from_scale(Vector3(xs, ys, 1.0)), Vector3.ZERO)
				var corner := ic == 0 or ic == n - 1
				if f == 0 and ic == n / 2:
					# entrance: steel door in a plain brick bay under a concrete canopy
					_piece(pieces, "Brick_BottomTrim", xf)
					_piece(pieces, "Door_1", at * Transform3D(Basis(), Vector3(0.5, 0.0, 0.05)))
					var canopy := at * Transform3D(Basis(), Vector3(0, 2.55, 0.6))
					add_box(canopy.origin, Vector3(2.4, 0.15, 1.2), m_concrete, false, basis.get_euler().y, root)
					continue
				if corner:
					_piece(pieces, "Brick_BottomTrim" if f == 0 else "Brick_Plain_3", xf)
					continue
				_piece(pieces, WIN, xf)
				if f == 1:
					openings.append(o)
				if r.randf() < 0.07:
					_boards.append(root.transform * at * Transform3D(Basis.from_scale(Vector3(WIN_GLASS.size.x * xs + 0.12, WIN_GLASS.size.y * ys + 0.12, 1.0) / Vector3(1.35, 1.55, 1.0)), Vector3(0, WIN_GLASS.get_center().y * ys, -0.12)))
				elif f >= 1 and r.randf() < 0.22:
					_piece(pieces, "Prop_ACUnit", at * Transform3D(Basis(), Vector3(-0.04, WIN_GLASS.position.y * ys, -0.06)))
		# parapet above the top floor
		for ic in n:
			var o := -along / 2.0 + w * (ic + 0.5)
			_piece(pieces, "Brick_Plain_1", Transform3D(basis, basis * Vector3(o, floors * FLOOR_H, depth / 2.0)) * Transform3D(Basis.from_scale(Vector3(xs, 0.6, 1.0)), Vector3.ZERO))
		_wall_shell(shell, basis, along, depth, xs, floors, h, openings)
	for key in pieces:
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _kit_mesh(key)
		var list: Array = pieces[key]
		mm.instance_count = list.size()
		for k in list.size():
			mm.set_instance_transform(k, list[k])
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)

	# collision: the solid core is set back to the glass, and a thin shell covers the brick in front of it,
	# so bullet holes land right on the brick or right on the glass instead of floating in the window recess
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var core := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(sx - WIN_DEPTH * 2.0, h, sz - WIN_DEPTH * 2.0)
	core.shape = bs
	core.position.y = h / 2.0
	body.add_child(core)
	var cs := CollisionShape3D.new()
	var cps := ConcavePolygonShape3D.new()
	cps.backface_collision = true
	cps.set_faces(shell)
	cs.shape = cps
	body.add_child(cs)
	root.add_child(body)

	# graffiti on the low walk-ups (mirrored with the other side's building like the rest)
	if not tower:
		for i in 2:
			var fc := r.randi() % 4
			var face: int = [0, 1, 3, 2][fc] if flip else fc
			var yaw: float = by + [0.0, PI, PI / 2, -PI / 2][face]
			var basis := Basis(Vector3.UP, yaw)
			var along := sx if face < 2 else sz
			var center := c + basis * Vector3(0, 0, (sz if face < 2 else sx) / 2.0 + 0.09)
			var o := r.randf_range(-along / 2 + 3, along / 2 - 3)
			var p := center + basis * Vector3(-o if flip else o, 1.7, 0)
			_tag(p, yaw, TAGS[r.randi() % TAGS.size()], r.randf_range(0.8, 1.4))


const KIT := "res://assets/citykit/%s.gltf"
const WIN := "Brick_Window_Trim"
const WIN_GLASS := Rect2(-0.55, 0.28, 1.1, 2.08) # window opening in the unscaled piece (x, y), a little past the glass
const WIN_DEPTH := 0.2 # how far the glass sits back from the wall face
var _kit_cache := {}


func _piece(pieces: Dictionary, key: String, xf: Transform3D) -> void:
	if not pieces.has(key):
		pieces[key] = []
	pieces[key].append(xf)


func _kit_mesh(key: String) -> Mesh:
	# a kit piece's mesh without the inside-of-the-room surfaces (never seen behind opaque glass), glass made opaque
	if _kit_cache.has(key):
		return _kit_cache[key]
	var scene: Node = load(KIT % key).instantiate()
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
	_kit_cache[key] = mesh
	return mesh


func _wall_shell(tris: PackedVector3Array, basis: Basis, along: float, depth: float, xs: float, floors: int, h: float, openings: Array[float]) -> void:
	# collision quads on one wall face (building-local), leaving holes where the window openings are
	# (the middle bay of the ground floor is the door, not a window)
	var ys := FLOOR_H / 3.0
	var hw := WIN_GLASS.size.x / 2.0 * xs
	var y0 := WIN_GLASS.position.y * ys
	var y1 := WIN_GLASS.end.y * ys
	var quad := func(xa: float, xb: float, ya: float, yb: float) -> void:
		var p := [Vector3(xa, ya, depth / 2.0), Vector3(xb, ya, depth / 2.0), Vector3(xb, yb, depth / 2.0), Vector3(xa, yb, depth / 2.0)]
		for k in [0, 1, 2, 0, 2, 3]:
			tris.append(basis * p[k])
	for f in floors:
		var base := f * FLOOR_H
		quad.call(-along / 2.0, along / 2.0, base, base + y0)
		quad.call(-along / 2.0, along / 2.0, base + y1, base + FLOOR_H)
		var x := -along / 2.0
		for o in openings:
			if f == 0 and absf(o) < 0.01:
				continue
			quad.call(x, o - hw, base + y0, base + y1)
			x = o + hw
		quad.call(x, along / 2.0, base + y0, base + y1)
	quad.call(-along / 2.0, along / 2.0, floors * FLOOR_H, h)


func _entrance() -> void:
	# guard booth on an island in the middle of the drive
	add_box(Vector3(0, (0.24 + ROAD_Y) / 2.0, 63), Vector3(3.2, 0.24 - ROAD_Y, 9), m_curb) # curbed island, from the road up
	add_box(Vector3(0, 1.45, 63), Vector3(2.2, 2.5, 2.8), m_paint)
	add_box(Vector3(0, 1.75, 63), Vector3(2.25, 0.9, 2.2), m_glass, false)
	add_box(Vector3(0, 1.75, 63), Vector3(1.6, 0.9, 2.85), m_glass, false)
	add_box(Vector3(0, 2.8, 63), Vector3(3.0, 0.22, 3.6), m_concrete, false)
	_block(Vector2(0, 63), Vector2(3.6, 9), 0.0)
	# yellow bollards
	for z in [59.0, 67.0]:
		for x in [-0.9, 0.9]:
			add_cyl(Vector3(x, 0.24 + 0.55, z), 0.13, 0.13, 1.1, m_yellow, true) # on the island
	# barrier arms (orange/white)
	for side in [-1.0, 1.0]:
		add_box(Vector3(side * 4.9, 1.0, 61.0), Vector3(6.6, 0.12, 0.12), m_orange, false) # reaches the fence
		add_box(Vector3(side * 1.6, 0.24 + 0.6, 61.0), Vector3(0.3, 1.2, 0.3), m_paint, true)
	# "no trespassing" sign by the gate
	add_cyl(Vector3(-7.5, 1.3, 66), 0.05, 0.05, 2.6, m_iron)
	add_box(Vector3(-7.5, 2.4, 66.05), Vector3(0.9, 0.6, 0.05), m_paint, false)
	var sign := Label3D.new()
	sign.text = "NO\nTRESPASSING"
	sign.font_size = 48
	sign.pixel_size = 0.004
	sign.modulate = Color(0.8, 0.05, 0.05)
	sign.position = Vector3(-7.5, 2.4, 66.09)
	add_child(sign)


func _fences() -> void:
	# perimeter, with the gate gap on the south side
	_fence(Vector2(-90, 67), Vector2(-8.2, 67))
	_fence(Vector2(-8.2, 67), Vector2(-8.2, 61)) # turns up the road edge to meet the gate arm
	_fence(Vector2(8.2, 67), Vector2(90, 67))
	_fence(Vector2(8.2, 67), Vector2(8.2, 61))
	_fence(Vector2(-90, 67), Vector2(-90, -82))
	_fence(Vector2(90, 67), Vector2(90, -82))
	_fence(Vector2(-90, -82), Vector2(90, -82))
	# fences lining the street up from the gate (cover you can shoot through)
	_fence(Vector2(-8.5, 34), Vector2(-8.5, 56), 1.5)
	_fence(Vector2(8.5, 34), Vector2(8.5, 56), 1.5)


func _fence(a: Vector2, b: Vector2, h := 1.9) -> void:
	var d := b - a
	var length := d.length()
	var mid := (a + b) / 2.0
	var yaw := atan2(-d.y, d.x)
	var basis := Basis(Vector3.UP, yaw)
	for ry in [0.2, h - 0.12]:
		add_box(Vector3(mid.x, ry, mid.y), Vector3(length, 0.05, 0.05), m_iron, false, yaw)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(length, h + 0.5, 0.2)
	cs.shape = bs
	body.add_child(cs)
	body.position = Vector3(mid.x, (h + 0.5) / 2.0, mid.y)
	body.rotation.y = yaw
	add_child(body)
	var dir3 := Vector3(d.x, 0, d.y) / length
	var start := Vector3(a.x, 0, a.y)
	var count := int(length / 0.14)
	for i in count + 1:
		_pickets.append(Transform3D(basis.scaled(Vector3(1, h, 1)), start + dir3 * (i * length / count) + Vector3(0, h / 2.0, 0)))
	var posts := int(length / 2.4)
	for i in posts + 1:
		_posts.append(Transform3D(basis.scaled(Vector3(1, h + 0.1, 1)), start + dir3 * (i * length / maxi(posts, 1)) + Vector3(0, (h + 0.1) / 2.0, 0)))


func _parking() -> void:
	# the two Car_Free_02s go in random lot spots far apart from each other
	var a := rng.randi_range(2, 20)
	_free02_slots = [a, a + rng.randi_range(14, 22)]
	var c := a + rng.randi_range(5, 9)
	_covered_slots = [c, c + rng.randi_range(16, 24)]
	if _covered_slots[1] in _free02_slots:
		_covered_slots[1] += 2
	# Spots run diagonal with the diamond:
	#  - a row along each of the four lot edges, cars pulled in nose-first toward the building on that side
	#  - a driving lane all the way around inside those rows, open to the street at the bottom
	#  - a small diamond island in the middle with spots on its four sides and grass in the very center
	# Right-side numbers; the left side is the mirror image (s = -1).
	var ne_in := Vector2(-0.719, 0.695) # inward normal of the top-right lot edge
	var se_in := Vector2(-0.643, -0.766) # inward normal of the bottom-right lot edge
	for s: float in [1.0, -1.0]:
		var m := func(v: Vector2) -> Vector2: return Vector2(v.x * s, v.y)
		# outer rows along the lot edges (nose toward the building = against the inward normal)
		_stall_row(m.call(Vector2(0, -37.8)), m.call(Vector2(31.3, -5.4)), m.call(ne_in), 5.5, 5.5, false)
		_stall_row(m.call(Vector2(31.3, -5.4)), m.call(Vector2(5, 16.7)), m.call(se_in), 5.5, 6.0, false)
		# center island rows (nose pulled in toward the middle of the island)
		_stall_row(m.call(Vector2(0, -21.5)), m.call(Vector2(14.7, -6.3)), m.call(ne_in), 5.5, 5.7, true)
		_stall_row(m.call(Vector2(14.7, -6.3)), m.call(Vector2(0, 6.0)), m.call(se_in), 5.7, 4.4, true)
	# grass in the very middle of the island, with a tree
	var island := PackedVector2Array([Vector2(0, -13.9), Vector2(6.9, -6.7), Vector2(0, -0.9), Vector2(-6.9, -6.7)])
	_ground_slab(island) # raised, curbed
	_flat_poly(island, 0.01, m_lawn)
	_tree(0.0, -7.0, 6.5)
	_block(Vector2(0, -7), Vector2(1.2, 1.2), 0.0)
	# cars parked on the street outside
	for x in [-70.0, -50.0, -31.0, -18.0, 22.0, 41.0, 57.0, 75.0]:
		_car(x, 74.0 if rng.randf() < 0.5 else 82.0, rng.randf_range(-0.05, 0.05) + (PI if rng.randf() < 0.5 else 0.0), true)


func _stall_row(a: Vector2, b: Vector2, inward: Vector2, inset_a: float, inset_b: float, nose_in: bool) -> void:
	# a row of 2.8 m wide, 5 m deep parking spots along the edge a -> b, extending in the inward direction
	var d := (b - a).normalized()
	var usable := a.distance_to(b) - inset_a - inset_b
	var count := int(usable / 2.8)
	var start := inset_a + (usable - count * 2.8) / 2.0
	var line_yaw := atan2(-inward.y, inward.x)
	var nose := inward if nose_in else -inward
	var car_yaw := atan2(-nose.y, nose.x)
	for k in count + 1:
		var p := a + d * (start + k * 2.8) + inward * 2.5
		add_box(Vector3(p.x, ROAD_Y + 0.006, p.y), Vector3(5.0, 0.01, 0.12), m_paint, false, line_yaw)
	for k in count:
		if rng.randf() < 0.88:
			var c := a + d * (start + (k + 0.5) * 2.8) + inward * 2.65
			c += d * rng.randf_range(-0.15, 0.15) + inward * rng.randf_range(-0.2, 0.2)
			_car(c.x, c.y, car_yaw + rng.randf_range(-0.06, 0.06), false, Vector2.ZERO if nose_in else inward)


func _car(x: float, z: float, yaw: float, street := false, push := Vector2.ZERO) -> void:
	# a parked car from the user's picks (cars.gd), shuffled so the same model never sits next to itself.
	# push: direction to slide a long car so its back end stays inside the lot edge
	var root := Node3D.new()
	root.position = Vector3(x, ROAD_Y, z)
	root.rotation.y = yaw
	add_child(root)
	var size := Vector3(4.38, 1.4, 1.79)
	var hull: Shape3D = null
	if not street and _lot_cars in _covered_slots:
		# a car that hasn't moved in years, under a dusty tarp (Poly Haven, CC0): two of these, lot only
		var covered: Node3D = COVERED_CAR.instantiate()
		covered.rotation.y = PI / 2
		root.add_child(covered)
		_last_car = "covered"
		_lot_cars += 1
	else:
		var id := _pick_car(street)
		var made: Array = Cars.make(id, rng)
		root.add_child(made[0])
		size = made[1]
		hull = made[2]
		var extra := maxf(0.0, size.x / 2.0 - 2.3)
		if extra > 0.0 and push != Vector2.ZERO:
			x += push.x * extra
			z += push.y * extra
			root.position = Vector3(x, ROAD_Y, z)
	# collision that hugs the body, so bullet holes land on the car instead of floating around it
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	if hull:
		cs.shape = hull
	else:
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		cs.position.y = size.y / 2.0
	body.add_child(cs)
	root.add_child(body)
	_block(Vector2(x, z), Vector2(size.x + 0.3, size.z + 0.35), yaw)
	_cars.append([Vector2(x, z), Vector2(size.x, size.z) / 2.0, yaw])


var _covered_slots: Array = [] # which lot cars are tarp-covered (two, never on the street)
var _last_car := ""
var _lot_cars := 0
var _free02_slots: Array = [] # which lot cars are Car_Free_02 (only two, never on the street)


func _pick_car(street: bool) -> String:
	var id := ""
	if not street and _lot_cars in _free02_slots:
		id = "carfree02"
	else:
		var pool: Array = Cars.MODELS.keys().filter(func(k): return k != "carfree02" and k != _last_car)
		id = pool[rng.randi() % pool.size()]
	if not street:
		_lot_cars += 1
	_last_car = id
	return id


func _in_lot(p: Vector2) -> bool:
	# the parking lot and the street up from the gate
	return Geometry2D.is_point_in_polygon(p, PackedVector2Array(LOT)) or (absf(p.x) < 6.0 and p.y > 5.0)


func _spot_free(p: Vector2, margin: float) -> bool:
	return not (_in_lot(p) or _is_blocked(p, margin) or _is_blocked(p, 1.0, _clear))


func _random_spot(margin: float) -> Variant:
	# picks a spot on the left half whose mirror image on the right is also free
	for i in 80:
		var p := Vector2(rng.randf_range(-86, -7), rng.randf_range(-79, 64))
		if _spot_free(p, margin) and _spot_free(Vector2(-p.x, p.y), margin):
			return p
	return null


func _mirror(p: Vector2) -> Vector2:
	return Vector2(-p.x, p.y)


func _props() -> void:
	# every prop is placed in mirrored pairs so the map stays symmetrical
	# bare winter trees on the lawns
	for i in 22:
		var spot = _random_spot(3.0)
		if spot == null:
			continue
		var h := rng.randf_range(5.0, 8.0)
		for p in [spot, _mirror(spot)]:
			_tree(p.x, p.y, h)
			_block(p, Vector2(1.2, 1.2), 0.0)
	# snow piles out on the lawns (more go in corners and at walkway ends in _snow_piles)
	for i in 9:
		var spot = _random_spot(1.5)
		if spot == null:
			continue
		var size := rng.randf_range(1.6, 3.0)
		var yaw := rng.randf() * TAU
		_snow_pile(spot, size, yaw)
		_snow_pile(_mirror(spot), size, -yaw)
	# dumpsters + trash bags
	for i in 4:
		var spot = _random_spot(2.5)
		if spot == null:
			continue
		var yaw := rng.randf() * TAU
		for k in 2:
			var p: Vector2 = spot if k == 0 else _mirror(spot)
			var y := yaw if k == 0 else -yaw
			var pos := Vector3(p.x, 0, p.y)
			# real dumpster model (CC0, NaiveGoblin), turned so its long side runs along local X
			_prop(DUMPSTER, pos, y + PI / 2, 1.15)
			add_box(pos + Vector3(0, 0.7, 0), Vector3(2.3, 1.4, 1.3), m_dumpster, true, y).visible = false
			_block(p, Vector2(2.4, 3.6), y)
			# trash bags piled against the front (Poly Haven, CC0), mirrored with the dumpster
			var r := RandomNumberGenerator.new()
			r.seed = i * 97 + 5
			for j in 4:
				var off := Vector3(-0.9 + j * 0.6 + r.randf_range(-0.1, 0.1), 0, 1.0 + r.randf_range(0.0, 0.35))
				if k == 1:
					off.x = -off.x
				var spin := r.randf() * TAU
				_prop(TRASHBAG, pos + Basis(Vector3.UP, y) * off, spin if k == 0 else -spin, r.randf_range(0.85, 1.25))
			var box_off := Vector3(1.6, 0, 0.3) * Vector3(1.0 if k == 0 else -1.0, 1, 1)
			_prop(BOX, pos + Basis(Vector3.UP, y) * box_off, y + 0.4, 1.3)
	# street clutter by the walk-ups: dented trash cans, old tires, more bags
	for i in 7:
		var spot = _random_spot(1.5)
		if spot == null:
			continue
		var yaw := rng.randf() * TAU
		var kind := i % 3
		for k in 2:
			var p: Vector2 = spot if k == 0 else _mirror(spot)
			var y := yaw if k == 0 else -yaw
			var pos := Vector3(p.x, 0, p.y)
			if kind == 0:
				_prop(TRASH_CAN, pos, y, 1.0, "rust", Vector3(0.5, 0, 0))
				_prop(TRASH_CAN, pos + Basis(Vector3.UP, y) * Vector3(0.65, 0, 0), y + 1.0, 1.0, "rust", Vector3(0.5, 0, 0))
				_prop(TRASHBAG, pos + Basis(Vector3.UP, y) * Vector3(0.3, 0, 0.6), y, 0.9)
			elif kind == 1:
				for t in 3:
					_prop(TIRE, pos + Vector3(0, 0.08 + t * 0.165, 0), y + t * 0.7, 1.0, "", Vector3.ZERO, Vector3(PI / 2, 0, 0))
				_prop(TIRE, pos + Basis(Vector3.UP, y) * Vector3(0.75, 0.3, 0.1), y, 1.0, "", Vector3.ZERO, Vector3(0, 0, 0.25))
			else:
				for j in 3:
					_prop(TRASHBAG, pos + Basis(Vector3.UP, y) * Vector3(j * 0.55 - 0.55, 0, (j % 2) * 0.3), y + j, 1.1)
			_block(p, Vector2(1.6, 1.6), y)
	# fire hydrants on the street sidewalks
	for spot in [Vector2(-6.4, 26.0), Vector2(-6.4, 52.0)]:
		for p in [spot, _mirror(spot)]:
			_prop(HYDRANT, Vector3(p.x, 0.08, p.y), (PI / 2 if p.x < 0 else -PI / 2), 1.0, "aged", Vector3(-0.3, 0, 0))
			_block(p, Vector2(0.5, 0.5), 0.0)
	# concrete jersey barriers (hard cover)
	for i in 5:
		var spot = _random_spot(2.5)
		if spot == null:
			continue
		var yaw := rng.randf() * TAU
		_jersey(spot, yaw)
		_jersey(_mirror(spot), -yaw)
	# streetlights in mirrored pairs along the street and in the lot
	for spot in [Vector2(-8, 20), Vector2(-8, 45), Vector2(-3, -33), Vector2(-16.5, -8), Vector2(-20, 69)]:
		for p in [spot, _mirror(spot)]:
			var dir := 1.0 if p.x < 0 else -1.0 # arm reaches over the street / lot
			var base := Vector3(p.x, 0, p.y)
			add_cyl(base + Vector3(0, 3.5 + ROAD_Y / 2.0, 0), 0.08, 0.12, 7.0 - ROAD_Y, m_iron, true) # reaches down to the road when it stands in the lot
			add_box(base + Vector3(0.7 * dir, 7.0, 0), Vector3(1.6, 0.1, 0.1), m_iron, false)
			add_box(base + Vector3(1.4 * dir, 6.9, 0), Vector3(0.6, 0.15, 0.35), m_frame, false)
			_block(p, Vector2(0.6, 0.6), 0.0)


func _jersey(spot: Vector2, yaw: float) -> void:
	add_box(Vector3(spot.x, 0.45, spot.y), Vector3(3.0, 0.9, 0.6), m_concrete, true, yaw)
	_block(spot, Vector2(3.2, 0.8), yaw)


func _tree(x: float, z: float, height: float) -> void:
	# bare dead winter tree (generated, Poly Haven bark texture). Variant and turn come from a seed
	# based on |x| so a mirrored pair of trees is the exact mirror image.
	var r := RandomNumberGenerator.new()
	r.seed = int(absf(x) * 1000.0 + z * 7.0)
	var mi := MeshInstance3D.new()
	mi.mesh = _dead_tree_mesh(r.randi() % TREE_VARIANTS)
	mi.material_override = m_bark
	var s := height / TREE_BASE_HEIGHT
	mi.scale = Vector3(-s if x > 0.0 else s, s, s)
	var turn := r.randf() * TAU
	mi.rotation.y = turn if x <= 0.0 else -turn
	mi.position = Vector3(x, 0, z)
	add_child(mi)
	# trunk collision
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.25
	shape.height = height * 0.45
	cs.shape = shape
	cs.position = Vector3(x, height * 0.225, z)
	body.add_child(cs)
	add_child(body)


func _backdrop() -> void:
	# the neighborhood around the block, from the user's city pack: old brick storefronts lining the street
	# across from the gate and standing just outside the other three fences, high-rises and panel blocks
	# further out. All in mirrored pairs; pieces only ever face the block.
	var r := RandomNumberGenerator.new()
	r.seed = 7171
	var placed := {} # pack piece + "|shadow"/"|flat" -> Array[Transform3D]
	# street across from the gate: fronts on the far sidewalk (z 89), facing the gate
	_shop_row(r, placed, Vector3(0, 0, 89.3), Vector3.RIGHT, 130.0, true)
	# behind the fences: north, and west (east is its mirror image)
	_shop_row(r, placed, Vector3(0, 0, -95.0), Vector3.RIGHT, 130.0, false)
	_shop_row(r, placed, Vector3(-101.0, 0, -4.0), Vector3.BACK, 88.0, false) # stops short of the north row and the street
	# skyline ring
	for i in 22:
		var ang := lerpf(PI * 0.5, PI * 1.5, (i + r.randf_range(0.1, 0.9)) / 22.0) # left half (x < 0)
		var dist := r.randf_range(138, 175)
		var p := Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		var piece: String = SKYLINE[r.randi() % SKYLINE.size()]
		var s := r.randf_range(3.6, 4.4)
		var yaw := atan2(-p.x, -p.z) + r.randf_range(-0.2, 0.2) # front toward the middle of the map
		for k in 2:
			var q := p if k == 0 else Vector3(-p.x, 0, p.z)
			_pack_place(placed, piece, q, yaw if k == 0 else -yaw, s, false, false)
	for key: String in placed:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _pack_piece(key.get_slice("|", 0))[0]
		var list: Array = placed[key]
		mm.instance_count = list.size()
		for k in list.size():
			mm.set_instance_transform(k, list[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if key.ends_with("|flat"):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	_pack_root.free() # only needed to pull the meshes out
	_pack_root = null


const CITY_PACK := preload("res://assets/city_pack/city_pack.fbx")
const PACK_SCALE := 4.0 # the pack is modeled about a quarter of real size
const SHOPS := ["Plane_002", "Plane_008", "Plane_001", "Cube_002", "Plane_004", "Cube_001", "Cube_003"] # storefronts, front faces +Z
const SKYLINE := ["Plane_027", "Plane_028", "Plane_029", "Plane_030", "Cube_014", "Cube_014"] # high-rises (open backs) + panel block
const PACK_FRONT := {"Plane_027": -PI / 2, "Cube_014": -PI / 2} # pieces whose front faces +X instead of +Z
var _pack_root: Node3D
var _pack_cache := {}


func _pack_piece(piece: String) -> Array:
	# [mesh, transform of its node in the pack, bounds in the pack]
	if not _pack_cache.has(piece):
		if _pack_root == null:
			_pack_root = CITY_PACK.instantiate()
		var mi: MeshInstance3D = _pack_root.find_child(piece, true, false)
		var xf := Transform3D.IDENTITY
		var n: Node3D = mi
		while n != _pack_root:
			xf = n.transform * xf
			n = n.get_parent()
		_pack_cache[piece] = [mi.mesh, xf, xf * mi.get_aabb()]
	return _pack_cache[piece]


func _pack_size(piece: String, s: float) -> Vector3:
	# width (along its front), height, depth once placed
	var size: Vector3 = _pack_piece(piece)[2].size * s
	return Vector3(size.z, size.y, size.x) if PACK_FRONT.has(piece) else size


func _pack_place(placed: Dictionary, piece: String, pos: Vector3, yaw: float, s: float, shadows: bool, collide: bool) -> void:
	# stands a piece with the middle of its footprint at pos, on the ground, its front turned toward yaw
	var data := _pack_piece(piece)
	var box: AABB = data[2]
	var bottom := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var basis := Basis(Vector3.UP, yaw + PACK_FRONT.get(piece, 0.0)) * Basis.from_scale(Vector3.ONE * s)
	var key := piece + ("|shadow" if shadows else "|flat")
	if not placed.has(key):
		placed[key] = []
	placed[key].append(Transform3D(basis, pos) * Transform3D(Basis(), -bottom) * data[1])
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = box.size * s
		cs.shape = bs
		cs.position.y = bs.size.y / 2.0
		body.add_child(cs)
		body.position = pos
		body.rotation.y = yaw + PACK_FRONT.get(piece, 0.0)
		add_child(body)


func _shop_row(r: RandomNumberGenerator, placed: Dictionary, front_mid: Vector3, along: Vector3, half_len: float, street: bool) -> void:
	# storefronts shoulder to shoulder, fronts on a line through front_mid running along `along` and facing
	# the map, built outward from the middle both ways. A row off to the west is copied to the east.
	var n := Vector3(-along.z, 0, along.x)
	if n.dot(-front_mid) < 0.0:
		n = -n
	var yaw := atan2(n.x, n.z)
	var spots: Array = [] # [piece, offset along the row]
	var last := ""
	var cursor := 0.0
	while true:
		var pool := SHOPS.filter(func(k): return k != last)
		var piece: String = pool[r.randi() % pool.size()]
		var w := _pack_size(piece, PACK_SCALE).x
		if spots.is_empty():
			spots.append([piece, 0.0])
			cursor = w / 2.0
		else:
			if cursor + w > half_len:
				break
			spots.append([piece, cursor + w / 2.0])
			spots.append([piece, -(cursor + w / 2.0)])
			cursor += w
		last = piece
	for spot: Array in spots:
		var size := _pack_size(spot[0], PACK_SCALE)
		var p: Vector3 = front_mid + along * float(spot[1]) - n * (size.z / 2.0)
		_pack_place(placed, spot[0], p, yaw, PACK_SCALE, street, true)
		if absf(front_mid.x) > 0.01:
			_pack_place(placed, spot[0], Vector3(-p.x, 0, p.z), -yaw, PACK_SCALE, street, true)


func _bounds() -> void:
	_invisible_wall(Vector3(-93, 20, 3), Vector3(1, 40, 190))
	_invisible_wall(Vector3(93, 20, 3), Vector3(1, 40, 190))
	_invisible_wall(Vector3(0, 20, -85), Vector3(190, 40, 1))
	_invisible_wall(Vector3(0, 20, 91), Vector3(190, 40, 1))


func _flush_multimeshes() -> void:
	_multimesh(Vector3(1.35, 1.55, 0.06), m_board, _boards)
	_multimesh(Vector3(0.035, 1.0, 0.035), m_iron, _pickets)
	_multimesh(Vector3(0.1, 1.0, 0.1), m_iron, _posts)


func _multimesh(size: Vector3, mat: Material, xforms: Array[Transform3D]) -> void:
	if xforms.is_empty():
		return
	var bm := BoxMesh.new()
	bm.size = size
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bm
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


var _clear: Array = [] # walkways and grass strips: props stay off them, but bots can walk them


func _block(center: Vector2, size: Vector2, yaw: float) -> void:
	_blocked.append([center, size / 2.0, yaw])


func _keep_clear(center: Vector2, size: Vector2, yaw: float) -> void:
	_clear.append([center, size / 2.0, yaw])


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


func _spawns_and_waypoints() -> void:
	player_spawns = [
		Vector3(0, 0.2, 80), Vector3(-35, 0.2, 80), Vector3(35, 0.2, 80),
		Vector3(-60, 0.2, 58), Vector3(60, 0.2, 58), Vector3(0, 0.2, 45),
	]
	bot_spawns = [
		Vector3(0, 0.2, -62), Vector3(0, 0.2, -45), Vector3(-80, 0.2, -40), Vector3(80, 0.2, -40),
		Vector3(-78, 0.2, 25), Vector3(78, 0.2, 25), Vector3(-50, 0.2, -75), Vector3(50, 0.2, -75),
	]
	for x in range(-86, 87, 6):
		for z in range(-80, 89, 6):
			if not _is_blocked(Vector2(x, z), 1.2):
				waypoints.append(Vector3(x, 0.2, z))


# ---------------------------------------------------------------- dev check

var _bldg: Array = []
var _cars: Array = []


func _rect_poly(b: Array) -> PackedVector2Array:
	var c: Vector2 = b[0]
	var h: Vector2 = b[1]
	var y: float = b[2]
	var u := Vector2(cos(y), -sin(y))
	var n := Vector2(sin(y), cos(y))
	return PackedVector2Array([c + u * h.x + n * h.y, c - u * h.x + n * h.y, c - u * h.x - n * h.y, c + u * h.x - n * h.y])


func check_overlaps() -> int:
	# reports buildings (with their aprons) that overlap each other, a walkway/grass strip, or the lot
	var count := 0
	var lot := PackedVector2Array(LOT)
	for i in _bldg.size():
		var a := _rect_poly(_bldg[i])
		for j in range(i + 1, _bldg.size()):
			if not Geometry2D.intersect_polygons(a, _rect_poly(_bldg[j])).is_empty():
				print("[overlap] building %d <-> building %d" % [i, j])
				count += 1
		for k in _clear.size():
			if not Geometry2D.intersect_polygons(a, _rect_poly(_clear[k])).is_empty():
				print("[overlap] building %d <-> walkway/grass %d" % [i, k])
				count += 1
		if not Geometry2D.intersect_polygons(a, lot).is_empty():
			print("[overlap] building %d <-> parking lot" % i)
			count += 1
	for c in _cars:
		var cp: Vector2 = c[0]
		if cp.y > 60.0:
			continue # street parking
		for p in _rect_poly(c):
			if not Geometry2D.is_point_in_polygon(p, lot):
				print("[overlap] car at %s sticks out of the lot" % cp)
				count += 1
				break
	print("[overlap] total: %d" % count)
	for i in _cars.size():
		for j in range(i + 1, _cars.size()):
			if not Geometry2D.intersect_polygons(_rect_poly(_cars[i]), _rect_poly(_cars[j])).is_empty():
				print("[overlap] car %s <-> car %s" % [_cars[i][0], _cars[j][0]])
				count += 1
	print("[overlap] parked cars in lot: %d" % (_cars.size() - 8))
	return count


var _grimy_cache := {}


func _grimy(src: Material) -> Material:
	# darker, duller copy of a model material (keeps its texture)
	if src == null:
		return null
	if _grimy_cache.has(src):
		return _grimy_cache[src]
	var m: Material = src.duplicate()
	if m is BaseMaterial3D:
		m.albedo_color = m.albedo_color * Color(0.62, 0.6, 0.58)
		m.roughness = 0.75
		m.metallic = 0.0
	_grimy_cache[src] = m
	return m


var _paint_cache := {}
var _grime_noise: NoiseTexture2D


func _car_paint(color: Color, dirt: float) -> ShaderMaterial:
	var key := "%s_%d" % [color.to_html(), int(dirt * 4.0)]
	if _paint_cache.has(key):
		return _paint_cache[key]
	if _grime_noise == null:
		_grime_noise = NoiseTexture2D.new()
		_grime_noise.seamless = true
		var fn := FastNoiseLite.new()
		fn.frequency = 0.02
		_grime_noise.noise = fn
	var m := ShaderMaterial.new()
	m.shader = CAR_PAINT
	m.set_shader_parameter("colormap", load("res://assets/cars/Textures/colormap.png"))
	m.set_shader_parameter("paint", color)
	m.set_shader_parameter("dirt", int(dirt * 4.0) / 4.0)
	m.set_shader_parameter("grime_tex", _grime_noise)
	_paint_cache[key] = m
	return m


# ---------------------------------------------------------------- dead trees

static var _tree_meshes := {}
const TREE_VARIANTS := 6
const TREE_BASE_HEIGHT := 6.5 # rough height of a generated tree before scaling


func _dead_tree_mesh(variant: int) -> ArrayMesh:
	# a bare, leafless winter tree grown from tapered branches; a few variants are built once and shared
	if _tree_meshes.has(variant):
		return _tree_meshes[variant]
	var r := RandomNumberGenerator.new()
	r.seed = 9100 + variant * 31
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_grow_branch(st, r, Vector3.ZERO, Vector3(r.randf_range(-0.08, 0.08), 1, r.randf_range(-0.08, 0.08)).normalized(), 2.6, 0.2, 0)
	var mesh := st.commit()
	_tree_meshes[variant] = mesh
	return mesh


func _grow_branch(st: SurfaceTool, r: RandomNumberGenerator, start: Vector3, dir: Vector3, length: float, radius: float, depth: int) -> void:
	var segments := 3
	var pos := start
	var d := dir
	for i in segments:
		var nd := (d + Vector3(r.randf_range(-1, 1), r.randf_range(-0.3, 0.5), r.randf_range(-1, 1)) * 0.22).normalized()
		var end := pos + nd * (length / segments)
		var r0 := radius * (1.0 - 0.35 * float(i) / segments)
		var r1 := radius * (1.0 - 0.35 * float(i + 1) / segments)
		_tube(st, pos, end, r0, r1 if depth < 4 or i < segments - 1 else r1 * 0.3)
		if depth < 4 and (depth > 0 or i > 0):
			for k in (2 if depth < 2 else r.randi_range(1, 2)):
				var side := nd.cross(Vector3(r.randf_range(-1, 1), r.randf_range(-0.2, 0.2), r.randf_range(-1, 1))).normalized()
				var bd := (nd * 0.6 + side * r.randf_range(0.6, 1.1)).normalized()
				bd.y = absf(bd.y) * 0.7 + 0.25 # branches reach up and out
				_grow_branch(st, r, end, bd.normalized(), length * r.randf_range(0.5, 0.72), r1 * r.randf_range(0.5, 0.7), depth + 1)
		pos = end
		d = nd


func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float) -> void:
	var sides := 7 if ra > 0.05 else 4
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u)
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		var n0 := u * cos(a0) + v * sin(a0)
		var n1 := u * cos(a1) + v * sin(a1)
		var quad := [[a + n0 * ra, n0], [b + n0 * rb, n0], [b + n1 * rb, n1], [a + n0 * ra, n0], [b + n1 * rb, n1], [a + n1 * ra, n1]]
		for q in quad:
			st.set_normal(q[1])
			st.add_vertex(q[0])


func _prop(scene: PackedScene, pos: Vector3, yaw: float, scale := 1.0, keep := "", offset := Vector3.ZERO, tilt := Vector3.ZERO) -> Node3D:
	# places a model; keep = only meshes whose name contains this (packs that ship several variants side by side),
	# offset recenters that variant, tilt lays it over (e.g. a tire on its side)
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	root.scale = Vector3.ONE * scale
	add_child(root)
	var model: Node3D = scene.instantiate()
	model.position = offset
	var holder := Node3D.new()
	holder.rotation = tilt
	holder.add_child(model)
	root.add_child(holder)
	if keep != "":
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			if not mi.name.contains(keep):
				mi.visible = false
	return root


func _rect_pts(x0: float, x1: float, z0: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


func _ground_slab(poly: PackedVector2Array) -> void:
	# lawn-level ground (top at y = 0) over any outline, with curb faces down to the road on every edge
	var tris := Geometry2D.triangulate_polygon(poly)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, tris.size(), 3):
		for k in [0, 1, 2]:
			var p: Vector2 = poly[tris[i + k]]
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, 0.0, p.y))
	var top := st.commit()
	var cw := Geometry2D.is_polygon_clockwise(poly)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var n2 := (b - a).orthogonal().normalized() * (-1.0 if cw else 1.0)
		var n := Vector3(n2.x, 0, n2.y)
		var quad := [Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(b.x, ROAD_Y - 0.02, b.y), Vector3(a.x, ROAD_Y - 0.02, a.y)]
		for idx in [0, 1, 2, 0, 2, 3]:
			walls.set_normal(n)
			walls.add_vertex(quad[idx])
	var top_mi := MeshInstance3D.new()
	top_mi.mesh = top
	top_mi.material_override = m_ground
	add_child(top_mi)
	var wall_mi := MeshInstance3D.new()
	wall_mi.mesh = walls.commit()
	var curb := m_curb.duplicate()
	curb.cull_mode = BaseMaterial3D.CULL_DISABLED # outline winding can go either way
	wall_mi.material_override = curb
	add_child(wall_mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	var faces := top.get_faces()
	faces.append_array(wall_mi.mesh.get_faces())
	shape.set_faces(faces)
	shape.backface_collision = true
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


func _grass() -> void:
	# grass clumps (the user's grass.png on crossed cards) scattered over the lawns, one MultiMesh
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	var card := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2: # two cards crossed at right angles so the clump reads from every side
		var a := Vector3(0.5, 0, 0) if k == 0 else Vector3(0, 0, 0.5)
		var quad := [[-a, Vector2(0, 1)], [a, Vector2(1, 1)], [a + Vector3.UP, Vector2(1, 0)], [-a + Vector3.UP, Vector2(0, 0)]]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_uv(quad[idx][1])
			st.set_normal(Vector3.UP)
			st.add_vertex(quad[idx][0])
	card = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/grass.gdshader")
	mat.set_shader_parameter("clump", preload("res://assets/nature/grass_clump.png"))
	card.surface_set_material(0, mat)
	# the base layer reaches the horizon; a denser layer with long clumps mixed in only draws near the
	# camera, where it shows (cut-out cards are what cost the most on a laptop GPU)
	var total := _grass_layer(r, card, 26000, 0.0, 140.0)
	total += _grass_layer(r, card, 16000, 0.35, 70.0)
	# low turf (tools/make_short_grass.py) carpeting the lawns between the clumps: ankle high at most,
	# so it fills the ground without hiding anyone. Too small to see far off, so it only draws close by.
	# One card each, turned to face the camera in the shader, so the short cards never read as X shapes.
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := [[Vector3(-0.5, 0, 0), Vector2(0, 1)], [Vector3(0.5, 0, 0), Vector2(1, 1)], [Vector3(0.5, 1, 0), Vector2(1, 0)], [Vector3(-0.5, 1, 0), Vector2(0, 0)]]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_uv(quad[idx][1])
		st.set_normal(Vector3.UP)
		st.add_vertex(quad[idx][0])
	var turf := st.commit()
	var turf_mat := ShaderMaterial.new()
	turf_mat.shader = preload("res://scripts/grass_turf.gdshader")
	turf_mat.set_shader_parameter("clump", preload("res://assets/nature/grass_short.png"))
	turf.surface_set_material(0, turf_mat)
	total += _grass_layer(r, turf, 45000, 0.0, 50.0, true)
	print("[map] grass clumps: ", total)


const GRASS_TILE := 24.0


func _grass_layer(r: RandomNumberGenerator, card: Mesh, tries: int, long_share: float, draw_range: float, low := false) -> int:
	var xforms: Array[Transform3D] = []
	var shades: Array[Color] = []
	# grass grows in patches with bare snow between them (same patches for every layer)
	var patches := FastNoiseLite.new()
	patches.seed = 911
	patches.frequency = 0.09
	for i in tries:
		var p := Vector2(r.randf_range(-88, 88), r.randf_range(-80, 65))
		if patches.get_noise_2d(p.x, p.y) < -0.05 and r.randf() < 0.85:
			continue
		if _in_lot(p) or _is_blocked(p, 0.5) or _is_blocked(p, 0.4, _clear) or _is_blocked(p, 0.4, _bldg) or p.y > 64.5: # never on concrete (walkways, building aprons, street sidewalks)
			continue
		var basis: Basis
		if low:
			var h := r.randf_range(0.14, 0.3) # 14-30 cm, about 10-25 cm showing above the snow
			var w := h * r.randf_range(1.7, 2.3) # close to the texture's 2:1 so blades aren't squashed
			basis = Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(w, h, w))
		else:
			var size := r.randf_range(0.9, 1.4) if r.randf() < long_share else r.randf_range(0.45, 0.85)
			basis = Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(size * r.randf_range(0.9, 1.4), size, size * r.randf_range(0.9, 1.4)))
		# turf is sunk a little so the dense band at the roots stays under the snow
		xforms.append(Transform3D(basis, Vector3(p.x, -basis.y.length() * 0.15 if low else -0.02, p.y)))
		var s := r.randf_range(0.75, 1.1) # some clumps greener, some dried out
		shades.append(Color(s, s * r.randf_range(0.92, 1.05), s * 0.9))
	# split into tiles so each one is culled and range-checked on its own (a single map-wide MultiMesh is
	# measured from the map's center, so a short draw range would hide it everywhere else)
	var tiles := {}
	for i in xforms.size():
		var key := Vector2i(floori(xforms[i].origin.x / GRASS_TILE), floori(xforms[i].origin.z / GRASS_TILE))
		if not tiles.has(key):
			tiles[key] = []
		tiles[key].append(i)
	for key: Vector2i in tiles:
		var center := Vector3((key.x + 0.5) * GRASS_TILE, 0, (key.y + 0.5) * GRASS_TILE)
		var list: Array = tiles[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = card
		mm.instance_count = list.size()
		for k in list.size():
			var xf: Transform3D = xforms[list[k]]
			mm.set_instance_transform(k, Transform3D(xf.basis, xf.origin - center))
			mm.set_instance_custom_data(k, shades[list[k]])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = center
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = draw_range
		add_child(mmi)
	return xforms.size()


const SNOW_PILE := preload("res://assets/props/snowpile/snowpile.fbx")


func _snow_pile(p: Vector2, size: float, yaw: float) -> void:
	# the user's snow mound model (about 1 m across, 0.4 m tall as shipped) with the snow texture
	var pile: Node3D = SNOW_PILE.instantiate()
	pile.position = Vector3(p.x, 0.2 * size * 0.6, p.y)
	pile.rotation.y = yaw
	pile.scale = Vector3(size, size * 0.6, size * rng.randf_range(0.8, 1.2))
	for mi in pile.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = m_snow
	add_child(pile)


func _snow_piles() -> void:
	# snow shoveled into corners: the outside corners of every building's concrete apron,
	# the far corners of the fenced yard, and the dead ends of the walkways
	var spots: Array = []
	for b in _bldg:
		var c: Vector2 = b[0]
		var h: Vector2 = b[1]
		if c.x > 0.0:
			continue # left side only; mirrored below
		var basis := Transform2D(-b[2], Vector2.ZERO)
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			if rng.randf() < 0.7:
				spots.append(c + basis * (corner * (h + Vector2(0.6, 0.6))))
	spots.append_array([Vector2(-88, -80), Vector2(-88, 65)]) # yard corners by the fence
	# walkway dead ends: far end of each wing walkway, outer end of the bottom-building walkway
	var w: Array = LEFT_WING
	var unit := Vector2(cos(deg_to_rad(w[3])), -sin(deg_to_rad(w[3])))
	var lot_side := -Vector2(sin(deg_to_rad(w[3])), cos(deg_to_rad(w[3])))
	var ends := [w[0] + unit * (w[1] / 2.0 + 1.2) + lot_side * 11.25, w[0] - unit * (w[1] / 2.0 + 1.2) + lot_side * 11.25]
	spots.append(ends[0] if ends[0].y < ends[1].y else ends[1])
	spots.append(Vector2(-69.5, 31.5))
	for p: Vector2 in spots:
		if _in_lot(p):
			continue
		var size := rng.randf_range(1.4, 2.6)
		var yaw := rng.randf() * TAU
		_snow_pile(p, size, yaw)
		_snow_pile(_mirror(p), size, -yaw)
