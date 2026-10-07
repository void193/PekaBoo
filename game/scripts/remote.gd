class_name RemotePlayer
extends Node3D
## Another player, drawn from the state they send 15 times a second.

var id := -1
var player_name := ""
var char_index := 0
var color := Color.WHITE
var disguise := ""
var disguise_scale := Kit.SCALE
var hide_spot := -1
var ghost := false
var moving := false
var show_name := true
var house: House
var anim_name := "idle"
var outfit := {}
var pinned := false   # placed every frame by someone else (on the swing), don't glide to the network position

var _target := Vector3.ZERO
var _target_yaw := 0.0
var _prop_yaw := 0.0
var _first := true
var _visual: Node3D
var _rig: CharRig
var _prop: Node3D
var _label: Label3D
var _bubble: Label3D
var _bubble_t := 0.0
var _step_d := 0.0
var _last_pos := Vector3.ZERO
var _stun := 0.0
var _hop := 0.0
var _dance := 0.0
var _xray := 0.0
var prints := false            # leave glowing footprints (only the seeker's phone turns this on)
var on_footprint: Callable     # set by main
var _print_d := 0.0

static var _xray_mat: StandardMaterial3D
var _prop_mats := []
var _probe_t := 0.0


func setup(pid: int, pname: String, idx: int, c: Color, h: House) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # moved smoothly in _process already
	id = pid
	player_name = pname
	char_index = idx
	color = c
	house = h
	_visual = Node3D.new()
	add_child(_visual)
	_label = Label3D.new()
	_label.font = Kit.ui_font()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 56
	_label.pixel_size = 0.004
	_label.outline_size = 14
	_label.modulate = c.lightened(0.35)
	_label.outline_modulate = Color("#2b2033")
	_label.position.y = 1.85
	_label.text = pname
	add_child(_label)
	_bubble = Player.make_bubble()
	add_child(_bubble)
	_rebuild()


func _rebuild() -> void:
	for ch in _visual.get_children():
		ch.queue_free()
	_rig = null
	_prop = null
	if disguise != "":
		_prop = Kit.model(disguise, disguise_scale)
		_prop.rotation.y = _prop_yaw
		_visual.add_child(_prop)
		_prop_mats = Kit.apply_probe_look(_prop, 0.3)
		Kit.set_shadows(_prop, true)
	else:
		_rig = CharRig.new()
		_visual.add_child(_rig)
		_rig.setup(char_index, outfit)
		_rig.set_ghost(ghost)


var _vel := Vector3.ZERO      # how fast they're moving, to look a tiny bit ahead
var _last_state_t := 0.0
var last_heard := 0.0


func apply_state(m: Dictionary) -> void:
	var p = m.get("p", [0, 0, 0])
	var now := Time.get_ticks_msec() / 1000.0
	var np := Vector3(float(p[0]), float(p[1]), float(p[2]))
	var gap := now - _last_state_t
	if _last_state_t > 0.0 and gap > 0.01 and gap < 0.5:
		_vel = _vel.lerp((np - _target) / gap, 0.5)
	else:
		_vel = Vector3.ZERO
	_last_state_t = now
	last_heard = now
	_target = np
	_target_yaw = float(m.get("y", 0.0))
	moving = bool(m.get("m", false))
	hide_spot = int(m.get("h", -1))
	anim_name = str(m.get("a", "idle"))
	var d := str(m.get("d", ""))
	var ds := float(m.get("ds", Kit.SCALE))
	var dy := float(m.get("dy", 0.0))
	var g := bool(m.get("g", false))
	if d != disguise or g != ghost or (d != "" and absf(ds - disguise_scale) > 0.01):
		disguise = d
		disguise_scale = ds
		ghost = g
		_prop_yaw = dy
		_rebuild()
	if _prop != null and absf(dy - _prop_yaw) > 0.01:
		_prop_yaw = dy
		_prop.rotation.y = dy
	if _first or _target.distance_to(global_position) > 4.0:
		_first = false
		global_position = _target
		_last_pos = _target
		_visual.rotation.y = _target_yaw


func set_outfit(o: Dictionary) -> void:
	outfit = o
	_rebuild()


func reset_round_state() -> void:
	disguise = ""
	ghost = false
	hide_spot = -1
	_rebuild()


func set_ghost(on: bool) -> void:
	ghost = on
	disguise = ""
	_rebuild()


func say(text: String) -> void:
	Player.pop_bubble(_bubble, text)
	_bubble_t = 3.0


func stun(t: float) -> void:
	_stun = t


func hop() -> void:
	_hop = 0.5


func dance() -> void:
	_dance = CharRig.DANCE_LEN


var _dot: Label3D


## The seeker's X-ray: a blurry ring seen through walls, a few metres off from where this
## hider really is, so it says "somewhere around here", never "exactly here".
func xray(t: float, off := Vector3.ZERO) -> void:
	if _dot == null:
		_dot = Label3D.new()
		_dot.text = "◯"
		_dot.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_dot.no_depth_test = true
		_dot.fixed_size = true
		_dot.pixel_size = 0.0011
		_dot.font_size = 150
		_dot.outline_size = 10
		_dot.outline_modulate = Color(1, 1, 1, 0.9)
		_dot.render_priority = 10
		add_child(_dot)
	_dot.position = Vector3(off.x, 0.9, off.z)
	_dot.modulate = Color(0.5, 0.75, 1.0, 0.55)
	_dot.visible = true
	_xray = t


func _set_overlay(m: Material) -> void:
	for mi in Kit.meshes(_visual):
		(mi as GeometryInstance3D).material_overlay = m


func _process(dt: float) -> void:
	if not pinned:
		# glide towards where they are now, plus a little of where they're heading,
		# so they keep up with the other phone instead of trailing behind
		var ahead := _target
		var since := Time.get_ticks_msec() / 1000.0 - _last_state_t
		if moving and since < 0.25 and _vel.length() < 12.0:
			ahead += Vector3(_vel.x, 0.0, _vel.z) * minf(since + 0.03, 0.12)
		global_position = global_position.lerp(ahead, 1.0 - exp(-16.0 * dt))
	_probe_t -= dt
	if _probe_t <= 0.0 and house:
		_probe_t = 0.12
		var c := house.light_at(global_position + Vector3(0, 0.9, 0))
		if _rig:
			_rig.set_light(c)
		Kit.set_probe_light(_prop_mats, c)
	if _dance > 0.0:
		if _rig == null:
			_visual.rotation.y += dt * 9.0
	else:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, _target_yaw, 1.0 - exp(-12.0 * dt))
	var on_bike: bool = hide_spot >= 0 and house != null and hide_spot < house.hide_spots.size() and house.hide_spots[hide_spot].get("kind", "") == "bike"
	_visual.visible = hide_spot < 0 or on_bike
	if _xray > 0.0:
		_xray -= dt
		if _dot:
			_dot.modulate.a = clampf(_xray * 2.0, 0.0, 1.0) * (0.45 + 0.15 * sin(_xray * 10.0))
		if _xray <= 0.0 and _dot:
			_dot.visible = false
	if _hop > 0.0:
		_hop -= dt
		_visual.position.y = sin((0.5 - _hop) / 0.5 * PI) * 0.45
		_visual.rotation.z = sin(_hop * 40.0) * 0.12
	elif _dance > 0.0:
		_dance -= dt
		_visual.rotation.z = 0.0
		if _rig:
			_rig.dance_tick(CharRig.DANCE_LEN - maxf(_dance, 0.0), _target_yaw, _visual)
		else:
			_visual.position.y = absf(sin(_dance * 9.0)) * 0.3
	else:
		_visual.position.y = 0.0
		_visual.rotation.z = 0.0
	if anim_name == "lie":
		_visual.rotation.x = PI / 2.0
	elif not pinned:
		_visual.rotation.x = 0.0
	if anim_name == "lie":
		_visual.rotation.y = 0.0
	_label.visible = show_name and hide_spot < 0 and disguise == ""
	if _rig != null:
		if anim_name != "" and anim_name != _rig.current:
			if anim_name in ["jump", "emote-yes", "emote-no", "interact-right", "pick-up"]:
				_rig.gesture(anim_name)
			else:
				_rig.play(anim_name)
		if _stun > 0.0:
			_stun -= dt
			_rig.rotation.y += dt * 16.0
		else:
			_rig.rotation.y = 0.0
	# footsteps you can hear through the house
	if not ghost and hide_spot < 0 and disguise == "":
		var moved := Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
		if prints and anim_name != "crouch" and on_footprint.is_valid():
			_print_d += moved
			if _print_d > 0.75:
				_print_d = 0.0
				on_footprint.call(global_position)
		_step_d += moved
		var stride := 0.55 if anim_name == "crouch" else 0.85
		if _step_d > stride:
			_step_d = 0.0
			var vol := -18.0 if anim_name == "crouch" else -4.0
			Sfx.footstep_at(house.surface_at(global_position) if house else "wood", global_position, vol)
	_last_pos = global_position
	if _bubble_t > 0.0:
		_bubble_t -= dt
		_bubble.modulate.a = clampf(_bubble_t * 2.0, 0.0, 1.0)
		if _bubble_t <= 0.0:
			_bubble.visible = false
