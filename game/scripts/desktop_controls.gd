extends RefCounted
## One input route for desktop. Buttons remain the source of truth for actions.

const SLOTS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUAL, KEY_BRACKETLEFT, KEY_BRACKETRIGHT]
var m: Node
var u: UI
var help: Control
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _shift_held := false
var _run_before_shift := false

func setup(main: Node) -> void:
	m = main
	u = m.ui
	_build_help()
	u.main_btn.tooltip_text = "Main action · E / F"
	u.alt_btn.tooltip_text = "Alternate action · Q"
	u.jump_btn.tooltip_text = "Jump · Space"
	u.crouch_btn.tooltip_text = "Toggle crouch · C / Ctrl"
	u.run_btn.tooltip_text = "Toggle run · R / Hold Shift"
	u.tools_btn.tooltip_text = "Tools · T · Choose with 1–9, 0, -, =, [, ]"
	u.fun_btn.tooltip_text = "Pranks · P · Choose with 1–9 or Shift + 1–9"
	u.emote_btn.tooltip_text = "Emotes · G · Choose with 1–8"

func _build_help() -> void:
	help = Control.new()
	help.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	help.visible = false
	u.root.add_child(help)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.02, 0.08, 0.9)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	help.add_child(bg)
	var v := u._centered_scroll(help)
	v.add_child(u._label("Keyboard controls", 38, UI.PURPLE))
	var text := u._label("WASD / arrows   Move     ·     Mouse   Look\nSpace   Jump     ·     C / Ctrl   Crouch\nShift   Hold to run     ·     R   Toggle run\nE / F   Main action     ·     Q   Alternate action\nT   Tools     ·     P   Pranks     ·     G   Emotes\n1–9, 0, -, =, [, ]   Choose a tool\nShift + 1–9   Prank     ·     1–8 in emotes   React\n\nTab / Shift + Tab   Focus any button or field\nEnter   Activate     ·     Arrows   Adjust sliders\nF2   Wardrobe     ·     F3   Settings\nF1   This help     ·     F11   Fullscreen\nEsc   Close a panel / release the mouse\nF10   Leave the game and return to the menu\n\nMenu: H / J   Host / find nearby\nO / I   Host / join online     ·     [ / ]   Character\nB / V   Practise hiding / seeking\nX   Explore     ·     N   Chill night", 20, UI.INK)
	v.add_child(text)
	var done := u._btn("Got it", UI.PURPLE, Vector2(0, 52), 22)
	done.pressed.connect(_close_help)
	v.add_child(done)

func _close_help() -> void:
	help.visible = false
	Input.mouse_mode = _mouse_before
	_release_focus()

func modal() -> Control:
	if help.visible:
		return help
	if u.settings_panel.visible:
		return u.settings_panel
	if u.find_panel.visible:
		return u.find_panel
	if u.wardrobe.visible:
		return u.wardrobe
	for panel in [u.overlays.grid_panel, u.overlays.asker, u.overlays.card, u.overlays.game]:
		if panel != null and panel.is_visible_in_tree():
			return panel
	return null

func blocks_movement() -> bool:
	var focus := u.root.get_viewport().gui_get_focus_owner()
	return modal() != null or u.results.visible or u.menu.visible or (focus != null and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)

func _typing() -> bool:
	var focus := u.root.get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit

func _release_focus() -> void:
	var focus := u.root.get_viewport().gui_get_focus_owner()
	if focus:
		focus.release_focus()

func _collect(node: Node, out: Array[Control]) -> void:
	if node is Control and not node.is_visible_in_tree():
		return
	if node is Control and node.focus_mode == Control.FOCUS_ALL:
		if not node is BaseButton or not node.disabled:
			out.append(node)
	for child in node.get_children():
		_collect(child, out)

func _tab(reverse: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var scope := modal()
	if scope == null:
		scope = u.menu if u.menu.visible else (u.results if u.results.visible else u.root)
	var controls: Array[Control] = []
	_collect(scope, controls)
	if controls.is_empty():
		return
	var index := controls.find(u.root.get_viewport().gui_get_focus_owner())
	if index == -1:
		index = controls.size() - 1 if reverse else 0
	else:
		index = posmod(index + (-1 if reverse else 1), controls.size())
	controls[index].grab_focus()

func _press(b: Button) -> bool:
	if b == null or not b.is_visible_in_tree() or b.disabled:
		return false
	b.pressed.emit()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_release_focus()
	return true

func _slot(buttons: Array, index: int) -> bool:
	return _press(buttons[index]) if index >= 0 and index < buttons.size() else false

func _escape() -> void:
	if help.visible:
		_close_help()
	elif u.settings_panel.visible:
		u.settings_panel.visible = false
	elif u.find_panel.visible:
		u.find_panel.visible = false
		u.lan_cancel.emit()
	elif u.wardrobe.visible:
		u.wardrobe.visible = false
	elif modal() != null:
		var panel := modal()
		# Cancel the text asker through the same path as its button.
		panel.visible = false
	elif u.tools_card.visible or u.fun_card.visible:
		u.close_panels()
	elif u.emote_btns[0].visible:
		u._toggle_emotes(false)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_release_focus()

func handle(ev: InputEvent) -> bool:
	if not ev is InputEventKey:
		return false
	var key: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
	if key == KEY_SHIFT and not ev.echo:
		if ev.pressed and not blocks_movement():
			_run_before_shift = m.me.run
			_shift_held = true
		elif not ev.pressed and _shift_held:
			m.me.run = _run_before_shift
			_shift_held = false
	if not ev.pressed or ev.echo:
		return false
	if key == KEY_F11:
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		return true
	if key == KEY_ESCAPE:
		_escape()
		return true
	if key == KEY_F1:
		if help.visible:
			_close_help()
		else:
			_mouse_before = Input.mouse_mode
			u.root.move_child(help, -1)
			help.visible = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_release_focus()
		return true
	if key == KEY_TAB:
		_tab(ev.shift_pressed)
		return true
	var active := modal()
	var owner := u.root.get_viewport().gui_get_focus_owner()
	if active != null and owner != null and owner != active and not active.is_ancestor_of(owner):
		_release_focus()
	# Never steal letters, digits, Enter, or editing chords from a text field.
	if _typing():
		return false
	if ev.alt_pressed or ev.meta_pressed:
		return false
	var focus := u.root.get_viewport().gui_get_focus_owner()
	if key == KEY_ENTER or key == KEY_KP_ENTER:
		if focus is Button:
			return _press(focus)
		if focus is Slider:
			return false
		if modal() != null:
			var buttons: Array[Control] = []
			_collect(modal(), buttons)
			for b in buttons:
				if b is Button:
					return _press(b)
		if u.results.visible:
			return _press(u.res_next)
		if u.lobby.visible:
			return _press(u.lobby_start)
	if modal() != null:
		var slot := SLOTS.find(key)
		if slot >= 0 and slot < 9:
			var options: Array[Control] = []
			_collect(modal(), options)
			var buttons: Array[Button] = []
			for option in options:
				if option is Button:
					buttons.append(option)
			return _slot(buttons, slot)
		return false
	if key == KEY_F2:
		u.open_wardrobe()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return true
	if key == KEY_F3:
		u.open_settings()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return true
	if ev.ctrl_pressed and key != KEY_CTRL:
		return false
	if u.menu.visible:
		if key == KEY_BRACKETLEFT or key == KEY_BRACKETRIGHT:
			u._cycle_char(-1 if key == KEY_BRACKETLEFT else 1)
			return true
		# Shortcuts work across all menu pages, even when a page is not selected.
		match key:
			KEY_H: u.lan_host.emit(u._name(), u.char_idx)
			KEY_J: u.lan_find.emit(u._name(), u.char_idx)
			KEY_O: u.create_room.emit(u._name(), u.char_idx, u.settings["server"])
			KEY_I: u.join_room.emit(u.code_edit.text.strip_edges().to_upper(), u._name(), u.char_idx, u.settings["server"])
			KEY_B: u.play_bot.emit(u._name(), u.char_idx, "hide")
			KEY_V: u.play_bot.emit(u._name(), u.char_idx, "seek")
			KEY_X: u.explore.emit(u._name(), u.char_idx)
			KEY_N: u.chill_solo.emit(u._name(), u.char_idx)
			_: return false
		_release_focus()
		return true
	if key == KEY_F10:
		u.leave.emit()
		return true
	if u.results.visible:
		return false
	# Focused controls keep Space and arrow keys for normal UI navigation.
	if focus != null and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if key in [KEY_SPACE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			return false
	var index := SLOTS.find(key)
	if index >= 0:
		if u.emote_btns[0].visible and not ev.shift_pressed:
			return _slot(u.emote_btns, index)
		if ev.shift_pressed or u.fun_card.visible:
			return _item(u.fun_btns, u.fun_ids, index)
		return _slot(u.tool_btns, index) if u.tools_card.visible else _tool(index)
	match key:
		KEY_E, KEY_F: return _press(u.main_btn)
		KEY_Q: return _press(u.alt_btn)
		KEY_SPACE: return _press(u.jump_btn)
		KEY_C, KEY_CTRL: return _press(u.crouch_btn)
		KEY_R: return _press(u.run_btn)
		KEY_T: return _press(u.tools_btn)
		KEY_P: return _press(u.fun_btn)
		KEY_G: return _press(u.emote_btn)
	return false

func _tool(index: int) -> bool:
	return _item(u.tool_btns, u.tool_ids, index)

func reset_shift() -> void:
	_shift_held = false

func _item(buttons: Array, ids: Array, index: int) -> bool:
	# Tools can be used without opening their card, but never while unavailable.
	if index < 0 or index >= ids.size():
		return false
	var b: Button = buttons[index]
	if not b.visible or b.disabled or ids[index] == "" or not u.hud.visible:
		return false
	b.pressed.emit()
	return true
