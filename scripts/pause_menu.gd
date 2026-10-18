extends CanvasLayer
## COD-style pause menu (Esc / Start): Resume, Loadout, Settings, Restart, Quit.
## Loadout: three custom classes, each a pistol with four attachments, a camo and three perks
## (all in loadout.gd). Pages: main, loadout, class, weapons, gunsmith, camo, perks, settings.
## Esc / B goes back a page; edits are saved and go on the player when the game resumes.
## Everything is built in code; art dropped into assets/ui shows up in place of the placeholders.

const Loadout = preload("res://scripts/loadout.gd")
const Pistol = preload("res://scripts/pistol.gd")

const ACCENT := Color(0.96, 0.76, 0.18)
const PANEL := Color(0.04, 0.05, 0.06, 0.9)
const DIM := Color(0.66, 0.68, 0.72)
const GOOD := Color(0.35, 0.9, 0.4)
const BAD := Color(0.95, 0.32, 0.25)
const SLOT_NAMES := {"muzzle": "MUZZLE", "magazine": "MAGAZINE", "laser": "UNDERBARREL", "trigger": "TRIGGER"}


class StatBars extends Control:
	## the stat bars, with the change from `before` shown in green (better) or red (worse)
	var rows: Array = []
	var before: Array = []

	func show_stats(now: Array, base: Array = []) -> void:
		rows = now
		before = base
		custom_minimum_size.y = rows.size() * 34
		queue_redraw()

	func _draw() -> void:
		var font := get_theme_font("font", "Label")
		var y := 0.0
		for i in rows.size():
			var v: float = rows[i][1]
			var b: float = v if before.is_empty() else float(before[i][1])
			draw_string(font, Vector2(0, y + 19), rows[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.85, 0.86, 0.88))
			var bar := Rect2(140, y + 8, size.x - 140, 10)
			draw_rect(bar, Color(1, 1, 1, 0.12))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * minf(v, b), bar.size.y)), Color(0.93, 0.93, 0.93))
			if absf(v - b) > 0.003:
				draw_rect(Rect2(bar.position + Vector2(bar.size.x * minf(v, b), 0), Vector2(bar.size.x * absf(v - b), bar.size.y)),
					Color(0.35, 0.9, 0.4) if v > b else Color(0.95, 0.32, 0.25))
			y += 34


var game: Node
var player: Node
var is_open := false

var _root: Control
var _page: Control
var _stack: Array = [] # pages, [name, arg]
var _edit := 0 # the class being edited
var _dirty := false # the equipped class changed: re-equip on resume
var _focusables: Array = []
var _focus_index := 0 # which button to focus when the page is rebuilt
var _preview_pivot: Node3D
var _preview_gun: Node3D
var _spin_t := 0.0
var _bars: StatBars
var _info: Label
var _confirm := ""


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	Loadout.load_all()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = _make_theme()
	add_child(_root)
	# the frozen game behind the menu, blurred and darkened
	var blur := ColorRect.new()
	blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;\nvoid fragment() {\n\tvec3 c = textureLod(screen_tex, SCREEN_UV, 3.5).rgb;\n\tCOLOR = vec4(c * 0.4, 1.0);\n}\n"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	blur.material = sm
	_root.add_child(blur)
	var bg := Loadout.art("menu", "background") # optional menu art over the blur
	if bg:
		var tr := TextureRect.new()
		tr.texture = bg
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.modulate.a = 0.55
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(tr)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or (is_open and event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		if is_open:
			_back()
		else:
			open()
	elif is_open and event is InputEventJoypadButton and event.pressed and _stack[-1][0] == "gunsmith" \
			and event.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		# LB / RB flip through the gunsmith slots
		get_viewport().set_input_as_handled()
		var i: int = Loadout.SLOTS.find(_stack[-1][1]) + (1 if event.button_index == JOY_BUTTON_RIGHT_SHOULDER else -1)
		_stack[-1][1] = Loadout.SLOTS[wrapi(i, 0, Loadout.SLOTS.size())]
		_focus_index = 0
		_build()


func _process(delta: float) -> void:
	if is_open and is_instance_valid(_preview_pivot):
		_spin_t += delta
		_preview_pivot.rotation.y = sin(_spin_t * 0.6) * 0.55


func open() -> void:
	is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_stack = [["main", null]]
	_focus_index = 0
	_build()


func close() -> void:
	is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Loadout.save_all()
	if _dirty and player and player.alive:
		# the new class goes on right away, with a fresh mag
		player.apply_loadout()
		player.ammo = player.mag_size
		player.reserve = player.reserve_max
		player.reloading = false
		player._update_ammo_hud()
	_dirty = false


func _go(page: String, arg = null) -> void:
	_stack[-1].append(_focused_index()) # come back to the same button
	_stack.append([page, arg])
	_focus_index = 0
	_build()


func _back() -> void:
	Loadout.save_all()
	if _stack.size() <= 1:
		close()
		return
	_stack.pop_back()
	_focus_index = _stack[-1][2] if _stack[-1].size() > 2 else 0
	_stack[-1] = _stack[-1].slice(0, 2)
	_build()


func _rebuild_here() -> void:
	_focus_index = _focused_index()
	_build()


func _focused_index() -> int:
	var f := _root.get_viewport().gui_get_focus_owner()
	return maxi(_focusables.find(f), 0)


func _build() -> void:
	if _page:
		_root.remove_child(_page)
		_page.queue_free()
	_focusables.clear()
	_preview_pivot = null
	_preview_gun = null
	_bars = null
	_info = null
	_confirm = ""
	_page = Control.new()
	_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_page)
	var top: Array = _stack[-1]
	match top[0]:
		"main": _page_main()
		"loadout": _page_loadout()
		"class": _page_class()
		"weapons": _page_weapons()
		"gunsmith": _page_gunsmith(top[1])
		"camo": _page_camo()
		"perks": _page_perks(top[1])
		"settings": _page_settings()
	if not _focusables.is_empty():
		var f: Control = _focusables[clampi(_focus_index, 0, _focusables.size() - 1)]
		f.grab_focus.call_deferred()


# ---------------------------------------------------------------- pages

func _page_main() -> void:
	var side := ColorRect.new()
	side.color = PANEL
	side.anchor_bottom = 1.0
	side.offset_right = 520
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(side)
	var stripe := ColorRect.new()
	stripe.color = ACCENT
	stripe.anchor_bottom = 1.0
	stripe.offset_left = 520
	stripe.offset_right = 524
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(stripe)
	var col := VBoxContainer.new()
	col.position = Vector2(64, 120)
	col.custom_minimum_size.x = 400
	col.add_theme_constant_override("separation", 6)
	_page.add_child(col)
	var koth: bool = game != null and game.mode == "koth"
	_add_label(col, "KING OF THE HOOD" if koth else "TEAM DEATHMATCH", 18, ACCENT)
	_add_label(col, "PAUSED", 72, Color.WHITE)
	if game and koth:
		_add_label(col, "ROUND %d      YOUR CREW  %d   —   %d  OPPS      BEST OF %d" % [game.round_num, game.round_wins[0], game.round_wins[1], game.ROUNDS_TO_WIN * 2 - 1], 18, DIM)
	elif game:
		_add_label(col, "YOUR CREW  %d   —   %d  OPPS      FIRST TO %d" % [game.kills, game.deaths, game.get_script().KILLS_TO_WIN], 18, DIM)
	_spacer(col, 40)
	_btn(col, "RESUME", close, 30)
	_btn(col, "LOADOUT", func(): _go("loadout"), 30)
	_btn(col, "SETTINGS", func(): _go("settings"), 30)
	_spacer(col, 24)
	var other := "tdm" if koth else "koth"
	var switch := _btn(col, "PLAY " + ("TEAM DEATHMATCH" if koth else "KING OF THE HOOD"), Callable(), 22)
	switch.pressed.connect(func(): _confirm_then(switch, "switch", func():
		Loadout.settings.mode = other
		Loadout.save_all()
		get_tree().paused = false
		get_tree().reload_current_scene()))
	var restart := _btn(col, "RESTART MATCH", Callable(), 22)
	restart.pressed.connect(func(): _confirm_then(restart, "restart", func():
		get_tree().paused = false
		get_tree().reload_current_scene()))
	var quit := _btn(col, "QUIT GAME", Callable(), 22)
	quit.pressed.connect(func(): _confirm_then(quit, "quit", func(): get_tree().quit()))
	# what you're carrying, bottom right
	var c := Loadout.current()
	var eq := _label("EQUIPPED   %s  ·  %s  ·  %s" % [c.name, Loadout.WEAPONS[c.weapon].name, Loadout.camo(c.camo).name], 18, DIM)
	eq.anchor_left = 1.0
	eq.anchor_right = 1.0
	eq.anchor_top = 1.0
	eq.anchor_bottom = 1.0
	eq.offset_left = -700
	eq.offset_right = -48
	eq.offset_top = -64
	eq.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_page.add_child(eq)


func _page_loadout() -> void:
	_header("LOADOUT", "PAUSED")
	var body := _body()
	var left := _col(body, 340)
	_section(left, "CUSTOM CLASSES")
	var right := _col(body, 640)
	for i in Loadout.CLASS_COUNT:
		var c: Dictionary = Loadout.classes[i]
		var b := _btn(left, c.name + ("      EQUIPPED" if i == Loadout.active else ""), func():
			_edit = i
			_go("class"), 26)
		b.focus_entered.connect(func(): _class_summary(right, i))
	_spacer(left, 20)
	_add_label(left, "Pick a class to edit it.\nEQUIP a class to carry it\n(goes on when you resume).", 17, DIM)


func _class_summary(panel: VBoxContainer, i: int) -> void:
	for n in panel.get_children():
		n.queue_free()
	var c: Dictionary = Loadout.classes[i]
	var w: Dictionary = Loadout.WEAPONS[c.weapon]
	_section(panel, "SIDEARM")
	panel.add_child(_art_box("weapons", c.weapon, w.name, Vector2(640, 220)))
	_add_label(panel, "%s   ·   %s" % [w.name, w.caliber], 26, Color.WHITE)
	var parts := []
	for slot in Loadout.SLOTS:
		var a: Dictionary = Loadout.attachment(slot, c[slot])
		if a.id != "none":
			parts.append(a.name)
	_add_label(panel, "ATTACHMENTS:  " + (", ".join(parts) if not parts.is_empty() else "none"), 18, DIM)
	_add_label(panel, "CAMO:  " + Loadout.camo(c.camo).name, 18, DIM)
	var perks := []
	for p in Loadout.PERKS.size():
		perks.append(Loadout.perk(p, c.perks[p]).name)
	_add_label(panel, "PERKS:  " + "  ·  ".join(perks), 18, DIM)
	_spacer(panel, 10)
	var bars := StatBars.new()
	bars.custom_minimum_size.x = 520
	panel.add_child(bars)
	bars.show_stats(Loadout.bars(Loadout.stats(c)))


func _page_class() -> void:
	var c: Dictionary = Loadout.classes[_edit]
	_header(c.name, "PAUSED  /  LOADOUT")
	var body := _body()
	var left := _col(body, 480)
	_section(left, "SIDEARM")
	_btn(left, "%s\n%s  ·  %s" % [Loadout.WEAPONS[c.weapon].name, Loadout.WEAPONS[c.weapon].caliber, Loadout.WEAPONS[c.weapon].kind], func(): _go("weapons"), 26)
	_section(left, "GUNSMITH")
	for slot in Loadout.SLOTS:
		_btn(left, "%s:   %s" % [SLOT_NAMES[slot], Loadout.attachment(slot, c[slot]).name], func(): _go("gunsmith", slot), 19)
	_section(left, "CAMO")
	_btn(left, Loadout.camo(c.camo).name, func(): _go("camo"), 19)
	_section(left, "PERKS")
	for p in Loadout.PERKS.size():
		_btn(left, "PERK %d:   %s" % [p + 1, Loadout.perk(p, c.perks[p]).name], func(): _go("perks", p), 19)
	_spacer(left, 12)
	var equipped := _edit == Loadout.active
	var eq := _btn(left, "EQUIPPED" if equipped else "EQUIP CLASS", func():
		if Loadout.active != _edit:
			Loadout.active = _edit
			_dirty = true
			Loadout.save_all()
			_rebuild_here(), 24)
	if equipped:
		eq.add_theme_color_override("font_color", ACCENT)
	var right := _col(body, 620)
	_preview(right, Vector2(620, 330), c)
	_stats_panel(right, c)


func _page_weapons() -> void:
	var c: Dictionary = Loadout.classes[_edit]
	_header("SIDEARM", "LOADOUT  /  " + c.name)
	var body := _body()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	body.add_child(grid)
	var right := _col(body, 520)
	_stats_panel(right, c)
	var ids := Loadout.WEAPONS.keys()
	for id in ids:
		var w: Dictionary = Loadout.WEAPONS[id]
		var card := Button.new()
		card.custom_minimum_size = Vector2(330, 210)
		card.focus_mode = Control.FOCUS_ALL
		var v := VBoxContainer.new()
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 14
		v.offset_top = 12
		v.offset_right = -14
		v.offset_bottom = -10
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(v)
		var art := _art_box("weapons", id, w.name, Vector2(300, 120))
		v.add_child(art)
		_add_label(v, w.name + ("      EQUIPPED" if id == c.weapon else ""), 22, ACCENT if id == c.weapon else Color.WHITE)
		_add_label(v, "%s  ·  %s  ·  %d rounds" % [w.caliber, w.kind, w.mag], 15, DIM)
		grid.add_child(card)
		_hook(card)
		card.focus_entered.connect(func():
			var hypo := c.duplicate(true)
			hypo.weapon = id
			_bars.show_stats(Loadout.bars(Loadout.stats(hypo)), Loadout.bars(Loadout.stats(c)))
			_info.text = "%s  —  %s, %s. %d damage, %d-round mag." % [w.name, w.kind, w.caliber, int(w.damage), w.mag])
		card.pressed.connect(func():
			c.weapon = id
			_changed()
			_back())


func _page_gunsmith(slot: String) -> void:
	var c: Dictionary = Loadout.classes[_edit]
	_header("GUNSMITH", "LOADOUT  /  %s  /  %s" % [c.name, Loadout.WEAPONS[c.weapon].name])
	# slot tabs across the top
	var tabs := HBoxContainer.new()
	tabs.position = Vector2(64, 132)
	tabs.add_theme_constant_override("separation", 6)
	_page.add_child(tabs)
	for s in Loadout.SLOTS:
		var t := Button.new()
		t.text = SLOT_NAMES[s]
		t.focus_mode = Control.FOCUS_NONE # Q/E-style tabs: click them (controller: back out and pick the slot)
		if s == slot:
			t.add_theme_color_override("font_color", ACCENT)
			t.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.14), 0, 4))
		t.pressed.connect(func():
			_stack[-1][1] = s
			_focus_index = 0
			_build())
		tabs.add_child(t)
	var body := _body(200)
	var left := _col(body, 400)
	var right := _col(body, 640)
	_preview(right, Vector2(640, 330), c)
	_stats_panel(right, c)
	for a in Loadout.ATTACHMENTS[slot]:
		var on: bool = c[slot] == a.id
		var b := _btn(left, a.name + ("      ✓" if on else ""), func():
			c[slot] = a.id
			_changed()
			_rebuild_here(), 22)
		if on:
			b.add_theme_color_override("font_color", ACCENT)
		var icon := Loadout.art("attachments", a.id)
		if icon:
			b.icon = icon
			b.expand_icon = true
		b.focus_entered.connect(func():
			var hypo := c.duplicate(true)
			hypo[slot] = a.id
			_bars.show_stats(Loadout.bars(Loadout.stats(hypo)), Loadout.bars(Loadout.stats(c)))
			_dress_preview(hypo)
			_info.text = a.desc)


func _page_camo() -> void:
	var c: Dictionary = Loadout.classes[_edit]
	_header("CAMO", "LOADOUT  /  %s  /  %s" % [c.name, Loadout.WEAPONS[c.weapon].name])
	var body := _body()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(grid)
	var right := _col(body, 640)
	_preview(right, Vector2(640, 380), c)
	_info = _add_label(right, "", 20, Color.WHITE)
	for cm in Loadout.CAMOS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(120, 130)
		var sw_art := Loadout.art("camos", cm.id)
		var sw: Control
		if sw_art:
			var tr := TextureRect.new()
			tr.texture = sw_art
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			sw = tr
		else:
			var cr := ColorRect.new()
			cr.color = Color(0.2, 0.2, 0.22) if cm.id == "factory" else Color(cm.color.r, cm.color.g, cm.color.b).clamp()
			sw = cr
		sw.position = Vector2(14, 12)
		sw.size = Vector2(92, 76)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sw)
		var l := _label(cm.name, 14, ACCENT if c.camo == cm.id else Color.WHITE)
		l.position = Vector2(8, 96)
		l.size = Vector2(104, 24)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(l)
		grid.add_child(b)
		_hook(b)
		b.focus_entered.connect(func():
			var hypo := c.duplicate(true)
			hypo.camo = cm.id
			_dress_preview(hypo)
			_info.text = cm.name + ("   (equipped)" if c.camo == cm.id else ""))
		b.pressed.connect(func():
			c.camo = cm.id
			_changed()
			_rebuild_here())


func _page_perks(slot: int) -> void:
	var c: Dictionary = Loadout.classes[_edit]
	_header("PERK %d" % (slot + 1), "LOADOUT  /  " + c.name)
	var body := _body()
	var left := _col(body, 460)
	var right := _col(body, 560)
	_info = _add_label(right, "", 24, Color.WHITE)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info.custom_minimum_size.x = 540
	for p in Loadout.PERKS[slot]:
		var on: bool = c.perks[slot] == p.id
		var b := _btn(left, p.name + ("      ✓" if on else ""), func():
			c.perks[slot] = p.id
			_changed()
			_back(), 26)
		if on:
			b.add_theme_color_override("font_color", ACCENT)
		var icon := Loadout.art("perks", p.id)
		if icon:
			b.icon = icon
			b.expand_icon = true
		b.focus_entered.connect(func(): _info.text = p.name + "\n\n" + p.desc)


func _page_settings() -> void:
	_header("SETTINGS", "PAUSED")
	var body := _body()
	var col := _col(body, 760)
	var s := Loadout.settings
	_section(col, "CONTROLS")
	_slider(col, "MOUSE SENSITIVITY", "sens", 0.2, 3.0, 0.05, "%.2f")
	_slider(col, "CONTROLLER SENSITIVITY", "stick", 0.2, 3.0, 0.05, "%.2f")
	_toggle(col, "INVERT LOOK", "invert")
	_section(col, "VIDEO")
	_slider(col, "FIELD OF VIEW", "fov", 60.0, 100.0, 1.0, "%d")
	_toggle(col, "SHOW FPS", "fps")
	_section(col, "MATCH")
	_toggle(col, "KING OF THE HOOD 8 V 8 (OFF: 4 V 4, FASTER)  ·  NEXT MATCH", "big_teams")
	_section(col, "AUDIO")
	_slider(col, "MASTER VOLUME", "volume", 0.0, 1.0, 0.05, "%d%%", 100.0)
	_spacer(col, 16)
	_btn(col, "RESET TO DEFAULTS", func():
		for k in {"sens": 1.0, "stick": 1.0, "invert": false, "fov": 78.0, "volume": 1.0, "fps": true}.keys():
			s[k] = {"sens": 1.0, "stick": 1.0, "invert": false, "fov": 78.0, "volume": 1.0, "fps": true}[k]
		_apply_settings()
		_rebuild_here(), 18)


# ---------------------------------------------------------------- pieces

func _changed() -> void:
	if _edit == Loadout.active:
		_dirty = true
	Loadout.save_all()


func _apply_settings() -> void:
	Loadout.save_all()
	if player:
		player.apply_settings()


func _confirm_then(b: Button, what: String, action: Callable) -> void:
	if _confirm == what:
		action.call()
		return
	_confirm = what
	b.text = "PRESS AGAIN TO CONFIRM"


func _header(title: String, crumb: String) -> void:
	var c := _label(crumb, 17, DIM)
	c.position = Vector2(64, 34)
	_page.add_child(c)
	var t := _label(title, 56, Color.WHITE)
	t.position = Vector2(60, 54)
	_page.add_child(t)
	var line := ColorRect.new()
	line.color = ACCENT
	line.position = Vector2(64, 124)
	line.size = Vector2(80, 4)
	_page.add_child(line)
	var hint := _label("ESC / B   BACK          ENTER / A   SELECT" + ("          LB / RB   SLOT" if _stack[-1][0] == "gunsmith" else ""), 16, DIM)
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 64
	hint.offset_top = -52
	_page.add_child(hint)


func _body(top := 160) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 64
	h.offset_top = top
	h.offset_right = -64
	h.offset_bottom = -80
	h.add_theme_constant_override("separation", 56)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(h)
	return h


func _col(parent: Control, width: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = width
	v.add_theme_constant_override("separation", 6)
	parent.add_child(v)
	return v


func _section(parent: Control, text: String) -> void:
	_spacer(parent, 6)
	_add_label(parent, text, 15, ACCENT)


func _spacer(parent: Control, h: float) -> void:
	var s := Control.new()
	s.custom_minimum_size.y = h
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(s)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _add_label(parent: Control, text: String, size: int, color: Color) -> Label:
	var l := _label(text, size, color)
	parent.add_child(l)
	return l


func _btn(parent: Control, text: String, on_press: Callable, size := 22) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", size)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	parent.add_child(b)
	_hook(b)
	return b


func _hook(c: Control) -> void:
	# hovering with the mouse moves the focus too, so mouse and controller look and behave the same
	c.focus_mode = Control.FOCUS_ALL
	c.mouse_entered.connect(func(): if c.is_inside_tree(): c.grab_focus())
	_focusables.append(c)


func _slider(parent: Control, label: String, key: String, lo: float, hi: float, step: float, fmt: String, show_mult := 1.0) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	parent.add_child(row)
	var l := _add_label(row, label, 20, Color.WHITE)
	l.custom_minimum_size.x = 320
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = float(Loadout.settings[key])
	sl.custom_minimum_size = Vector2(320, 32)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sl)
	var val := _add_label(row, fmt % (sl.value * show_mult), 20, ACCENT)
	sl.value_changed.connect(func(v: float):
		Loadout.settings[key] = v
		val.text = fmt % (v * show_mult)
		_apply_settings())
	_hook(sl)


func _toggle(parent: Control, label: String, key: String) -> void:
	var b := CheckButton.new()
	b.text = label
	b.button_pressed = bool(Loadout.settings[key])
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size.x = 420
	b.toggled.connect(func(on: bool):
		Loadout.settings[key] = on
		_apply_settings())
	parent.add_child(b)
	_hook(b)


func _stats_panel(parent: Control, c: Dictionary) -> void:
	_section(parent, "STATS")
	_bars = StatBars.new()
	_bars.custom_minimum_size.x = 520
	parent.add_child(_bars)
	_bars.show_stats(Loadout.bars(Loadout.stats(c)))
	_info = _add_label(parent, "", 18, DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info.custom_minimum_size.x = 520


func _art_box(kind: String, id: String, title: String, box: Vector2) -> Control:
	# the user's art if it's there, else a placeholder plate with the name on it
	var tex := Loadout.art(kind, id)
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.custom_minimum_size = box
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	var plate := PanelContainer.new()
	plate.custom_minimum_size = box
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	plate.add_theme_stylebox_override("panel", sb)
	var l := _label(title + "\nART COMING", 18, Color(1, 1, 1, 0.35))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate.add_child(l)
	return plate


func _preview(parent: Control, box: Vector2, c: Dictionary) -> void:
	# the class's gun in 3D, turning slowly, in a little world of its own
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.custom_minimum_size = box
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	holder.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 55, 0)
	key.light_energy = 1.4
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, -120, 0)
	rim.light_energy = 0.7
	vp.add_child(rim)
	var center := Vector3(0, 0.02, -0.1)
	var cam := Camera3D.new()
	cam.fov = 30.0
	var eye := center + Vector3(0.68, 0.06, 0.0)
	cam.transform = Transform3D(Basis.looking_at(center - eye), eye)
	vp.add_child(cam)
	_preview_pivot = Node3D.new()
	_preview_pivot.position = center
	vp.add_child(_preview_pivot)
	_preview_gun = Pistol.make(false)
	_preview_gun.position = -center
	_preview_pivot.add_child(_preview_gun)
	_dress_preview(c)


func _dress_preview(c: Dictionary) -> void:
	if not is_instance_valid(_preview_gun):
		return
	var parts := {}
	for slot in Loadout.SLOTS:
		parts[slot] = c[slot]
	Pistol.dress(_preview_gun, Loadout.camo(c.camo), parts)


func _box(bg: Color, accent_w: int, pad_top := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_left = accent_w
	s.border_color = ACCENT
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = pad_top
	s.content_margin_bottom = pad_top
	return s


func _make_theme() -> Theme:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Arial Narrow", "Arial"]) # condensed, COD-like
	font.font_weight = 600
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 20
	var focus := _box(Color(1, 1, 1, 0.13), 6)
	for type in ["Button", "CheckButton"]:
		t.set_stylebox("normal", type, _box(Color(1, 1, 1, 0.035), 0))
		t.set_stylebox("hover", type, _box(Color(1, 1, 1, 0.13), 6))
		t.set_stylebox("pressed", type, _box(Color(1, 1, 1, 0.2), 6))
		t.set_stylebox("hover_pressed", type, _box(Color(1, 1, 1, 0.2), 6))
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, Color(0.88, 0.89, 0.9))
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, ACCENT)
		t.set_color("font_hover_pressed_color", type, ACCENT)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.15)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := track.duplicate()
	fill.bg_color = ACCENT
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var sfocus := StyleBoxFlat.new()
	sfocus.draw_center = false
	sfocus.border_color = ACCENT
	sfocus.set_border_width_all(1)
	t.set_stylebox("focus", "HSlider", sfocus)
	return t
