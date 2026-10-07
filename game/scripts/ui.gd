class_name UI
extends CanvasLayer
## Menus, lobby, settings, in-game HUD and touch joystick. Built in code.

signal create_room(player_name: String, char_index: int, server: String)
signal join_room(code: String, player_name: String, char_index: int, server: String)
signal explore(player_name: String, char_index: int)
signal char_changed(char_index: int)
signal play_bot(player_name: String, char_index: int, role: String)
signal lan_host(player_name: String, char_index: int)
signal lan_find(player_name: String, char_index: int)
signal lan_join(ip: String)
signal lan_cancel
signal start_round
signal outfit_changed(outfit: Dictionary)
signal chill_together
signal chill_solo(player_name: String, char_index: int)
signal leave
signal next_round
signal back_to_lobby
signal action(id: String)
signal settings_changed(s: Dictionary)
signal round_options(hide_time: float, seek_time: float)

const PINK := Color("#ff4f86")
const BLUE := Color("#3f86ff")
const PURPLE := Color("#8a5cf0")
const GREEN := Color("#1fb070")
const ORANGE := Color("#ff8a3d")
const INK := Color("#2b2033")
const CREAM := Color("#fff7ef")
const MUTED := Color("#7a6880")
const GLASS := Color(0.12, 0.08, 0.16, 0.62)

var settings := {"music": 0.7, "sfx": 0.9, "sens": 1.0, "quality": 1, "server": "", "fps": false,
	"hide": 45.0, "seek": 180.0, "bot": 1, "prints": true, "wiggle": true, "heat": true, "halfping": true,
	"bananas": 2, "smokes": 2, "pillows": 5, "xrays": 3}
var s_hide: HSlider
var s_seek: HSlider
var s_bananas: HSlider
var s_smokes: HSlider
var s_pillows: HSlider
var s_xrays: HSlider
var s_bot: Array[Button] = []
var s_toggles := {}
var char_idx := 0
var hide_choice := 45.0
var seek_choice := 180.0

var root: Control
var menu: Control
var name_edit: LineEdit
var code_edit: LineEdit
var status_label: Label
var char_label: Label

var settings_panel: Control
var s_music: HSlider
var s_sfx: HSlider
var s_sens: HSlider
var s_quality: Array[Button] = []
var s_server: LineEdit

var lobby: Control
var lobby_title: Label
var lobby_players: Label
var lobby_start: Button
var lobby_chill: Button
var anniv_label: Label
var lobby_hint: Label
var lobby_opts: Control
var hide_btns: Array[Button] = []
var seek_btns: Array[Button] = []

var hud: Control
var timer_label: Label
var timer_pill: Control
var role_label: Label
var score_label: Label
var hint_label: Label
var toast_label: Label
var _toast_t := 0.0
var crosshair: Control
var small_hint: Label
var main_btn: Button
var main_id := ""
var alt_btn: Button
var alt_id := ""
var fps_label: Label
var latency_label: Label
var fps_btn: Button
var music_btn: Button
var _last_flags := ""
var jump_btn: Button
var crouch_btn: Button
var run_btn: Button
var top_left: HBoxContainer
var overlays: Overlays
var emote_btn: Button
var emote_btns: Array[Button] = []
var wardrobe: PanelContainer
var outfit := {}          # {"top": Color or null, "bottom": Color or null, "acc": String}
var stick_base: Panel
var stick_knob: Panel
var blind: ColorRect
var blind_label: Label
var slats: Control
var danger: ColorRect
var vignette: ColorRect
var dark: ColorRect
var results: Control
var res_title: Label
var res_body: Label
var res_next: Button
var res_lobby: Button
var res_wait: Label


func build(chat_lines: Array, emotes: Array) -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font_size = 26
	# Fredoka: a soft, rounded font that suits the game (emoji still come from the system font)
	var base: FontFile = Kit.ui_font()
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": 560}
	th.default_font = fv
	root.theme = th
	add_child(root)
	_build_hud(chat_lines, emotes)
	_build_lobby()
	_build_results()
	overlays = Overlays.new()
	root.add_child(overlays)
	overlays.setup(self)
	_build_menu()
	_build_find_panel()
	_build_settings()


# ---------- small builders ----------

func _box(c: Color, r := 22, pad := 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.5
	s.content_margin_bottom = pad * 0.5
	s.anti_aliasing = true
	return s


func _style_btn(b: Button, c: Color, r := 22) -> void:
	var n := _box(c, r)
	n.shadow_color = Color(0, 0, 0, 0.18)
	n.shadow_size = 4
	n.shadow_offset = Vector2(0, 3)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", _box(c.lightened(0.12), r))
	b.add_theme_stylebox_override("pressed", _box(c.darkened(0.2), r))
	b.add_theme_stylebox_override("disabled", _box(Color(c.r, c.g, c.b, 0.35), r))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _btn(text: String, c: Color, min_size := Vector2(0, 64), fs := 26, r := 22) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	_style_btn(b, c, r)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.65))
	b.add_theme_font_size_override("font_size", fs)
	b.pressed.connect(func(): Sfx.play("click", -6.0))
	return b


func _label(text: String, fs := 26, c := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	return l


func _outlined(l: Label, size := 10) -> Label:
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", size)
	return l


func _edit(placeholder: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size = Vector2(0, 60)
	var sb := _box(Color.WHITE, 16, 16)
	sb.border_color = Color("#ead8c8")
	sb.set_border_width_all(3)
	e.add_theme_stylebox_override("normal", sb)
	var sf := sb.duplicate()
	sf.border_color = PINK
	e.add_theme_stylebox_override("focus", sf)
	e.add_theme_color_override("font_color", INK)
	e.add_theme_color_override("font_placeholder_color", Color("#b9a9b5"))
	e.add_theme_color_override("caret_color", PINK)
	return e


func _card(c := CREAM) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(c, 30, 30)
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 16
	p.add_theme_stylebox_override("panel", sb)
	return p


func _centered_scroll(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	center.add_child(margin)
	var card := _card()
	card.custom_minimum_size = Vector2(580, 0)
	margin.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)
	return v


func _round_btn(text: String, c: Color, d: float, fs := 26) -> Button:
	var b := _btn(text, c, Vector2(d, d), fs, int(d / 2.0))
	return b


# ---------- menu ----------

func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(menu)
	# the 3D house and your character stay visible on the left; a soft dusk gradient on the right
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	g.colors = PackedColorArray([Color(0.1, 0.05, 0.16, 0.0), Color(0.1, 0.05, 0.16, 0.08), Color(0.1, 0.05, 0.16, 0.72)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	var shade := TextureRect.new()
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(shade)

	# the logo, cut out, sitting right on the scene (top left)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/ui_logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.position = Vector2(18, 10)
	logo.size = Vector2(350, 280)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(logo)
	_menu_parts.append(logo)

	# you: name + character + wardrobe, bottom left (your character stands right behind it)
	var me_card := PanelContainer.new()
	me_card.add_theme_stylebox_override("panel", _box(Color(0.12, 0.07, 0.18, 0.72), 24, 14))
	me_card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	me_card.position = Vector2(30, -170)
	me_card.custom_minimum_size = Vector2(400, 0)
	menu.add_child(me_card)
	_menu_parts.append(me_card)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 10)
	me_card.add_child(mv)
	name_edit = _edit("Your name", 14)
	mv.add_child(name_edit)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	mv.add_child(crow)
	var prev := _btn("◀", PURPLE, Vector2(60, 56), 26)
	prev.pressed.connect(func(): _cycle_char(-1))
	crow.add_child(prev)
	char_label = _label("", 24, Color.WHITE)
	char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	char_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crow.add_child(char_label)
	var nxt := _btn("▶", PURPLE, Vector2(60, 56), 26)
	nxt.pressed.connect(func(): _cycle_char(1))
	crow.add_child(nxt)
	var wb := _btn("👗", PINK, Vector2(60, 56), 26)
	wb.pressed.connect(open_wardrobe)
	crow.add_child(wb)

	# the big buttons, right side
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.anchor_left = 1.0
	col.anchor_right = 1.0
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = -560
	col.offset_right = -40
	col.offset_top = -230
	col.offset_bottom = 230
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_child(col)
	_menu_parts.append(col)
	col.add_child(_menu_btn("👫", "PLAY TOGETHER", "Online, or on the same Wi-Fi / hotspot", PINK, Vector2(0, 112), func(): _show_menu_panel(play_panel)))
	col.add_child(_menu_btn("🌙", "CHILL NIGHT", "Candles, stars and love songs", Color("#6a42a8"), Vector2(0, 96), func(): chill_solo.emit(_name(), char_idx)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	var pr := _menu_btn("🤖", "PRACTICE", "Play with a bot", ORANGE, Vector2(0, 88), func(): _show_menu_panel(practice_panel))
	pr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pr)
	var ex := _menu_btn("🏠", "EXPLORE", "Walk around", BLUE, Vector2(0, 88), func(): explore.emit(_name(), char_idx))
	ex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ex)
	status_label = _label("", 20, Color("#ffb3b3"))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outlined(status_label, 8)
	col.add_child(status_label)

	# settings, top right
	var gear := _icon_btn("⚙️", Color(0.12, 0.07, 0.18, 0.7), 64, 30)
	gear.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	gear.position = Vector2(-90, 24)
	gear.pressed.connect(open_settings)
	menu.add_child(gear)
	_menu_parts.append(gear)

	# credits + anniversary, bottom right
	var foot := VBoxContainer.new()
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	foot.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.position = Vector2(-40, -20)
	foot.alignment = BoxContainer.ALIGNMENT_END
	menu.add_child(foot)
	_menu_parts.append(foot)
	anniv_label = _outlined(_label("", 19, Color("#ffd1ec")), 6)
	anniv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	foot.add_child(anniv_label)
	var by := _outlined(_label("made with 💜 by RubinBastakoti  ·  v1.0", 15, Color(1, 1, 1, 0.8)), 5)
	by.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	foot.add_child(by)

	_build_play_panel()
	_build_practice_panel()
	_build_wardrobe()


## A big title-screen button: emoji, a bold title and a short line under it.
func _menu_btn(icon: String, title: String, sub: String, c: Color, size: Vector2, cb: Callable) -> Button:
	var b := _btn("", c, size, 10, 26)
	var st: StyleBoxFlat = b.get_theme_stylebox("normal").duplicate()
	st.shadow_color = Color(0, 0, 0, 0.3)
	st.shadow_size = 10
	st.shadow_offset = Vector2(0, 4)
	b.add_theme_stylebox_override("normal", st)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 22
	h.offset_right = -16
	h.add_theme_constant_override("separation", 16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var ic := _label(icon, 42 if size.y > 90 else 34, Color.WHITE)
	ic.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var t := _label(title, 32 if size.y > 90 else 26, Color.WHITE)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var sl := _label(sub, 17, Color(1, 1, 1, 0.85))
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sl)
	b.pressed.connect(cb)
	return b


var play_panel: Control
var practice_panel: Control
var _menu_parts: Array[Control] = []   # hidden while the wardrobe is open


func _menu_modal(title: String) -> Array:
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.visible = false
	menu.add_child(holder)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.04, 0.12, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(c)
	var card := _card(CREAM)
	c.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var t := _label(title, 34, INK)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	var x := _btn("✕", MUTED, Vector2(52, 52), 24)
	x.pressed.connect(func(): holder.visible = false)
	top.add_child(x)
	return [holder, v]


func _build_play_panel() -> void:
	var m := _menu_modal("👫 Play together")
	play_panel = m[0]
	var v: VBoxContainer = m[1]
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	v.add_child(cols)
	# online
	var on := VBoxContainer.new()
	on.add_theme_constant_override("separation", 10)
	on.custom_minimum_size = Vector2(330, 0)
	cols.add_child(on)
	on.add_child(_label("🌐 Online", 26, INK))
	var ot := _label("From anywhere: send your partner the room code.", 17, MUTED)
	ot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	on.add_child(ot)
	var host_on := _btn("✨ Create a room", PINK, Vector2(0, 64), 24)
	host_on.pressed.connect(func(): play_panel.visible = false; create_room.emit(_name(), char_idx, settings["server"]))
	on.add_child(host_on)
	var jr := HBoxContainer.new()
	jr.add_theme_constant_override("separation", 8)
	on.add_child(jr)
	code_edit = _edit("CODE", 4)
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jr.add_child(code_edit)
	var join_on := _btn("Join", BLUE, Vector2(110, 64), 24)
	join_on.pressed.connect(func(): play_panel.visible = false; join_room.emit(code_edit.text.strip_edges().to_upper(), _name(), char_idx, settings["server"]))
	jr.add_child(join_on)
	var sep := VSeparator.new()
	cols.add_child(sep)
	# nearby
	var nb := VBoxContainer.new()
	nb.add_theme_constant_override("separation", 10)
	nb.custom_minimum_size = Vector2(330, 0)
	cols.add_child(nb)
	nb.add_child(_label("📶 Same Wi-Fi / hotspot", 26, INK))
	var nt := _label("No internet needed. Fastest when you're together.", 17, MUTED)
	nt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nb.add_child(nt)
	var host_b := _btn("📶 Host a game", PINK, Vector2(0, 64), 24)
	host_b.pressed.connect(func(): play_panel.visible = false; lan_host.emit(_name(), char_idx))
	nb.add_child(host_b)
	var find_b := _btn("🔎 Find a game", BLUE, Vector2(0, 64), 24)
	find_b.pressed.connect(func(): play_panel.visible = false; lan_find.emit(_name(), char_idx))
	nb.add_child(find_b)


func _build_practice_panel() -> void:
	var m := _menu_modal("🤖 Practice with a bot")
	practice_panel = m[0]
	var v: VBoxContainer = m[1]
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 14)
	v.add_child(r)
	var bh := _btn("🙈  I hide", ORANGE, Vector2(260, 84), 28)
	bh.pressed.connect(func(): practice_panel.visible = false; play_bot.emit(_name(), char_idx, "hide"))
	r.add_child(bh)
	var bs := _btn("👀  I seek", ORANGE, Vector2(260, 84), 28)
	bs.pressed.connect(func(): practice_panel.visible = false; play_bot.emit(_name(), char_idx, "seek"))
	r.add_child(bs)


func _show_menu_panel(p: Control) -> void:
	play_panel.visible = p == play_panel
	practice_panel.visible = p == practice_panel


# ---------- "nearby games" panel ----------

var find_panel: Control
var find_list: VBoxContainer
var find_status: Label
var ip_edit: LineEdit


func _build_find_panel() -> void:
	find_panel = Control.new()
	find_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	find_panel.visible = false
	root.add_child(find_panel)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.06, 0.14, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	find_panel.add_child(bg)
	var v := _centered_scroll(find_panel)
	var t := _label("🔎 Nearby games", 40, PINK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	find_status = _label("", 20, MUTED)
	find_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	find_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	find_status.custom_minimum_size = Vector2(520, 0)
	v.add_child(find_status)
	find_list = VBoxContainer.new()
	find_list.add_theme_constant_override("separation", 10)
	v.add_child(find_list)
	v.add_child(_label("Not showing up? Type the IP shown on your partner's screen:", 18, MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	ip_edit = _edit("192.168.43.1", 15)
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ip_edit)
	var go := _btn("Connect", BLUE, Vector2(150, 60), 24)
	go.pressed.connect(func(): if ip_edit.text.strip_edges() != "": lan_join.emit(ip_edit.text.strip_edges()))
	row.add_child(go)
	var cancel := _btn("Back", Color("#6f6478"), Vector2(0, 56), 22)
	cancel.pressed.connect(func(): find_panel.visible = false; lan_cancel.emit())
	v.add_child(cancel)


func show_find(found: Dictionary, status: String) -> void:
	find_panel.visible = true
	find_status.text = status
	for c in find_list.get_children():
		c.queue_free()
	for ip in found:
		var g: Dictionary = found[ip]
		var b := _btn("🎮 %s's game   ·   %d/4   ·   %s" % [g["name"], g["players"], ip], GREEN, Vector2(0, 70), 24)
		b.pressed.connect(func(): lan_join.emit(ip))
		find_list.add_child(b)
	if found.is_empty():
		find_list.add_child(_label("Looking for games...", 22, INK))


func hide_find() -> void:
	find_panel.visible = false


func _cycle_char(d: int) -> void:
	char_idx = posmod(char_idx + d, Kit.CHARS.size())
	_update_char_label()
	char_changed.emit(char_idx)


func _update_char_label() -> void:
	char_label.text = "%s  ·  %d of %d" % [Kit.CHAR_STYLES[char_idx]["name"], char_idx + 1, Kit.CHARS.size()]
	if wardrobe_open():
		_refresh_wardrobe.call_deferred()


func _upper_code(t: String) -> void:
	var up := t.to_upper()
	if up != t:
		var c := code_edit.caret_column
		code_edit.text = up
		code_edit.caret_column = c


func _name() -> String:
	var n := name_edit.text.strip_edges()
	return n if n != "" else "Player"


func show_menu(pname: String, idx: int, status := "") -> void:
	name_edit.text = pname
	char_idx = idx
	_update_char_label()
	status_label.text = status
	status_label.add_theme_color_override("font_color", Color("#ffb3b3"))
	play_panel.visible = false
	practice_panel.visible = false
	close_wardrobe()
	menu.visible = true
	lobby.visible = false
	hud.visible = false
	results.visible = false


func set_status(text: String, ok := false) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", Color("#b8ffcf") if ok else Color("#ffb3b3"))


# ---------- settings ----------

func _build_settings() -> void:
	settings_panel = Control.new()
	settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_panel.visible = false
	root.add_child(settings_panel)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.06, 0.14, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_panel.add_child(bg)
	var v := _centered_scroll(settings_panel)
	var t := _label("Settings", 44, PINK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	music_btn = _btn("", Color("#9b8fa6"), Vector2(0, 50), 20)
	music_btn.pressed.connect(func():
		settings["music_on"] = not settings.get("music_on", true)
		_refresh_fps_btn()
		settings_changed.emit(settings))
	v.add_child(music_btn)
	s_music = _slider(v, "🎵 Music volume", 0.0, 1.0)
	s_sfx = _slider(v, "🔊 Sound effects", 0.0, 1.0)
	s_sens = _slider(v, "👆 Look sensitivity", 0.3, 2.5)
	v.add_child(_label("✨ Graphics", 22, MUTED))
	var q := HBoxContainer.new()
	q.add_theme_constant_override("separation", 8)
	v.add_child(q)
	for i in 3:
		var b := _btn(["Smoothest", "Balanced", "Pretty"][i], BLUE, Vector2(0, 56), 22)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_quality.bind(i))
		q.add_child(b)
		s_quality.append(b)
	var mt := _label("🎮 Match rules (the room host's settings are used)", 22, PINK)
	mt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mt.custom_minimum_size = Vector2(520, 0)
	v.add_child(mt)
	s_hide = _value_slider(v, "🙈 Hiding time", 15, 120, 5, "hide", func(x): return "%d s" % x)
	s_seek = _value_slider(v, "👀 Seeking time", 60, 600, 30, "seek", func(x): return "%d:%02d" % [int(x) / 60, int(x) % 60])
	s_bananas = _value_slider(v, "🍌 Bananas each", 0, 6, 1, "bananas", func(x): return str(int(x)))
	s_smokes = _value_slider(v, "💨 Smoke bombs each", 0, 5, 1, "smokes", func(x): return str(int(x)))
	s_pillows = _value_slider(v, "🛏 Pillows each", 0, 15, 1, "pillows", func(x): return str(int(x)))
	s_xrays = _value_slider(v, "👁 X-Rays for the seeker", 0, 5, 1, "xrays", func(x): return str(int(x)))
	v.add_child(_label("🤖 Bot skill", 22, MUTED))
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 8)
	v.add_child(br)
	for i in 3:
		var b := _btn(["Easy", "Normal", "Hard"][i], BLUE, Vector2(0, 52), 22)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_bot.bind(i))
		br.add_child(b)
		s_bot.append(b)
	for tg in [["prints", "👣 Footprints for the seeker"], ["wiggle", "🌀 Disguises wiggle sometimes"], ["heat", "🌡 Hot/cold bar for the seeker"], ["halfping", "📡 Free radar at half time"]]:
		var tb := _btn("", Color("#9b8fa6"), Vector2(0, 50), 20)
		tb.pressed.connect(_toggle_rule.bind(tg[0]))
		tb.set_meta("label", tg[1])
		v.add_child(tb)
		s_toggles[tg[0]] = tb
	fps_btn = _btn("Show FPS: off", Color("#9b8fa6"), Vector2(0, 50), 20)
	fps_btn.pressed.connect(func(): settings["fps"] = not settings.get("fps", false); _refresh_fps_btn(); settings_changed.emit(settings))
	v.add_child(fps_btn)
	v.add_child(_label("🌐 Online server (both of you must use the same)", 20, MUTED))
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	v.add_child(srow)
	for opt in [["☁️ Render (Singapore)", Net.RENDER_SERVER], ["🖥 VPS (Mumbai)", Net.VPS_SERVER]]:
		var sb := _btn(opt[0], BLUE, Vector2(0, 50), 18)
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var url: String = opt[1]
		sb.pressed.connect(func():
			s_server.text = url
			settings["server"] = url
			settings_changed.emit(settings)
			Net.server_url = url
			Net.wake_server())
		srow.add_child(sb)
	s_server = _edit("wss://...", 200)
	s_server.add_theme_font_size_override("font_size", 20)
	s_server.text_changed.connect(func(tx): settings["server"] = tx.strip_edges(); settings_changed.emit(settings))
	v.add_child(s_server)
	var credits := _label(Music.CREDITS, 15, MUTED)
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credits.custom_minimum_size = Vector2(520, 0)
	v.add_child(credits)
	var close := _btn("Done", GREEN, Vector2(0, 62), 28)
	close.pressed.connect(func(): settings_panel.visible = false)
	v.add_child(close)


func _slider(v: VBoxContainer, text: String, lo: float, hi: float) -> HSlider:
	v.add_child(_label(text, 22, MUTED))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.custom_minimum_size = Vector2(0, 44)
	var grab := _box(PINK, 16, 0)
	grab.content_margin_left = 16
	grab.content_margin_top = 16
	s.add_theme_stylebox_override("slider", _box(Color("#ead8c8"), 6, 4))
	s.add_theme_stylebox_override("grabber_area", _box(PINK, 6, 4))
	s.add_theme_stylebox_override("grabber_area_highlight", _box(PINK, 6, 4))
	s.value_changed.connect(func(_x): _read_sliders())
	v.add_child(s)
	return s


func _value_slider(v: VBoxContainer, text: String, lo: float, hi: float, step: float, key: String, fmt: Callable) -> HSlider:
	var row := HBoxContainer.new()
	v.add_child(row)
	var l := _label(text, 22, MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var val := _label("", 22, INK)
	row.add_child(val)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.custom_minimum_size = Vector2(0, 44)
	sl.add_theme_stylebox_override("slider", _box(Color("#ead8c8"), 6, 4))
	sl.add_theme_stylebox_override("grabber_area", _box(PINK, 6, 4))
	sl.add_theme_stylebox_override("grabber_area_highlight", _box(PINK, 6, 4))
	sl.value_changed.connect(_on_value.bind(key, val, fmt))
	sl.set_meta("val", val)
	sl.set_meta("fmt", fmt)
	v.add_child(sl)
	return sl


func _on_value(x: float, key: String, val: Label, fmt: Callable) -> void:
	val.text = fmt.call(x)
	settings[key] = x
	settings_changed.emit(settings)


func _set_bot(i: int) -> void:
	settings["bot"] = i
	_refresh_rules()
	settings_changed.emit(settings)


func _toggle_rule(key: String) -> void:
	settings[key] = not settings.get(key, true)
	_refresh_rules()
	settings_changed.emit(settings)


func _refresh_rules() -> void:
	for k in s_bot.size():
		_style_btn(s_bot[k], PINK if k == int(settings.get("bot", 1)) else Color("#9b8fa6"))
	for key in s_toggles:
		var on: bool = settings.get(key, true)
		var b: Button = s_toggles[key]
		b.text = ("✅ " if on else "⬜ ") + str(b.get_meta("label"))
		_style_btn(b, GREEN if on else Color("#9b8fa6"))


func _read_sliders() -> void:
	settings["music"] = s_music.value
	settings["sfx"] = s_sfx.value
	settings["sens"] = s_sens.value
	settings_changed.emit(settings)


func _set_quality(i: int) -> void:
	settings["quality"] = i
	for k in s_quality.size():
		_style_btn(s_quality[k], PINK if k == i else Color("#9b8fa6"))
	settings_changed.emit(settings)


func _refresh_fps_btn() -> void:
	fps_btn.text = "Show FPS: on" if settings.get("fps", false) else "Show FPS: off"
	fps_label.visible = settings.get("fps", false)
	if music_btn:
		var on: bool = settings.get("music_on", true)
		music_btn.text = "🎵 Music: on" if on else "🔇 Music: off"
		_style_btn(music_btn, GREEN if on else Color("#9b8fa6"))


func apply_settings(s: Dictionary) -> void:
	settings = s
	_refresh_fps_btn()
	s_music.set_value_no_signal(s["music"])
	s_sfx.set_value_no_signal(s["sfx"])
	s_sens.set_value_no_signal(s["sens"])
	s_server.text = s["server"]
	for pair in [[s_hide, "hide"], [s_seek, "seek"], [s_bananas, "bananas"], [s_smokes, "smokes"], [s_pillows, "pillows"], [s_xrays, "xrays"]]:
		var sl: HSlider = pair[0]
		sl.set_value_no_signal(float(s.get(pair[1], sl.min_value)))
		(sl.get_meta("val") as Label).text = (sl.get_meta("fmt") as Callable).call(sl.value)
	_refresh_rules()
	for k in s_quality.size():
		_style_btn(s_quality[k], PINK if k == int(s["quality"]) else Color("#9b8fa6"))


func open_settings() -> void:
	settings_panel.visible = true


# ---------- lobby ----------

func _build_lobby() -> void:
	lobby = Control.new()
	lobby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lobby)
	var card := _card(Color(1, 0.968, 0.937, 0.94))
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.position.y = 14
	lobby.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	lobby_title = _label("Room ----", 44, PINK)
	lobby_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lobby_title)
	lobby_players = _label("", 22, INK)
	lobby_players.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lobby_players)
	lobby_hint = _label("", 18, MUTED)
	lobby_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lobby_hint)
	lobby_opts = VBoxContainer.new()
	v.add_child(lobby_opts)
	var mb := _btn("🎮 Match settings", PURPLE, Vector2(320, 50), 22)
	mb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mb.pressed.connect(open_settings)
	lobby_opts.add_child(mb)
	lobby_start = _btn("Start round", GREEN, Vector2(320, 60), 28)
	lobby_start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lobby_start.pressed.connect(func(): start_round.emit())
	v.add_child(lobby_start)
	lobby_chill = _btn("🌙 Chill together", Color("#5b3a8c"), Vector2(320, 56), 24)
	lobby_chill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lobby_chill.pressed.connect(func(): chill_together.emit())
	v.add_child(lobby_chill)


func _choice_row(parent: Control, text: String, labels: Array, cb: Callable) -> Array[Button]:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var l := _label(text, 18, MUTED)
	l.custom_minimum_size = Vector2(130, 0)
	row.add_child(l)
	var out: Array[Button] = []
	for i in labels.size():
		var b := _btn(labels[i], BLUE, Vector2(96, 42), 18, 14)
		b.pressed.connect(cb.bind(i))
		row.add_child(b)
		out.append(b)
	return out


func _refresh_opts() -> void:
	for i in hide_btns.size():
		_style_btn(hide_btns[i], PINK if [30.0, 45.0, 60.0][i] == hide_choice else Color("#9b8fa6"), 14)
	for i in seek_btns.size():
		_style_btn(seek_btns[i], PINK if [120.0, 180.0, 300.0][i] == seek_choice else Color("#9b8fa6"), 14)
	round_options.emit(hide_choice, seek_choice)


func show_lobby(code: String, players_text: String, is_host: bool, can_start: bool) -> void:
	menu.visible = false
	results.visible = false
	lobby.visible = true
	hud.visible = true
	lobby_title.text = "Room  " + code
	lobby_players.text = players_text
	lobby_start.visible = is_host
	lobby_opts.visible = is_host
	lobby_start.disabled = not can_start
	lobby_chill.visible = can_start and code != "Practice 🤖"
	if not can_start:
		lobby_hint.text = "Send the code to your partner. Walk around while you wait!"
	elif is_host:
		lobby_hint.text = "Everyone's here. Pick the times and start!"
	else:
		lobby_hint.text = "Waiting for the host to start the round..."
	timer_pill.visible = false
	role_label.text = ""


# ---------- HUD ----------

class Glyph extends Control:
	## White line icons for the movement buttons (no text).
	var kind := ""

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.2
		var col := Color(1, 1, 1, 0.95)
		var w := maxf(4.0, r * 0.28)
		match kind:
			"jump":
				draw_polyline(PackedVector2Array([c + Vector2(-r, r * 0.1), c + Vector2(0, -r * 0.9), c + Vector2(r, r * 0.1)]), col, w, true)
				draw_polyline(PackedVector2Array([c + Vector2(-r, r * 0.9), c + Vector2(0, -r * 0.1), c + Vector2(r, r * 0.9)]), Color(1, 1, 1, 0.6), w, true)
			"crouch":
				draw_polyline(PackedVector2Array([c + Vector2(-r, -r * 0.9), c + Vector2(0, 0), c + Vector2(r, -r * 0.9)]), Color(1, 1, 1, 0.6), w, true)
				draw_polyline(PackedVector2Array([c + Vector2(-r, -r * 0.1), c + Vector2(0, r * 0.8), c + Vector2(r, -r * 0.1)]), col, w, true)
				draw_line(c + Vector2(-r * 1.1, r * 1.15), c + Vector2(r * 1.1, r * 1.15), col, w, true)
			"run":
				draw_polyline(PackedVector2Array([c + Vector2(-r * 0.9, -r), c + Vector2(0, 0), c + Vector2(-r * 0.9, r)]), Color(1, 1, 1, 0.6), w, true)
				draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.9, 0), c + Vector2(0, r)]), col, w, true)


class RadarArrow extends Control:
	## A small ring around the centre dot with an arrow toward the nearest hider and the distance.
	var dir := Vector2.UP
	var col := Color.WHITE
	var text := ""

	func _draw() -> void:
		var c := size / 2.0
		var d := dir.normalized()
		var rad := 95.0
		var tip := c + d * (rad + 34.0)
		var side := Vector2(-d.y, d.x)
		draw_arc(c, rad, 0, TAU, 48, Color(col.r, col.g, col.b, 0.55), 6.0, true)
		draw_colored_polygon(PackedVector2Array([tip, tip - d * 40 + side * 24, tip - d * 26, tip - d * 40 - side * 24]), col)
		if text != "":
			var f := ThemeDB.fallback_font
			var fs := 30
			var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var p := c + Vector2(-w / 2.0, rad + 60.0)
			draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color("#2b2033"))
			draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


class Confetti extends Control:
	## Paper bits raining over the screen when someone pops confetti at you.
	var t := 0.0
	var bits := []

	func pop(dur: float) -> void:
		t = dur
		bits.clear()
		var cols := [Color("#ff4f86"), Color("#ffc23d"), Color("#3f86ff"), Color("#2fc77a"), Color("#a36bff")]
		for i in 140:
			bits.append([Vector2(randf() * size.x, randf_range(-size.y, size.y * 0.6)), randf_range(250, 520), cols[i % 5], randf() * TAU, randf_range(14, 30)])
		visible = true

	func _process(dt: float) -> void:
		if t <= 0.0:
			return
		t -= dt
		for b in bits:
			b[0].y += b[1] * dt
			b[0].x += sin(b[3] + t * 4.0) * 40.0 * dt
			b[3] += dt * 6.0
		if t <= 0.0:
			visible = false
		queue_redraw()

	func _draw() -> void:
		for b in bits:
			var p: Vector2 = b[0]
			var w: float = b[4]
			draw_set_transform(p, b[3], Vector2.ONE)
			draw_rect(Rect2(-w / 2.0, -w / 4.0, w, w / 2.0), b[2])
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


var heat_bar: Control
var heat_marker: Panel
var radar: RadarArrow
var confetti: Confetti
var smoke: ColorRect
var _smoke_t := 0.0
var tools_box: VBoxContainer
var tool_btns: Array[Button] = []
var tool_ids: Array[String] = []
var tool_cds: Array[Label] = []
var fun_btn: Button
var fun_panel: GridContainer
var tools_btn: Button
var tools_card: PanelContainer
var fun_card: PanelContainer
var fun_btns: Array[Button] = []
var fun_ids: Array[String] = []
var _radar_t := 0.0


func _icon_btn(icon: String, c: Color, d: float, fs: int) -> Button:
	var b := _btn(icon, c, Vector2(d, d), fs, int(d / 2.0))
	return b


func _glyph_btn(kind: String, d: float) -> Button:
	var b := _btn("", Color(0.1, 0.07, 0.14, 0.45), Vector2(d, d), 10, int(d / 2.0))
	var g := Glyph.new()
	g.kind = kind
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(g)
	var ring := _box(Color(0, 0, 0, 0), int(d / 2.0) - 3, 0)
	ring.corner_detail = 16
	ring.border_color = Color(1, 1, 1, 0.55)
	ring.set_border_width_all(3)
	ring.bg_color = Color(0.1, 0.07, 0.14, 0.4)
	b.add_theme_stylebox_override("normal", ring)
	var pressed := ring.duplicate()
	pressed.bg_color = Color(1, 1, 1, 0.3)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover", ring)
	return b


func _build_hud(_chat_lines: Array, _emotes: Array) -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)

	# soft cinematic vignette + a touch of warmth at the edges
	vignette = ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vsh := Shader.new()
	vsh.code = "shader_type canvas_item;\nvoid fragment(){ vec2 d = UV - vec2(0.5); float v = smoothstep(0.42, 0.95, length(d * vec2(1.25, 1.0))); COLOR = vec4(0.12, 0.05, 0.1, v * 0.42); }"
	var vmat := ShaderMaterial.new()
	vmat.shader = vsh
	vignette.material = vmat
	hud.add_child(vignette)

	danger = ColorRect.new()
	danger.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	danger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform float amount = 0.0;\nvoid fragment(){ float d = distance(UV, vec2(0.5)); COLOR = vec4(0.95, 0.12, 0.3, smoothstep(0.32, 0.78, d) * amount); }"
	var smat := ShaderMaterial.new()
	smat.shader = sh
	danger.material = smat
	hud.add_child(danger)

	dark = ColorRect.new()
	dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dsh := Shader.new()
	dsh.code = "shader_type canvas_item;\nuniform float amount = 0.0;\nuniform float hole = 0.0;\nuniform float aspect = 1.78;\nvoid fragment(){ float d = length((UV - vec2(0.5)) * vec2(aspect, 1.0)); float a = mix(1.0, smoothstep(0.18, 0.42, d), hole); COLOR = vec4(0.0, 0.0, 0.02, amount * a + hole * 0.35 * smoothstep(0.3, 0.6, d)); }"
	var dmat := ShaderMaterial.new()
	dmat.shader = dsh
	dark.material = dmat
	dark.visible = false
	hud.add_child(dark)

	slats = VBoxContainer.new()
	slats.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slats.add_theme_constant_override("separation", 26)
	for i in 30:
		var r := ColorRect.new()
		r.color = Color(0.1, 0.07, 0.05, 0.9)
		r.custom_minimum_size = Vector2(0, 16)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slats.add_child(r)
	slats.visible = false
	hud.add_child(slats)

	crosshair = Control.new()
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := Panel.new()
	dot.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.85), 6, 0))
	dot.size = Vector2(10, 10)
	dot.position = Vector2(-5, -5)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.add_child(dot)
	hud.add_child(crosshair)

	radar = RadarArrow.new()
	radar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radar.visible = false
	hud.add_child(radar)

	timer_pill = PanelContainer.new()
	timer_pill.add_theme_stylebox_override("panel", _box(GLASS, 30, 24))
	timer_pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	timer_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	timer_pill.position.y = 12
	timer_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(timer_pill)
	timer_label = _label("", 34, Color.WHITE)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_pill.add_child(timer_label)

	# hot / cold meter for the seeker: blue (far) to red (close), no words
	heat_bar = Control.new()
	heat_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	heat_bar.position = Vector2(-150, 80)
	heat_bar.size = Vector2(300, 16)
	heat_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := Gradient.new()
	grad.set_color(0, Color("#3fb4ff"))
	grad.set_color(1, Color("#ff3355"))
	grad.add_point(0.5, Color("#ffd23d"))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 8
	var bar := TextureRect.new()
	bar.texture = gt
	bar.stretch_mode = TextureRect.STRETCH_SCALE
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heat_bar.add_child(bar)
	heat_marker = Panel.new()
	var mk := _box(Color.WHITE, 8, 0)
	mk.border_color = INK
	mk.set_border_width_all(3)
	heat_marker.add_theme_stylebox_override("panel", mk)
	heat_marker.size = Vector2(16, 30)
	heat_marker.position = Vector2(0, -7)
	heat_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heat_bar.add_child(heat_marker)
	heat_bar.visible = false
	hud.add_child(heat_bar)

	role_label = _outlined(_label("", 22, Color.WHITE))
	role_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	role_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	role_label.position.y = 74
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(role_label)

	hint_label = _outlined(_label("", 30, Color.WHITE))
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_label.position.y = 108
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(hint_label)

	toast_label = _outlined(_label("", 44, Color.WHITE), 14)
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	toast_label.position.y -= 140
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.custom_minimum_size = Vector2(800, 0)
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(toast_label)

	top_left = HBoxContainer.new()
	top_left.position = Vector2(16, 14)
	top_left.add_theme_constant_override("separation", 8)
	hud.add_child(top_left)
	var leave_btn := _icon_btn("✕", GLASS, 54, 24)
	leave_btn.pressed.connect(func(): leave.emit())
	top_left.add_child(leave_btn)
	var gear := _icon_btn("⚙", GLASS, 54, 24)
	gear.pressed.connect(open_settings)
	top_left.add_child(gear)

	score_label = _outlined(_label("", 22, Color.WHITE), 8)
	score_label.position = Vector2(18, 76)
	hud.add_child(score_label)

	stick_base = Panel.new()
	var sb := _box(Color(1, 1, 1, 0.1), 95, 0)
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(3)
	stick_base.add_theme_stylebox_override("panel", sb)
	stick_base.size = Vector2(190, 190)
	stick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stick_base.visible = false
	hud.add_child(stick_base)
	stick_knob = Panel.new()
	stick_knob.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.6), 42, 0))
	stick_knob.size = Vector2(84, 84)
	stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stick_knob.visible = false
	hud.add_child(stick_knob)

	# bottom-right: big action button with jump / crouch / run around it
	var cluster := Control.new()
	cluster.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(cluster)
	main_btn = _icon_btn("", PINK, 150, 30)
	main_btn.position = Vector2(-180, -178)
	main_btn.pressed.connect(func(): if main_id != "": action.emit(main_id))
	cluster.add_child(main_btn)
	small_hint = _outlined(_label("", 18, Color.WHITE), 8)
	small_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	small_hint.size = Vector2(300, 26)
	small_hint.position = Vector2(-255, -280)
	small_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cluster.add_child(small_hint)
	jump_btn = _glyph_btn("jump", 112)
	jump_btn.position = Vector2(-306, -126)
	jump_btn.pressed.connect(func(): action.emit("jump"))
	cluster.add_child(jump_btn)
	crouch_btn = _glyph_btn("crouch", 92)
	crouch_btn.position = Vector2(-292, -236)
	crouch_btn.pressed.connect(func(): action.emit("crouch"))
	cluster.add_child(crouch_btn)
	run_btn = _glyph_btn("run", 86)
	run_btn.position = Vector2(-404, -104)
	run_btn.pressed.connect(func(): action.emit("run"))
	cluster.add_child(run_btn)
	alt_btn = _btn("", ORANGE, Vector2(150, 56), 22, 28)
	alt_btn.position = Vector2(-180, -250)
	alt_btn.pressed.connect(func(): if alt_id != "": action.emit(alt_id))
	alt_btn.visible = false
	cluster.add_child(alt_btn)

	# emote wheel: a smiley button on the left, opening a ring of reactions
	emote_btn = _icon_btn("😊", Color(0.1, 0.07, 0.14, 0.45), 74, 34)
	emote_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	emote_btn.position = Vector2(24, -330)
	emote_btn.pressed.connect(func(): _toggle_emotes(not emote_btns[0].visible))
	hud.add_child(emote_btn)
	var faces := ["😘", "😍", "😂", "🥺", "😡", "😴", "👋", "❤️"]
	for i in faces.size():
		var a := -PI / 2.0 + i * TAU / faces.size()
		var eb := _icon_btn(faces[i], Color(1, 1, 1, 0.92), 70, 36)
		eb.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		eb.position = Vector2(24 + 2, -330 + 2) + Vector2(cos(a), sin(a)) * 118 + Vector2(118, 0) * 0.0 + Vector2(130, 0)
		eb.visible = false
		var e: String = faces[i]
		eb.pressed.connect(func():
			_toggle_emotes(false)
			action.emit("emote:" + e))
		hud.add_child(eb)
		emote_btns.append(eb)

	fps_label = _outlined(_label("", 20, Color("#b9ffb0")), 8)
	fps_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	fps_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	fps_label.position += Vector2(-20, 16)
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(fps_label)
	latency_label = _outlined(_label("", 20, Color("#b9ffb0")), 8)
	latency_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	latency_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	latency_label.position += Vector2(-20, 84)
	latency_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	latency_label.visible = false
	root.add_child(latency_label)

	# top-right: two tidy buttons that open card panels (Tools for your role, Pranks for fun)
	var top_right := HBoxContainer.new()
	top_right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_right.position = Vector2(-20, 14)
	top_right.add_theme_constant_override("separation", 10)
	hud.add_child(top_right)
	tools_btn = _btn("🧰 Tools", Color(0.37, 0.27, 0.85, 0.92), Vector2(160, 58), 24, 29)
	tools_btn.pressed.connect(_toggle_panel.bind("tools"))
	top_right.add_child(tools_btn)
	fun_btn = _btn("😜 Pranks", Color(1.0, 0.5, 0.2, 0.92), Vector2(160, 58), 24, 29)
	fun_btn.pressed.connect(_toggle_panel.bind("fun"))
	top_right.add_child(fun_btn)

	tools_card = _panel_card("🧰 Tools")
	hud.add_child(tools_card)
	var tg: GridContainer = tools_card.get_meta("grid")
	for i in 14:
		var b := _btn("", Color(0.37, 0.27, 0.85, 0.95), Vector2(200, 56), 21, 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_tool.bind(i))
		b.visible = false
		tg.add_child(b)
		tool_btns.append(b)
		tool_ids.append("")
		tool_cds.append(null)

	fun_card = _panel_card("😜 Pranks")
	hud.add_child(fun_card)
	fun_panel = fun_card.get_meta("grid")
	for i in 9:
		var b := _btn("", Color(1.0, 0.5, 0.2, 0.95), Vector2(200, 62), 22, 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_fun.bind(i))
		b.visible = false
		fun_panel.add_child(b)
		fun_btns.append(b)
		fun_ids.append("")

	confetti = Confetti.new()
	confetti.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confetti.mouse_filter = Control.MOUSE_FILTER_IGNORE
	confetti.visible = false
	hud.add_child(confetti)

	smoke = ColorRect.new()
	smoke.color = Color(0.92, 0.92, 0.9, 0.0)
	smoke.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	smoke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	smoke.visible = false
	hud.add_child(smoke)

	blind = ColorRect.new()
	blind.color = Color("#120c16")
	blind.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blind.visible = false
	hud.add_child(blind)
	blind_label = _label("", 64, Color.WHITE)
	blind_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blind_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	blind_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blind.add_child(blind_label)
	hud.move_child(top_left, -1)


func _panel_card(title: String) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := _box(Color(0.1, 0.07, 0.14, 0.82), 24, 16)
	sb.border_color = Color(1, 1, 1, 0.15)
	sb.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", sb)
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	card.position = Vector2(-20, 84)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	var t := _label(title, 22, Color(1, 1, 1, 0.85))
	v.add_child(t)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	card.set_meta("grid", grid)
	card.visible = false
	return card


func _toggle_panel(which: String) -> void:
	var open_tools := which == "tools" and not tools_card.visible
	var open_fun := which == "fun" and not fun_card.visible
	tools_card.visible = open_tools
	fun_card.visible = open_fun


func close_panels() -> void:
	tools_card.visible = false
	fun_card.visible = false


func _on_tool(i: int) -> void:
	close_panels()
	if tool_ids[i] != "":
		action.emit(tool_ids[i])


func _on_fun(i: int) -> void:
	if fun_ids[i] != "":
		close_panels()
		action.emit(fun_ids[i])


func _fill(btns: Array[Button], ids: Array[String], items: Array, cds: Array = []) -> void:
	for i in btns.size():
		var b := btns[i]
		if i < items.size():
			var it: Dictionary = items[i]
			ids[i] = it["id"]
			var cd: float = it.get("cd", 0.0)
			var txt := "%s %s" % [it["icon"], it.get("name", "")]
			if cd > 0.0:
				txt = "%s %ds" % [it["icon"], ceili(cd)]
			if b.text != txt:
				b.text = txt
			b.disabled = not it.get("enabled", true)
			b.visible = true

		else:
			b.visible = false
			ids[i] = ""


## main / alt: {id, icon, color, enabled} or {}. tools / fun: Array of {id, icon, enabled, cd}
func set_controls(main: Dictionary, tools: Array, fun: Array, show_move: bool, crouch_on: bool, run_on: bool, alt := {}) -> void:
	if main.is_empty():
		main_btn.visible = false
		main_id = ""
	else:
		main_btn.visible = true
		main_id = main["id"]
		var mt := "%s\n%s" % [main["icon"], main.get("name", "")]
		if main_btn.text != mt:
			main_btn.text = mt
		main_btn.disabled = not main.get("enabled", true)
		var c: Color = main.get("color", PINK)
		if main_btn.get_meta("c", Color.BLACK) != c:
			main_btn.set_meta("c", c)
			_style_btn(main_btn, c, 75)
	if alt.is_empty():
		alt_btn.visible = false
		alt_id = ""
	else:
		alt_btn.visible = true
		alt_id = alt["id"]
		alt_btn.text = "%s %s" % [alt["icon"], alt.get("name", "")]
	jump_btn.visible = show_move
	crouch_btn.visible = show_move
	run_btn.visible = show_move
	var flags := "%s%s" % [crouch_on, run_on]
	if flags != _last_flags:
		_last_flags = flags
		for pair in [[crouch_btn, crouch_on], [run_btn, run_on]]:
			var st: StyleBoxFlat = (pair[0] as Button).get_theme_stylebox("normal").duplicate()
			st.bg_color = Color(1.0, 0.31, 0.53, 0.7) if pair[1] else Color(0.1, 0.07, 0.14, 0.4)
			(pair[0] as Button).add_theme_stylebox_override("normal", st)
			(pair[0] as Button).add_theme_stylebox_override("hover", st)
	_fill(tool_btns, tool_ids, tools)
	tools_btn.visible = not tools.is_empty()
	if tools.is_empty():
		tools_card.visible = false
	fun_btn.visible = not fun.is_empty()
	if fun.is_empty():
		fun_card.visible = false
	_fill(fun_btns, fun_ids, fun)


## heat: 0 = far away (cold) .. 1 = right next to you (hot); negative hides the meter.
func set_heat(heat: float) -> void:
	heat_bar.visible = heat >= 0.0
	if heat >= 0.0:
		heat_marker.position.x = lerpf(heat_marker.position.x, clampf(heat, 0.0, 1.0) * (heat_bar.size.x - 16.0), 0.2)


func show_radar(dir: Vector2, col: Color, dur := 3.0, text := "") -> void:
	radar.dir = dir
	radar.col = col
	radar.text = text
	close_panels()
	radar.visible = true
	radar.queue_redraw()
	_radar_t = dur


func pop_smoke(dur := 2.8) -> void:
	_smoke_t = dur
	smoke.visible = true


func pop_confetti(dur := 2.0) -> void:
	confetti.pop(dur)


func show_play() -> void:
	menu.visible = false
	lobby.visible = false
	results.visible = false
	hud.visible = true
	timer_pill.visible = true


func set_hint_small(text: String) -> void:
	small_hint.text = text


func set_timer(text: String) -> void:
	timer_label.text = text
	timer_pill.visible = text != ""


func set_role(text: String, c := Color.WHITE) -> void:
	role_label.text = text
	role_label.add_theme_color_override("font_color", c)


func set_scores(text: String) -> void:
	score_label.text = text


func set_hint(text: String) -> void:
	hint_label.text = text


func toast(text: String, dur := 2.6) -> void:
	toast_label.text = text
	toast_label.modulate.a = 1.0
	_toast_t = dur


func set_stick(active: bool, center := Vector2.ZERO, offset := Vector2.ZERO) -> void:
	stick_base.visible = active
	stick_knob.visible = active
	if active:
		stick_base.position = center - stick_base.size / 2.0
		stick_knob.position = center + offset - stick_knob.size / 2.0


func set_blind(on: bool, text := "") -> void:
	blind.visible = on
	blind_label.text = text


func set_slats(on: bool) -> void:
	slats.visible = on


func set_vignette(on: bool) -> void:
	vignette.visible = on


func set_dark(amount: float, flashlight: bool) -> void:
	dark.visible = amount > 0.0
	var m := dark.material as ShaderMaterial
	var vs := root.get_viewport_rect().size
	m.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	m.set_shader_parameter("amount", 0.92 if flashlight else amount)
	m.set_shader_parameter("hole", 1.0 if flashlight else 0.0)


func set_danger(a: float) -> void:
	(danger.material as ShaderMaterial).set_shader_parameter("amount", a)


## In-game buttons are pressed straight from touch events, so they work with any finger
## (Godot only turns the FIRST finger into button clicks, which broke jump while steering).
func _game_buttons() -> Array:
	var out: Array = []
	out.append_array(tool_btns)  # cards sit on top, check them first
	out.append_array(fun_btns)
	out.append_array(emote_btns)
	out.append_array([main_btn, alt_btn, jump_btn, crouch_btn, run_btn, fun_btn, tools_btn, emote_btn])
	for c in top_left.get_children():
		if c is Button:
			out.append(c)
	return out


func _toggle_emotes(on: bool) -> void:
	for i in emote_btns.size():
		var b := emote_btns[i]
		b.visible = on
		if on:
			b.pivot_offset = b.size / 2.0
			b.scale = Vector2(0.3, 0.3)
			var tw := b.create_tween()
			tw.tween_interval(i * 0.02)
			tw.tween_property(b, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func enable_multitouch() -> void:
	for b in _game_buttons():
		(b as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func touch_button_at(pos: Vector2) -> Button:
	if menu.visible or settings_panel.visible or (find_panel and find_panel.visible):
		return null
	for b in _game_buttons():
		if b.is_visible_in_tree() and b.get_global_rect().grow(6).has_point(pos):
			return b
	return null


func tap(b: Button) -> void:
	if b.disabled:
		return
	b.pivot_offset = b.size / 2.0
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2(0.88, 0.88), 0.05)
	tw.tween_property(b, "scale", Vector2.ONE, 0.1)
	print("TOUCHDBG tap '%s' f=%d" % [b.text, Engine.get_process_frames()])
	b.pressed.emit()


func is_over_ui(pos: Vector2) -> bool:
	if menu.visible or settings_panel.visible or (find_panel and find_panel.visible):
		return true
	var ctrls: Array = [main_btn, alt_btn, jump_btn, crouch_btn, run_btn, fun_btn, tools_btn, tools_card, fun_card, lobby_start, res_next, res_lobby]
	ctrls.append_array(top_left.get_children())
	ctrls.append_array(tool_btns)
	ctrls.append_array(fun_btns)
	ctrls.append_array(hide_btns)
	ctrls.append_array(seek_btns)
	for c in ctrls:
		if c.is_visible_in_tree() and c.get_global_rect().grow(8).has_point(pos):
			return true
	return false


# ---------- results ----------

func _build_results() -> void:
	results = CenterContainer.new()
	results.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(results)
	var card := _card()
	card.custom_minimum_size = Vector2(540, 0)
	results.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)
	res_title = _label("", 48, PINK)
	res_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(res_title)
	res_body = _label("", 24, INK)
	res_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	res_body.custom_minimum_size = Vector2(480, 0)
	v.add_child(res_body)
	res_next = _btn("Next round (swap roles)", GREEN, Vector2(0, 66), 26)
	res_next.pressed.connect(func(): next_round.emit())
	v.add_child(res_next)
	res_lobby = _btn("Back to the room", BLUE, Vector2(0, 56), 22)
	res_lobby.pressed.connect(func(): back_to_lobby.emit())
	v.add_child(res_lobby)
	res_wait = _label("Waiting for the host...", 20, MUTED)
	res_wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(res_wait)
	results.visible = false


func show_results(title: String, body: String, is_host: bool) -> void:
	results.visible = true
	res_title.text = title
	res_body.text = body
	res_next.visible = is_host
	res_lobby.visible = is_host
	res_wait.visible = not is_host
	set_blind(false)
	set_slats(false)


func hide_results() -> void:
	results.visible = false


func _process(dt: float) -> void:
	if _smoke_t > 0.0:
		_smoke_t -= dt
		smoke.color.a = clampf(_smoke_t / 1.2, 0.0, 0.97)
		if _smoke_t <= 0.0:
			smoke.visible = false
	if _radar_t > 0.0:
		_radar_t -= dt
		radar.modulate.a = clampf(_radar_t, 0.0, 1.0)
		if _radar_t <= 0.0:
			radar.visible = false
	if fps_label.visible and Engine.get_process_frames() % 20 == 0:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	latency_label.visible = Net.state == "open"
	if latency_label.visible:
		latency_label.text = "Ping: %d ms" % Net.latency_ms if Net.latency_ms >= 0 else "Ping: measuring…"
	if _toast_t > 0.0:
		_toast_t -= dt
		toast_label.modulate.a = clampf(_toast_t * 2.0, 0.0, 1.0)


# ---------- wardrobe ----------

const TOPS := ["#ff94c4", "#86c8ff", "#b99bff", "#ffd166", "#7ee0b0", "#ff7a7a", "#ffffff", "#3b3550"]
const ACCS := [["", "✖\nNone"], ["bow", "🎀\nBow"], ["flower", "🌸\nFlower"], ["rose", "🌹\nRose"], ["cap", "🧢\nCap"], ["crown", "👑\nCrown"], ["headphones", "🎧\nMusic"], ["sunglasses", "😎\nShades"]]
var _ward_rows := {}


var _ward_name: Label
var _ward_swatches := {}   # "top"/"bottom"/"acc" -> [[button, value], ...]


func _build_wardrobe() -> void:
	wardrobe = PanelContainer.new()
	var sb := _box(Color(1.0, 0.98, 0.95, 0.96), 30, 18)
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 18
	wardrobe.add_theme_stylebox_override("panel", sb)
	wardrobe.anchor_left = 1.0
	wardrobe.anchor_right = 1.0
	wardrobe.anchor_top = 0.0
	wardrobe.anchor_bottom = 1.0
	wardrobe.offset_left = -560
	wardrobe.offset_right = -24
	wardrobe.offset_top = 20
	wardrobe.offset_bottom = -20
	wardrobe.visible = false
	menu.add_child(wardrobe)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	wardrobe.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 7)
	scroll.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var t := _label("👗 Wardrobe", 30, INK)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	var done_x := _btn("✓", GREEN, Vector2(50, 48), 26)
	done_x.pressed.connect(close_wardrobe)
	top.add_child(done_x)
	# who you're dressing
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 8)
	v.add_child(who)
	var prev := _btn("◀", PURPLE, Vector2(52, 44), 22)
	prev.pressed.connect(func(): _cycle_char(-1))
	who.add_child(prev)
	_ward_name = _label("", 24, INK)
	_ward_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ward_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ward_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(_ward_name)
	var nxt := _btn("▶", PURPLE, Vector2(52, 44), 22)
	nxt.pressed.connect(func(): _cycle_char(1))
	who.add_child(nxt)
	for row in [["top", "👕 Top"], ["bottom", "👖 Bottom / extra"]]:
		v.add_child(_label(row[1], 19, MUTED))
		var grid := GridContainer.new()
		grid.columns = 9
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		v.add_child(grid)
		var key: String = row[0]
		var list := []
		var reset := _btn("↺", Color("#c9bfd2"), Vector2(50, 46), 22)
		reset.tooltip_text = "Original"
		reset.pressed.connect(func(): _set_outfit(key, null))
		grid.add_child(reset)
		list.append([reset, null])
		for col in TOPS:
			var b := _btn("", Color(col), Vector2(50, 46), 22)
			var cc := Color(col)
			b.pressed.connect(func(): _set_outfit(key, cc))
			grid.add_child(b)
			list.append([b, cc])
		_ward_swatches[key] = list
	v.add_child(_label("✨ Accessory", 19, MUTED))
	var ag := GridContainer.new()
	ag.columns = 4
	ag.add_theme_constant_override("h_separation", 10)
	ag.add_theme_constant_override("v_separation", 10)
	v.add_child(ag)
	var alist := []
	for a in ACCS:
		var ab := _btn(a[1], PURPLE, Vector2(112, 72), 18)
		var ak: String = a[0]
		ab.pressed.connect(func(): _set_outfit("acc", ak))
		ag.add_child(ab)
		alist.append([ab, ak])
	_ward_swatches["acc"] = alist
	var done := _btn("Done 💜", GREEN, Vector2(0, 52), 24)
	done.pressed.connect(close_wardrobe)
	v.add_child(done)


## The dressing room: the menu steps aside and the camera comes in close on your character.
func open_wardrobe() -> void:
	for c in _menu_parts:
		c.visible = false
	wardrobe.visible = true
	_refresh_wardrobe()


func close_wardrobe() -> void:
	wardrobe.visible = false
	for c in _menu_parts:
		c.visible = true


func wardrobe_open() -> bool:
	return wardrobe != null and wardrobe.visible


## Outline the picks that are on right now.
func _refresh_wardrobe() -> void:
	if _ward_name:
		_ward_name.text = Kit.CHAR_STYLES[char_idx]["name"]
	for key in _ward_swatches:
		var cur = outfit.get(key, null if key != "acc" else null)
		for pair in _ward_swatches[key]:
			var b: Button = pair[0]
			var val = pair[1]
			var on := false
			if key == "acc":
				on = (str(cur) == str(val)) if cur != null else val == "" and not outfit.has("acc")
				if not outfit.has("acc"):
					on = false
			elif val == null:
				on = cur == null
			elif cur != null:
				on = (Color(str(cur)) if not (cur is Color) else cur).is_equal_approx(val)
			var st: StyleBoxFlat = b.get_theme_stylebox("normal").duplicate()
			st.border_color = INK
			st.set_border_width_all(4 if on else 0)
			b.add_theme_stylebox_override("normal", st)


func _set_outfit(key: String, value) -> void:
	if value == null:
		outfit.erase(key)
	else:
		outfit[key] = value
	outfit_changed.emit(outfit.duplicate())
	_refresh_wardrobe()
