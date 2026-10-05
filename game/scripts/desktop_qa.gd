extends Node
## Desktop regression checks exercise real input events and real UI signals.

var m: Node
var passed := 0
var failed := 0
var actions: Array[String] = []

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("DESKTOP PASS ", label)
	else:
		failed += 1
		push_error("DESKTOP FAIL " + label)

func key(code: int, shift := false, pressed := true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.shift_pressed = shift
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func frames(count := 2) -> void:
	for i in count:
		await get_tree().process_frame

func screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../verification/" + name + ".png")

func run() -> void:
	m = get_parent()
	while not m.house.is_baked:
		await frames()
	await frames(4)
	var u: UI = m.ui
	var controls: RefCounted = m.desktop_controls
	if "--mobile-preview" in OS.get_cmdline_user_args():
		u.menu.queue_free()
		u._build_touch_menu()
		u.show_menu("Player", 0)
		await frames(4)
		await screenshot("menu-android-layout")
		get_tree().quit()
		return
	await screenshot("menu-nearby")
	m._start_warmup()
	await frames(2)
	check(m._loading.get_meta("bar", null) is ProgressBar, "new splash exposes real warm-up progress")
	await screenshot("splash-screen")
	m._warm_i = 0
	m._loading.queue_free()
	await frames(2)
	var menu_controls: Array[Control] = []
	controls._collect(u.menu, menu_controls)
	check(menu_controls.size() >= 10, "menu exposes keyboard focus for all visible buttons and fields")
	for i in menu_controls.size():
		key(KEY_TAB)
		await frames(1)
		check(menu_controls.has(get_viewport().gui_get_focus_owner()), "Tab stays in visible menu (%d)" % i)
	key(KEY_TAB, true)
	await frames()
	check(menu_controls.has(get_viewport().gui_get_focus_owner()), "Shift+Tab reverses focus")
	u.name_edit.grab_focus()
	var old_char := u.char_idx
	key(KEY_X)
	key(KEY_BRACKETRIGHT)
	await frames()
	check(m.phase == "menu" and u.char_idx == old_char, "typing letters or brackets does not trigger menu shortcuts")
	key(KEY_ESCAPE)
	key(KEY_BRACKETRIGHT)
	await frames()
	check(u.char_idx == (old_char + 1) % Kit.CHARS.size(), "character shortcut changes preview")
	key(KEY_F2)
	await frames()
	check(u.wardrobe.visible, "F2 opens wardrobe")
	u.char_label.get_parent().get_child(0).grab_focus()
	old_char = u.char_idx
	key(KEY_ENTER)
	check(u.char_idx == old_char, "modal Enter cannot activate a button behind the wardrobe")
	var wardrobe_controls: Array[Control] = []
	controls._collect(u.wardrobe, wardrobe_controls)
	for i in wardrobe_controls.size() + 1:
		key(KEY_TAB)
		await frames(1)
		check(wardrobe_controls.has(get_viewport().gui_get_focus_owner()), "wardrobe traps keyboard focus (%d)" % i)
	key(KEY_ESCAPE)
	await frames()
	check(not u.wardrobe.visible, "Escape closes wardrobe")
	key(KEY_F1)
	await frames()
	check(controls.help.visible, "F1 opens help")
	await screenshot("keyboard-help")
	key(KEY_TAB)
	key(KEY_ENTER)
	await frames()
	check(not controls.help.visible, "Enter activates focused help button")
	key(KEY_F3)
	await frames()
	check(u.settings_panel.visible, "F3 opens settings")
	key(KEY_ESCAPE)
	key(KEY_X)
	await get_tree().create_timer(0.35).timeout
	await frames(4)
	check(m.phase == "explore" and u.hud.visible, "X enters real explore mode")
	check(not controls.blocks_movement(), "explore keyboard movement is enabled")
	u.tools_btn.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = Vector2(640, 400)
	Input.parse_input_event(mouse)
	Input.flush_buffered_events()
	await frames()
	check(get_viewport().gui_get_focus_owner() == null, "clicking the world clears HUD focus and resumes keyboard movement")
	key(KEY_C)
	await frames()
	check(m.me.crouch, "C toggles crouch through real button")
	key(KEY_C)
	key(KEY_R)
	await frames()
	check(m.me.run, "R toggles run")
	key(KEY_SHIFT)
	key(KEY_SHIFT, false, false)
	check(m.me.run, "Shift release preserves toggled sprint")
	key(KEY_R)
	m.ui.action.connect(func(id: String): actions.append(id))
	# Isolate callback recording for arbitrary tool IDs, while movement still uses the game.
	var bound := Callable(m, "_do_action")
	u.action.disconnect(bound)
	var tools: Array = []
	for i in 14:
		tools.append({"id": "test_tool_%d" % i, "icon": "T", "name": "Tool %d" % i})
	var pranks: Array = []
	for i in 9:
		pranks.append({"id": "test_prank_%d" % i, "icon": "P", "name": "Prank %d" % i})
	u.set_controls({"id": "test_main", "icon": "E"}, tools, pranks, true, false, false, {"id": "test_alt", "icon": "Q"})
	key(KEY_E)
	key(KEY_Q)
	check(actions.has("test_main") and actions.has("test_alt"), "main and alternate buttons have independent shortcuts")
	for i in 14:
		key(controls.SLOTS[i])
		check(actions.back() == "test_tool_%d" % i, "tool slot %d works with panel closed" % (i + 1))
	for i in 9:
		key(controls.SLOTS[i], true)
		check(actions.back() == "test_prank_%d" % i, "prank slot %d works with Shift" % (i + 1))
	key(KEY_P)
	key(KEY_1)
	check(actions.back() == "test_prank_0" and not u.fun_card.visible, "open pranks use number keys and close after selection")
	key(KEY_T)
	key(KEY_EQUAL)
	check(actions.back() == "test_tool_11" and not u.tools_card.visible, "expanded tool slots work in open panel")
	u.tool_btns[0].disabled = true
	u.main_btn.disabled = true
	var before := actions.size()
	key(KEY_1)
	key(KEY_E)
	check(actions.size() == before, "disabled or cooling-down actions cannot be triggered")
	key(KEY_G)
	check(u.emote_btns[0].visible, "G opens emotes")
	key(KEY_8)
	check(actions.back().begins_with("emote:") and not u.emote_btns[0].visible, "all eight emotes have number-key access")
	key(KEY_F3)
	before = actions.size()
	key(KEY_Q)
	check(actions.size() == before and controls.blocks_movement(), "settings block actions and movement underneath")
	key(KEY_ESCAPE)
	u.action.connect(bound)
	m._to_menu("")
	# Reach hidden menu pages by Tab/Enter, then inspect each page's layout.
	menu_controls.clear()
	controls._collect(u.menu, menu_controls)
	for c in menu_controls:
		if c is Button and c.text == "Online":
			c.grab_focus()
			key(KEY_ENTER)
	await frames()
	check(u.code_edit.is_visible_in_tree(), "keyboard activates Online tab")
	await screenshot("menu-online")
	menu_controls.clear()
	controls._collect(u.menu, menu_controls)
	for c in menu_controls:
		if c is Button and c.text == "Solo":
			c.grab_focus()
			key(KEY_ENTER)
	await frames()
	await screenshot("menu-solo")
	for c in menu_controls:
		if c is Button and c.text == "Solo":
			c.release_focus()
	key(KEY_B)
	await frames(4)
	check(m.bot != null and m.phase in ["hide", "lobby"], "B starts actual bot practice")
	key(KEY_F10)
	await frames()
	check(m.phase == "menu", "F10 returns to main menu")
	check(not u.status_label.get_global_rect().end.y > get_viewport().get_visible_rect().size.y, "menu status remains within viewport")
	print("DESKTOP DONE passed=%d failed=%d" % [passed, failed])
	get_tree().quit(1 if failed else 0)
