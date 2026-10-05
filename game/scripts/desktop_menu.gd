extends RefCounted
## Desktop presentation only; the character, world and rendering stay untouched.

static func build(u: UI) -> void:
	u.menu = Control.new()
	u.menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	u.root.add_child(u.menu)
	var gradient := GradientTexture2D.new()
	gradient.gradient = Gradient.new()
	gradient.gradient.colors = PackedColorArray([Color(0.06, 0.03, 0.12, 0.62), Color(0.06, 0.03, 0.12, 0.25), Color(0.06, 0.03, 0.12, 0.94)])
	gradient.gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.fill_from = Vector2.ZERO
	gradient.fill_to = Vector2.RIGHT
	var veil := TextureRect.new()
	veil.texture = gradient
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	u.menu.add_child(veil)
	var brand := VBoxContainer.new()
	brand.position = Vector2(48, 44)
	brand.add_theme_constant_override("separation", 2)
	u.menu.add_child(brand)
	brand.add_child(u._label("READY OR NOT…", 17, Color("#e3c6f7")))
	var logo := TextureRect.new()
	logo.texture = load("res://assets/branding/pekaboo_logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(400, 286)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var logo_material := ShaderMaterial.new()
	logo_material.shader = load("res://assets/branding/menu_logo.gdshader")
	logo.material = logo_material
	brand.add_child(logo)
	brand.add_child(u._label("A little mischief. A lot of memories.", 21, Color("#eddbf9")))
	var foot := VBoxContainer.new()
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(48, -94)
	foot.add_theme_constant_override("separation", 8)
	u.menu.add_child(foot)
	u.anniv_label = u._label("", 17, Color("#eddbf9"))
	foot.add_child(u.anniv_label)
	foot.add_child(u._label("Made with love by RubinBastakoti", 15, Color("#d4b9dd")))

	# A full-height play area with short, switchable pages, rather than one long form.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.anchor_left = 0.49
	scroll.offset_left = 0
	scroll.offset_right = -36
	scroll.offset_top = 32
	scroll.offset_bottom = -32
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	u.menu.add_child(scroll)
	var panel := u._card(Color("#20172e"))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	v.add_child(u._label("MAKE YOURSELF AT HOME", 17, Color("#c9addc")))
	var profile := HBoxContainer.new()
	profile.add_theme_constant_override("separation", 12)
	v.add_child(profile)
	u.name_edit = u._edit("Your name", 14)
	u.name_edit.custom_minimum_size.y = 48
	u.name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile.add_child(u.name_edit)
	var dress := u._btn("Wardrobe", UI.PURPLE, Vector2(132, 48), 20, 14)
	dress.pressed.connect(u.open_wardrobe)
	dress.tooltip_text = "Wardrobe · F2"
	profile.add_child(dress)
	var chars := HBoxContainer.new()
	v.add_child(chars)
	for direction in [-1, 1]:
		var b := u._btn("‹" if direction == -1 else "›", Color("#49345e"), Vector2(48, 42), 28, 12)
		b.pressed.connect(u._cycle_char.bind(direction))
		b.tooltip_text = "Previous character · [" if direction == -1 else "Next character · ]"
		if direction == 1:
			u.char_label = u._label("", 21, Color("#fff7ef"))
			u.char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			u.char_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			u.char_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			chars.add_child(u.char_label)
		chars.add_child(b)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	v.add_child(tabs)
	var pages: Array[Control] = []
	var tab_buttons: Array[Button] = []
	for title in ["Nearby", "Online", "Solo"]:
		var tab := u._btn(title, Color("#49345e"), Vector2(0, 48), 21, 14)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(tab)
		tab_buttons.append(tab)
	var content := Control.new()
	content.custom_minimum_size = Vector2(0, 250)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(content)
	for i in 3:
		var page := VBoxContainer.new()
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.add_theme_constant_override("separation", 12)
		content.add_child(page)
		pages.append(page)
		var heading: String = ["Better together.", "Any distance. Same game.", "Your house. Your rules."][i]
		page.add_child(u._label(heading, 32, Color("#fff7ef")))
		var copy := u._label(["Host or find a game on the same Wi-Fi.", "Share a room code and play over the internet.", "Practise, explore, or unwind under the stars."][i], 18, Color("#c9addc"))
		copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		page.add_child(copy)
	_action(u, pages[0], "Host a game", "H", UI.PINK, func(): u.lan_host.emit(u._name(), u.char_idx))
	_action(u, pages[0], "Find a nearby game", "J", UI.BLUE, func(): u.lan_find.emit(u._name(), u.char_idx))
	u.code_edit = u._edit("4-letter room code", 4)
	u.code_edit.custom_minimum_size.y = 48
	pages[1].add_child(u.code_edit)
	var online := HBoxContainer.new()
	online.add_theme_constant_override("separation", 10)
	pages[1].add_child(online)
	_action(u, online, "Host online", "O", UI.PINK, func(): u.create_room.emit(u._name(), u.char_idx, u.settings["server"]))
	_action(u, online, "Join online", "I", UI.BLUE, func(): u.join_room.emit(u.code_edit.text.strip_edges().to_upper(), u._name(), u.char_idx, u.settings["server"]))
	var practice := HBoxContainer.new()
	practice.add_theme_constant_override("separation", 10)
	pages[2].add_child(practice)
	_action(u, practice, "I hide", "B", UI.ORANGE, func(): u.play_bot.emit(u._name(), u.char_idx, "hide"))
	_action(u, practice, "I seek", "V", UI.ORANGE, func(): u.play_bot.emit(u._name(), u.char_idx, "seek"))
	var solo := HBoxContainer.new()
	solo.add_theme_constant_override("separation", 10)
	pages[2].add_child(solo)
	_action(u, solo, "Explore", "X", UI.PURPLE, func(): u.explore.emit(u._name(), u.char_idx))
	_action(u, solo, "Chill night", "N", Color("#7050a4"), func(): u.chill_solo.emit(u._name(), u.char_idx))
	for i in 3:
		tab_buttons[i].pressed.connect(func():
			for j in 3:
				pages[j].visible = j == i
				u._style_btn(tab_buttons[j], UI.PURPLE if j == i else Color("#49345e"), 14))
		pages[i].visible = i == 0
	u._style_btn(tab_buttons[0], UI.PURPLE, 14)
	u.status_label = u._label("", 18, Color("#ffb6c8"))
	u.status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(u.status_label)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	v.add_child(bottom)
	var settings := u._btn("Settings", Color("#49345e"), Vector2(160, 48), 20, 14)
	settings.tooltip_text = "Settings · F3"
	settings.pressed.connect(u.open_settings)
	bottom.add_child(settings)
	var hint := u._label("F1  Controls   ·   F11  Fullscreen", 15, Color("#c9addc"))
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(hint)

static func _action(u: UI, parent: Control, text: String, key: String, color: Color, cb: Callable) -> void:
	var b := u._btn(text, color, Vector2(0, 64), 25, 16)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = text + " · " + key
	b.set_meta("desktop_key", key)
	b.pressed.connect(cb)
	parent.add_child(b)
