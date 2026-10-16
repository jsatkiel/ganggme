extends CanvasLayer
## HUD: crosshair, hitmarkers, ammo, health, damage direction, score, killfeed, messages.


class Crosshair extends Control:
	var gap := 8.0
	var alpha := 1.0

	func _draw() -> void:
		if alpha <= 0.01:
			return
		var c := Color(1, 1, 1, alpha)
		var shadow := Color(0, 0, 0, alpha * 0.6)
		var ctr := size / 2.0
		var length := 9.0
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			draw_line(ctr + d * gap + Vector2(1, 1), ctr + d * (gap + length) + Vector2(1, 1), shadow, 2.0)
			draw_line(ctr + d * gap, ctr + d * (gap + length), c, 2.0)
		draw_rect(Rect2(ctr - Vector2(1, 1), Vector2(2, 2)), c)


class Hitmarker extends Control:
	var t := 0.0
	var col := Color.WHITE

	func _process(delta: float) -> void:
		if t > 0.0:
			t -= delta
			queue_redraw()

	func _draw() -> void:
		if t <= 0.0:
			return
		var c := Color(col, clampf(t / 0.2, 0.0, 1.0))
		var ctr := size / 2.0
		for s in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(ctr + s * 7.0, ctr + s * 16.0, c, 3.0)


class DamageDir extends Control:
	var hits: Array = [] # [{pos, t}]
	var player: Node3D

	func _process(delta: float) -> void:
		for h in hits:
			h.t -= delta
		hits = hits.filter(func(h): return h.t > 0.0)
		queue_redraw()

	func _draw() -> void:
		if player == null:
			return
		var ctr := size / 2.0
		for h in hits:
			var local: Vector3 = player.global_transform.basis.inverse() * (h.pos - player.global_position)
			var ang := atan2(local.x, -local.z)
			var dir := Vector2(sin(ang), -cos(ang))
			var perp := Vector2(-dir.y, dir.x)
			var tip := ctr + dir * 150.0
			var c := Color(0.9, 0.05, 0.05, clampf(h.t, 0.0, 1.0) * 0.85)
			draw_colored_polygon(PackedVector2Array([tip + dir * 26.0, tip + perp * 22.0, tip - perp * 22.0]), c)


var player: Node3D:
	set(v):
		player = v
		if damage_dir:
			damage_dir.player = v

var crosshair: Crosshair
var hitmarker: Hitmarker
var damage_dir: DamageDir
var vignette: ColorRect
var health_bg: ColorRect
var health_fill: ColorRect
var ammo_label: Label
var reload_label: Label
var score_label: Label
var center_label: Label
var hint_label: Label
var killfeed_box: VBoxContainer
var _vignette_flash := 0.0
var _health := 100.0
var _center_t := 0.0


func _ready() -> void:
	vignette = ColorRect.new()
	vignette.color = Color(0.6, 0.0, 0.0, 0.0)
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	crosshair = Crosshair.new()
	_full(crosshair)
	hitmarker = Hitmarker.new()
	_full(hitmarker)
	damage_dir = DamageDir.new()
	damage_dir.player = player
	_full(damage_dir)

	health_bg = ColorRect.new()
	health_bg.color = Color(0, 0, 0, 0.55)
	health_bg.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health_bg.position = Vector2(40, -64)
	health_bg.size = Vector2(304, 24)
	health_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(health_bg)
	health_fill = ColorRect.new()
	health_fill.color = Color(0.92, 0.92, 0.9)
	health_fill.position = Vector2(2, 2)
	health_fill.size = Vector2(300, 20)
	health_bg.add_child(health_fill)

	ammo_label = _label(54, HORIZONTAL_ALIGNMENT_RIGHT)
	ammo_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_label.offset_left = -420
	ammo_label.offset_right = -40
	ammo_label.offset_top = -100
	ammo_label.offset_bottom = -30
	reload_label = _label(26, HORIZONTAL_ALIGNMENT_CENTER)
	reload_label.set_anchors_preset(Control.PRESET_CENTER)
	reload_label.offset_left = -200
	reload_label.offset_right = 200
	reload_label.offset_top = 60
	reload_label.offset_bottom = 100
	reload_label.modulate = Color(1, 0.85, 0.3)

	score_label = _label(28, HORIZONTAL_ALIGNMENT_CENTER)
	score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	score_label.offset_left = -400
	score_label.offset_right = 400
	score_label.offset_top = 16
	score_label.offset_bottom = 60

	center_label = _label(56, HORIZONTAL_ALIGNMENT_CENTER)
	center_label.set_anchors_preset(Control.PRESET_CENTER)
	center_label.offset_left = -700
	center_label.offset_right = 700
	center_label.offset_top = -200
	center_label.offset_bottom = -40

	hint_label = _label(18, HORIZONTAL_ALIGNMENT_LEFT)
	hint_label.position = Vector2(24, 70)
	hint_label.text = "WASD move  |  Mouse or ARROW KEYS look  |  LMB or E shoot  |  RMB or Q aim down sights\nShift sprint  |  C / Ctrl crouch (while sprinting = slide)  |  Space jump  |  R reload\nController: LT aim, RT shoot, A jump, B crouch/slide, X reload, L3 sprint\nEsc frees the mouse, click to grab it again"
	var tw := create_tween()
	tw.tween_interval(12.0)
	tw.tween_property(hint_label, "modulate:a", 0.0, 1.5)

	killfeed_box = VBoxContainer.new()
	killfeed_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	killfeed_box.offset_left = -520
	killfeed_box.offset_right = -24
	killfeed_box.offset_top = 20
	killfeed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	killfeed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(killfeed_box)


func _full(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)


func _label(font_size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 10)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _process(delta: float) -> void:
	_vignette_flash = move_toward(_vignette_flash, 0.0, delta * 1.5)
	var low := clampf(1.0 - _health / 100.0, 0.0, 1.0)
	vignette.color.a = clampf(low * 0.45 + _vignette_flash, 0.0, 0.7)
	if _center_t > 0.0:
		_center_t -= delta
		if _center_t <= 0.0:
			center_label.text = ""


func set_spread(spread: float, ads: float) -> void:
	crosshair.gap = 5.0 + spread * 520.0
	crosshair.alpha = clampf(1.0 - ads * 1.6, 0.0, 1.0)
	crosshair.queue_redraw()


func show_hitmarker(headshot: bool, killed: bool) -> void:
	hitmarker.t = 0.25
	hitmarker.col = Color(1, 0.15, 0.15) if killed else (Color(1, 0.85, 0.2) if headshot else Color.WHITE)


func show_damage(from_pos: Vector3) -> void:
	damage_dir.hits.append({"pos": from_pos, "t": 1.0})
	_vignette_flash = minf(_vignette_flash + 0.18, 0.4)


func update_health(hp: float) -> void:
	_health = hp
	health_fill.size.x = 300.0 * clampf(hp / 100.0, 0.0, 1.0)
	health_fill.color = Color(0.92, 0.92, 0.9) if hp > 40 else Color(0.9, 0.2, 0.15)


func update_ammo(ammo: int, reserve: int, reloading: bool) -> void:
	ammo_label.text = "%d  /  %d" % [ammo, reserve]
	ammo_label.modulate = Color(1, 0.3, 0.25) if ammo <= 5 else Color.WHITE
	reload_label.text = "RELOADING..." if reloading else ("RELOAD [R / X]" if ammo <= 5 and reserve > 0 else "")


func update_score(kills: int, deaths: int, target: int) -> void:
	score_label.text = "YOUR CREW  %d     —     %d  OPPS        (first to %d)" % [kills, deaths, target]


func killfeed(text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.modulate = col
	killfeed_box.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func center_message(text: String, duration := 0.0) -> void:
	center_label.text = text
	_center_t = duration
