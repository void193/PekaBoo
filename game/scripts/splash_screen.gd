extends Control
## The supplied artwork includes the wordmark; never draw a second game title.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color("#fdf8e9")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)
	var eyebrow := Label.new()
	eyebrow.text = "READY OR NOT…"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_size_override("font_size", 18)
	eyebrow.add_theme_color_override("font_color", Color("#7a6880"))
	v.add_child(eyebrow)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/branding/pekaboo_logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(440, 388)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(logo)
	var tagline := Label.new()
	tagline.text = "A little mischief. A lot of memories."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 22)
	tagline.add_theme_color_override("font_color", Color("#493b50"))
	v.add_child(tagline)
	var gap := Control.new()
	gap.custom_minimum_size.y = 14
	v.add_child(gap)
	var bar := ProgressBar.new()
	bar.name = "bar"
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(440, 5)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#eaded6")
	track.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#ff637d")
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", track)
	bar.add_theme_stylebox_override("fill", fill)
	v.add_child(bar)
	set_meta("bar", bar)
	var preparing := Label.new()
	preparing.text = "Making the house feel like home"
	preparing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preparing.add_theme_font_size_override("font_size", 16)
	preparing.add_theme_color_override("font_color", Color("#7a6880"))
	v.add_child(preparing)
	var credit := Label.new()
	credit.text = "RUBINBASTAKOTI  /  A GAME FOR TWO"
	credit.add_theme_font_size_override("font_size", 14)
	credit.add_theme_color_override("font_color", Color("#7a6880"))
	credit.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	credit.position = Vector2(-170, -36)
	add_child(credit)
