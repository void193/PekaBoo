class_name Bot
extends Node
## A computer player for practice matches. It drives a RemotePlayer body directly.
## As a hider it picks a hiding spot, a disguise or a bush, teases, answers "Polo!" and may BOO.
## As a seeker it walks the house on the navigation map, listens for footsteps and teasing,
## checks hiding spots, chases what it sees and gets fooled by bananas, BOOs and pillows.

const ID := 2
const NAMES := ["Botty", "Peekabot", "Sneaky Sam", "Robo Rosie"]
const WALK := 3.0
const CHASE := 5.0
const SEE_RANGE := 13.0
const HEAR_RANGE := 9.0

var main: Node  # main.gd
var body: RemotePlayer
var role := ""
var pos := Vector3.ZERO
var yaw := 0.0
var anim := "idle"
var hide_spot := -1
var disguise := ""
var disguise_scale := Kit.SCALE
var disguise_yaw := 0.0
var ghost := false
var stun := 0.0
var active := false
var skill := 1  # 0 easy, 1 normal, 2 hard

var path := PackedVector3Array()
var path_i := 0
var state := "idle"  # seeker: wander, investigate, chase, check ; hider: hidden
var goal := Vector3.ZERO
var goal_spot := -1
var visited := {}
var think_t := 0.0
var wait_t := 0.0
var last_seen := Vector3.ZERO
var suspicion := 0.0
var marco_t := 20.0
var tease_t := 30.0
var boo_t := 0.0
var stare_t := 0.0
var lights_used := false
var crouching := false
var radar_t := 22.0
var xray_t := 45.0
var xrays_left := 2


func setup(m: Node, b: RemotePlayer) -> void:
	main = m
	body = b


# ---------- round events ----------

func on_round_start(my_role: String) -> void:
	role = my_role
	active = true
	ghost = false
	stun = 0.0
	hide_spot = -1
	disguise = ""
	crouching = false
	path = PackedVector3Array()
	visited.clear()
	suspicion = 0.0
	marco_t = randf_range(18.0, 28.0)
	tease_t = randf_range(25.0, 40.0)
	boo_t = 0.0
	lights_used = false
	xrays_left = int(main.rules.get("xrays", 1))
	radar_t = randf_range(18.0, 26.0)
	xray_t = randf_range(40.0, 55.0)
	if role == "seeker":
		pos = main.house.seeker_spawn
		state = "blind"
	else:
		pos = main.house.hider_spawns[1]
		state = "hiding"
		wait_t = randf_range(2.0, 5.0)
	_push()


func on_seek() -> void:
	if role == "seeker":
		state = "wander"
		_say(["😈", "👀", "🔍"].pick_random())


func on_caught(id: int) -> void:
	if id == ID:
		ghost = true
		active = false
		hide_spot = -1
		disguise = ""
		_push()


func on_end() -> void:
	active = false
	ghost = false
	hide_spot = -1
	disguise = ""
	_push()


func on_fx(k: String, m: Dictionary, from: int) -> void:
	if not active or from == ID:
		return
	var me: Player = main.me
	if k == "smoke" and role == "seeker" and me.global_position.distance_to(pos) < 7.0:
		stun = maxf(stun, 2.0)
		state = "wander"
		path = PackedVector3Array()
		_say("😵💨")
	if k == "confetti" and role == "seeker" and me.global_position.distance_to(pos) < 4.5:
		stun = maxf(stun, 1.6)
		_say("🎉😵")
	match k:
		"marco":
			if role == "hider":
				get_tree().create_timer(0.6).timeout.connect(_polo)
		"polo":
			if role == "seeker":
				var p = m["p"]
				_investigate(Vector3(float(p[0]), float(p[1]), float(p[2])))
		"say", "emote", "giggle", "fart", "honk", "dance", "kiss", "confetti":
			# teasing gives you away: the bot comes to check it out
			if role == "seeker":
				var where: Vector3 = me.global_position
				if k == "giggle":
					var p = m["p"]
					where = Vector3(float(p[0]), float(p[1]), float(p[2]))
				if where.distance_to(pos) < 22.0:
					_investigate(where)
		"confetti":
			pass
		"boo":
			if role == "seeker" and me.global_position.distance_to(pos) < 5.0:
				stun = 1.4
				body.stun(1.4)
				_say("😱")
		"hit":
			if int(m.get("id", -1)) == ID:
				stun = maxf(stun, 0.8)
				if role == "seeker":
					_investigate(me.global_position)
		"sniff":
			if role == "hider" and not ghost:
				var pts := []
				for i in 6:
					var p := pos + Vector3(randf_range(-2.5, 2.5), 0.05, randf_range(-2.5, 2.5)) * (6 - i) / 6.0
					pts.append([p.x, pos.y + 0.05, p.z])
				main._bot_fx({"k": "trail", "pts": pts})
		"lights":
			pass


func _polo() -> void:
	if active and not ghost:
		var e := _eye()
		main._bot_fx({"k": "polo", "p": [e.x, e.y, e.z]})


# ---------- per frame ----------

func tick(dt: float) -> void:
	if not active or main.phase not in ["hide", "seek"]:
		return
	if stun > 0.0:
		stun -= dt
		_push()
		return
	if role == "seeker":
		_seeker(dt)
	else:
		_hider(dt)
	_push()


func _push() -> void:
	body.apply_state({"p": [pos.x, pos.y, pos.z], "y": yaw, "m": anim in ["walk", "sprint"], "a": anim,
		"d": disguise, "ds": disguise_scale, "dy": disguise_yaw, "h": hide_spot, "g": ghost})


func _say(text: String) -> void:
	main._bot_fx({"k": "say", "s": text})


func _eye() -> Vector3:
	if hide_spot >= 0:
		return main.house.hide_spots[hide_spot]["cam"]
	return pos + Vector3(0, 1.2, 0)


# ---------- moving around ----------

func _path_to(target: Vector3) -> void:
	var map: RID = main.get_world_3d().navigation_map
	var from := NavigationServer3D.map_get_closest_point(map, pos)
	var to := NavigationServer3D.map_get_closest_point(map, target)
	path = NavigationServer3D.map_get_path(map, from, to, true)
	path_i = 0
	goal = to


## Moves along the current path. Returns true when it has arrived.
func _follow(dt: float, speed: float) -> bool:
	while path_i < path.size() and Vector2(pos.x - path[path_i].x, pos.z - path[path_i].z).length() < 0.12:
		path_i += 1
	if path_i >= path.size():
		anim = "idle"
		return true
	var target := path[path_i]
	var d := target - pos
	var step := speed * dt
	if d.length() <= step:
		pos = target
		path_i += 1
	else:
		pos += d.normalized() * step
	if Vector2(d.x, d.z).length() > 0.01:
		yaw = lerp_angle(yaw, atan2(-d.x, -d.z), minf(1.0, dt * 10.0))
	anim = "sprint" if speed > 4.0 else "walk"
	return false


# ---------- seeker brain ----------

func _seeker(dt: float) -> void:
	if state == "blind":
		anim = "idle"
		return
	var me: Player = main.me
	if main.caught.has(Net.my_id):
		anim = "idle"
		return
	# traps
	for key in main.items.keys():
		var it: Dictionary = main.items[key]
		var ip: Vector3 = it["pos"]
		if Vector2(pos.x - ip.x, pos.z - ip.z).length() < 0.6 and absf(pos.y - ip.y) < 0.8:
			main.items[key]["pos"] = Vector3(9999, 0, 9999)
			main._bot_fx({"k": "slip" if it["kind"] == "banana" else "pfft", "id": key})
			if it["kind"] == "banana":
				stun = 1.8
			return
	think_t -= dt
	if think_t <= 0.0:
		think_t = 0.2
		_look_and_listen(me)
	marco_t -= dt
	if marco_t <= 0.0:
		marco_t = randf_range(28.0, 40.0)
		main._bot_fx({"k": "marco"})
	radar_t -= dt
	if radar_t <= 0.0:
		radar_t = randf_range(22.0, 30.0) * [1.6, 1.0, 0.7][skill]
		main._bot_fx({"k": "radar"})
		if not me.ghost:
			_investigate(me.global_position + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)))
	xray_t -= dt
	if xray_t <= 0.0 and xrays_left > 0:
		xrays_left -= 1
		xray_t = randf_range(45.0, 60.0) * [1.6, 1.0, 0.7][skill]
		main._bot_fx({"k": "xray"})
		# same blurry X-ray as players get: it only learns roughly where you are
		if not me.ghost and me.global_position.distance_to(pos) < 20.0:
			_investigate(me.global_position + main.xray_blur())
	match state:
		"wander":
			if path_i >= path.size():
				_pick_wander_goal()
			if _follow(dt, WALK):
				_arrived()
		"check":
			if _follow(dt, WALK):
				_arrived()
		"investigate":
			if _follow(dt, WALK * 1.3):
				wait_t -= dt
				anim = "idle"
				yaw += dt * 2.5
				if wait_t <= 0.0:
					state = "wander"
					path = PackedVector3Array()
		"chase":
			wait_t -= dt
			if wait_t <= 0.0:
				wait_t = 0.4
				_path_to(last_seen)
			_follow(dt, CHASE * [0.85, 1.0, 1.12][skill])
			var to_me := me.global_position - pos
			if Vector2(to_me.x, to_me.z).length() < 1.4 and absf(to_me.y) < 1.5 and me.hide_spot < 0 and _sees(me, 3.0):
				main._bot_catch_player()
				state = "idle"
		"pause":
			anim = "idle"
			wait_t -= dt
			if wait_t <= 0.0:
				state = "wander"
				path = PackedVector3Array()


func _sees(me: Player, max_d: float) -> bool:
	var target: Vector3 = me.global_position + Vector3(0, 0.7 if me.crouch else 1.0, 0)
	var eye := pos + Vector3(0, 1.3, 0)
	var d := eye.distance_to(target)
	if d > max_d:
		return false
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var dir := (target - eye).normalized()
	if d > 2.0 and Vector3(dir.x, 0, dir.z).normalized().dot(fwd) < 0.25:
		return false
	return main._los(eye, target)


func _look_and_listen(me: Player) -> void:
	if me.ghost or me.hide_spot >= 0:
		return
	var vis: float = SEE_RANGE * [0.7, 1.0, 1.3][skill] * (0.4 if main.lights_off > 0.0 else 1.0)
	# crouching inside a bush makes you nearly invisible
	if me.crouch:
		for b in main.house.bushes:
			if Vector2(me.global_position.x - b.x, me.global_position.z - b.z).length() < 1.0:
				vis = 1.6
				break
	if _sees(me, vis):
		if me.disguise == "":
			if state != "chase":
				_say(["😈❗", "👀❗", "🏃💨"].pick_random())
			state = "chase"
			last_seen = me.global_position
			return
		# disguised: moving props are suspicious, still ones only up close
		var d := pos.distance_to(me.global_position)
		if me.is_moving():
			suspicion += 0.35
		elif d < 3.0:
			suspicion += 0.06
		if suspicion > 1.0:
			suspicion = 0.0
			last_seen = me.global_position
			state = "chase"
			_say("🤨❗")
			return
	elif state == "chase":
		state = "investigate"
		_path_to(last_seen)
		wait_t = 3.0
		return
	# footsteps
	if me.is_moving() and me.is_on_floor():
		var hear: float = HEAR_RANGE * [0.65, 1.0, 1.35][skill] * (0.35 if me.crouch else (1.4 if me.run else 1.0))
		if me.global_position.distance_to(pos) < hear and state != "chase":
			_investigate(me.global_position)


func _investigate(p: Vector3) -> void:
	if state == "chase" or state == "blind":
		return
	state = "investigate"
	_path_to(p)
	wait_t = 2.5


func _pick_wander_goal() -> void:
	var spots: Array = main.house.hide_spots
	var options := []
	for i in spots.size():
		if not visited.has(i):
			options.append(i)
	if options.is_empty():
		visited.clear()
		options = Array(range(spots.size()))
	# prefer spots near the bot, with some randomness
	options.sort_custom(func(a, b): return pos.distance_to(spots[a]["exit"]) < pos.distance_to(spots[b]["exit"]))
	var pick: int = options[mini(randi() % 3, options.size() - 1)]
	if randf() < 0.3:
		# wander to a random piece of furniture instead
		var p: Dictionary = main.house.props.pick_random()
		goal_spot = -1
		_path_to((p["node"] as Node3D).global_position + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)))
	else:
		goal_spot = pick
		_path_to(spots[pick]["exit"])
	state = "check" if goal_spot >= 0 else "wander"


func _arrived() -> void:
	var me: Player = main.me
	if goal_spot >= 0:
		visited[goal_spot] = true
		Sfx.play_at("open", pos + Vector3.UP, 0.0)
		if me.hide_spot == goal_spot and not me.ghost:
			main._bot_catch_player()
			state = "idle"
			return
		if randf() < 0.3:
			_say(["🤔", "😤", "👀"].pick_random())
	# a prop that's exactly where a prop shouldn't be?
	if me.disguise != "" and me.global_position.distance_to(pos) < 2.2 and randf() < 0.35:
		state = "chase"
		last_seen = me.global_position
		return
	goal_spot = -1
	state = "pause"
	wait_t = randf_range(0.6, 1.6)
	yaw += randf_range(-1.5, 1.5)


# ---------- hider brain ----------

func _hider(dt: float) -> void:
	var me: Player = main.me
	if state == "hiding":
		wait_t -= dt
		anim = "walk"
		if wait_t <= 0.0:
			_choose_hiding_place()
			state = "hidden"
		return
	anim = "crouch" if crouching else "idle"
	if main.phase != "seek" or ghost:
		return
	tease_t -= dt
	if tease_t <= 0.0:
		tease_t = randf_range(30.0, 50.0)
		main._bot_fx({"k": ["honk", "fart", "dance", "kiss", "confetti"].pick_random()})
	if not lights_used and main.phase_left < main.seek_time * 0.5 and randf() < 0.002:
		lights_used = true
		main._bot_fx({"k": "lights", "d": 10.0})
	# stare at the bot's hiding place too long and it might BOO you
	boo_t -= dt
	var d := me.global_position.distance_to(_eye())
	if d < 3.0 and hide_spot < 0:
		stare_t += dt
		if stare_t > 2.5 and boo_t <= 0.0 and randf() < 0.5:
			boo_t = 25.0
			stare_t = 0.0
			main._bot_fx({"k": "boo"})
	else:
		stare_t = 0.0


func _fits(model_name: String, scl: float, at: Vector3) -> bool:
	var d := Player.prop_dims(model_name, scl)
	var cyl := CylinderShape3D.new()
	cyl.radius = d.x
	cyl.height = d.y - 0.08
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cyl
	q.collision_mask = 1
	q.transform = Transform3D(Basis(), at + Vector3(0, d.y / 2.0 + 0.06, 0))
	return main.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _choose_hiding_place() -> void:
	# start clean: never end up disguised and inside a hiding spot at the same time
	hide_spot = -1
	disguise = ""
	crouching = false
	var house: House = main.house
	var r := randf()
	if r < 0.4:
		var free := []
		for i in house.hide_spots.size():
			if main.me.hide_spot != i and house.hide_spots[i].get("kind", "hide") != "bike":
				free.append(i)
		hide_spot = free.pick_random()
		pos = house.hide_spots[hide_spot]["cam"] - Vector3(0, 1.35, 0)
	elif r < 0.8:
		# become a copy of something, placed near the real thing
		var map: RID = main.get_world_3d().navigation_map
		for attempt in 40:
			var p: Dictionary = house.props.pick_random()
			var size := Kit.size_of(p["name"], p["scale"])
			if size.y < 0.4 or size.y > 2.0:
				continue
			var base := (p["node"] as Node3D).global_position
			var cand := NavigationServer3D.map_get_closest_point(map, base + Vector3(randf_range(-1.8, 1.8), 0, randf_range(-1.8, 1.8)))
			# same room as the real object (no wall between) and enough free space for it
			if cand.distance_to(base) < 3.0 and absf(cand.y - base.y) < 0.6 \
					and house.walls_clear(base + Vector3(0, 0.5, 0), cand + Vector3(0, 0.5, 0)) \
					and _fits(p["name"], p["scale"], cand):
				pos = cand
				disguise = p["name"]
				disguise_scale = p["scale"]
				disguise_yaw = (p["node"] as Node3D).rotation.y + [0.0, PI / 2.0, PI, -PI / 2.0].pick_random()
				yaw = 0.0
				return
		hide_spot = 0
		pos = house.hide_spots[hide_spot]["cam"] - Vector3(0, 1.35, 0)
	else:
		var b: Vector3 = house.bushes.pick_random()
		pos = Vector3(b.x, 0.0, b.z)
		crouching = true
		yaw = randf() * TAU
