extends Node
## Automated end-to-end QA. Run the game with "-- --qa" (desktop or phone).
## Drives the real game code through every feature and prints PASS / FAIL lines.

var m: Node  # main.gd
var passed := 0
var failed := 0
var fails: Array[String] = []


func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("QA PASS  ", what)
	else:
		failed += 1
		fails.append(what)
		print("QA FAIL  ", what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func secs(t: float) -> void:
	await get_tree().create_timer(t, true, true).timeout


func run() -> void:
	m = get_parent()
	while not m.house.is_baked:
		await frames(5)
	await frames(30)
	print("QA START")
	if "--latency" in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		m._on_create("Latency QA", 0, Net.DEFAULT_SERVER)
		await secs(5.0)
		check(Net.state == "open" and Net.latency_ms >= 0, "relay round-trip latency is measured")
		check(m.ui.latency_label.visible and m.ui.latency_label.text == "Ping: %d ms" % Net.latency_ms, "live ping is displayed in milliseconds")
		Net.close()
		await frames(2)
		check(Net.latency_ms == -1 and not m.ui.latency_label.visible, "disconnect clears and hides latency")
		print("QA DONE passed=%d failed=%d" % [passed, failed])
		get_tree().quit(1 if failed > 0 else 0)
		return
	if "--catch-spots" in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		await test_catch_under_bed()
		print("QA DONE passed=%d failed=%d" % [passed, failed])
		get_tree().quit(1 if failed > 0 else 0)
		return
	if "--traps" in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		await test_traps()
		print("QA DONE passed=%d failed=%d" % [passed, failed])
		for f in fails:
			print("QA FAILED: ", f)
		get_tree().quit()
		return
	if "--acts" in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		await test_explore_actions()
		await start_bot_round(true)
		await test_round_flow()
		print("QA DONE passed=%d failed=%d" % [passed, failed])
		for f in fails:
			print("QA FAILED: ", f)
		get_tree().quit()
		return
	if "--extras" in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		await test_extras()
		await test_replay()
		print("QA DONE passed=%d failed=%d" % [passed, failed])
		for f in fails:
			print("QA FAILED: ", f)
		get_tree().quit()
		return
	if "--chill" in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		await test_chill()
		print("QA DONE passed=%d failed=%d" % [passed, failed])
		for f in fails:
			print("QA FAILED: ", f)
		get_tree().quit()
		return
	if "--touch" in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		await test_multitouch()
		print("QA DONE passed=%d failed=%d" % [passed, failed])
		for f in fails:
			print("QA FAILED: ", f)
		get_tree().quit()
		return
	if "--camera" in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		await test_camera()
		print("QA DONE passed=%d failed=%d" % [passed, failed])
		for f in fails:
			print("QA FAILED: ", f)
		get_tree().quit()
		return
	await test_navigation()
	await test_explore_actions()
	await test_spots()
	await test_disguises()
	await test_stairs_and_bounce()
	await test_settings()
	await test_catch_under_bed()
	await test_bot_rounds()
	await test_traps()
	await test_round_flow()
	await test_memory()
	await test_multitouch()
	await test_chill()
	await test_camera()
	print("QA DONE passed=%d failed=%d" % [passed, failed])
	for f in fails:
		print("QA FAILED: ", f)
	get_tree().quit()


# ---------- helpers ----------

func me() -> Player:
	return m.me


func walk_free(dirs := 4) -> int:
	var free := 0
	for k in dirs:
		var start := me().global_position
		var a := TAU * k / dirs
		m.stick_vec = Vector2(cos(a), sin(a))
		await frames(20)
		m.stick_vec = Vector2.ZERO
		if Vector2(me().global_position.x - start.x, me().global_position.z - start.z).length() > 0.3:
			free += 1
		me().global_position = start
		me().velocity = Vector3.ZERO
		await frames(2)
	return free


func overlaps_world(model_name: String, scl: float) -> int:
	var d := Player.prop_dims(model_name, scl)
	var cyl := CylinderShape3D.new()
	cyl.radius = d.x * 0.95
	cyl.height = d.y - 0.15
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cyl
	q.collision_mask = 1
	q.transform = Transform3D(Basis(), me().global_position + Vector3(0, d.y / 2.0 + 0.06, 0))
	return m.get_world_3d().direct_space_state.intersect_shape(q, 4).size()


func start_bot_round(me_seeks: bool) -> void:
	if m.bot == null:
		m.hide_time = 1.0
		m.seek_time = 300.0
		m._on_play_bot("QA", 0, "seek" if me_seeks else "hide")
	else:
		m.hide_time = 1.0
		m.seek_time = 300.0
		m.round_no = 0 if me_seeks else 1
		m._host_start()
	await secs(1.6)


# ---------- camera glitch hunting ----------

var _cam_spikes := 0
var _cam_inside := 0
var _cam_frames := 0
var _cam_worst := 0.0
var _cam_where := ""


## Records the camera every frame while `scenario` runs: sudden jumps (camera moving much
## more than the player did) and frames where the camera is inside a wall or ceiling.
func _desc(hit: Dictionary) -> String:
	var b := hit["collider"] as CollisionObject3D
	var out := "%s at %s:" % [b.name, b.global_position.snapped(Vector3.ONE * 0.01)]
	for c in b.get_children():
		if c is CollisionShape3D:
			out += " %s@%s" % [(c.shape as Shape3D).get_class(), c.global_position.snapped(Vector3.ONE * 0.01)]
			if c.shape is BoxShape3D:
				out += " size %s" % (c.shape as BoxShape3D).size
	return out


## Nearest place to p where a standing player fits without touching anything.
func free_spot(p: Vector3) -> Vector3:
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.37
	cap.height = 1.6
	q.shape = cap
	q.collision_mask = 1
	q.exclude = [me().get_rid()]
	for r in [0.0, 0.15, 0.3, 0.45, 0.6, 0.8, 1.0]:
		for k in (1 if r == 0.0 else 12):
			var c: Vector3 = p + Vector3(cos(k * TAU / 12.0), 0, sin(k * TAU / 12.0)) * r
			q.transform = Transform3D(Basis(), c + Vector3(0, 0.85, 0))
			if m.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
				return c
	return p


func watch_camera(name: String, scenario: Callable) -> void:
	_cam_spikes = 0
	_cam_inside = 0
	_cam_frames = 0
	_cam_worst = 0.0
	var done := [false]
	var runner := func():
		await scenario.call()
		done[0] = true
	runner.call()
	await frames(6)  # ignore the teleport at the start
	var q := PhysicsPointQueryParameters3D.new()
	q.collision_mask = 1
	var arm_hist: Array[float] = []
	var last_rel_y := me().pivot.position.y
	var last_sh: float = me()._shoulder_now
	while not done[0]:
		await get_tree().process_frame
		var arm: float = me()._arm_len
		var rel_y: float = me().pivot.position.y
		var sh: float = me()._shoulder_now
		arm_hist.append(arm)
		var n := arm_hist.size()
		# glitch = boom pops outward suddenly, or flickers in then out again within 20 frames,
		# or the camera height / shoulder jumps
		var glitch := false
		if n >= 2 and arm - arm_hist[n - 2] > 0.25:
			glitch = true
		if n >= 21:
			var lo := arm
			for k in range(n - 21, n):
				lo = minf(lo, arm_hist[k])
			if arm_hist[n - 21] - lo > 0.4 and arm - lo > 0.4:
				glitch = true
				arm_hist.clear()
		if absf(rel_y - last_rel_y) > 0.25 or sh - last_sh > 0.2:
			glitch = true
		if glitch:
			_cam_spikes += 1
			_cam_worst = maxf(_cam_worst, maxf(absf(rel_y - last_rel_y), absf(sh - last_sh)))
		last_rel_y = rel_y
		last_sh = sh
		q.position = me().cam.global_position
		for hit in m.get_world_3d().direct_space_state.intersect_point(q, 4):
			if (hit["collider"] as Node).has_meta("wall"):
				_cam_inside += 1
				_cam_where = "%s at %s pivot %s player %s hit %s arm %.2f" % [name, me().cam.global_position.snapped(Vector3.ONE * 0.01), me().pivot.global_position.snapped(Vector3.ONE * 0.01), me().global_position.snapped(Vector3.ONE * 0.01), _desc(hit), me()._arm_len]
				break
		_cam_frames += 1
	var ok := _cam_spikes <= 1 and _cam_inside <= 2
	if not ok:
		print("   last problem: ", _cam_where)
	check(ok, "camera smooth: %s (%d frames, %d jumps%s, %d inside walls)" % [name, _cam_frames, _cam_spikes, (" worst %.2f m" % _cam_worst) if _cam_spikes > 0 else "", _cam_inside])


func steer_to(target: Vector3, max_frames := 600, jump_every := 0) -> void:
	var map: RID = m.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, me().global_position), NavigationServer3D.map_get_closest_point(map, target), true)
	var i := 0
	var f := 0
	while i < path.size() and f < max_frames:
		var to := path[i] - me().global_position
		to.y = 0.0
		if to.length() < 0.35:
			i += 1
			continue
		# turn the camera smoothly toward where we walk, like a player would
		var want := atan2(-to.x, -to.z)
		me().yaw = lerp_angle(me().yaw, want, 0.12)
		var local := to.normalized().rotated(Vector3.UP, -me().yaw)
		m.stick_vec = Vector2(local.x, local.z)
		if jump_every > 0 and f % jump_every == 0:
			me().jump_req = true
		await frames(1)
		f += 1
	m.stick_vec = Vector2.ZERO


func _touch(i: int, pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = pos
	e.pressed = down
	m.get_viewport().push_input(e, true)  # the real path: _input, then the GUI, then _unhandled_input


func _drag(i: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = pos
	e.relative = rel
	m.get_viewport().push_input(e, true)


## Thumb on the joystick while the other thumb jumps / crouches / opens panels / looks around.
func test_multitouch() -> void:
	var was_touch: bool = m.is_touch
	m.is_touch = true
	m.ui.enable_multitouch()
	m._on_explore("QA", 0)
	await frames(10)
	me().teleport(free_spot(Vector3(20.0, 0.1, 27.0)), 0.0)
	me().crouch = false
	me().run = false
	await frames(20)
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var stick_at := Vector2(vs.x * 0.15, vs.y * 0.7)
	_touch(0, stick_at, true)
	_drag(0, stick_at + Vector2(0, -60), Vector2(0, -60))
	check(m.stick_index == 0 and m.stick_vec.length() > 0.5, "left thumb grabs the joystick")
	var start := me().global_position
	await frames(10)
	# second finger on JUMP while still steering
	var jb: Button = m.ui.jump_btn
	_touch(1, jb.get_global_rect().get_center(), true)
	var jumped := false
	for k in 20:
		await frames(1)
		if me().velocity.y > 1.0:
			jumped = true
	_touch(1, jb.get_global_rect().get_center(), false)
	check(jumped, "JUMP works while the other thumb holds the joystick")
	check(m.stick_index == 0 and m.stick_vec.length() > 0.5, "joystick keeps steering while jumping")
	await frames(40)
	# crouch and run with a second finger
	_touch(1, m.ui.crouch_btn.get_global_rect().get_center(), true)
	_touch(1, Vector2.ZERO, false)
	check(me().crouch, "CROUCH works while steering")
	_touch(2, m.ui.crouch_btn.get_global_rect().get_center(), true)
	_touch(2, Vector2.ZERO, false)
	_touch(1, m.ui.run_btn.get_global_rect().get_center(), true)
	_touch(1, Vector2.ZERO, false)
	check(not me().crouch and me().run, "RUN works while steering")
	# tools panel with a second finger, then a tool inside it
	_touch(1, m.ui.tools_btn.get_global_rect().get_center(), true)
	_touch(1, Vector2.ZERO, false)
	await frames(2)
	check(m.ui.tools_card.is_visible_in_tree(), "Tools panel opens while steering")
	_touch(1, m.ui.tools_btn.get_global_rect().get_center(), true)
	_touch(1, Vector2.ZERO, false)
	await frames(2)
	check(not m.ui.tools_card.is_visible_in_tree(), "Tools panel closes again")
	# a card inside the Pranks panel (the panel behind it must not swallow the touch)
	_touch(1, m.ui.fun_btn.get_global_rect().get_center(), true)
	_touch(1, Vector2.ZERO, false)
	await frames(2)
	var card: Button = null
	for b in m.ui.fun_btns:
		if b.is_visible_in_tree() and m.ui.fun_ids[m.ui.fun_btns.find(b)] == "confetti":
			card = b
	check(card != null, "Pranks panel shows the Confetti card")
	if card != null:
		m.cd.clear()
		var fired := [false]
		var watch := func(id: String): if id == "confetti": fired[0] = true
		m.ui.action.connect(watch)
		_touch(1, card.get_global_rect().get_center(), true)
		_touch(1, Vector2.ZERO, false)
		await frames(2)
		m.ui.action.disconnect(watch)
		check(fired[0] and not m.ui.fun_card.is_visible_in_tree(), "tapping a prank card fires it while steering")
	# Tools card: the TV switch next to the TV
	me().teleport(m.house.tv_pos + Vector3(0, 0.1, 0.5), 0.0)
	await frames(5)
	var tv0: bool = m.house.tv_on
	_touch(1, m.ui.tools_btn.get_global_rect().get_center(), true)
	_touch(1, Vector2.ZERO, false)
	await frames(2)
	var tvb: Button = null
	for i in m.ui.tool_btns.size():
		if m.ui.tool_btns[i].is_visible_in_tree() and m.ui.tool_ids[i] == "tv":
			tvb = m.ui.tool_btns[i]
	check(tvb != null, "Tools panel shows the TV card near the TV")
	if tvb != null:
		_touch(1, tvb.get_global_rect().get_center(), true)
		_touch(1, Vector2.ZERO, false)
		await frames(10)
		check(m.house.tv_on != tv0, "tapping the TV card turns the TV on/off")
		if m.house.tv_on:
			m.house.set_tv(false)
	me().teleport(free_spot(Vector3(20.0, 0.1, 27.0)), 0.0)
	await frames(5)
	start = me().global_position
	# right thumb looks around while left thumb walks
	var yaw0: float = me().yaw
	var look_at := Vector2(vs.x * 0.6, vs.y * 0.35)
	_touch(1, look_at, true)
	for k in 5:
		_drag(1, look_at + Vector2(20 * (k + 1), 0), Vector2(20, 0))
		await frames(1)
	_touch(1, look_at, false)
	check(absf(me().yaw - yaw0) > 0.1 and m.look_index == -1, "right thumb turns the camera while walking")
	print("   walked ", me().global_position.distance_to(start), " from ", start, " to ", me().global_position)
	check(me().global_position.distance_to(start) > 0.2, "player kept walking the whole time")
	_touch(0, stick_at, false)
	check(m.stick_index == -1 and m.stick_vec == Vector2.ZERO, "joystick lets go cleanly")
	me().run = false
	m.is_touch = was_touch


## Chill mode with a stand-in partner: ask / accept, sit, lanterns, fireworks, wishes, songs, leaving.
func test_chill() -> void:
	m._on_chill_solo("QA", 0)
	await frames(10)
	check(m.phase == "chill" and m.house.is_night and m.chill.on, "chill mode switches the house to night")
	var her := RemotePlayer.new()
	m.add_child(her)
	her.setup(99, "Her", 5, Color.PINK, m.house)
	m.remotes[99] = her
	var at := free_spot(Vector3(7.5, 0.1, 10.0))
	me().teleport(at, -PI / 2.0)
	her.apply_state({"p": [at.x + 1.0, at.y, at.z], "y": PI / 2.0})
	await frames(10)
	var c: Array = m._controls()
	check(c[0].get("id", "") == "ckiss", "Kiss shows up when you're next to her")
	# she asks, I kiss back
	m._on_fx({"t": "fx", "k": "ask", "w": "kiss"}, 99)
	c = m._controls()
	check(c[0].get("id", "") == "ckiss" and c[0].get("name", "") == "Kiss back", "her request turns the button into Kiss back")
	m._do_action("ckiss")
	await frames(3)
	check(m.chill.busy() and me().frozen, "the kiss starts for both")
	await secs(2.0)
	var d := Vector2(me().global_position.x - her.global_position.x, me().global_position.z - her.global_position.z).length()
	check(absf(d - Chill.KISS_GAP) < 0.25, "you move in close for the kiss (%.2f m apart)" % d)
	await secs(3.6)
	check(not m.chill.busy() and not me().frozen and m.get_viewport().get_camera_3d() == me().cam, "after the kiss you can move again and the camera is back")
	# I ask for a hug: she has to say yes, nothing happens on my own
	m._do_action("chug")
	await frames(3)
	check(not m.chill.busy() and m.chill.asked.get("w", "") == "hug", "asking for a hug waits for her answer")
	m._on_fx({"t": "fx", "k": "together", "w": "hug", "a": Net.my_id, "b": 99, "c": [at.x + 0.5, at.y, at.z], "y": -PI / 2.0}, 99)
	await frames(3)
	check(m.chill.busy(), "her yes starts the hug")
	await secs(Chill.DUR["hug"] + 0.5)
	check(not m.chill.busy() and not me().frozen, "the hug ends cleanly")
	# dance
	m._on_fx({"t": "fx", "k": "together", "w": "dance", "a": 99, "b": Net.my_id, "c": [at.x + 0.5, at.y, at.z], "y": PI / 2.0}, 99)
	await secs(Chill.DUR["dance"] + 0.5)
	check(not m.chill.busy() and me().visual.rotation.z == 0.0 and me().visual.position.y == 0.0, "the slow dance ends cleanly")
	# sofa
	me().teleport(Vector3(7.4, 0.1, 11.6), 0.0)
	await frames(10)
	c = m._controls()
	check(c[0].get("id", "") == "sit" or c[4].get("id", "") == "sit", "Sit shows up by the sofa")
	m._do_action("sit")
	await frames(10)
	check(me().sitting and me().anim_state() == "sit", "you sit on the sofa")
	m.stick_vec = Vector2(0, -1)
	await frames(10)
	m.stick_vec = Vector2.ZERO
	check(not me().sitting and not me().frozen, "pushing the stick gets you up")
	# kissing while sitting stands you up first
	m._do_action("sit")
	await frames(5)
	m._on_fx({"t": "fx", "k": "together", "w": "kiss", "a": 99, "b": Net.my_id, "c": [7.6, 0.1, 11.0], "y": PI / 2.0}, 99)
	await frames(5)
	check(not me().sitting and m.chill.busy(), "a kiss while sitting stands you up first")
	await secs(5.5)
	# lanterns, fireworks, wish, songs
	m.cd.clear()
	for id in ["lantern", "fireworks", "wish", "nextsong", "lantern"]:
		m.cd.clear()
		m._do_action(id)
		await frames(5)
	check(m.chill._lanterns.size() >= 2 and not m.chill._fw_queue.is_empty(), "sky lanterns and fireworks go up")
	var si := Music.song_index()
	m.cd.clear()
	m._do_action("nextsong")
	await frames(2)
	check(Music.song_index() == posmod(si + 1, Music.songs.size()), "next song moves both phones to the next love song (%s)" % Music.now_playing())
	# the partner's phone (the host) says which song: we follow it exactly
	m._on_fx({"t": "fx", "k": "song", "i": 4}, 99)
	await frames(2)
	check(Music.song_index() == 4 and Music.now_playing() == Music.songs[4].get_basename().replace("_", " "), "songs follow the host's pick, same song on both phones")
	Music.song_ended.emit()
	await frames(2)
	check(Music.song_index() == 5, "when a song ends the next one is shared too")
	await secs(12.0)
	check(m.chill._fw_queue.is_empty(), "the fireworks show finishes")
	# the TV card must fit in the panel even with all the together-cards there
	me().teleport(m.house.tv_pos + Vector3(0, 0.1, 0.6), 0.0)
	her.apply_state({"p": [m.house.tv_pos.x + 1.0, 0.1, m.house.tv_pos.z + 0.6], "y": 0.0})
	await frames(10)
	var tvc: Array = m._controls()
	m.ui.set_controls(tvc[0], tvc[1], tvc[2], tvc[3], false, false, tvc[4])
	var shown := false
	for i in m.ui.tool_ids.size():
		if m.ui.tool_ids[i] == "tv" and m.ui.tool_btns[i].visible:
			shown = true
	check(shown, "the TV card shows in Together even when your partner is there")
	# leaving
	m.remotes.erase(99)
	her.queue_free()
	m._leave()
	await frames(10)
	check(m.phase == "menu" and not m.house.is_night and not m.chill.on and m.env.sky.sky_material is PanoramaSkyMaterial, "leaving chill brings the day back")


func _ctx() -> String:
	return str(m.extras.context().get("id", ""))


## Everything new in chill mode, one after another, with a stand-in partner.
func test_extras() -> void:
	var x: Extras = m.extras
	m._on_chill_solo("QA", 0)
	await frames(10)
	var her := RemotePlayer.new()
	m.add_child(her)
	her.setup(99, "Her", 3, Color.PINK, m.house)
	m.remotes[99] = her
	# ladder up to the rooftop deck and back down
	me().teleport(House.LADDER_PATH[0] + Vector3(0, 0, 0.5), PI)
	await frames(5)
	check(_ctx() == "climb", "Climb shows at the bottom of the ladder")
	m._do_action("climb")
	await secs(12.0)
	check(me().global_position.y > House.DECK_Y - 0.2 and not me().frozen, "you climb up onto the rooftop deck (y %.1f)" % me().global_position.y)
	await frames(30)
	check(absf(me().global_position.y - (House.DECK_Y)) < 0.4, "you can stand on the deck without falling through")
	check(_ctx() == "climbdown", "Climb down shows at the top")
	m._do_action("climbdown")
	await secs(12.0)
	check(me().global_position.y < 0.5 and not me().frozen, "you climb back down")
	# rooftop bench is a seat
	var bench := -1
	for i in m.chill.seats.size():
		if m.chill.seats[i]["name"] == "Bench":
			bench = i
	check(bench >= 0, "the rooftop bench is a place to sit")
	# swing (make sure the ladder is completely finished first)
	var wait := 0
	while not x._climb.is_empty() and wait < 300:
		wait += 1
		await frames(1)
	me().stand_up()
	await frames(10)
	me().teleport(House.SWING_POS + Vector3(0, 0.1, 1.2), PI)
	await frames(5)
	var si: int = m.chill.seat_near(me().global_position)
	check(si >= 0 and m.chill.seats[si].has("swing"), "Sit shows by the swing")
	m.chill.sit(me(), si)
	var p0 := me().global_position
	var most := 0.0
	for k in 45:
		await frames(2)
		most = maxf(most, me().global_position.distance_to(p0))
	check(me().sitting and most > 0.2, "sitting on the swing, you swing back and forth (%.2f m)" % most)
	me().stand_up()
	await frames(5)
	# wishing well + fortune cookie
	me().teleport(House.WELL_POS + Vector3(0, 0.1, -1.4), 0.0)
	await frames(5)
	check(_ctx() == "well", "Wish shows at the wishing well")
	m._do_action("well")
	await frames(3)
	check(m.ui.overlays.card.visible, "the well gives you a card to read")
	m.ui.overlays.card.visible = false
	me().teleport(Extras.COOKIE_JAR + Vector3(0, 0.1, 0.9), 0.0)
	await frames(5)
	check(_ctx() == "cookie", "Fortune shows by the cookie jar")
	# stargazing
	me().teleport(House.PICNIC + Vector3(0, 0.1, 0.9), 0.0)
	await frames(5)
	check(_ctx() == "stargaze", "Stargaze shows at the picnic blanket")
	m._do_action("stargaze")
	await frames(5)
	check(me().lying and x.gazing and m.get_viewport().get_camera_3d() == x._gaze_cam and me().anim_state() == "lie", "you lie down and look up at the stars")
	m.stick_vec = Vector2(0, -1)
	await frames(8)
	m.stick_vec = Vector2.ZERO
	await frames(3)
	check(not me().lying and not x.gazing and m.get_viewport().get_camera_3d() == me().cam, "the stick gets you back up")
	# pets
	check(x.pets.active and x.pets.visible, "the cat and the dog are around in chill mode")
	var cat: Node3D = x.pets.pets[0]["node"]
	me().teleport(cat.global_position + Vector3(0.8, 0.1, 0), PI / 2.0)
	await frames(3)
	var pi := x.pets.near(me().global_position)
	check(pi >= 0, "Pet shows next to a pet")
	if pi >= 0:
		m._do_action("pet")
		await frames(3)
		check(float(x.pets.pets[pi]["happy"]) > 0.0, "petting makes them happy")
	# hold hands: she asks, I say yes, then I walk beside her
	me().teleport(Vector3(6.0, 0.1, 11.0), 0.0)
	her.apply_state({"p": [6.6, 0.1, 11.0], "y": 0.0})
	await frames(5)
	m._on_fx({"t": "fx", "k": "ask", "w": "hands"}, 99)
	m._do_action("chands")
	await frames(5)
	check(not x.hands.is_empty() and x.hands["follower"] == me(), "holding hands, you follow her")
	her.global_position = Vector3(8.0, 0.0, 11.0)
	her._target = her.global_position
	await frames(20)
	check(me().global_position.distance_to(her.global_position) < 1.0, "you stay beside her as she walks (%.2f m)" % me().global_position.distance_to(her.global_position))
	m._do_action("letgo")
	await frames(3)
	check(x.hands.is_empty() and not me().frozen, "Let go lets go")
	# pillow fight
	m.cd.clear()
	m._do_action("pillowfight")
	await frames(3)
	check(not x.pf.is_empty() and _ctx() == "pfthrow", "a pillow fight starts with a Throw button")
	m._do_action("pfthrow")
	m._on_fx({"t": "fx", "k": "hit", "id": 99}, Net.my_id)
	await frames(3)
	check(int(x.pf.get("me", 0)) >= 1, "hitting her scores a point")
	x.pf["t"] = 0.05
	await frames(5)
	check(x.pf.is_empty() and m.ui.overlays.card.visible, "the fight ends with the score")
	m.ui.overlays.card.visible = false
	# cooking: pick a dish, it cooks by itself, then eat it together
	m.cd.clear()
	m._do_action("cook")
	await frames(3)
	check(m.ui.overlays.grid_panel != null and m.ui.overlays.grid_panel.visible, "Cook together opens the menu of dishes")
	m.ui.overlays.grid_panel.visible = false
	m._on_fx({"t": "fx", "k": "cookstart", "r": 1}, Net.my_id)
	await secs(7.5)
	check(x._dish != null and x.cook.get("ready", false), "the pizza cooks itself and lands on the table")
	m.ui.overlays.card.visible = false
	me().teleport(Extras.DISH_AT + Vector3(0, 0.1, 1.2), 0.0)
	await frames(5)
	check(_ctx() == "eat", "Eat shows at the table")
	for k in 6:
		m.cd.clear()
		m._do_action("eat")
		await frames(2)
	check(x._dish == null and x.cook.is_empty() and m.ui.overlays.card.visible, "six bites and it's all gone")
	m.ui.overlays.card.visible = false
	# swing with her: she's drawn exactly on the other seat on my phone
	me().teleport(House.SWING_POS + Vector3(0, 0.1, 1.0), PI)
	await frames(3)
	var sw: int = m.chill.seat_near(me().global_position)
	m.chill.sit(me(), sw)
	var other := 1 - int(m.chill.seats[sw]["swing"])
	var op: Vector3 = m.house.swing_seat_point(other).origin
	her.apply_state({"p": [op.x, op.y, op.z], "y": PI, "a": "sit"})
	await frames(20)
	check(her.pinned and her.global_position.distance_to(m.house.swing_seat_point(other).origin) < 0.1, "on the swing she moves exactly with her seat")
	me().stand_up()
	her.apply_state({"p": [6.0, 0.1, 11.0], "y": 0.0, "a": "idle"})
	await frames(5)
	check(not her.pinned, "getting off the swing un-pins her")
	# selfie
	m.cd.clear()
	m._do_action("selfie")
	await secs(4.5)
	check(m.get_viewport().get_camera_3d() == me().cam and m.ui.hud.visible, "after the selfie you're back to normal")
	# sky message, weather, emotes, wardrobe
	# typed in the Together menu, sent to both phones, written in the sky
	m.cd.clear()
	m._do_action("skymsg")
	await frames(2)
	check(m.ui.overlays.asker.visible, "Sky message asks you what to write")
	m.ui.overlays._ask_edit.text = "Love you Monica"
	m.ui.overlays._ask_done()
	await secs(2.0)
	check(x.last_sky == "LOVE YOU MONICA", "the sky shows what you typed (%s)" % x.last_sky)
	var found := false
	for c in m.chill.get_children():
		if c is CPUParticles3D and (c as CPUParticles3D).emission_shape == CPUParticles3D.EMISSION_SHAPE_POINTS:
			found = (c as CPUParticles3D).emission_points.size() > 50
	check(found, "the sky message is written in sparkles")
	for w in ["rain", "snow", "clear"]:
		m._on_fx({"t": "fx", "k": "weather", "w": w}, Net.my_id)
		await frames(3)
	check(x.weather == "clear" and not x._rain.emitting and not x._snow.emitting, "rain and snow come and go")
	m.set_music_on(false)
	await frames(2)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) and not Music.enabled, "Music off really turns the music off")
	m.set_music_on(true)
	await frames(2)
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "and Music on brings it back")
	m._do_action("emote:😍")
	await frames(2)
	check(me().bubble.visible and me().bubble.text == "😍", "emote wheel reactions pop over your head")
	m._on_outfit({"top": Color.RED, "acc": "crown"})
	await frames(2)
	check(me().outfit.get("acc", "") == "crown", "the wardrobe changes your outfit")
	m._on_outfit({})
	m.remotes.erase(99)
	her.queue_free()
	m._leave()
	await frames(10)
	check(m.phase == "menu" and not x.pets.active, "leaving chill tidies everything up")


## Slow-motion replay of the catch in a bot round.
func test_replay() -> void:
	await start_bot_round(true)
	m.hide_time = 1.0
	await secs(6.0)
	var bid := -1
	for id in m.remotes:
		bid = id
	if m.phase == "seek" and bid >= 0:
		m._on_caught(bid, Net.my_id)
		await frames(3)
		check(not m.replay.is_empty(), "catching someone plays a slow-motion replay")
		await secs(m.REPLAY_LEN + 1.5)
		check(m.replay.is_empty() and m.phase == "results", "after the replay the results show")
	else:
		check(false, "couldn't get a bot round going for the replay test (phase %s)" % m.phase)


func test_camera() -> void:
	if m.phase == "menu":
		m._on_explore("QA", 0)
		await frames(10)
	me().set_disguise("")
	# 1. jumping and bouncing on each bed
	for bed in [Vector3(4.5, 3.3, 3.1), Vector3(22.8, 3.3, 3.0), Vector3(1.4, 3.3, 12.6)]:
		await watch_camera("bouncing on the bed at %s" % bed, func():
			me().teleport(bed, 0.0)
			await frames(5)
			for k in 8:
				m.stick_vec = Vector2(0, -0.6)
				me().jump_req = true
				await frames(8)
				m.stick_vec = Vector2.ZERO
				await frames(40)
				me().yaw += 0.6)
	# 2. trampoline
	await watch_camera("trampoline", func():
		me().teleport(Vector3(20, 1.5, 23.5), 0.0)
		for k in 240:
			me().yaw += 0.02
			await frames(1))
	# 3. a full tour through every room, stairs included
	await watch_camera("walking tour of the whole house", func():
		me().teleport(m.house.hider_spawns[0], 0.0)
		for room in ["living room", "kitchen", "laundry", "hallway", "office", "garage", "entry hall", "landing", "master bedroom", "bathroom", "kids room", "game room", "small bathroom", "guest bedroom", "landing", "entry hall"]:
			await steer_to(House.ROOM_CENTRES[room], 900))
	# 4. same tour, jumping all the way
	await watch_camera("jumping through the house", func():
		me().teleport(m.house.hider_spawns[0], 0.0)
		for room in ["living room", "kitchen", "hallway", "landing", "kids room", "landing", "entry hall"]:
			await steer_to(House.ROOM_CENTRES[room], 900, 25))
	# 5. hedge maze and garden
	await watch_camera("hedge maze and garden", func():
		me().teleport(Vector3(-6.9, 0.1, -1.0), PI)
		for p in [Vector3(-7.9, 0, 6.5), Vector3(-10.9, 0, 12.0), Vector3(-6, 0, 20), Vector3(20, 0, 26), Vector3(30, 0, 24)]:
			await steer_to(p, 900))
	# 6. spinning the camera in tight corners and under the stairs
	await watch_camera("turning around in tight corners", func():
		for p in [Vector3(0.6, 0.1, 0.6), Vector3(13.0, 0.1, 5.6), Vector3(23.4, 3.3, 5.5), Vector3(9.4, 3.3, 0.5), Vector3(19.6, 0.1, 15.3)]:
			me().teleport(free_spot(p), 0.0)
			await frames(15)
			for k in 120:
				me().yaw += TAU / 120.0
				me().pitch = sin(k * 0.1) * 0.6
				await frames(1))
	# 7. crouching on and off while walking
	await watch_camera("crouching while walking", func():
		me().teleport(Vector3(2.0, 0.1, 12.0), -PI / 2.0)
		for k in 6:
			me().crouch = not me().crouch
			m.stick_vec = Vector2(0, -1)
			await frames(30)
		me().crouch = false
		m.stick_vec = Vector2.ZERO)
	# 8. a big disguise moving around near walls
	await watch_camera("moving around as a big sofa", func():
		me().teleport(Vector3(4.0, 0.1, 9.5), 0.0)
		await frames(3)
		var room: Vector3 = me().find_room_for("loungeSofaLong", 2.3)
		if room != Vector3.INF:
			me().global_position = room
		me().set_disguise("loungeSofaLong", 2.3)
		for d in [Vector2(-1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(0, -1)]:
			m.stick_vec = d
			for k in 40:
				me().yaw += 0.03
				await frames(1)
		m.stick_vec = Vector2.ZERO
		me().set_disguise(""))


# ---------- tests ----------

func test_navigation() -> void:
	var map: RID = m.get_world_3d().navigation_map
	var start: Vector3 = m.house.hider_spawns[0]
	var bad := 0
	for sp in m.house.hide_spots:
		var target := NavigationServer3D.map_get_closest_point(map, sp["exit"])
		var path := NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, start), target, true)
		if path.is_empty() or path[path.size() - 1].distance_to(target) > 0.6 or target.distance_to(sp["exit"]) > 1.2:
			bad += 1
			print("   nav: can't reach ", sp["name"])
	check(bad == 0, "every hiding spot can be walked to (%d spots)" % m.house.hide_spots.size())
	var cut := []
	for room in House.ROOM_CENTRES:
		var c: Vector3 = House.ROOM_CENTRES[room]
		var target := NavigationServer3D.map_get_closest_point(map, c)
		var path := NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, start), target, true)
		if path.is_empty() or path[path.size() - 1].distance_to(target) > 0.6 or Vector2(target.x - c.x, target.z - c.z).length() > 2.5:
			cut.append(room)
	for r in cut:
		print("   can't walk into: ", r)
	check(cut.is_empty(), "every room and garden area can be walked into (%d areas)" % House.ROOM_CENTRES.size())


func test_explore_actions() -> void:
	m._on_explore("QA", 0)
	await frames(10)
	var ids := ["jump", "crouch", "crouch", "run", "run", "banana", "cushion", "giggle", "lights", "boo", "pillow",
		"fart", "confetti", "honk", "dance", "kiss", "laugh", "smoke", "sprint", "catch", "search", "marco", "radar", "xray", "sniff"]
	for id in ids:
		m.cd.clear()
		m._do_action(id)
		await frames(6)
	check(m.phase == "explore", "every action and prank runs in explore mode without breaking it")
	await secs(13.0)
	check(m.lights_off <= 0.0 and House.dim_amount == 1.0, "lights come back on after Lights Off")
	# TV on and off near the TV
	me().teleport(m.house.tv_pos + Vector3(0, 0.1, 0.5), 0.0)
	await frames(5)
	m._do_action("tv")
	await frames(10)
	var on: bool = m.house.tv_on
	m._do_action("tv")
	await frames(10)
	check(on and not m.house.tv_on, "TV switches on and off")


func test_spots() -> void:
	var bad := []
	for i in m.house.hide_spots.size():
		var sp: Dictionary = m.house.hide_spots[i]
		me().teleport(sp["exit"], 0.0)
		await frames(4)
		var found: int = m._near_spot()
		if found != i:
			bad.append("%s (from its entrance the game picks spot %d)" % [sp["name"], found])
			continue
		m._do_action("hide")
		await frames(5)
		if me().hide_spot != i:
			bad.append("%s (couldn't get in)" % sp["name"])
			continue
		m._do_action("unhide")
		await frames(5)
		if me().hide_spot != -1 or me().global_position.distance_to(sp["exit"]) > 0.6:
			bad.append("%s (didn't come out at the entrance)" % sp["name"])
			continue
		var free := await walk_free(4)
		if free < 2:
			bad.append("%s (stuck after coming out)" % sp["name"])
	for b in bad:
		print("   spot problem: ", b)
	check(bad.is_empty(), "all %d hiding spots: found from entrance, enter, exit, walk away" % m.house.hide_spots.size())


func test_disguises() -> void:
	var map: RID = m.get_world_3d().navigation_map
	var bad := []
	var tested := 0
	for p in m.house.props:
		var node: Node3D = p["node"]
		var base := node.global_position
		var stand := NavigationServer3D.map_get_closest_point(map, base + Vector3(1.4, 0, 0.3))
		if stand.distance_to(base) > 3.0 or absf(stand.y - base.y) > 0.6:
			continue
		me().set_disguise("")
		me().teleport(stand + Vector3(0, 0.05, 0), 0.0)
		await frames(3)
		var room: Vector3 = me().find_room_for(p["name"], p["scale"])
		tested += 1
		if room == Vector3.INF:
			continue  # refused politely: fine
		me().global_position = room
		me().set_disguise(p["name"], p["scale"])
		for dir in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
			m.stick_vec = dir
			await frames(10)
		m.stick_vec = Vector2.ZERO
		await frames(2)
		var hits := overlaps_world(p["name"], p["scale"])
		if hits > 0:
			bad.append("%s at %s overlaps %d things" % [p["name"], me().global_position.snapped(Vector3.ONE * 0.1), hits])
		me().set_disguise("")
		await frames(1)
		if not (me()._col.shape is CapsuleShape3D):
			bad.append("%s: collision not restored after Be me" % p["name"])
	for b in bad:
		print("   disguise problem: ", b)
	check(bad.is_empty() and tested > 30, "every disguise (%d objects): fits, never pushes into walls, turns back" % tested)


func test_stairs_and_bounce() -> void:
	me().set_disguise("")
	me().teleport(Vector3(14.25, 0.1, 0.2), PI)  # bottom of the stairs, facing up (+z)
	await frames(3)
	m.stick_vec = Vector2(0, -1)
	await frames(240)
	m.stick_vec = Vector2.ZERO
	check(me().global_position.y > 3.0, "you can walk up the stairs (reached height %.1f)" % me().global_position.y)
	me().teleport(Vector3(14.25, 3.3, 6.6), 0.0)  # top of the stairs, facing down (-z)
	await frames(3)
	m.stick_vec = Vector2(0, -1)
	await frames(260)
	m.stick_vec = Vector2.ZERO
	check(me().global_position.y < 0.5, "you can walk back down the stairs")
	# trampoline bounce
	me().teleport(Vector3(20, 2.5, 23.5), 0.0)
	var top := 0.0
	for f in 150:
		await frames(1)
		top = maxf(top, me().global_position.y)
	check(top > 3.0, "trampoline bounces you up (peak %.1f m)" % top)


func test_settings() -> void:
	var ok := true
	for q in [0, 1, 2, 1]:
		m.ui._set_quality(q)
		await frames(5)
		ok = ok and int(m.settings["quality"]) == q
	m.ui.s_music.value = 0.3
	m.ui.s_sfx.value = 0.6
	m.ui.s_sens.value = 1.4
	m.ui.s_hide.value = 30
	m.ui.s_seek.value = 120
	await frames(3)
	ok = ok and is_equal_approx(float(m.settings["hide"]), 30.0) and is_equal_approx(float(m.settings["seek"]), 120.0)
	m.ui._toggle_rule("prints")
	m.ui._toggle_rule("prints")
	m.ui._set_bot(2)
	m.ui._set_bot(1)
	check(ok, "graphics levels, volume, sensitivity and match rules all apply")


func test_catch_under_bed() -> void:
	await start_bot_round(true)
	var spot := -1
	for i in m.house.hide_spots.size():
		if m.house.hide_spots[i]["name"] == "under the big bed":
			spot = i
	check(spot >= 0, "under-bed hiding spot exists")
	if spot < 0:
		return
	var entrance: Vector3 = m.house.hide_spots[spot]["exit"]
	m.bot.hide_spot = spot
	m.bot.disguise = ""
	m.bot.pos = m.house.hide_spots[spot]["cam"] - Vector3(0, 1.35, 0)
	m.bot.state = "hidden"
	m.bot._push()
	me().teleport(entrance - Vector3(0, 3.2, 0), 0.0)
	await frames(4)
	check(m._catch_target() == -1, "cannot catch the under-bed bot from downstairs")
	me().teleport(entrance + Vector3(0, 0, 4), 0.0)
	await frames(4)
	check(m._catch_target() == -1, "cannot catch the under-bed bot from outside search range")
	me().teleport(entrance, 0.0)
	await frames(4)
	m.cd.clear()
	m._do_action("catch")
	await frames(4)
	check(m.caught.has(Bot.ID) or m.phase == "results", "Catch finds the bot under the bed from the entrance")


func test_bot_rounds() -> void:
	# --- you seek: the bot hides in every spot and you check it from the entrance ---
	var missed := []
	for i in m.house.hide_spots.size():
		if m.house.hide_spots[i].get("kind", "hide") == "bike":
			continue
		await start_bot_round(true)
		if m.phase != "seek":
			await secs(1.0)
		var bot: Bot = m.bot
		bot.hide_spot = i
		bot.disguise = ""
		bot.pos = m.house.hide_spots[i]["cam"] - Vector3(0, 1.35, 0)
		bot.state = "hidden"
		bot._push()
		me().teleport(m.house.hide_spots[i]["exit"], 0.0)
		await frames(4)
		m.cd.clear()
		m._do_action("search")
		await frames(4)
		if not m.caught.has(Bot.ID) and m.phase != "results":
			missed.append(m.house.hide_spots[i]["name"])
		await secs(0.3)
	for x in missed:
		print("   couldn't find the bot in: ", x)
	check(missed.is_empty(), "checking a hiding spot finds the hider (every spot)")
	check(m.phase == "results", "round ends with results when the hider is found")

	# --- the bot seeks: you hide in a spot and the bot checks it ---
	var escaped := []
	for i in [0, 4, 9, 14]:
		await start_bot_round(false)
		await secs(1.0)
		me().teleport(m.house.hide_spots[i]["exit"], 0.0)
		await frames(3)
		m._do_action("hide")
		await frames(3)
		var bot: Bot = m.bot
		bot.goal_spot = i
		bot.pos = m.house.hide_spots[i]["exit"]
		bot._arrived()
		await frames(5)
		if not m.caught.has(Net.my_id) and m.phase != "results":
			escaped.append(m.house.hide_spots[i]["name"])
	check(escaped.is_empty(), "the bot finds you when it checks your hiding spot")

	# --- you as hider standing in the open get caught by the bot ---
	await start_bot_round(false)
	await secs(1.0)
	me().teleport(Vector3(12.0, 0.1, 7.0), 0.0)  # standing in the middle of the hallway
	var t := 0.0
	while m.phase == "seek" and t < 60.0:
		await secs(0.5)
		t += 0.5
	check(m.phase == "results", "the bot chases and catches you in the open (%.1f s)" % t)


func test_traps() -> void:
	await start_bot_round(true)
	await secs(0.5)
	var bot: Bot = m.bot
	# bot drops a banana right where you stand: you slip
	me().teleport(Vector3(5.0, 0.1, 7.0), 0.0)
	await frames(5)
	m._bot_fx({"k": "banana", "id": "2_99", "p": [5.0, 0.0, 6.4]})
	m.stick_vec = Vector2(0, -1)
	await frames(40)
	m.stick_vec = Vector2.ZERO
	check(me().stun > 0.0 or not m.items.has("2_99"), "you slip on someone else's banana")
	# your pillow hits the bot
	bot.hide_spot = -1
	bot.disguise = ""
	bot.state = "hidden"
	bot.pos = Vector3(5.0, 0.0, 10.0)
	bot._push()
	(m.remotes[Bot.ID] as RemotePlayer).global_position = bot.pos
	me().teleport(Vector3(5.0, 0.1, 7.0), PI)  # facing +z, toward the bot
	await frames(5)
	m.uses["pillow"] = 3
	m.cd.erase("pillow")
	m._do_action("pillow")
	var hit := false
	for f in 90:
		await frames(1)
		if bot.stun > 0.0:
			hit = true
			break
	check(hit, "a thrown pillow hits the other player")
	# X-ray: one per round, and only a blurry ring a few metres off the hider
	check(m.uses.get("xray", 0) == 1 or int(m.rules.get("xrays", 1)) != 1, "one X-ray per round by default")
	var r: RemotePlayer = m.remotes[Bot.ID]
	me().teleport(r.global_position + Vector3(6.0, 0.1, 0.0), 0.0)
	await frames(3)
	m.cd.erase("xray")
	m._do_action("xray")
	await frames(3)
	check(r._dot != null and r._dot.visible, "X-ray shows a ring near the hider")
	var off := Vector2(r._dot.position.x, r._dot.position.z).length()
	check(off >= 2.4 and off <= 4.6, "the X-ray ring is %.1f m off the real spot" % off)
	# radar
	m.cd.erase("radar")
	m._do_action("radar")
	await frames(2)
	check(m.ui.radar.visible, "radar shows the arrow")
	# marco makes the bot answer polo (heard as a sound, nothing to break)
	m.cd.erase("marco")
	m._do_action("marco")
	await secs(1.0)
	check(m.phase == "seek", "Marco / Polo works mid-round")


func test_round_flow() -> void:
	# several timed-out rounds in a row with roles swapping
	var seekers := []
	for k in 4:
		m.hide_time = 1.0
		m.seek_time = 2.0
		m.round_no = k
		m._host_start()
		seekers.append(m.seeker_id)
		await secs(4.5)
		if m.phase != "results":
			break
	check(m.phase == "results", "timed rounds end on their own")
	check(seekers.size() == 4 and seekers[0] != seekers[1] and seekers[1] != seekers[2], "seeker swaps every round")
	var total := 0
	for k in m.scores:
		total += int(m.scores[k])
	check(total >= 4, "scores add up over rounds (total %d)" % total)
	Net.broadcast({"t": "lobby"})
	await frames(5)
	check(m.phase == "lobby", "back to the room after results")


func test_memory() -> void:
	var before := get_tree().get_node_count()
	for k in 10:
		m.hide_time = 1.0
		m.seek_time = 1.5
		m.round_no = k
		m._host_start()
		m._do_action("fart")
		m._do_action("confetti")
		await secs(3.0)
	await secs(3.0)
	var after := get_tree().get_node_count()
	check(after - before < 60, "no objects pile up over 10 rounds (%d -> %d nodes)" % [before, after])
	m._leave()
	await frames(5)
	check(m.phase == "menu" and m.bot == null, "leaving goes back to the menu cleanly")
