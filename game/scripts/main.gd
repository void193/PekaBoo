extends Node3D
## Game rules, input, graphics settings and message handling.
## The room host runs the clock (start / seek / end). Every phone simulates its own player
## and shares its state 15 times a second; tricks and catches travel as small "fx" messages.

const SLOT_COLORS := [Color("#ff4f86"), Color("#3f86ff"), Color("#ffc23d"), Color("#2fc77a")]
const EMOTES := ["❤️", "😘", "😂", "😜", "👋", "🙈"]
const CHAT := ["Can't find me! 😜", "I'm right here 😘", "Ready or not! 😈", "Cold... so cold ❄️", "Getting warm? 🔥", "Peekaboo! 🙈", "Too slow 🐢", "Come find me 💕"]
const C_SEEK := Color("#e8453c")
const C_HIDE := Color("#8a5cf0")
const C_PROP := Color("#1fb070")
const PILLOWS := 5

var house: House
var me: Player
var ui: UI
var env: Environment
var sun: DirectionalLight3D
var remotes := {}  # id -> RemotePlayer
var bot: Bot
var chill: Chill
var extras: Extras

var phase := "menu"  # menu, explore, lobby, hide, seek, results
var seeker_id := -1
var round_no := 0
var phase_left := 0.0
var caught := {}
var scores := {}
var hide_time := 45.0
var seek_time := 180.0
var teases := 0

var my_name := ""
var my_char := 0
var settings := {"music": 0.7, "sfx": 0.9, "sens": 1.0, "quality": 1, "server": "", "fps": false,
	"hide": 45.0, "seek": 180.0, "bot": 1, "prints": true, "wiggle": true, "heat": true, "halfping": true,
	"bananas": 2, "smokes": 2, "pillows": 5, "xrays": 3}
const RULE_KEYS := ["hide", "seek", "bot", "prints", "wiggle", "heat", "halfping", "bananas", "smokes", "pillows", "xrays"]
var rules := {}  # the host's rules for the current round

var items := {}  # key -> {kind, node, pos}
var item_counter := 0
var pillows := []  # {node, vel, mine, life}
var footprints := []  # {node, life}
var trail := []
var lights_off := 0.0
var cd := {}
var uses := {}

var is_touch := false
var stick_index := -1
var stick_center := Vector2.ZERO
var stick_vec := Vector2.ZERO
var look_index := -1
var _send_t := 0.0
var _ui_t := 0.0
var _beat_t := 0.0
var _trail_t := 0.0
var _last_beep := -1
var _hurry := false
var _date_override := Vector2i.ZERO
var _chill_args: PackedStringArray = []
var _snap_out := ""
var _menu_panel := ""


## Desktop preview of chill mode: --chillshot=x,y,z,yaw,pitch,dist,mode  (mode: look / kiss / hug / dance / sit / fw)
func _chill_shot() -> void:
	var v := _chill_args
	_on_chill_solo("Lumi", my_char)
	# a stand-in partner that moves itself like a real player would
	var her := Player.new()
	add_child(her)
	her.setup(5, house)
	remotes[99] = her
	her.cam.queue_free()
	her.cam = Camera3D.new()
	me.cam.make_current()
	var mode := v[6] if v.size() > 6 else "look"
	var at := Vector3(float(v[0]), float(v[1]), float(v[2]))
	me.teleport(at, float(v[3]))
	me.pitch = float(v[4])
	me.cam_dist = float(v[5])
	her.teleport(at + Vector3(0.6, 0, -0.3), 0.0)
	await get_tree().create_timer(1.0).timeout
	match mode:
		"kiss", "hug", "dance":
			chill.start_together(mode, me, her, at + Vector3(0.4, 0, 0), -PI / 2.0)
		"sit", "sitg", "sitfront":
			var first := 2 if mode == "sitg" or OS.get_environment("SIDECAM") == "garden" else 0
			chill.sit(me, first)
			chill.sit(her, first + 1)
			if mode == "sitfront":
				me.yaw = float(v[8]) if v.size() > 8 else PI
				me.pitch = float(v[4])
			if OS.has_environment("SIDECAM"):
				var oc := Camera3D.new()
				oc.projection = Camera3D.PROJECTION_ORTHOGONAL
				oc.size = 2.6
				add_child(oc)
				var ctr := House.PICNIC + Vector3(0, 0.9, -1.5) if first == 2 else Vector3(8.0, 0.9, 12.3)
				oc.global_position = ctr - Vector3(1.8, 0, 0)
				oc.look_at(ctr)
				oc.make_current()
				ui.hud.visible = false
		"groove":
			me.dance()
		"top":
			var oc := Camera3D.new()
			oc.projection = Camera3D.PROJECTION_ORTHOGONAL
			oc.size = 9.0
			add_child(oc)
			oc.look_at_from_position(House.PICNIC + Vector3(0, 12, 1.5), House.PICNIC + Vector3(0, 0, 1.5), Vector3(0, 0, 1))
			oc.make_current()
			ui.hud.visible = false
		"gaze":
			me.teleport(House.PICNIC + Vector3(0, 0.1, 0.9), 0.0)
			extras._start_gaze()
			chill.set_heart(true)
		"rain", "snow":
			extras.set_weather(mode)
		"skytext":
			extras._sky_text("I LOVE YOU")
		"cook":
			remotes.erase(99)
			extras.action("cook")
		"wheel":
			ui._toggle_emotes(true)
		"ward":
			ui.open_wardrobe()
		"pets":
			var cat: Node3D = extras.pets.pets[0]["node"]
			cat.global_position = at + Vector3(0, -0.1, -1.3)
			extras.pets.pets[0]["target"] = cat.global_position
			var dog: Node3D = extras.pets.pets[1]["node"]
			dog.global_position = at + Vector3(0.9, -0.1, -1.6)
			extras.pets.pets[1]["target"] = dog.global_position
		"fw":
			chill.fireworks(7)
		"lantern":
			for k in 4:
				chill.lantern(at + Vector3(k * 0.7 - 1.0, -1.0 - k * 1.2, 1.0 + k))
	if v.size() > 8:
		# measuring: hide one kind of effect (fireflies / halos / sky)
		for c in chill._decor.get_children():
			if (v[8] == "noflies" and c is CPUParticles3D) or (v[8] == "nohalo" and c is MeshInstance3D and c.material_override is StandardMaterial3D and (c.material_override as StandardMaterial3D).blend_mode == BaseMaterial3D.BLEND_MODE_ADD):
				c.visible = false
		if v[8] == "nosky":
			env.sky.sky_material = PanoramaSkyMaterial.new()
	await get_tree().create_timer(float(v[7]) if v.size() > 7 else 2.5).timeout
	if _snap_out != "":
		get_viewport().get_texture().get_image().save_png(_snap_out)
	get_tree().quit()
var _ended := false
var _preview_t := 0.0
var _aim := {}

# automated test mode (desktop): --autotest=host|join --codefile=PATH, or --shot=x,z,yaw,pitch[,y]
var auto := ""
var auto_file := ""
var auto_t := 0.0
var auto_done := false
var auto_lan := false
var bench_quality := -1
var _bench := {"i": -1, "t": 0.0, "frames": 0, "draws": 0, "results": []}
var _fps_log_t := 0.0
var _warm_i := 0
var _exp_nolights := false
var _exp_nochar := false
var _exp_plainfont := false
var _exp_scale := 1.0
var _reset_profile := false
var _shot_args := PackedStringArray()
var _loading: ColorRect
const BENCH_VIEWS := [
	[12.0, 0.1, -9.0, PI, -0.05], [11.5, 0.1, 3.0, PI, -0.2], [8.5, 0.1, 13.5, 0.0, -0.2], [15.0, 0.1, 13.0, 2.6, -0.25],
	[4.5, 3.3, 4.5, 0.0, -0.3], [18.0, 3.3, 13.0, -1.2, -0.25], [-6.0, 0.1, 6.0, 2.4, -0.2], [20.0, 0.1, 19.0, PI, -0.1],
]


func _ready() -> void:
	randomize()
	is_touch = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_parse_args()
	_load_cfg()
	if _reset_profile:
		my_name = ""
		settings["quality"] = 1 if is_touch else 2
		_save_cfg()
	_setup_world()

	# the fancy surface shader is for "Pretty"; Balanced uses the lean built-in material
	House.detail_on = int(settings["quality"]) >= 2
	Kit.ui_font()  # bundles colour emoji as a fallback before anything draws text
	house = House.new()
	house.bake_out = "--bake-out" in OS.get_cmdline_user_args()
	if house.bake_out:
		house.baked.connect(func(): get_tree().quit())
	add_child(house)
	me = Player.new()
	add_child(me)
	me.setup(my_char, house)
	chill = Chill.new()
	add_child(chill)
	chill.setup(self, house)

	ui = UI.new()
	add_child(ui)
	ui.build(CHAT, EMOTES)
	if is_touch:
		ui.enable_multitouch()
	ui.apply_settings(settings)
	ui.create_room.connect(_on_create)
	ui.join_room.connect(_on_join)
	ui.explore.connect(_on_explore)
	ui.play_bot.connect(_on_play_bot)
	ui.lan_host.connect(_on_lan_host)
	ui.lan_find.connect(_on_lan_find)
	ui.lan_join.connect(_on_lan_join)
	ui.lan_cancel.connect(func(): Lan.stop_listening())
	Lan.found_changed.connect(_refresh_find)
	ui.char_changed.connect(_on_char_changed)
	ui.start_round.connect(_host_start)
	ui.chill_together.connect(func(): Net.broadcast({"t": "chill"}))
	ui.outfit_changed.connect(_on_outfit)
	extras = Extras.new()
	add_child(extras)
	extras.setup(self, house, chill)
	ui.chill_solo.connect(_on_chill_solo)
	ui.next_round.connect(_host_start)
	ui.back_to_lobby.connect(func(): Net.broadcast({"t": "lobby"}))
	ui.leave.connect(_leave)
	ui.action.connect(_do_action)
	ui.settings_changed.connect(_on_settings)
	ui.round_options.connect(_on_round_options)
	Net.message.connect(_on_net)
	Net.disconnected.connect(_on_disconnected)
	_apply_settings()
	_apply_outfit()
	if _is_anniversary():
		house.baked.connect(chill.build_anniversary, CONNECT_ONE_SHOT) if not house.is_baked else chill.build_anniversary()
	_to_menu("")
	if auto == "" or auto == "bench" or auto.begins_with("shot"):
		_start_warmup()
	if auto == "qa":
		var qa: Node = load("res://scripts/qa.gd").new()
		add_child(qa)
		qa.call_deferred("run")
	elif auto == "bench":
		_on_explore("Bench", my_char)
		if _exp_nochar:
			me.visual.visible = false
			me.set_process(false)
		if "--hidechar" in OS.get_cmdline_args() + OS.get_cmdline_user_args():
			me.rig.visible = false
		me.no_probe = "--noprobe" in OS.get_cmdline_args() + OS.get_cmdline_user_args()
		me.no_boom = "--noboom" in OS.get_cmdline_args() + OS.get_cmdline_user_args()
		if _exp_plainfont:
			ui.root.theme.default_font = null
	elif auto == "shotfun":
		_on_explore("Lumi", my_char)
		me.teleport(Vector3(8.5, 0.1, 13.5), 0.0)
	elif auto == "shotset":
		ui.open_settings()
	elif auto == "shot":
		_shot_args = auto_file.split(",")
	elif auto != "":
		_log("autotest " + auto + " server=" + Net.server_url)


## Shows every corner of the house once behind a loading screen so all shaders are
## compiled up front, instead of stuttering the first time you walk into a room.
func _start_warmup() -> void:
	_loading = ColorRect.new()
	_loading.color = Color(0.992, 0.984, 0.937)
	_loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var art := TextureRect.new()
	art.texture = load("res://splash.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(art)
	var bar := ProgressBar.new()
	bar.name = "bar"
	bar.show_percentage = false
	# a thin line between the name and the peeking face
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	# a slim pink bar under the logo
	bar.anchor_top = 0.9
	bar.anchor_bottom = 0.9
	bar.offset_left = -160
	bar.offset_right = 160
	bar.offset_top = -4
	bar.offset_bottom = 4
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.07, 0.14, 0.1)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#ff2d6f")
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	_loading.add_child(bar)
	ui.root.add_child(_loading)
	_warm_i = 1


func _warm_tick() -> void:
	if not house.is_baked:
		return
	var views := BENCH_VIEWS.size() * 4
	var bar := _loading.get_node_or_null("bar") as ProgressBar
	if bar:
		bar.value = 100.0 * _warm_i / views
	if _warm_i > views:
		_warm_i = 0
		_loading.queue_free()
		if auto == "":
			_to_menu("")
		elif auto == "shot":
			var v := _shot_args
			_on_explore("Lumi", my_char)
			me.teleport(Vector3(float(v[0]), float(v[4]) if v.size() > 4 else 0.1, float(v[1])), float(v[2]))
			me.pitch = float(v[3]) if v.size() > 3 else -0.25
			if v.size() > 5:
				me.cam_dist = float(v[5])
			if v.size() > 6:
				me.enter_spot(int(v[6]), house.hide_spots[int(v[6])])
				me.pitch = float(v[3])
		elif auto == "shotmenu":
			_to_menu("")
			if _menu_panel == "play":
				ui._show_menu_panel(ui.play_panel)
			elif _menu_panel == "practice":
				ui._show_menu_panel(ui.practice_panel)
			await get_tree().create_timer(2.0).timeout
			if _snap_out != "":
				get_viewport().get_texture().get_image().save_png(_snap_out)
				get_tree().quit()
		elif auto == "shotchill":
			_chill_shot()
		elif auto == "shotfun" or auto == "shottv" or auto == "shottools":
			_on_explore("Lumi", my_char)
			me.teleport(Vector3(8.5, 0.1, 13.5), 0.0)
			ui.fun_card.visible = auto == "shotfun"
			ui.tools_card.visible = auto == "shottools"
			if auto == "shottv":
				me.teleport(Vector3(9.3, 0.1, 11.2), 0.15)
				me.pitch = -0.05
				me.cam_dist = 1.8
				house.set_tv(true, 0)
		return
	var v: Array = BENCH_VIEWS[(_warm_i - 1) / 4]
	me.teleport(Vector3(v[0], v[1], v[2]), v[3] + ((_warm_i - 1) % 4) * PI / 2.0)
	me.pitch = v[4]
	_warm_i += 1


func _on_char_changed(i: int) -> void:
	my_char = i
	me.set_char(i)
	_save_cfg()
	_apply_outfit()


func _on_round_options(h: float, s: float) -> void:
	hide_time = h
	seek_time = s


func _setup_world() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load("res://assets/tex/sky.hdr")
	sky.sky_material = pano
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.ambient_light_sky_contribution = 0.75
	env.ambient_light_color = Color("#ffe9d6")
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.35
	sun.light_color = Color("#fff1dc")
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 45.0
	sun.shadow_bias = 0.04
	add_child(sun)


# ---------- settings ----------

func _parse_args() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a in args:
		if a == "--bench":
			auto = "bench"
		elif a == "--nolights":
			_exp_nolights = true
		elif a.begins_with("--scale="):
			_exp_scale = float(a.substr(8))
		elif a == "--oldchar":
			CharRig.use_probe_look = false
		elif a == "--nochar":
			_exp_nochar = true
		elif a == "--plainfont":
			_exp_plainfont = true
		elif a == "--reset-profile":
			_reset_profile = true
		elif a.begins_with("--quality="):
			bench_quality = int(a.substr(10))
		elif a.begins_with("--server="):
			settings["server"] = a.substr(9)
		elif a.begins_with("--bottest="):
			auto = "bot" + a.substr(10)
		elif a.begins_with("--autotest="):
			auto = a.substr(11)
		elif a.begins_with("--date="):
			var md := a.substr(7).split("-")
			_date_override = Vector2i(int(md[0]), int(md[1]))
		elif a == "--qa":
			auto = "qa"
		elif a == "--lan":
			auto_lan = true
		elif a.begins_with("--codefile="):
			auto_file = a.substr(11)
		elif a.begins_with("--menushot"):
			auto = "shotmenu"
			_menu_panel = a.substr(11) if a.length() > 11 else ""
		elif a.begins_with("--chillshot="):
			auto = "shotchill"
			_chill_args = a.substr(12).replace(":", ",").split(",")
		elif a.begins_with("--snapout="):
			_snap_out = a.substr(10)
		elif a == "--shotfun" or a == "--shotset" or a == "--shottv" or a == "--shottools":
			auto = a.substr(2)
		elif a.begins_with("--shot="):
			auto = "shot"
			auto_file = a.substr(7)


func _load_cfg() -> void:
	var cf := ConfigFile.new()
	cf.load("user://settings.cfg")
	my_name = cf.get_value("p", "name", "")
	my_char = clampi(int(cf.get_value("p", "char", randi() % Kit.CHARS.size())), 0, Kit.CHARS.size() - 1)
	var override: String = settings["server"]
	settings["music"] = float(cf.get_value("s", "music", 0.7))
	settings["sfx"] = float(cf.get_value("s", "sfx", 0.9))
	settings["sens"] = float(cf.get_value("s", "sens", 1.0))
	settings["quality"] = int(cf.get_value("s", "quality", 1 if is_touch else 2))
	settings["fps"] = bool(cf.get_value("s", "fps", false))
	settings["music_on"] = bool(cf.get_value("s", "music_on", true))
	settings["outfits"] = cf.get_value("p", "outfits", {})
	for k in RULE_KEYS:
		settings[k] = cf.get_value("r", k, settings[k])
	# X-ray got stronger: move people on the old default (2) to the new default (3) once
	if int(cf.get_value("r", "rules_version", 1)) < 2 and int(settings["xrays"]) == 2:
		settings["xrays"] = 3
	if bench_quality >= 0:
		settings["quality"] = bench_quality
	var saved := str(cf.get_value("s", "server", Net.DEFAULT_SERVER))
	# old builds saved the local test address; move them to the online default
	if saved == "" or saved.contains("127.0.0.1"):
		saved = Net.DEFAULT_SERVER
	settings["server"] = override if override != "" else saved


func _save_cfg() -> void:
	if auto != "" and not _reset_profile:
		return
	var cf := ConfigFile.new()
	cf.set_value("p", "name", my_name)
	cf.set_value("p", "char", my_char)
	cf.set_value("p", "outfits", settings.get("outfits", {}))
	for k in ["music", "sfx", "sens", "quality", "server", "fps", "music_on"]:
		cf.set_value("s", k, settings[k])
	for k in RULE_KEYS:
		cf.set_value("r", k, settings[k])
	cf.set_value("r", "rules_version", 2)
	cf.save("user://settings.cfg")


func _on_settings(s: Dictionary) -> void:
	settings = s.duplicate()
	_apply_settings()
	_save_cfg()


func _apply_settings() -> void:
	Net.server_url = settings["server"]
	if auto == "":
		hide_time = float(settings["hide"])
		seek_time = float(settings["seek"])
	Music.enabled = bool(settings.get("music_on", true))
	Sfx.set_volume("Music", settings["music"] if Music.enabled else 0.0)
	Sfx.set_volume("SFX", settings["sfx"])
	var vp := get_viewport()
	Engine.max_fps = 60
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.anisotropic_filtering_level = Viewport.ANISOTROPY_DISABLED
	sun.shadow_enabled = false
	env.glow_enabled = false
	match int(settings["quality"]):
		0:
			vp.scaling_3d_scale = 0.6 if is_touch else 0.75
		1:
			vp.scaling_3d_scale = (0.72 if is_touch else 1.0) * _exp_scale
		_:
			vp.scaling_3d_scale = 0.95 if is_touch else 1.0
			vp.anisotropic_filtering_level = Viewport.ANISOTROPY_4X


func _apply_profile(pname: String, idx: int, server := "") -> void:
	my_name = pname
	my_char = idx
	if server.strip_edges() != "":
		settings["server"] = server.strip_edges()
	Net.server_url = settings["server"]
	me.set_char(my_char)
	_save_cfg()


# ---------- menu flow ----------

var _woke := false


func _to_menu(status: String) -> void:
	if not _woke and auto == "":
		_woke = true
		Net.server_url = settings["server"]
		Net.wake_server()
	_leave_chill()
	phase = "menu"
	if bot != null:
		bot.queue_free()
		bot = null
	if Net.is_offline():
		Net.close()
	Net.connect_timeout = 90.0
	_clear_round()
	for id in remotes.keys():
		remotes[id].queue_free()
	remotes.clear()
	me.reset_round_state()
	me.frozen = true
	me.role = ""
	me.teleport(Vector3(12.0, 0.05, -9.0), PI)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_menu(my_name, my_char, status)
	if _is_anniversary():
		ui.anniv_label.text = "💜 Happy Anniversary, you two 💜"
	else:
		var dd := _days_to_anniversary()
		ui.anniv_label.text = "💜 %d day%s to our anniversary" % [dd, "" if dd == 1 else "s"]
	Music.play("menu")


func _on_create(pname: String, idx: int, server: String) -> void:
	_apply_profile(pname, idx, server)
	ui.set_status("Connecting... a sleeping server can take up to a minute to wake up.", true)
	Net.open({"t": "create", "name": my_name, "color": my_char})


func _on_join(code: String, pname: String, idx: int, server: String) -> void:
	if code.length() != 4:
		ui.set_status("Type the 4-letter room code your partner sees on their screen.")
		return
	_apply_profile(pname, idx, server)
	ui.set_status("Connecting... a sleeping server can take up to a minute to wake up.", true)
	Net.open({"t": "join", "room": code, "name": my_name, "color": my_char})


func _on_explore(pname: String, idx: int) -> void:
	_apply_profile(pname, idx)
	phase = "explore"
	_reset_my_round()
	me.frozen = false
	me.role = "hider"
	me.teleport(house.hider_spawns[0], PI)
	_restore_camera()
	ui.show_play()
	ui.set_timer("")
	ui.set_role("")
	ui.set_scores("")
	Music.play("hide")
	_capture_mouse()


# ---------- chill mode ----------

func _on_chill_solo(pname: String, idx: int) -> void:
	_apply_profile(pname, idx)
	_enter_chill()


func _enter_chill() -> void:
	_clear_round()
	phase = "chill"
	_reset_my_round()
	me.frozen = false
	me.role = ""
	var ids := Net.players.keys()
	ids.sort()
	var n := maxi(0, ids.find(Net.my_id))
	me.teleport(Vector3(7.4 + n * 1.3, 0.1, 10.0), PI * 0.85)
	for r in remotes.values():
		r.reset_round_state()
		r.show_name = true
	_restore_camera()
	ui.show_play()
	ui.set_timer("")
	ui.set_role("")
	ui.set_scores("")
	ui.tools_btn.text = "💞 Together"
	chill.enter()
	if _is_anniversary():
		get_tree().create_timer(3.0).timeout.connect(func():
			if phase == "chill":
				ui.toast("💜 Happy Anniversary 💜", 5.0)
				chill.fireworks(int(Time.get_unix_time_from_system()) / 600, 16))
	_capture_mouse()


func _leave_chill() -> void:
	if chill == null or not chill.on:
		return
	me.stand_up()
	extras.reset()
	chill.exit()
	ui.tools_btn.text = "🧰 Tools"
	ui.set_timer("")


func _partner() -> Node3D:
	for r in remotes.values():
		return r
	return null


func _chill_controls() -> Array:
	var main := {}
	var tools := []
	var partner := _partner()
	var near := partner != null and _flat_dist(partner.global_position, me.global_position) < 2.4 and absf(partner.global_position.y - me.global_position.y) < 1.0
	var busy := chill.busy()
	if busy:
		return [main, tools, [], false, {}]
	var ctx: Dictionary = extras.context()
	var alt := {}
	var seat := chill.seat_near(me.global_position)
	if not chill.pending.is_empty() and partner != null:
		var w: String = chill.pending["w"]
		main = {"id": "c" + w, "icon": {"kiss": "💋", "hug": "🤗", "dance": "💃", "hands": "🤝"}[w], "name": {"kiss": "Kiss back", "hug": "Hug back", "dance": "Let's dance", "hands": "Hold hands"}[w], "color": Color("#e0457b")}
	elif ctx.get("id", "") in ["none", "letgo", "pfthrow"]:
		main = ctx
	elif me.sitting:
		main = {"id": "stand", "icon": "🧍", "name": "Get up" if me.lying else "Stand up", "color": C_PROP}
	elif near:
		main = {"id": "ckiss", "icon": "💋", "name": "Kiss", "color": Color("#e0457b")}
		if not ctx.is_empty():
			alt = ctx
		elif seat >= 0:
			alt = {"id": "sit", "icon": "🛋", "name": "Sit"}
	elif not ctx.is_empty():
		main = ctx
		if seat >= 0:
			alt = {"id": "sit", "icon": "🛋", "name": "Sit"}
	elif seat >= 0:
		main = {"id": "sit", "icon": "🛋", "name": "Sit", "color": C_PROP}
	if partner != null:
		tools.append(_tool("chug", "🤗", "Hug"))
		tools.append(_tool("cdance", "💃", "Slow dance"))
	tools.append_array(extras.tools(partner))
	tools.append(_tool("lantern", "🏮", "Sky lantern", "lantern"))
	tools.append(_tool("fireworks", "🎆", "Fireworks", "fireworks"))
	tools.append(_tool("wish", "🌠", "Make a wish", "wish"))
	tools.append(_tool("nextsong", "🎵", "Next song", "nextsong"))
	var near_tv := _flat_dist(me.global_position, house.tv_pos) < 2.6 and me.global_position.y < 1.5
	if near_tv or (me.sitting and me.global_position.z > 12.0 and me.global_position.z < 13.0):
		tools.insert(0, _tool("tv", "📺", "TV"))  # first, so it's never the one that doesn't fit
	return [main, tools, [], not me.sitting, alt]


## Ask for a kiss / hug / dance, or say yes if they already asked.
func _chill_ask(w: String) -> void:
	var partner := _partner()
	if partner == null:
		ui.toast("This one needs your partner 💜")
		return
	if chill.pending.get("w", "") == w:
		var a: int = chill.pending["from"]
		chill.pending.clear()
		var pa := partner.global_position
		var pb := me.global_position
		var d := Vector3(pb.x - pa.x, 0, pb.z - pa.z)
		if d.length() < 0.01:
			d = Vector3.FORWARD
		d = d.normalized()
		var c := (pa + pb) * 0.5
		c.y = minf(pa.y, pb.y)
		_fx({"k": "together", "w": w, "a": a, "b": Net.my_id, "c": [c.x, c.y, c.z], "y": atan2(-d.x, -d.z)})
		return
	if _flat_dist(partner.global_position, me.global_position) > 2.6:
		ui.toast("Go to %s first 💜" % _player_name(int(_partner_id())))
		return
	chill.asked = {"w": w, "t": Time.get_ticks_msec() / 1000.0}
	_fx({"k": "ask", "w": w})
	ui.toast({"kiss": "💋 Waiting for a kiss back...", "hug": "🤗 Arms open...", "dance": "💃 Waiting for your partner...", "hands": "🤝 Hand out..."}[w], 3.0)


func _on_outfit(o: Dictionary) -> void:
	var out := {}
	for k in o:
		out[k] = (o[k] as Color).to_html(false) if o[k] is Color else str(o[k])
	var all: Dictionary = settings.get("outfits", {})
	all[str(my_char)] = out
	settings["outfits"] = all
	_save_cfg()
	_apply_outfit()


func _apply_outfit() -> void:
	var o: Dictionary = settings.get("outfits", {}).get(str(my_char), {})
	ui.outfit = o.duplicate()
	me.set_outfit(_outfit_in(o))
	if Net.is_online():
		_fx({"k": "outfit", "o": o})


func _outfit_in(o) -> Dictionary:
	var out := {}
	if o is Dictionary:
		for k in o:
			out[k] = Color(str(o[k])) if k in ["top", "bottom"] else str(o[k])
	return out


func set_music_on(on: bool) -> void:
	settings["music_on"] = on
	_apply_settings()
	_save_cfg()
	ui.apply_settings(settings)
	ui.toast("🎵 Music on" if on else "🔇 Music off", 1.5)


## Both phones play song i, starting now.
func send_song(i: int) -> void:
	_fx({"k": "song", "i": posmod(i, maxi(1, Music.songs.size()))})


func _partner_id() -> int:
	for id in remotes.keys():
		return id
	return -1


func _is_anniversary() -> bool:
	var d := _today()
	return d.x == 2 and d.y == 2


func _today() -> Vector2i:
	if _date_override != Vector2i.ZERO:
		return _date_override
	var t := Time.get_date_dict_from_system()
	return Vector2i(int(t["month"]), int(t["day"]))


func _days_to_anniversary() -> int:
	var d := Time.get_date_dict_from_system()
	var today := Time.get_unix_time_from_datetime_dict({"year": d["year"], "month": d["month"], "day": d["day"], "hour": 12, "minute": 0, "second": 0})
	if _date_override != Vector2i.ZERO:
		today = Time.get_unix_time_from_datetime_dict({"year": d["year"], "month": _date_override.x, "day": _date_override.y, "hour": 12, "minute": 0, "second": 0})
	for yy in [int(d["year"]), int(d["year"]) + 1]:
		var t := Time.get_unix_time_from_datetime_dict({"year": yy, "month": 2, "day": 2, "hour": 12, "minute": 0, "second": 0})
		if t >= today:
			return roundi((t - today) / 86400.0)
	return 0


# ---------- hotspot / Wi-Fi play ----------

func _on_lan_host(pname: String, idx: int) -> void:
	_apply_profile(pname, idx)
	Lan.stop_listening()
	if not Lan.start_host(my_name):
		ui.set_status("Couldn't start hosting. Close other games using the network and try again.")
		return
	Net.connect_timeout = 10.0
	Net.server_url = "ws://127.0.0.1:%d" % Lan.PORT
	Net.open({"t": "create", "name": my_name, "color": my_char})


func _on_lan_find(pname: String, idx: int) -> void:
	_apply_profile(pname, idx)
	if not Lan.start_listening():
		ui.show_find({}, "Can't search on this network. Type your partner's IP below instead.")
		return
	_refresh_find()


func _refresh_find() -> void:
	if not Lan.listening:
		return
	var tip := "Connect to your partner's hotspot (or the same Wi-Fi), and their game shows up here."
	ui.show_find(Lan.found, tip)


func _on_lan_join(ip: String) -> void:
	Lan.stop_listening()
	ui.hide_find()
	Net.connect_timeout = 10.0
	Net.server_url = "ws://%s:%d" % [ip, Lan.PORT]
	ui.set_status("Joining %s..." % ip, true)
	Net.open({"t": "join", "room": "LAN", "name": my_name, "color": my_char})


func _lan_ip_text() -> String:
	var ips := Lan.local_ips()
	return ", ".join(ips) if not ips.is_empty() else "no network yet"


func _on_play_bot(pname: String, idx: int, my_role: String) -> void:
	_apply_profile(pname, idx)
	var bot_char := (idx + 1 + randi() % (Kit.CHARS.size() - 1)) % Kit.CHARS.size()
	Net.start_offline(my_name, my_char, Bot.NAMES.pick_random(), bot_char)
	_add_remote(Bot.ID)
	bot = Bot.new()
	add_child(bot)
	bot.setup(self, remotes[Bot.ID])
	bot.skill = int(settings["bot"])
	scores = {}
	round_no = 0 if my_role == "seek" else 1
	_to_lobby()
	_host_start()


## Messages the bot "sends": delivered locally as if they came from player 2.
func _bot_fx(m: Dictionary) -> void:
	m["t"] = "fx"
	_on_fx(m, Bot.ID)


func _bot_catch_player() -> void:
	_on_caught(Net.my_id, Bot.ID)


func _leave() -> void:
	if phase == "chill" and Net.is_online():
		Net.broadcast({"t": "lobby"})
		return
	Net.close()
	Lan.stop_host()
	_to_menu("")


func _on_disconnected(reason: String) -> void:
	if Net.server_url.begins_with("ws://") and not Net.server_url.contains("127.0.0.1") and reason.begins_with("Lost"):
		reason = "Your partner's game closed, or you left their hotspot."
	elif Lan.hosting and reason.begins_with("Lost"):
		reason = "The game stopped hosting."
	_log("disconnected: " + reason + " -> back to menu")
	Lan.stop_host()
	_to_menu(reason)


func _lobby_refresh() -> void:
	var names := []
	var ids := Net.players.keys()
	ids.sort()
	for id in ids:
		var n: String = Net.players[id]["name"]
		if id == Net.host_id:
			n += " 👑"
		if id == Net.my_id:
			n += " (you)"
		names.append(n)
	if Net.is_offline():
		ui.show_lobby("Practice 🤖", "  ·  ".join(names), true, true)
	elif Net.room == "LAN":
		ui.show_lobby("📶 Hotspot game", "  ·  ".join(names), Net.is_host(), Net.players.size() >= 2)
		if Net.players.size() < 2 and Lan.hosting:
			ui.lobby_hint.text = "Turn on your hotspot. Your partner connects to it and taps 🔎 Join a game.\nYour IP: " + _lan_ip_text()
	else:
		ui.show_lobby(Net.room, "  ·  ".join(names), Net.is_host(), Net.players.size() >= 2)
	ui.set_scores(_score_text())


func _to_lobby() -> void:
	_leave_chill()
	phase = "lobby"
	_clear_round()
	_reset_my_round()
	me.role = ""
	for r in remotes.values():
		r.reset_round_state()
		r.show_name = true
	_restore_camera()
	_lobby_refresh()
	Music.play("menu")
	_capture_mouse()


func _restore_camera() -> void:
	me.shoulder = 0.55
	me.cam_dist = 4.0
	me.visual.rotation.y = me.yaw


func _reset_my_round() -> void:
	me.reset_round_state()
	var rr: Dictionary = rules if not rules.is_empty() else settings
	uses = {"banana": int(rr["bananas"]), "cushion": 1, "lights": 1, "pillow": int(rr["pillows"]), "smoke": int(rr["smokes"]), "xray": int(rr.get("xrays", 3))}
	cd.clear()
	teases = 0
	trail.clear()
	ui.set_slats(false)


# ---------- network ----------

func _on_net(m: Dictionary) -> void:
	var t := str(m.get("t", ""))
	var from := int(m.get("from", -1))
	match t:
		"welcome":
			for id in Net.players:
				if id != Net.my_id:
					_add_remote(id)
			_log("welcome room=" + Net.room + " id=" + str(Net.my_id))
			if auto == "host" and auto_file != "":
				var f := FileAccess.open(auto_file, FileAccess.WRITE)
				f.store_string(Net.room)
				f.close()
			me.teleport(house.hider_spawns[Net.my_id % house.hider_spawns.size()], PI)
			_to_lobby()
			_apply_outfit()
		"peer_join":
			var pid := int(m["id"])
			_add_remote(pid)
			ui.toast(str(m["name"]) + " joined! 💕")
			_apply_outfit()
			Sfx.play("confirm")
			_log("peer_join " + str(pid))
			if phase == "lobby":
				_lobby_refresh()
		"peer_leave":
			var pid := int(m["id"])
			var who := "Your partner"
			if remotes.has(pid):
				who = remotes[pid].player_name
				remotes[pid].queue_free()
				remotes.erase(pid)
			ui.toast(who + " left the game.")
			_log("peer_leave %d, now in %s" % [pid, "lobby" if phase in ["hide", "seek", "results"] else phase])
			if phase in ["hide", "seek", "results"]:
				_to_lobby()
			elif phase == "lobby":
				_lobby_refresh()
		"host":
			if phase == "lobby":
				_lobby_refresh()
		"st":
			if _sync.has("ages") and m.has("ts"):
				_sync["ages"].append(posmod(int(Time.get_unix_time_from_system() * 1000.0) % 1000000 - int(m["ts"]), 1000000))
			_ensure_remote(from)
			if not replay.is_empty():
				_held_states[from] = m
			elif remotes.has(from):
				remotes[from].apply_state(m)
		"hi":
			_on_hi(m, from)
		"start":
			_on_start(m)
		"phase":
			_on_seek_phase(m)
		"caught":
			_on_caught(int(m["id"]), from)
		"end":
			_on_end(m)
		"lobby":
			_to_lobby()
		"chill":
			_enter_chill()
		"fx":
			_ensure_remote(from)
			_on_fx(m, from)


## Someone we hear from must be in the game, even if we missed them joining.
func _ensure_remote(id: int) -> void:
	if id < 0 or id == Net.my_id or remotes.has(id) or Net.is_offline():
		return
	if not Net.players.has(id):
		Net.players[id] = {"name": "Partner", "color": 0}
	_add_remote(id)


## Every 1.5 s each phone says what it looks like and (from the host) what's going on, so
## anything a phone missed - a mode change, the song, the weather, an outfit - fixes itself.
var _hi_t := 0.0


func _send_hi(dt: float) -> void:
	if not Net.is_online() or Net.is_offline() or phase == "menu":
		return
	_hi_t -= dt
	if _hi_t > 0.0:
		return
	_hi_t = 1.5
	var m := {"t": "hi", "name": my_name, "c": my_char, "o": settings.get("outfits", {}).get(str(my_char), {}), "ph": phase}
	if Net.is_host():
		m["song"] = Music.song_index()
		m["w"] = extras.weather
	Net.send(m)


func _on_hi(m: Dictionary, from: int) -> void:
	if from == Net.my_id:
		return
	_ensure_remote(from)
	var r: RemotePlayer = remotes.get(from)
	if r == null:
		return
	r.last_heard = Time.get_ticks_msec() / 1000.0
	# name, character and outfit
	var nm := str(m.get("name", ""))
	if nm != "" and Net.players.has(from) and Net.players[from]["name"] != nm:
		Net.players[from]["name"] = nm
		r.player_name = nm
		r._label.text = nm
	var c := int(m.get("c", r.char_index)) % Kit.CHARS.size()
	var o := _outfit_in(m.get("o", {}))
	if c != r.char_index or str(o) != str(r.outfit):
		r.char_index = c
		r.outfit = o
		r._rebuild()
	# the host keeps everyone in the same mode, song and weather
	if from != Net.host_id:
		return
	var hp := str(m.get("ph", ""))
	if hp == "chill" and phase in ["lobby", "results"]:
		_enter_chill()
	elif hp == "lobby" and phase == "chill":
		_to_lobby()
	if phase == "chill":
		var song := int(m.get("song", -1))
		if song >= 0 and song != Music.song_index():
			Music.play_song(song)
		var w := str(m.get("w", "clear"))
		if w != extras.weather:
			extras.set_weather(w)


func _add_remote(id: int) -> void:
	if remotes.has(id) or not Net.players.has(id):
		return
	var p: Dictionary = Net.players[id]
	var r := RemotePlayer.new()
	add_child(r)
	var ids := Net.players.keys()
	ids.sort()
	r.setup(id, p["name"], int(p["color"]) % Kit.CHARS.size(), SLOT_COLORS[ids.find(id) % SLOT_COLORS.size()], house)
	r.global_position = house.hider_spawns[0]
	remotes[id] = r


func _player_name(id: int) -> String:
	if id == Net.my_id:
		return my_name
	if Net.players.has(id):
		return Net.players[id]["name"]
	return "Someone"


# ---------- rounds ----------

func _host_start() -> void:
	if not Net.is_host() or Net.players.size() < 2:
		return
	var ids := Net.players.keys()
	ids.sort()
	var seeker: int = ids[round_no % ids.size()]
	var r := {}
	for k in RULE_KEYS:
		r[k] = settings[k]
	Net.broadcast({"t": "start", "seeker": seeker, "round": round_no + 1, "hide": hide_time, "seek": seek_time, "rules": r})


func _on_start(m: Dictionary) -> void:
	Music.new_round()
	_clear_round()
	seeker_id = int(m["seeker"])
	round_no = int(m["round"])
	rules = settings.duplicate()
	var mr = m.get("rules", {})
	if mr is Dictionary:
		for k in mr:
			rules[k] = mr[k]
	hide_time = float(m["hide"])
	seek_time = float(m["seek"])
	phase = "hide"
	phase_left = hide_time
	_ended = false
	caught.clear()
	_last_beep = -1
	_half_ping = false
	_wiggle_t = randf_range(20.0, 30.0)
	_reset_my_round()
	_restore_camera()
	ui.show_play()
	for r in remotes.values():
		r.reset_round_state()
		r.show_name = true
	var ids := Net.players.keys()
	ids.sort()
	if Net.my_id == seeker_id:
		me.role = "seeker"
		me.teleport(house.seeker_spawn, PI / 2.0)
		me.frozen = true
		ui.set_role("👀", Color.WHITE)
		ui.set_blind(true, "🙈")
	else:
		me.role = "hider"
		me.teleport(house.hider_spawns[ids.find(Net.my_id) % house.hider_spawns.size()], PI)
		me.frozen = false
		ui.set_role("🤫", Color.WHITE)
		ui.toast("🏃 Hide!")
	Music.play("hide")
	Sfx.play("hidestart", -2.0)
	_hurry = false
	if bot != null:
		bot.on_round_start("seeker" if seeker_id == Bot.ID else "hider")
	_log("start round=%d seeker=%d me=%s" % [round_no, seeker_id, me.role])
	_capture_mouse()


func _on_seek_phase(m: Dictionary) -> void:
	if phase != "hide":
		return
	phase = "seek"
	phase_left = float(m.get("seek", seek_time))
	if bot != null:
		bot.on_seek()
	Sfx.say("go")
	Music.play("seek")
	if me.role == "seeker":
		me.frozen = false
		ui.set_blind(false)
		ui.toast("😈 Go!")
		for r in remotes.values():
			r.show_name = false
	else:
		ui.toast("👀 🤫")
	_log("seek phase")


func _hiders() -> Array:
	var out := []
	for id in Net.players.keys():
		if id != seeker_id:
			out.append(id)
	return out


func _on_caught(id: int, by: int) -> void:
	if caught.has(id) or phase != "seek":
		return
	caught[id] = true
	Sfx.play("catch")
	Sfx.play("gasp", -6.0)
	if id == Net.my_id or me.role == "seeker":
		_start_replay(id)
	if bot != null:
		bot.on_caught(id)
	if id == Net.my_id:
		if me.hide_spot >= 0:
			me.exit_spot()
			ui.set_slats(false)
		me.set_ghost(true)
		ui.toast("👻 Found!")
		ui.set_role("👻", Color.WHITE)
	else:
		if remotes.has(id):
			remotes[id].set_ghost(true)
			remotes[id].show_name = true
		ui.toast("🎉 " + _player_name(id))
	_log("caught " + str(id))
	if Net.is_host():
		var left := 0
		for h in _hiders():
			if not caught.has(h):
				left += 1
		if left == 0:
			_host_end("seeker")


# ---------- slow-motion replay of the moment you were found ----------

const REPLAY_KEEP := 3.0      # seconds of play we remember
const REPLAY_SPAN := 1.7      # how much of it the replay shows...
const REPLAY_LEN := 3.6       # ...stretched over this long
var _rec: Array = []          # [time, {id: [pos, yaw]}]
var _rec_t := 0.0
var replay := {}
var _held_end := {}           # an "end" message that arrived during the replay
var _held_states := {}        # latest network state per player during the replay


func _record(dt: float) -> void:
	_rec_t += dt
	if _rec.size() > 0 and _rec_t - float(_rec[_rec.size() - 1][0]) < 1.0 / 30.0:
		return
	var snap := {Net.my_id: [me.global_position, me.visual.rotation.y]}
	for rid in remotes:
		var r: RemotePlayer = remotes[rid]
		snap[rid] = [r.global_position, r._visual.rotation.y]
	_rec.append([_rec_t, snap])
	while _rec.size() > 0 and _rec_t - float(_rec[0][0]) > REPLAY_KEEP:
		_rec.pop_front()


func _start_replay(caught_id: int) -> void:
	if _rec.size() < 10 or not replay.is_empty():
		return
	var target := _actor(caught_id)
	replay = {"t": 0.0, "frames": _rec.duplicate(), "end": _rec_t, "target": target, "me_pos": me.global_position, "me_yaw": me.visual.rotation.y}
	me.frozen = true
	Music.slowmo(true)
	chill._cinema(true)
	ui.toast("🔁 REPLAY", REPLAY_LEN)


func _replay_tick(dt: float) -> void:
	replay["t"] += dt
	var k: float = minf(float(replay["t"]) / REPLAY_LEN, 1.0)
	var frames: Array = replay["frames"]
	var at: float = float(replay["end"]) - REPLAY_SPAN + REPLAY_SPAN * k
	# find the two recorded moments around 'at' and blend between them
	var a: Array = frames[0]
	var b: Array = frames[frames.size() - 1]
	for i in frames.size() - 1:
		if float(frames[i + 1][0]) >= at:
			a = frames[i]
			b = frames[i + 1]
			break
	var f := clampf((at - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001), 0.0, 1.0)
	for pid in a[1]:
		if not b[1].has(pid):
			continue
		var p: Vector3 = (a[1][pid][0] as Vector3).lerp(b[1][pid][0], f)
		var y := lerp_angle(float(a[1][pid][1]), float(b[1][pid][1]), f)
		var who := _actor(pid)
		if who is Player:
			(who as Player).global_position = p
			(who as Player).visual.rotation.y = y
		elif who is RemotePlayer:
			(who as RemotePlayer).global_position = p
			(who as RemotePlayer)._visual.rotation.y = y
	# a slow, low orbit around the one who got caught
	var target: Node3D = replay["target"] if is_instance_valid(replay["target"]) else me
	var c := target.global_position + Vector3(0, 0.9, 0)
	var ang := 0.6 + k * 1.2
	var want := c + Vector3(cos(ang) * 3.2, 1.0, sin(ang) * 3.2)
	var cam: Camera3D = chill._cam
	cam.global_position = cam.global_position.lerp(c + (want - c) * chill._cam_room(c, want - c), 0.12)
	cam.look_at(c, Vector3.UP)
	if k >= 1.0:
		_end_replay()


func _end_replay() -> void:
	var rp := replay
	replay = {}
	me.global_position = rp.get("me_pos", me.global_position)
	me.visual.rotation.y = rp.get("me_yaw", me.visual.rotation.y)
	me.frozen = me.role == "seeker" and phase == "hide"
	Music.slowmo(false)
	chill._cinema(false)
	for rid in _held_states:
		if remotes.has(rid):
			remotes[rid].apply_state(_held_states[rid])
	_held_states.clear()
	if not _held_end.is_empty():
		var m := _held_end
		_held_end = {}
		_on_end(m)


func _host_end(winner: String) -> void:
	if _ended:
		return
	_ended = true
	var sc := scores.duplicate()
	var sk := str(seeker_id)
	sc[sk] = int(sc.get(sk, 0)) + caught.size()
	if winner == "hiders":
		for h in _hiders():
			if not caught.has(h):
				sc[str(h)] = int(sc.get(str(h), 0)) + 1
	Net.broadcast({"t": "end", "winner": winner, "scores": sc, "left": phase_left})


func _on_end(m: Dictionary) -> void:
	if phase not in ["hide", "seek"]:
		return
	if not replay.is_empty():
		_held_end = m
		return
	phase = "results"
	_ended = true
	if bot != null:
		bot.on_end()
	scores = m["scores"]
	var winner := str(m["winner"])
	var title := ""
	var body := ""
	if winner == "seeker":
		title = "You found everyone! 🎉" if me.role == "seeker" else "Found! 🙈"
		var used := seek_time - float(m.get("left", 0.0))
		body = "%s found everyone in %d:%02d." % [_player_name(seeker_id), int(used) / 60, int(used) % 60]
	else:
		if me.role == "seeker":
			title = "Time's up! ⏰"
			body = "Couldn't find everyone. Sneaky!"
		else:
			title = "Never found! 😎" if not caught.has(Net.my_id) else "Time's up! ⏰"
			body = "The hiders win this round."
	if teases > 0:
		body += "\nYou teased %d time%s 😜" % [teases, "" if teases == 1 else "s"]
	body += "\n\n" + _score_text()
	_clear_round()
	_reset_my_round()
	for r in remotes.values():
		r.reset_round_state()
		r.show_name = true
	ui.show_results(title, body, Net.is_host())
	ui.set_timer("")
	ui.set_role("")
	ui.set_hint("")
	ui.set_scores(_score_text())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var i_won := (winner == "seeker" and me.role == "seeker") or (winner == "hiders" and me.role != "seeker" and not caught.has(Net.my_id))
	if i_won:
		Sfx.play("win")
		Sfx.play("cheer", -8.0)
	else:
		Sfx.play("lose")
	get_tree().create_timer(0.9).timeout.connect(func(): Sfx.say("you_win" if i_won else "you_lose"))
	Music.play("results")
	_log("end winner=" + winner)


func _score_text() -> String:
	var parts := []
	var ids := Net.players.keys()
	ids.sort()
	for id in ids:
		parts.append("%s %d" % [_player_name(id), int(scores.get(str(id), 0))])
	return ("🏆 " + "   ".join(parts)) if parts.size() > 0 else ""


func _clear_round() -> void:
	for k in items.keys():
		items[k]["node"].queue_free()
	items.clear()
	for p in pillows:
		p["node"].queue_free()
	pillows.clear()
	for f in footprints:
		f["node"].queue_free()
	footprints.clear()
	lights_off = 0.0
	house.set_lights(true)
	ui.set_dark(0.0, false)
	env.ambient_light_energy = 0.6
	if house.tv_on:
		house.set_tv(false)
	seeker_id = -1
	ui.set_blind(false)
	ui.set_slats(false)
	ui.set_danger(0.0)
	ui.set_hint("")
	ui.hide_results()


# ---------- what the buttons do right now ----------

func _cd_left(k: String) -> float:
	return maxf(0.0, cd.get(k, 0.0))


func _cd_text(label: String, k: String) -> String:
	var c := _cd_left(k)
	return label if c <= 0.0 else "%s  %d" % [label.split(" ")[0], ceili(c)]


func _near_spot() -> int:
	var best := -1
	var bd := 1.8
	for i in house.hide_spots.size():
		var e: Vector3 = house.hide_spots[i]["exit"]
		if absf(e.y - me.global_position.y) > 1.5:
			continue
		var d := _flat_dist(me.global_position, e)
		if d < bd:
			bd = d
			best = i
	return best


func _spot_taken(i: int) -> bool:
	for r in remotes.values():
		if r.hide_spot == i:
			return true
	return false


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The object under the crosshair (or the nearest one) that you could turn into.
func _find_prop() -> Dictionary:
	var from := me.cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + me.aim_dir() * 14.0, 1)
	q.exclude = [me.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit["collider"] is Node and (hit["collider"] as Node).has_meta("prop"):
		var c: Node = hit["collider"]
		if (hit["position"] as Vector3).distance_to(me.global_position) < 9.0:
			return {"name": c.get_meta("prop"), "scale": c.get_meta("pscale", Kit.SCALE)}
	var best := {}
	var bd := 2.3
	for p in house.props:
		var n: Node3D = p["node"]
		var d := n.global_position.distance_to(me.global_position)
		if d < bd:
			bd = d
			best = {"name": p["name"], "scale": p["scale"]}
	return best


static func _cap(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1)


static func _pretty(model_name: String) -> String:
	var n := model_name.trim_prefix("ph:").replace("_", " ")
	var out := ""
	for i in n.length():
		var ch := n[i]
		if i > 0 and ch == ch.to_upper() and ch != ch.to_lower() and n[i - 1] != " ":
			out += " "
		out += ch.to_lower()
	var words := out.split(" ")
	while words.size() > 1 and words[words.size() - 1] in ["round", "square", "modern", "cushion", "closed", "open", "large", "small", "1", "2", "3", "glass", "design", "doors", "drawer", "long", "low", "wide", "corner", "relax", "cloth", "frame", "antenna", "floor"]:
		words.remove_at(words.size() - 1)
	if words.size() > 2:
		words = words.slice(words.size() - 2)
	return " ".join(words)


func _tool(id: String, icon: String, label: String, cd_key := "", enabled := true) -> Dictionary:
	var c := _cd_left(cd_key) if cd_key != "" else 0.0
	return {"id": id, "icon": icon, "name": label, "cd": c, "enabled": enabled and c <= 0.0}


func _controls() -> Array:
	# returns [main, tools, fun, show_move, alt]
	var main := {}
	var tools := []
	var fun := []
	var alt := {}
	ui.set_hint_small("")
	if phase == "menu":
		return [main, tools, fun, false, alt]
	if phase == "chill":
		return _chill_controls()
	var playing := phase in ["hide", "seek"]
	var free_play := phase in ["explore", "lobby", "results"]
	var blind := me.role == "seeker" and phase == "hide"
	if not blind:
		fun = [
			_tool("fart", "💨", "Fart", "fart"), _tool("confetti", "🎉", "Confetti", "confetti"),
			_tool("honk", "📯", "Honk", "honk"), _tool("dance", "💃", "Dance", "dance"),
			_tool("kiss", "😘", "Kiss", "kiss"),
			_tool("laugh", "🤣", "Laugh", "laugh"),
			_tool("banana", "🍌", "Banana ×%d" % uses.get("banana", 0) if not free_play else "Banana", "", uses.get("banana", 0) > 0 or free_play),
			_tool("pillow", "🛏", "Pillow ×%d" % uses.get("pillow", 0) if not free_play else "Pillow", "pillow", (uses.get("pillow", 0) > 0 or free_play) and me.hide_spot < 0),
		]

	if me.ghost:
		return [main, tools, fun, true, alt]
	var near_tv := me.hide_spot < 0 and _flat_dist(me.global_position, house.tv_pos) < 2.6 and me.global_position.y < 1.5
	if me.role == "seeker" and playing:
		if phase == "seek":
			var s := _near_spot()
			if s >= 0:
				main = {"id": "search", "icon": "🚪", "name": "Check", "color": C_HIDE, "enabled": _cd_left("search") <= 0.0}
				ui.set_hint_small(_cap(house.hide_spots[s]["name"]))
			else:
				main = {"id": "catch", "icon": "✋", "name": "Catch", "color": C_SEEK, "enabled": _cd_left("catch") <= 0.0}
			tools = [_tool("radar", "📡", "Radar", "radar"), _tool("xray", "👁", "X-Ray ×%d" % uses.get("xray", 0), "xray", uses.get("xray", 0) > 0),
				_tool("marco", "📣", "Marco!", "marco"), _tool("sprint", "⚡", "Sprint", "sprint")]
			if near_tv:
				tools.append(_tool("tv", "📺", "TV"))
		return [main, tools, fun, phase == "seek", alt]
	# hider (or free play)
	if me.hide_spot >= 0:
		var k: String = house.hide_spots[me.hide_spot].get("kind", "hide")
		main = {"id": "unhide", "icon": "🚪", "name": "Get off" if k == "bike" else ("Get out" if k == "car" else "Exit"), "color": C_HIDE}
		if k in ["car", "bike"]:
			alt = {"id": "rev", "icon": "🔊", "name": "Rev"} if _cd_left("rev") <= 0.0 else {}
	elif me.disguise != "":
		main = {"id": "lock", "icon": "🔓" if me.prop_locked else "🔒", "name": "Move" if me.prop_locked else "Freeze", "color": C_PROP}
		alt = {"id": "undisguise", "icon": "🧍", "name": "Be me"}
	else:
		var s := _near_spot()
		if s >= 0 and not _spot_taken(s):
			var k: String = house.hide_spots[s].get("kind", "hide")
			main = {"id": "hide", "icon": {"car": "🚗", "bike": "🏍"}.get(k, "🙈"), "name": {"car": "Get in", "bike": "Ride"}.get(k, "Hide"), "color": C_HIDE}
			ui.set_hint_small(_cap(house.hide_spots[s]["name"]))
		elif not _aim.is_empty():
			main = {"id": "disguise", "icon": "✨", "name": "Become", "color": C_PROP}
			ui.set_hint_small(_cap(_pretty(_aim["name"])))
	if playing or free_play:
		if _seeker_dist() < 4.0 or free_play:
			tools.append(_tool("boo", "👻", "BOO!", "boo"))
		tools.append(_tool("smoke", "💨", "Smoke ×%d" % uses.get("smoke", 0) if not free_play else "Smoke", "smoke", uses.get("smoke", 0) > 0 or free_play))
		tools.append(_tool("sprint", "⚡", "Sprint", "sprint", me.hide_spot < 0))
		tools.append(_tool("giggle", "🤭", "Decoy", "giggle"))
		if phase == "seek" or free_play:
			tools.append(_tool("lights", "💡", "Lights Off", "", (uses.get("lights", 0) > 0 or free_play) and lights_off <= 0.0))
	if me.disguise != "":
		tools.append(_tool("rotate", "🔄", "Turn"))
	if near_tv:
		tools.insert(0, _tool("tv", "📺", "TV"))  # first, so it's never the one that doesn't fit
	# when the seeker is right next to you, BOO! gets its own quick button
	if alt.is_empty() and playing and _seeker_dist() < 4.0 and _cd_left("boo") <= 0.0:
		alt = {"id": "boo", "icon": "👻", "name": "BOO!"}
	return [main, tools, fun, me.hide_spot < 0, alt]


func _seeker_dist() -> float:
	var s: RemotePlayer = remotes.get(seeker_id)
	if s == null:
		return 999.0
	return s.global_position.distance_to(me.global_position)


func _new_key() -> String:
	item_counter += 1
	return "%d_%d" % [Net.my_id, item_counter]


func _drop_point() -> Vector3:
	var p := me.global_position + me.facing() * 0.3
	return Vector3(p.x, me.global_position.y, p.z)


func _do_action(id: String) -> void:
	if id.begins_with("emote:"):
		_fx({"k": "emote", "e": id.substr(6)})
		_count_tease()
		return
	if id.begins_with("say:"):
		_fx({"k": "say", "s": id.substr(4)})
		_count_tease()
		return
	var free_play := phase in ["explore", "lobby", "results", "chill"]
	if phase == "chill" and extras.action(id):
		return
	match id:
		"jump":
			me.jump_req = true
		"crouch":
			me.crouch = not me.crouch
		"run":
			me.run = not me.run
		"hide":
			var s := _near_spot()
			if s >= 0 and not _spot_taken(s):
				if me.disguise != "":
					me.set_disguise("")
				me.enter_spot(s, house.hide_spots[s])
				ui.set_slats(house.hide_spots[s].get("kind", "hide") == "hide")
				Sfx.play("open")
				ui.toast("🤫")
		"unhide":
			me.exit_spot()
			ui.set_slats(false)
			Sfx.play("close")
		"disguise":
			var p := _find_prop()
			if not p.is_empty():
				var room := me.find_room_for(p["name"], p["scale"])
				if room == Vector3.INF:
					ui.toast("🚫 No room here")
					Sfx.play("error")
					return
				if room.distance_to(me.global_position) > 0.01:
					me.global_position = room
					me.reset_physics_interpolation()
				me.set_disguise(p["name"], p["scale"])
				Sfx.play("poof")
				ui.toast("✨")
		"undisguise":
			me.set_disguise("")
			Sfx.play("poof", 0.0, 1.3)
		"lock":
			me.prop_locked = not me.prop_locked
			Sfx.play("switch")
		"rotate":
			me.rotate_prop()
			Sfx.play("click")
		"banana":
			if not free_play:
				uses["banana"] = uses.get("banana", 2) - 1
			var p := _drop_point()
			_fx({"k": "banana", "id": _new_key(), "p": [p.x, p.y, p.z]})
		"cushion":
			if not free_play:
				uses["cushion"] = uses.get("cushion", 1) - 1
			var p := _drop_point()
			_fx({"k": "cushion", "id": _new_key(), "p": [p.x, p.y, p.z]})
		"giggle":
			cd["giggle"] = 15.0
			var p := _throw_point(7.0)
			_fx({"k": "giggle", "p": [p.x, p.y, p.z]})
			ui.toast("🤭")
		"lights":
			if not free_play:
				uses["lights"] = 0
			_fx({"k": "lights", "d": 12.0})
		"boo":
			cd["boo"] = 25.0
			_fx({"k": "boo"})
			_count_tease()
		"pillow":
			if not free_play:
				uses["pillow"] = uses.get("pillow", PILLOWS) - 1
			cd["pillow"] = 1.0
			_throw_pillow()
		"ckiss":
			_chill_ask("kiss")
		"chug":
			_chill_ask("hug")
		"chands":
			_chill_ask("hands")
		"cdance":
			_chill_ask("dance")
		"sit":
			var si := chill.seat_near(me.global_position)
			if si >= 0:
				chill.sit(me, si)
		"stand":
			me.stand_up()
		"lantern":
			cd["lantern"] = 3.0
			var lp := me.global_position
			_fx({"k": "lantern", "p": [lp.x, lp.y, lp.z]})
		"fireworks":
			cd["fireworks"] = 14.0
			_fx({"k": "fireworks", "s": randi() % 100000})
		"wish":
			cd["wish"] = 8.0
			_fx({"k": "wish"})
		"nextsong":
			cd["nextsong"] = 1.0
			send_song(Music.song_index() + 1)
		"tv":
			var clip := randi() % maxi(1, house.tv_clip_count())
			_fx({"k": "tv", "on": not house.tv_on, "v": clip})
		"catch":
			_try_catch()
		"search":
			_try_search()
		"rev":
			cd["rev"] = 2.5
			if me.hide_spot >= 0:
				_fx({"k": "rev", "s": me.hide_spot})
		"marco":
			cd["marco"] = 20.0
			_fx({"k": "marco"})
		"radar":
			cd["radar"] = 20.0
			_radar()
		"xray":
			cd["xray"] = 45.0
			uses["xray"] = uses.get("xray", 3) - 1
			_fx({"k": "xray"})
		"fart":
			cd["fart"] = 6.0
			_fx({"k": "fart"})
		"sprint":
			cd["sprint"] = 18.0
			me.boost = 4.0
			Sfx.play("whoosh")
		"smoke":
			if not free_play:
				uses["smoke"] = uses.get("smoke", 2) - 1
			cd["smoke"] = 12.0
			_fx({"k": "smoke"})
		"confetti":
			cd["confetti"] = 10.0
			_fx({"k": "confetti"})
		"honk":
			cd["honk"] = 1.5
			_fx({"k": "honk"})
		"dance":
			cd["dance"] = 4.0
			_fx({"k": "dance"})
		"kiss":
			cd["kiss"] = 2.0
			_fx({"k": "kiss"})
		"laugh":
			cd["laugh"] = 3.0
			_fx({"k": "laugh"})

		"sniff":
			cd["sniff"] = 30.0
			_fx({"k": "sniff"})
			pass


func _count_tease() -> void:
	if phase == "seek" and me.role == "hider" and _seeker_dist() < 12.0:
		teases += 1


## Throw a pillow forwards, gently aimed at whoever is in front of you.
func _throw_pillow() -> void:
		var from := me.global_position + Vector3(0, 1.3, 0) + me.facing() * 0.6
		var flat := me.facing()
		var speed := 16.0
		var v := flat * speed + Vector3(0, 3.0, 0)
		# gentle auto-aim at whoever is in front of you
		var best := 99.0
		for rid in remotes:
			var r: RemotePlayer = remotes[rid]
			if caught.has(rid) or r.hide_spot >= 0:
				continue
			var to: Vector3 = r.global_position + Vector3(0, 0.8, 0) - from
			var d := to.length()
			if d < 14.0 and d < best and Vector3(to.x, 0, to.z).normalized().dot(flat) > 0.85:
				best = d
				var t := d / speed
				v = to / t + Vector3(0, 7.0 * t, 0)
		_fx({"k": "pillow", "p": [from.x, from.y, from.z], "v": [v.x, v.y, v.z]})


func _bubble_for(who: Node, text: String) -> void:
	if who is Player:
		(who as Player).say(text)
	elif who is RemotePlayer:
		(who as RemotePlayer).say(text)


func _fx(m: Dictionary) -> void:
	m["t"] = "fx"
	if Net.is_online():
		Net.broadcast(m)
	else:
		m["from"] = Net.my_id
		_on_fx(m, Net.my_id)


func _throw_point(dist: float) -> Vector3:
	var from := me.global_position + Vector3(0, 1.0, 0)
	var to := from + me.facing() * dist
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		return hit["position"] - me.facing() * 0.3
	return to


func _los(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Footprint radius of whatever the hider looks like right now (big for a sofa, small for a person).
func _hider_radius(r: RemotePlayer) -> float:
	if r.disguise != "":
		var sz := Kit.size_of(r.disguise, r.disguise_scale)
		return clampf(maxf(sz.x, sz.z) * 0.5, 0.3, 1.6)
	return 0.35


## Can you reach them? Walls, floors and hedges block; furniture in between doesn't.
func _can_see_part(r: RemotePlayer) -> bool:
	var eye := me.global_position + Vector3(0, 1.1, 0)
	for h in [0.3, 0.8, 1.3]:
		if house.walls_clear(eye, r.global_position + Vector3(0, h, 0)):
			return true
	return false


func _try_catch() -> void:
	var best := _catch_target()
	if best >= 0:
		Net.broadcast({"t": "caught", "id": best})
	else:
		cd["catch"] = 1.5
		Sfx.play("miss")
		ui.toast("😅")


## Who a Catch right now would grab, or -1.
func _catch_target() -> int:
	var best := -1
	var bd := 99.0
	var eye := me.cam.global_position
	var aim := me.aim_dir()
	var near_spot := _near_spot()
	for id in remotes:
		var r: RemotePlayer = remotes[id]
		if id == seeker_id or caught.has(id):
			continue
		if r.hide_spot >= 0:
			# Search and Catch both find a hider from the spot's reachable entrance.
			# Hidden positions can be below the floor, so don't use body height or sight.
			if r.hide_spot == near_spot:
				return id
			continue
		var to := r.global_position - me.global_position
		if absf(to.y) > 1.8:
			continue
		var rad := _hider_radius(r)
		var gap := maxf(0.0, Vector2(to.x, to.z).length() - rad)
		var facing_ok := gap < 1.0 or Vector3(to.x, 0, to.z).normalized().dot(me.facing()) > 0.0
		# also count it if the centre dot is pointing at them
		var c := r.global_position + Vector3(0, 0.6, 0)
		var along := (c - eye).dot(aim)
		var aimed := along > 0.0 and (eye + aim * along).distance_to(c) < rad + 0.7 and gap < 4.0
		if ((gap < 1.9 and facing_ok) or aimed) and gap < bd and _can_see_part(r):
			best = id
			bd = gap
	return best


func _try_search() -> void:
	var s := _near_spot()
	if s < 0:
		return
	Sfx.play("open")
	for id in remotes:
		var r: RemotePlayer = remotes[id]
		if id != seeker_id and not caught.has(id) and r.hide_spot == s:
			Net.broadcast({"t": "caught", "id": id})
			return
	cd["search"] = 3.0
	ui.toast("🚫")


func _actor(id: int) -> Node3D:
	if id == Net.my_id:
		return me
	return remotes.get(id)


func _on_fx(m: Dictionary, from: int) -> void:
	var k := str(m.get("k", ""))
	if bot != null:
		bot.on_fx(k, m, from)
	var mine := from == Net.my_id
	var who := _actor(from)
	var who_pos := who.global_position if who != null else me.global_position
	if extras.on_fx(k, m, from, mine):
		return
	match k:
		"emote":
			var e := str(m.get("e", "❤️"))
			if mine:
				me.say(e)
			elif who is RemotePlayer:
				(who as RemotePlayer).say(e)
			Sfx.play_at("kiss" if e == "😘" else "pop", who_pos + Vector3.UP, 0.0)
		"say":
			var s := str(m.get("s", ""))
			if mine:
				me.say(s)
				if me.rig:
					me.rig.gesture("emote-yes")
			elif who is RemotePlayer:
				(who as RemotePlayer).say(s)
			Sfx.play_at(["squeak", "peekaboo", "whistle"][s.length() % 3], who_pos + Vector3.UP, 2.0)
		"banana", "cushion":
			var p = m["p"]
			var node := Build.banana() if k == "banana" else Build.cushion()
			node.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
			node.rotation.y = randf() * TAU
			add_child(node)
			items[str(m["id"])] = {"kind": k, "node": node, "pos": node.position}
			if mine:
				Sfx.play("drop")
				pass
		"slip", "pfft":
			var key := str(m["id"])
			var pos := who_pos
			if items.has(key):
				pos = items[key]["pos"]
				items[key]["node"].queue_free()
				items.erase(key)
			if k == "slip":
				Sfx.play_at("slip", pos + Vector3.UP)
				if mine:
					me.stun = 1.6
					me.shake(0.6)
					ui.toast("🍌😵")
				else:
					if who is RemotePlayer:
						(who as RemotePlayer).stun(1.6)
					ui.toast("🍌😂")
			else:
				Sfx.play_at("fart", pos + Vector3.UP * 0.3, 6.0)
				ui.toast("💨😂")
		"giggle":
			var p = m["p"]
			Sfx.play_at("giggle", Vector3(float(p[0]), float(p[1]), float(p[2])), 4.0)
		"lights":
			lights_off = float(m.get("d", 12.0))
			house.set_lights(false)
			env.ambient_light_energy = 0.15
			Sfx.play("lights")
			ui.set_dark(0.55, me.role == "seeker")
			if me.role == "seeker":
				ui.toast("💡❌")
			else:
				ui.toast("💡❌")
		"ask":
			if not mine and phase == "chill":
				var w := str(m.get("w", "kiss"))
				chill.pending = {"w": w, "from": from, "t": Time.get_ticks_msec() / 1000.0}
				var nm := _player_name(from)
				ui.toast({"kiss": "💋 %s wants a kiss", "hug": "🤗 %s wants a hug", "dance": "💃 %s asks you to dance", "hands": "🤝 %s wants to hold your hand"}[w] % nm, 4.0)
				Sfx.play("twinkle", -6.0)
		"together":
			if phase == "chill":
				var c: Array = m.get("c", [0, 0, 0])
				var ca := _actor(int(m.get("a", -1)))
				var cb := _actor(int(m.get("b", -1)))
				if ca != null and cb != null:
					chill.asked.clear()
					chill.pending.clear()
					if me.sitting:
						me.stand_up()
					if str(m.get("w", "")) == "hands":
						extras.start_hands(ca, cb)
					else:
						chill.start_together(str(m.get("w", "kiss")), ca, cb, Vector3(float(c[0]), float(c[1]), float(c[2])), float(m.get("y", 0.0)))
		"lantern":
			var lp: Array = m.get("p", [0, 0, 0])
			chill.lantern(Vector3(float(lp[0]), float(lp[1]), float(lp[2])))
		"fireworks":
			chill.fireworks(int(m.get("s", 1)))
			if mine:
				ui.toast("🎆 Look up at the garden sky!", 3.0)
		"outfit":
			if not mine and remotes.has(from):
				remotes[from].set_outfit(_outfit_in(m.get("o", {})))
		"song":
			chill._song_wait = -1.0
			Music.play_song(int(m.get("i", 0)))
		"wish":
			chill.wish(-me.cam.global_transform.basis.z)
			ui.toast("🌠 Make a wish...", 3.5)
		"tv":
			house.set_tv(bool(m.get("on", false)), int(m.get("v", -1)))
		"marco":
			Sfx.play_at("marco", who_pos + Vector3.UP * 1.4, 3.0)
			if me.role == "hider" and not me.ghost and phase == "seek":
				var p := me.eye_pos()
				_fx({"k": "polo", "p": [p.x, p.y, p.z]})
				ui.toast("📣 😬")
		"polo":
			var p = m["p"]
			Sfx.play_at("polo", Vector3(float(p[0]), float(p[1]), float(p[2])), 5.0)
			if me.role == "seeker":
				ui.toast("👂")
		"boo":
			Sfx.play_at("boo", who_pos + Vector3.UP * 1.2, 6.0)
			if mine:
				me.say("👻 BOO!")
				if me.rig:
					me.rig.gesture("interact-right")
			elif who is RemotePlayer:
				(who as RemotePlayer).say("👻 BOO!")
			if me.role == "seeker" and not mine and who_pos.distance_to(me.global_position) < 5.0:
				me.stun = 1.3
				me.shake(1.2)
				ui.toast("😱")
		"pillow":
			var p = m["p"]
			var v = m["v"]
			var node := Kit.model("pillow", 3.6)
			node.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
			add_child(node)
			Sfx.play_at("whoosh", node.position, -4.0)
			pillows.append({"node": node, "vel": Vector3(float(v[0]), float(v[1]), float(v[2])), "mine": mine, "life": 3.0})
		"hit":
			var target := int(m.get("id", -1))
			extras.on_hit(from, target)
			var pos := who_pos
			var tgt := _actor(target)
			if tgt != null:
				pos = tgt.global_position
			Build.burst(self, pos, "poof")
			Sfx.play_at("poof", pos + Vector3.UP, 4.0)
			Sfx.play_at("ouch", pos + Vector3.UP, 4.0)
			if target == Net.my_id:
				me.stun = 1.0
				me.shake(0.7)
				var push := (me.global_position - who_pos)
				push.y = 0.0
				me.velocity += push.normalized() * 7.0 + Vector3(0, 4.0, 0)
				me.say("Ouch! 😣")
				ui.toast("🛏💥")
			elif tgt is RemotePlayer:
				var r := tgt as RemotePlayer
				r.stun(1.0)
				r.say("Ouch! 😣")
				if mine:
					ui.toast("👀❗" if r.disguise != "" else "🛏😂")
		"sniff":
			Sfx.play_at("sniff", who_pos + Vector3.UP, 0.0)
			if me.role == "hider" and not me.ghost and phase == "seek" and not mine:
				var pts := []
				for t in trail:
					pts.append([snappedf(t.x, 0.1), snappedf(t.y, 0.1), snappedf(t.z, 0.1)])
				_fx({"k": "trail", "pts": pts})
				pass
		"rev":
			var si := int(m.get("s", -1))
			if si >= 0 and si < house.hide_spots.size():
				var sp: Dictionary = house.hide_spots[si]
				var kind: String = sp.get("kind", "car")
				_snd(mine, "rev_bike" if kind == "bike" else "rev_car", sp["cam"], 8.0)
				house.flash_lights(kind)
				if mine:
					me.shake(0.25)
		"fart":
			Build.burst(self, who_pos, "fart")
			_snd(mine, "fart", who_pos + Vector3.UP * 0.5, 6.0, randf_range(0.8, 1.2))
		"smoke":
			for i in 3:
				Build.burst(self, who_pos + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), "smoke")
			Sfx.play_at("poof", who_pos + Vector3.UP, 6.0, 0.6)
			if not mine and me.global_position.distance_to(who_pos) < 7.0:
				ui.pop_smoke(2.8)
		"confetti":
			Build.burst(self, who_pos, "confetti")
			_snd(mine, "partyhorn", who_pos + Vector3.UP, 4.0)
			if not mine and me.global_position.distance_to(who_pos) < 4.5:
				ui.pop_confetti(2.2)
		"honk":
			if mine:
				Sfx.play("honk", 2.0, randf_range(0.9, 1.15))
				me.say("📯 HONK!")
				me.hop()
			else:
				Sfx.play_at("honk", who_pos + Vector3.UP, 10.0, randf_range(0.9, 1.15))
				if who is RemotePlayer:
					(who as RemotePlayer).say("📯 HONK!")
					(who as RemotePlayer).hop()
				if me.global_position.distance_to(who_pos) < 5.0 and me.hide_spot < 0:
					me.hop()
					me.stun = maxf(me.stun, 0.4)
					me.shake(0.4)
		"dance":
			Build.burst(self, who_pos, "notes")
			_snd(mine, "dance", who_pos + Vector3.UP, 2.0)
			if mine:
				me.dance()
			elif who is RemotePlayer:
				(who as RemotePlayer).dance()
		"kiss":
			Build.burst(self, who_pos, "hearts")
			_snd(mine, "kiss", who_pos + Vector3.UP, 4.0)
		"laugh":
			_snd(mine, "laugh", who_pos + Vector3.UP, 4.0)
			_bubble_for(who, "🤣")

		"wiggle":
			Sfx.play_at("wiggle", who_pos + Vector3.UP * 0.5, 6.0)
			if mine:
				me.hop()
			elif who is RemotePlayer:
				(who as RemotePlayer).hop()
		"xray":
			Sfx.play_at("xray", who_pos + Vector3.UP, 2.0)
			if mine and me.role == "seeker":
				for id in remotes:
					var r: RemotePlayer = remotes[id]
					if id != seeker_id and not caught.has(id) and r.global_position.distance_to(me.global_position) < 35.0:
						r.xray(3.0, r.global_position.distance_to(me.global_position) < 10.0)
			elif me.role == "hider" and phase == "seek":
				ui.toast("👁")
		"radar":
			Sfx.play_at("radar", who_pos + Vector3.UP, 2.0)
			if not mine and me.role == "hider":
				Sfx.play("radar", -6.0)
		"trail":
			if me.role == "seeker":
				for p in m.get("pts", []):
					_footprint(Vector3(float(p[0]), float(p[1]), float(p[2])))


func _snd(mine: bool, sound: String, pos: Vector3, vol := 0.0, pitch := 1.0) -> void:
	if mine:
		Sfx.play(sound, vol - 4.0, pitch)
	else:
		Sfx.play_at(sound, pos, vol, pitch)


## Points the radar arrow at the nearest hider: red = close, yellow = medium, blue = far.
func _radar() -> void:
	var best: Node3D = null
	var bd := 1e9
	for id in remotes:
		if id != seeker_id and not caught.has(id):
			var d: float = remotes[id].global_position.distance_to(me.global_position)
			if d < bd:
				bd = d
				best = remotes[id]
	_fx({"k": "radar"})
	if best == null:
		return
	var local := me.cam.global_transform.basis.inverse() * (best.global_position - me.cam.global_position)
	var dir := Vector2(local.x, local.z)
	if dir.length() < 0.01:
		dir = Vector2.UP
	var col := Color("#ff3355") if bd < 6.0 else (Color("#ffd23d") if bd < 14.0 else Color("#3fb4ff"))
	ui.show_radar(dir, col, 3.0, "%d m" % roundi(bd))


func _footprint(p: Vector3) -> void:
	var n := Build.ball(self, 0.13, p + Vector3(0, 0.03, 0), Color("#ff4f86"), Vector3(1, 0.15, 1.5))
	n.material_override = Build.mat(Color("#ff6fa0"), 0.5, 2.0)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	footprints.append({"node": n, "life": 9.0})


# ---------- per-frame ----------

func _process(dt: float) -> void:
	Sfx.amb_on = phase in ["explore", "lobby", "hide", "seek", "chill"]
	if Sfx.amb_on and house:
		Sfx.outdoors = 1.0 if house.surface_at(me.global_position) == "grass" else 0.0
	if _warm_i > 0:
		_warm_tick()
		return
	_read_keyboard()
	for k in cd.keys():
		cd[k] -= dt

	if phase == "chill":
		var song := Music.now_playing()
		ui.set_timer("♪ " + song if song != "" else "")
	if phase in ["hide", "seek"]:
		phase_left = maxf(0.0, phase_left - dt)
		var secs := ceili(phase_left)
		ui.set_timer(("🙈 Hide  " if phase == "hide" else "👀 Seek  ") + "%d:%02d" % [secs / 60, secs % 60])
		if phase == "hide":
			if me.role == "seeker":
				ui.set_blind(true, "No peeking! 🙈\n\n%d" % secs)
			if secs <= 3 and secs != _last_beep and secs > 0:
				_last_beep = secs
				Sfx.say(str(secs))
			if phase_left <= 0.0 and Net.is_host():
				phase_left = 999.0
				Net.broadcast({"t": "phase", "seek": seek_time})
		elif phase == "seek":
			if phase_left <= 0.0 and Net.is_host():
				_host_end("hiders")
			if not _hurry and phase_left < 30.0 and seek_time >= 60.0:
				_hurry = true
				Sfx.say("hurry_up")
			_seek_tick(dt)
			if replay.is_empty():
				_record(dt)
	if not replay.is_empty():
		_replay_tick(dt)

	if lights_off > 0.0:
		lights_off -= dt
		if lights_off <= 0.0:
			house.set_lights(true)
			env.ambient_light_energy = 0.6
			ui.set_dark(0.0, false)
			Sfx.play("lights", 0.0, 1.5)

	if bot != null:
		bot.tick(dt)
	if phase != "menu":
		_check_traps()
	if not (phase == "seek" and me.role == "seeker"):
		ui.set_heat(-1.0)
	_update_pillows(dt)
	for i in range(footprints.size() - 1, -1, -1):
		footprints[i]["life"] -= dt
		if footprints[i]["life"] <= 0.0:
			footprints[i]["node"].queue_free()
			footprints.remove_at(i)

	# breadcrumb trail for the seeker's sniff
	_trail_t -= dt
	if _trail_t <= 0.0 and me.is_moving():
		_trail_t = 0.6
		trail.append(me.global_position)
		if trail.size() > 25:
			trail.pop_front()

	if phase == "menu":
		_menu_preview(dt)

	_send_hi(dt)
	_send_t -= dt
	if _send_t <= 0.0 and Net.is_online() and phase != "menu":
		_send_t = 1.0 / 20.0
		var p := me.global_position
		Net.send({"t": "st", "p": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)],
			"y": snappedf(me.visual.rotation.y, 0.01), "m": me.is_moving(), "a": me.anim_state(),
			"d": me.disguise, "ds": me.disguise_scale, "dy": snappedf(me.disguise_yaw, 0.01), "h": me.hide_spot, "g": me.ghost,
			"ts": int(Time.get_unix_time_from_system() * 1000.0) % 1000000})

	_ui_t -= dt
	if _ui_t <= 0.0:
		_ui_t = 0.12
		var no_aim := (me.role == "seeker" and phase in ["hide", "seek"]) or me.disguise != "" or me.hide_spot >= 0 or phase == "menu"
		_aim = {} if no_aim else _find_prop()
		var c := _controls()
		ui.set_controls(c[0], c[1], c[2], c[3], me.crouch, me.run, c[4])
		ui.crosshair.visible = phase != "menu" and me.hide_spot < 0

	if auto == "bench":
		_bench_tick(dt)
	elif auto != "" and auto != "qa" and not auto.begins_with("shot"):
		_autotest(dt)
	_fps_log_t += dt
	if _fps_log_t > 5.0:
		_fps_log_t = 0.0
		print("PERF fps=%d draws=%d objects=%d q=%d" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), int(settings["quality"])])


func _menu_preview(dt: float) -> void:
	_preview_t += dt
	me.visual.visible = true
	me.yaw = PI
	me.pitch = -0.02
	me.shoulder = 1.0
	me.cam_dist = 3.6
	me.visual.rotation.y = sin(_preview_t * 0.6) * 0.5


func _update_pillows(dt: float) -> void:
	for i in range(pillows.size() - 1, -1, -1):
		var pl: Dictionary = pillows[i]
		var node: Node3D = pl["node"]
		var v: Vector3 = pl["vel"]
		v.y -= 14.0 * dt
		pl["vel"] = v
		var from := node.position
		var to := from + v * dt
		node.rotation += Vector3(dt * 9.0, dt * 6.0, 0)
		pl["life"] -= dt
		var done: bool = pl["life"] <= 0.0
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			to = hit["position"]
			done = true
			Sfx.play_at("thud", to, -2.0)
			Build.burst(self, to - Vector3(0, 0.8, 0), "poof")
		node.position = to
		if pl["mine"] and not done:
			for id in remotes:
				var r: RemotePlayer = remotes[id]
				if r.hide_spot >= 0 or caught.has(id):
					continue
				if (r.global_position + Vector3(0, 0.8, 0)).distance_to(to) < 1.1:
					_fx({"k": "hit", "id": id})
					done = true
					break
		if done:
			node.queue_free()
			pillows.remove_at(i)


var _wiggle_t := 30.0
var _half_ping := false


## Anyone can slip on a banana or sit on a whoopee cushion someone else put down.
func _check_traps() -> void:
	if me.ghost or me.hide_spot >= 0 or not me.is_on_floor():
		return
	var mine_prefix := "%d_" % Net.my_id
	for key in items.keys():
		var k: String = key
		if k.begins_with(mine_prefix):
			continue
		var it: Dictionary = items[key]
		var ip: Vector3 = it["pos"]
		if _flat_dist(me.global_position, ip) < 0.6 and absf(me.global_position.y - ip.y) < 0.6:
			items[key]["pos"] = Vector3(9999, 0, 9999)
			_fx({"k": "slip" if it["kind"] == "banana" else "pfft", "id": key})


func _seek_tick(dt: float) -> void:
	if me.role == "seeker":
		var nearest := 999.0
		for id in remotes:
			var r: RemotePlayer = remotes[id]
			var hunted: bool = id != seeker_id and not caught.has(id)
			r.prints = hunted and bool(rules.get("prints", true))
			if r.on_footprint.is_null():
				r.on_footprint = _footprint_short
			if hunted:
				nearest = minf(nearest, r.global_position.distance_to(me.global_position))
		# heat meter: always on, gets exact in the last minute
		var heat := clampf(1.0 - nearest / 22.0, 0.0, 1.0)
		if phase_left > 60.0:
			heat = snappedf(heat, 0.25)
		ui.set_heat((heat if nearest < 999.0 else 0.0) if bool(rules.get("heat", true)) else -1.0)
		if not _half_ping and bool(rules.get("halfping", true)) and phase_left < seek_time * 0.5:
			_half_ping = true
			_radar()
		Music.play("chase" if nearest < 4.0 else "seek")
		ui.set_danger(0.0)
	elif not me.ghost:
		var d := _seeker_dist()
		var amt := clampf(1.0 - d / 7.0, 0.0, 1.0)
		ui.set_danger(amt * 0.8)
		Music.play("chase" if d < 6.0 else "seek")
		_beat_t -= dt
		if amt > 0.05 and _beat_t <= 0.0:
			Sfx.play("heart", linear_to_db(0.4 + amt * 0.6))
			_beat_t = lerpf(1.0, 0.4, amt)
		# disguised hiders can't stay perfectly still forever
		if me.disguise != "" and bool(rules.get("wiggle", true)):
			_wiggle_t -= dt
			if _wiggle_t <= 0.0:
				_wiggle_t = randf_range(25.0, 35.0)
				_fx({"k": "wiggle"})


func _footprint_short(p: Vector3) -> void:
	var n := Build.ball(self, 0.12, p + Vector3(0, 0.03, 0), Color("#ff4f86"), Vector3(1, 0.15, 1.5))
	n.material_override = Build.mat(Color("#ff6fa0"), 0.5, 2.0)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	footprints.append({"node": n, "life": 7.0})


# ---------- input ----------

func _read_keyboard() -> void:
	var k := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		k.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		k.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		k.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		k.x += 1.0
	if k != Vector2.ZERO:
		me.move_input = k.normalized()
		if Input.is_physical_key_pressed(KEY_SHIFT):
			me.run = true
	else:
		me.move_input = stick_vec


func _capture_mouse() -> void:
	if not is_touch and auto == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Buttons get every finger first, before panels or the joystick can swallow the touch.
func _input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch or ev is InputEventMouseButton:
		print("TOUCHDBG ev %s f=%d" % [ev.as_text(), Engine.get_process_frames()])
	if is_touch and ev is InputEventScreenTouch and ev.pressed and ui != null:
		var b: Button = ui.touch_button_at(ev.position)
		if b != null:
			ui.tap(b)
			get_viewport().set_input_as_handled()


func _unhandled_input(ev: InputEvent) -> void:
	var sens: float = settings["sens"]
	if ev is InputEventScreenTouch:
		if ev.pressed:
			if ui.is_over_ui(ev.position):
				return
			if ev.position.x < get_viewport().get_visible_rect().size.x * 0.42 and stick_index < 0:
				stick_index = ev.index
				stick_center = ev.position
				ui.set_stick(true, stick_center, Vector2.ZERO)
			elif look_index < 0:
				look_index = ev.index
		else:
			if ev.index == stick_index:
				stick_index = -1
				stick_vec = Vector2.ZERO
				ui.set_stick(false)
			if ev.index == look_index:
				look_index = -1
	elif ev is InputEventScreenDrag:
		if ev.index == stick_index:
			var off: Vector2 = ev.position - stick_center
			if off.length() > 85.0:
				# floating joystick: the base follows your thumb
				stick_center += off - off.normalized() * 85.0
				off = off.normalized() * 85.0
			stick_vec = off / 85.0
			ui.set_stick(true, stick_center, off)
		elif ev.index == look_index:
			me.look(ev.relative * 0.0055 * sens)
	elif ev is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		me.look(ev.relative * 0.0022 * sens)
	elif ev is InputEventMouseButton and ev.pressed and not is_touch and phase != "menu":
		_capture_mouse()
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_F11:
				var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
			KEY_SPACE:
				me.jump_req = true
			KEY_C, KEY_CTRL:
				me.crouch = not me.crouch
			KEY_E, KEY_F:
				if ui.main_id != "" and not ui.main_btn.disabled:
					_do_action(ui.main_id)
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				var i: int = ev.physical_keycode - KEY_1
				if i < ui.tool_ids.size() and ui.tool_btns[i].visible and not ui.tool_btns[i].disabled:
					_do_action(ui.tool_ids[i])
	elif ev is InputEventKey and not ev.pressed and ev.physical_keycode == KEY_SHIFT:
		me.run = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		stick_index = -1
		look_index = -1
		stick_vec = Vector2.ZERO
		if ui:
			ui.set_stick(false)


# ---------- automated test (desktop only) ----------

var _stress := {"i": 0, "fail": 0, "fails": [], "phase": 0, "t": 0.0}


func _bot_catch_stress() -> void:
	var st := _stress
	if phase != "seek":
		return
	st["t"] += get_process_delta_time()
	if st["phase"] == 0:
		# bot picks a new disguise spot
		bot.hide_spot = -1
		bot.disguise = ""
		bot.crouching = false
		for tries in 30:
			bot.hide_spot = -1
			bot.disguise = ""
			bot.crouching = false
			bot._choose_hiding_place()
			if bot.disguise != "":
				break
		bot._push()
		remotes[Bot.ID].global_position = bot.pos
		st["phase"] = 1
		st["t"] = 0.0
	elif st["phase"] == 1 and st["t"] > 0.1:
		var r: RemotePlayer = remotes[Bot.ID]
		var rad := _hider_radius(r)
		var map := get_world_3d().navigation_map
		var stood := false
		var off0 := randf() * TAU
		var want := rad + randf_range(0.4, 1.7)
		for k in 16:
			var a := off0 + TAU * k / 16.0
			var p := NavigationServer3D.map_get_closest_point(map, bot.pos + Vector3(cos(a), 0, sin(a)) * want)
			var flat_d := Vector2(p.x - bot.pos.x, p.z - bot.pos.z).length()
			if absf(p.y - bot.pos.y) > 0.5 or flat_d < rad + 0.35 or flat_d > rad + 1.75:
				continue
			if not house.walls_clear(p + Vector3(0, 1.2, 0), bot.pos + Vector3(0, 0.6, 0)):
				continue
			var to := bot.pos - p
			me.teleport(p + Vector3(0, 0.1, 0), atan2(-to.x, -to.z))
			me.pitch = -0.2
			stood = true
			break
		if not stood:
			st["phase"] = 0
			return
		st["phase"] = 2
		st["t"] = 0.0
	elif st["phase"] == 2 and st["t"] > 0.15:
		var got := _catch_target()
		st["i"] += 1
		if got != Bot.ID:
			st["fail"] += 1
			var r: RemotePlayer = remotes[Bot.ID]
			var to := r.global_position - me.global_position
			var gap := maxf(0.0, Vector2(to.x, to.z).length() - _hider_radius(r))
			st["fails"].append("%s at %s (me at %s) gap=%.2f dy=%.2f facing=%.2f spot=%d clear=%s remote_at=%s" % [bot.disguise, bot.pos.snapped(Vector3.ONE * 0.1), me.global_position.snapped(Vector3.ONE * 0.1), gap, to.y, Vector3(to.x, 0, to.z).normalized().dot(me.facing()), r.hide_spot, _can_see_part(r), r.global_position.snapped(Vector3.ONE * 0.1)])
		st["phase"] = 0
		if st["i"] >= 150:
			print("[stress] catch attempts=%d failed=%d" % [st["i"], st["fail"]])
			for f in st["fails"]:
				print("[stress]   miss: ", f)
			get_tree().quit()


func _bot_autotest() -> void:
	if auto == "botxray":
		if phase == "menu" and auto_t > 0.5 and bot == null:
			hide_time = 1.0
			seek_time = 600.0
			_on_play_bot("Tester", 0, "seek")
		elif phase == "seek" and not auto_done:
			auto_done = true
			bot.hide_spot = 13  # the top bunk upstairs
			bot.disguise = ""
			bot.pos = house.hide_spots[13]["cam"] - Vector3(0, 1.35, 0)
			bot._push()
			me.teleport(Vector3(12.0, 0.1, 6.6), -1.11)
			me.pitch = 0.3
			_do_action("xray")
		return
	if auto == "botstress":
		if phase == "menu" and auto_t > 0.5 and bot == null:
			hide_time = 1.0
			seek_time = 600.0
			_on_play_bot("Tester", 0, "seek")
		else:
			_bot_catch_stress()
		return
	if phase == "menu" and auto_t > 0.5 and bot == null:
		hide_time = 3.0
		seek_time = 90.0
		_on_play_bot("Tester", 0, "seek" if auto in ["botseek", "botsofa"] else "hide")
		if auto == "bothide":
			me.teleport(Vector3(6.5, 3.3, 3.5), 0.0)
	elif phase == "seek":
		if int(auto_t * 2) != int((auto_t - get_process_delta_time()) * 2):
			print("[bot] t=%.1f state=%s pos=%s spot=%d disguise=%s path=%d" % [auto_t, bot.state, bot.pos.snapped(Vector3.ONE * 0.1), bot.hide_spot, bot.disguise, bot.path.size()])
		if auto == "botsofa" and phase_left < seek_time - 2.0 and _cd_left("catch") <= 0.0:
			# the bot pretends to be a big sofa; stand 1.2 m from its edge and catch it
			bot.hide_spot = -1
			bot.disguise = "loungeSofaLong"
			bot.disguise_scale = 2.3
			bot.pos = Vector3(5.0, 0.0, 4.0)
			bot._push()
			remotes[Bot.ID].global_position = bot.pos
			var rad := _hider_radius(remotes[Bot.ID])
			me.teleport(bot.pos + Vector3(rad + 1.2, 0.1, 0), PI / 2.0)
			print("[bot] sofa radius %.2f, standing %.2f m from its centre" % [rad, rad + 1.2])
			_do_action("catch")
		if auto == "botseek" and phase_left < seek_time - 4.0:
			# walk straight to the bot and catch / check it
			if bot.hide_spot >= 0:
				me.teleport(house.hide_spots[bot.hide_spot]["exit"], 0.0)
				_do_action("search")
			else:
				me.teleport(bot.pos + Vector3(1.0, 0.1, 0), PI / 2.0)
				_do_action("catch")
	elif phase == "results" and not auto_done:
		auto_done = true
		print("[bot] AUTOTEST DONE t=%.1f scores=%s caught=%s" % [auto_t, str(scores), str(caught.keys())])
		get_tree().quit()


func _bench_tick(dt: float) -> void:
	var b := _bench
	b["t"] += dt
	if b["i"] >= 0 and b["t"] > 1.0:
		b["frames"] += 1
		b["draws"] += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	if b["i"] < 0 or b["t"] > 4.0:
		if b["i"] >= 0:
			var secs: float = b["t"] - 1.0
			b["results"].append([b["frames"] / secs, b["draws"] / maxf(1.0, b["frames"])])
			print("BENCH view=%d fps=%.1f draws=%d" % [b["i"], b["frames"] / secs, int(b["draws"] / maxf(1.0, b["frames"]))])
		b["i"] += 1
		b["t"] = 0.0
		b["frames"] = 0
		b["draws"] = 0
		if b["i"] >= BENCH_VIEWS.size():
			var tot := 0.0
			var worst := 999.0
			for r in b["results"]:
				tot += r[0]
				worst = minf(worst, r[0])
			print("BENCH DONE quality=%d avg_fps=%.1f worst_fps=%.1f" % [int(settings["quality"]), tot / b["results"].size(), worst])
			auto = ""
			get_tree().quit()
			return
		var v: Array = BENCH_VIEWS[b["i"]]
		me.teleport(Vector3(v[0], v[1], v[2]), v[3])
		me.pitch = v[4]
	# keep turning slowly so the view changes like real play
	me.yaw += dt * 0.6


func _log(s: String) -> void:
	if auto != "" and auto != "shot":
		print("[%s] %s" % [auto, s])


## Two copies of the game on one PC over the hotspot relay: go to chill mode together, walk
## about, measure how old the partner's positions are when they arrive, and check that a phone
## which missed "partner joined" or "go to chill mode" puts itself right.
var _sync := {}


func _sync_test(dt: float) -> void:
	if _sync.is_empty():
		_sync = {"t": 0.0, "ages": [], "chill": false, "dropped": false, "back": -1.0, "left": false, "rejoin": -1.0, "ok": true}
	_sync["t"] += dt
	var t: float = _sync["t"]
	if auto == "host" and phase == "lobby" and Net.players.size() >= 2 and not _sync["chill"] and t > 2.0:
		_sync["chill"] = true
		Net.broadcast({"t": "chill"})
	if phase == "chill":
		var a := t * 0.9 + (0.0 if auto == "host" else PI)
		stick_vec = Vector2(cos(a), sin(a))
	if auto == "host" and t > 7.0 and not _sync["dropped"]:
		# pretend we never heard about our partner
		_sync["dropped"] = true
		for id in remotes.keys():
			remotes[id].queue_free()
		remotes.clear()
		_sync["back"] = t
	if auto == "host" and _sync["back"] > 0.0 and not remotes.is_empty():
		print("[host] SYNC partner reappeared %.2fs after being forgotten" % (t - float(_sync["back"])))
		_sync["back"] = -1.0
	if auto == "join" and t > 8.0 and not _sync["left"] and phase == "chill":
		# pretend we missed the host's "chill" message
		_sync["left"] = true
		_to_lobby()
		_sync["rejoin"] = t
	if auto == "join" and _sync["rejoin"] > 0.0 and phase == "chill":
		print("[join] SYNC back in chill mode %.2fs after missing it" % (t - float(_sync["rejoin"])))
		_sync["rejoin"] = -1.0
	if t > (18.0 if auto == "host" else 12.0):
		var ages: Array = _sync["ages"]
		var avg := 0.0
		var worst := 0
		for g in ages:
			avg += g
			worst = maxi(worst, g)
		avg /= maxf(1.0, ages.size())
		var vis := "none"
		for id in remotes:
			var r: RemotePlayer = remotes[id]
			vis = "%s visible=%s err=%.2fm" % [r.player_name, r._visual.visible, r.global_position.distance_to(r._target)]
		print("[%s] SYNC states=%d avg_age=%.0fms worst=%dms phase=%s partner: %s" % [auto, ages.size(), avg, worst, phase, vis])
		get_tree().quit()


func _autotest(dt: float) -> void:
	auto_t += dt
	if auto.begins_with("bot"):
		_bot_autotest()
		return
	if phase == "menu" and auto_lan:
		if auto == "host" and auto_t > 0.5 and Net.state == "idle" and not Lan.hosting:
			_on_lan_host("Host", 0)
		elif auto == "join" and auto_t > 1.0 and Net.state == "idle":
			if not Lan.listening:
				_on_lan_find("Joiner", 1)
			elif not Lan.found.is_empty():
				_log("found games: " + str(Lan.found.keys()))
				_on_lan_join(Lan.found.keys()[0])
		if auto_t > 30.0:
			print("[%s] AUTOTEST FAIL: never connected" % auto)
			get_tree().quit(1)
	elif phase == "menu":
		if auto == "host" and auto_t > 0.5 and Net.state == "idle":
			_on_create("Host", 0, "")
		elif auto == "join" and auto_t > 1.0 and Net.state == "idle" and FileAccess.file_exists(auto_file):
			var code := FileAccess.get_file_as_string(auto_file).strip_edges()
			if code.length() == 4:
				_on_join(code, "Joiner", 1, "")
		if auto_t > 30.0:
			print("[%s] AUTOTEST FAIL: never connected" % auto)
			get_tree().quit(1)
	elif "--synctest" in OS.get_cmdline_user_args():
		_sync_test(dt)
	elif phase == "lobby":
		if auto == "host" and Net.players.size() >= 2 and auto_t > 2.0 and round_no == 0:
			auto_t = 0.0
			hide_time = 3.0
			seek_time = 10.0
			_host_start()
	elif phase == "seek" and "--quitmid" in OS.get_cmdline_user_args():
		print("[%s] quitting in the middle of the round" % auto)
		get_tree().quit()
	elif phase == "seek":
		if me.role == "seeker":
			if _cd_left("marco") <= 0.0:
				_do_action("marco")
			if _cd_left("sniff") <= 0.0:
				_do_action("sniff")
			if uses.get("pillow", 0) == PILLOWS:
				for id in remotes:
					var target: Vector3 = remotes[id].global_position
					me.teleport(target + Vector3(3.0, 0, 0), PI / 2.0)
					me.pitch = 0.0
				_do_action("pillow")
			elif phase_left < seek_time - 3.0 and _cd_left("catch") <= 0.0:
				for id in remotes:
					var target: Vector3 = remotes[id].global_position
					me.teleport(target + Vector3(1.2, 0, 0), PI / 2.0)
				_do_action("catch")
		elif uses.get("banana", 0) > 0:
			_do_action("banana")
			_do_action("say:" + CHAT[0])
			_do_action("disguise")
	elif phase == "results" and not auto_done:
		auto_done = true
		print("[%s] AUTOTEST PASS round=%d scores=%s" % [auto, round_no, str(scores)])
		get_tree().create_timer(1.0).timeout.connect(func(): get_tree().quit(0))
