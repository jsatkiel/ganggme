extends SceneTree
## Dev tool: paints the wall graffiti as spray-paint images in assets/graffiti, read by map_builder.gd as decals.
## "tag" = a quick handstyle in one color (Sedgwick Ave Display, by graffiti writer Kevin Burke) with a few drips;
## "throw" = a bubbly throw-up (Rubik Wet Paint) with a thick dark outline. Every piece gets a soft overspray
## halo and stray specks. The fill is white so the game can tint each one; outlines stay dark.
## Needs a window (text is drawn by the renderer):  godot --path . -s tools/bake_graffiti.gd

const OUT := "res://assets/graffiti/"
const FONTS := {
	"tag": preload("res://assets/fonts/SedgwickAveDisplay-Regular.ttf"),
	"throw": preload("res://assets/fonts/RubikWetPaint-Regular.ttf"),
}
const PIECES := [ # [file name, text, style]; keep in step with map_builder.gd GRAFFITI
	["southside", "SOUTHSIDE", "throw"],
	["block", "BLOCK", "throw"],
	["twin", "TWIN", "throw"],
	["opps", "OPPS", "throw"],
	["64th_st", "64th St", "tag"],
	["no_lackin", "No Lackin", "tag"],
	["long_live", "Long Live Twin", "tag"],
	["keep_out", "KEEP OUT", "tag"],
	["rip", "R.I.P. Lil Ty", "tag"],
	["stay_down", "Stay Down", "tag"],
]
const W := 1024
const H := 384

var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	rng.seed = 64
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for p in PIECES:
		var img: Image = await _draw_text(p[1], p[2])
		img = _spray(img, p[2])
		img.save_png(OUT + p[0] + ".png")
		print("[graffiti] ", p[0], " ", img.get_size())
	quit()


func _draw_text(text: String, style: String) -> Image:
	var font: Font = FONTS[style]
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var label := Label.new()
	var ls := LabelSettings.new()
	ls.font = font
	# biggest size that fits with room for the overspray around it
	var size := 220
	while size > 40 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > W * 0.86:
		size -= 6
	ls.font_size = size
	ls.font_color = Color.WHITE
	if style == "throw":
		ls.outline_size = int(size * 0.14)
		ls.outline_color = Color(0.04, 0.04, 0.05)
	label.label_settings = ls
	label.text = text
	label.size = Vector2(W, H)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.rotation = deg_to_rad(rng.randf_range(-6.0, 3.0)) # tags lean, rarely level
	label.pivot_offset = Vector2(W, H) / 2.0
	vp.add_child(label)
	root.add_child(vp)
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	vp.queue_free()
	return img


func _spray(src: Image, style: String) -> Image:
	# overspray: the paint's alpha blurred out wide and faint, behind the sharp letters
	var halo: Image = src.duplicate()
	halo.resize(W / 16, H / 16, Image.INTERPOLATE_BILINEAR)
	halo.resize(W, H, Image.INTERPOLATE_BILINEAR)
	var out := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var mist := 0.32 if style == "tag" else 0.22
	for y in H:
		for x in W:
			var s := src.get_pixel(x, y)
			var h := halo.get_pixel(x, y).a * mist
			# letters over the mist (the mist is fill-colored: white, tinted in game)
			var a := s.a + h * (1.0 - s.a)
			var c := Color(1, 1, 1) if a <= 0.0 else (Color(s.r, s.g, s.b) * s.a + Color(1, 1, 1) * h * (1.0 - s.a)) / a
			out.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	# stray specks where the can spat
	for i in 900:
		var x := rng.randi_range(2, W - 3)
		var y := rng.randi_range(2, H - 3)
		var near := halo.get_pixel(x, y).a
		if near > 0.04 and src.get_pixel(x, y).a < 0.1 and rng.randf() < near * 3.0:
			var r := rng.randi_range(1, 2)
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if dx * dx + dy * dy <= r * r:
						out.set_pixel(x + dx, y + dy, Color(1, 1, 1, rng.randf_range(0.5, 0.9)))
	if style == "tag":
		_drips(out, src)
	return out


func _drips(out: Image, src: Image) -> void:
	# a few runs of paint down from the bottoms of letters (thin, fading)
	var made := 0
	var tries := 0
	while made < 6 and tries < 4000:
		tries += 1
		var x := rng.randi_range(20, W - 20)
		var y := rng.randi_range(H / 3, H - 40)
		if src.get_pixel(x, y).a > 0.8 and src.get_pixel(x, y + 3).a < 0.2:
			var length := rng.randi_range(18, 70)
			var width := rng.randi_range(2, 4)
			for dy in length:
				var fade := 1.0 - float(dy) / length
				for dx in width:
					if y + dy < H:
						out.set_pixel(x + dx, y + dy, Color(1, 1, 1, 0.9 * fade + 0.1))
			# a bead at the end
			for dx in range(-1, width + 1):
				for dy2 in 3:
					if y + length + dy2 < H:
						out.set_pixel(x + dx, y + length + dy2, Color(1, 1, 1, 0.85))
			made += 1
