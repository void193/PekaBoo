class_name Extras
extends Node3D
## More things to do in chill mode: climb to the rooftop deck, swing, hold hands, stargaze on the
## picnic blanket, write messages in the sky, take a couple selfie, rain / snow, the wishing well
## and fortune cookies, a pillow fight and cooking together.

var main: Node
var house: House
var chill: Chill
var overlays: Overlays

# ---------- shared lists ----------

const FORTUNES := [
	["💌", "Sweet", "Tell each other one thing you loved about today."],
	["💌", "Sweet", "Say the first thing you noticed about each other."],
	["💌", "Sweet", "Describe your partner in three words. Go!"],
	["💌", "Sweet", "You are someone's favourite notification. 💜"],
	["💌", "Sweet", "Send a voice note right now saying 'I miss you' in your cutest voice."],
	["💌", "Sweet", "Name a song that reminds you of them and play it tonight."],
	["💌", "Sweet", "Tum ho toh sab theek hai. 💜"],
	["💌", "Sweet", "Your smile is the best thing in this house."],
	["💌", "Sweet", "Plan your next date right now: where, when, what you'll eat."],
	["💌", "Sweet", "Write a 1-line love letter in the sky ✍️ (use Sky message)."],
	["🎯", "Dare", "Do your best Oggy impression. The other one rates it out of 10."],
	["🎯", "Dare", "Sing two lines of an Arijit song. No skipping!"],
	["🎯", "Dare", "Send your partner the most embarrassing photo of you in your gallery."],
	["🎯", "Dare", "Talk in a Bollywood villain voice until the next song."],
	["🎯", "Dare", "Give your partner a cute nickname and use it for the rest of the night."],
	["🎯", "Dare", "Do 10 squats right now. Partner counts. 😂"],
	["🎯", "Dare", "Recreate a famous movie dialogue, full drama."],
	["🎯", "Dare", "Let your partner change your WhatsApp DP for 1 hour."],
	["🎯", "Dare", "Slow-dance in the game AND in real life, wherever you are."],
	["🎯", "Dare", "Say 'I love you' in three different languages."],
	["🎯", "Dare", "Show your partner your last 5 Google searches. 👀"],
	["🎯", "Dare", "Hide in the house in 30 seconds. Partner has 1 minute to find you!"],
	["❓", "Question", "What's your favourite memory of us?"],
	["❓", "Question", "If we could travel anywhere tomorrow, where would we go?"],
	["❓", "Question", "What was your first impression of me? Be honest."],
	["❓", "Question", "Which song do you secretly think is 'our song'?"],
	["❓", "Question", "What's one small thing I do that you love?"],
	["❓", "Question", "Pizza date or street-food date?"],
	["❓", "Question", "What would our dream house have that this one doesn't?"],
	["❓", "Question", "If we were a movie, what would it be called?"],
	["❓", "Question", "What made you smile today?"],
	["❓", "Question", "Which one of us would survive a zombie movie longer?"],
	["❓", "Question", "Rate my cooking out of 10. Truthfully. 😅"],
	["❓", "Question", "What's a goal you want us to reach together this year?"],
	["😂", "Funny", "Whoever reads this owes the other one a hug. No refunds."],
	["😂", "Funny", "The cockroaches have stolen your snacks. Blame your partner."],
	["😂", "Funny", "Today's horoscope: you will lose at hide and seek. Sorry."],
	["😂", "Funny", "Error 404: personal space not found. 🤗"],
	["😂", "Funny", "You've been chosen to cook the next meal. The cake knows."],
	["😂", "Funny", "Warning: excessive cuteness detected in this house."],
	["😂", "Funny", "Moye moye... just kidding, you're winning tonight. 😜"],
	["😂", "Funny", "Loser of the next round does the dishes. In real life."],
	["🔮", "Fortune", "A surprise is coming your way very soon. 👀"],
	["🔮", "Fortune", "Someone is thinking about you right now. (It's them.)"],
	["🔮", "Fortune", "Your next date will be your best one yet."],
	["🔮", "Fortune", "Good things are coming, and they're coming together."],
	["🔮", "Fortune", "The stars say: more kisses, less overthinking."],
	["🔮", "Fortune", "You will win the next pillow fight. Probably."],
	["🔮", "Fortune", "A long call is in your near future. Charge your phone."],
	["🔮", "Fortune", "Lucky number tonight: the number of hugs you get."],
]

const BITES := 6.0
const DISHES := [
	["🍰", "Strawberry cake", ["🥚", "🥛", "🧈", "🍓"]],
	["🍕", "Pizza", ["🍅", "🧀", "🍄", "🌽"]],
	["☕", "Masala chai", ["💧", "🍃", "🥛", "🍬"]],
	["🥤", "Chocolate shake", ["🥛", "🍫", "🍨", "🍌"]],
	["🍜", "Maggi", ["💧", "🍜", "🧅", "🌶"]],
	["🍔", "Burger", ["🍞", "🥩", "🧀", "🥬"]],
]
const RECIPES := [
	["🍰", "Strawberry cake", ["🌾", "🥚", "🥛", "🧈", "🥄", "🍓", "🔥"]],
	["🍕", "Pizza", ["🍞", "🍅", "🧀", "🌽", "🍄", "🔥"]],
	["☕", "Masala chai", ["💧", "🌿", "🍃", "🥛", "🍬", "🔥"]],
	["🥤", "Chocolate shake", ["🥛", "🍫", "🍨", "🍌", "🌀"]],
]
const DECOYS := ["🧅", "🌶", "🥕", "🐟", "🧄", "🍋", "🥒", "🍗", "🥔", "🍪", "🍯", "🧂", "🥜", "🍉", "🍇", "🥑"]

const COOKIE_JAR := Vector3(14.45, 0, 9.35)
const DISH_AT := Vector3(15.45, 0, 9.6)

# ---------- state ----------

var weather := "clear"
var _rain: CPUParticles3D
var _snow: CPUParticles3D
var _rain_snd: AudioStreamPlayer

var _climb := {}          # {path, i, t}
var hands := {}           # {leader, follower}
var _gaze_cam: Camera3D
var gazing := false
var pf := {}              # pillow fight: {t, me, them}
var cook := {}            # {r, step, t, opts, start}
var _dish: Node3D
var _pose_t := 0.0        # selfie pose countdown
var pets: Pets


func setup(m: Node, h: House, c: Chill) -> void:
	main = m
	house = h
	chill = c
	overlays = m.ui.overlays
	overlays.game_pick = _cook_pick
	_gaze_cam = Camera3D.new()
	_gaze_cam.fov = 70.0
	add_child(_gaze_cam)
	# extra seats: the rooftop bench and the two places on the swing
	for x in [15.6, 16.4]:
		chill.seats.append({"pos": Vector3(x, House.DECK_Y, 9.9), "yaw": PI, "h": 0.3, "name": "Bench"})
	for i in 2:
		chill.seats.append({"pos": House.SWING_POS + Vector3(-0.42 if i == 0 else 0.42, 0, 0.1), "yaw": PI, "h": 0.0, "name": "Swing", "swing": i})
	_build_jar()
	pets = Pets.new()
	add_child(pets)
	pets.setup(m, h)


func _build_jar() -> void:
	var y := house.surface_y(COOKIE_JAR.x, COOKIE_JAR.z, 1.5)
	var jar := Node3D.new()
	jar.position = Vector3(COOKIE_JAR.x, y, COOKIE_JAR.z)
	add_child(jar)
	var glass := Build.cyl(jar, 0.11, 0.11, 0.24, Vector3(0, 0.12, 0), Color(0.85, 0.92, 1.0, 0.45), 14)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Build.cyl(jar, 0.08, 0.08, 0.04, Vector3(0, 0.26, 0), Color("#ff8fb1"), 12)
	for k in 5:
		Build.cyl(jar, 0.06, 0.06, 0.02, Vector3(cos(k) * 0.02, 0.03 + k * 0.035, sin(k) * 0.02), Color("#d9a35a"), 10)
	house.dynamic_lit.append([Kit.apply_probe_look(jar, 0.3), jar.position + Vector3(0, 0.4, 0)])
	house.relight_dynamic()


# ---------- every frame ----------

func _process(dt: float) -> void:
	var phase: String = main.phase
	pets.active = phase in ["chill", "explore"]
	if phase != "chill":
		if not _climb.is_empty() or gazing or not hands.is_empty():
			reset()
		_swing_tick(dt, false)
		return
	_swing_tick(dt, true)
	if not _climb.is_empty():
		_climb_tick(dt)
	if not hands.is_empty():
		_hands_tick(dt)
	if gazing:
		_gaze_tick(dt)
	_weather_tick(dt)
	if not pf.is_empty():
		_pf_tick(dt)
	if not cook.is_empty():
		_cook_tick(dt)
	if _pose_t > 0.0:
		_pose_t -= dt
		var k := clampf(minf(_pose_t, 3.2 - _pose_t) * 3.0, 0.0, 1.0)
		for who in [main.me, main._partner()]:
			var rg: CharRig = chill._rig_of(who) if who != null else null
			if rg:
				rg.set_live(0.0, 0.0, 2.6 * k, 0.4 * k)


func reset() -> void:
	if not _climb.is_empty():
		main.me._shape_owner_disabled(false)
		main.me.held = false
		main.me.frozen = false
	_climb.clear()
	if not hands.is_empty():
		_let_go()
	if gazing:
		_stop_gaze()
	hands.clear()
	pf.clear()
	_end_cook(false)
	set_weather("clear")


# ---------- what the big button does here ----------

func context() -> Dictionary:
	var me: Player = main.me
	if not _climb.is_empty():
		return {"id": "none", "icon": "⬆️", "name": "Climbing", "color": UI.MUTED, "enabled": false}
	if not hands.is_empty() and hands.get("follower") == me:
		return {"id": "letgo", "icon": "🤝", "name": "Let go", "color": UI.PINK}
	if not pf.is_empty():
		return {"id": "pfthrow", "icon": "🛏", "name": "Throw", "color": UI.ORANGE, "enabled": main._cd_left("pfthrow") <= 0.0}
	if me.sitting:
		return {}
	var p := me.global_position
	var lp: Array = House.LADDER_PATH
	if p.distance_to(lp[0]) < 1.3:
		return {"id": "climb", "icon": "⬆️", "name": "Climb", "color": UI.PURPLE}
	if p.distance_to(lp[lp.size() - 1]) < 1.2:
		return {"id": "climbdown", "icon": "⬇️", "name": "Climb down", "color": UI.PURPLE}
	if _flat(p, House.WELL_POS) < 1.9:
		return {"id": "well", "icon": "✨", "name": "Wish", "color": Color("#c98b2b")}
	if _flat(p, COOKIE_JAR) < 1.4 and p.y < 1.5:
		return {"id": "cookie", "icon": "🥠", "name": "Fortune", "color": Color("#c98b2b")}
	if _flat(p, House.PICNIC) < 1.6:
		return {"id": "stargaze", "icon": "🌌", "name": "Stargaze", "color": UI.PURPLE}
	if can_eat(p):
		return {"id": "eat", "icon": "😋", "name": "Eat", "color": UI.ORANGE, "enabled": main._cd_left("eat") <= 0.0}
	var pet := pets.near(p)
	if pet >= 0:
		return {"id": "pet", "icon": "🐾", "name": "Pet", "color": UI.ORANGE}
	return {}


func tools(partner: Node3D) -> Array:
	var out := []
	if partner != null:
		out.append(main._tool("hands", "🤝", "Hold hands"))
		out.append(main._tool("pillowfight", "🛏", "Pillow fight", "pillowfight", pf.is_empty()))
	out.append(main._tool("cook", "🍳", "Cook together", "cook", cook.is_empty() or cook.get("ready", false)))
	out.append(main._tool("selfie", "📸", "Selfie", "selfie"))
	out.append(main._tool("skymsg", "✍️", "Sky message", "skymsg"))
	out.append(main._tool("musicoff", "🔇" if Music.enabled else "🎵", "Music off" if Music.enabled else "Music on"))
	out.append(main._tool("weather", "🌦", {"clear": "Rain", "rain": "Snow", "snow": "Clear sky"}[weather], "weather"))
	return out


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Returns true if it was one of ours.
func action(id: String) -> bool:
	var me: Player = main.me
	match id:
		"climb":
			_start_climb(true)
		"climbdown":
			_start_climb(false)
		"letgo":
			main._fx({"k": "letgo"})
		"hands":
			main._chill_ask("hands")
		"stargaze":
			_start_gaze()
		"well":
			main.cd["well"] = 2.0
			main._fx({"k": "fortune", "i": randi() % FORTUNES.size(), "src": "well"})
		"cookie":
			main.cd["cookie"] = 2.0
			main._fx({"k": "fortune", "i": randi() % FORTUNES.size(), "src": "cookie"})
		"pet":
			var i := pets.near(me.global_position)
			if i >= 0:
				main._fx({"k": "petpet", "i": i})
		"pillowfight":
			main.cd["pillowfight"] = 3.0
			main._fx({"k": "pfstart"})
		"pfthrow":
			main.cd["pfthrow"] = 0.55
			main._throw_pillow()
		"cook":
			main.cd["cook"] = 1.0
			_open_menu()
		"eat":
			main.cd["eat"] = 0.35
			main._fx({"k": "bite"})
		"selfie":
			main.cd["selfie"] = 6.0
			main._fx({"k": "selfie"})
			_take_selfie()
		"skymsg":
			overlays.ask_text("✍️ Write in the sky (letters & numbers)", "I LOVE YOU", func(t: String): main._fx({"k": "skytext", "msg": t.substr(0, 16)}))
		"musicoff":
			main.set_music_on(not Music.enabled)
		"weather":
			main.cd["weather"] = 1.5
			main._fx({"k": "weather", "w": {"clear": "rain", "rain": "snow", "snow": "clear"}[weather]})
		_:
			return false
	return true


## Network messages for all of the above. Returns true if handled.
func on_fx(k: String, m: Dictionary, from: int, mine: bool) -> bool:
	match k:
		"letgo":
			_let_go()
		"fortune":
			var f: Array = FORTUNES[int(m.get("i", 0)) % FORTUNES.size()]
			var src := "✨ The wishing well says…" if str(m.get("src", "")) == "well" else "🥠 Your fortune cookie says…"
			var who := "" if mine else "  (%s opened it)" % main._player_name(from)
			overlays.show_card(f[0], "%s  ·  %s%s" % [src, f[1], who], f[2])
			Sfx.play("twinkle", -6.0)
		"petpet":
			pets.pet(int(m.get("i", 0)))
		"pets":
			if not mine:
				pets.apply_state(m.get("p", []))
		"pfstart":
			_start_pf()
		"pfend":
			_end_pf()
		"cookstart":
			_start_cook(int(m.get("r", 0)), int(m.get("s", 0)), from)
		"bite":
			bite(from)
		"selfie":
			_pose_t = 3.2
			if not mine:
				main.ui.toast("📸 %s is taking a selfie, smile!" % main._player_name(from), 3.0)
		"skytext":
			_sky_text(str(m.get("msg", "")))
		"weather":
			set_weather(str(m.get("w", "clear")))
		_:
			return false
	return true


## The pillow fight counts hits (called from main's "hit" message).
func on_hit(thrower: int, target: int) -> void:
	if pf.is_empty():
		return
	if thrower == Net.my_id:
		pf["me"] += 1
	elif target == Net.my_id:
		pf["them"] += 1


# ---------- ladder to the rooftop ----------

func _start_climb(up: bool) -> void:
	var me: Player = main.me
	var path: Array = House.LADDER_PATH.duplicate()
	if not up:
		path.reverse()
	me.frozen = true
	me.held = true
	me.velocity = Vector3.ZERO
	me._shape_owner_disabled(true)
	me.anim_hold = "holding-both"
	_climb = {"path": path, "i": 0, "t": 0.0}
	me.global_position = path[0]


func _climb_tick(dt: float) -> void:
	var me: Player = main.me
	var path: Array = _climb["path"]
	var i: int = _climb["i"]
	if i >= path.size() - 1:
		me._shape_owner_disabled(false)
		me.frozen = false
		me.held = false
		me.anim_hold = ""
		if me.rig:
			me.rig.set_live(0.0, 0.0, 0.0, 0.0)
		_climb.clear()
		return
	var a: Vector3 = path[i]
	var b: Vector3 = path[i + 1]
	var steep := absf(b.y - a.y) > 0.5
	var speed := 1.5 if steep else 1.2
	_climb["t"] += dt * speed / maxf(a.distance_to(b), 0.01)
	var t: float = _climb["t"]
	if t >= 1.0:
		_climb["i"] = i + 1
		_climb["t"] = 0.0
		t = 1.0
	me.global_position = a.lerp(b, t)
	var d := b - a
	if Vector2(d.x, d.z).length() > 0.05:
		me.visual.rotation.y = atan2(-d.x, -d.z) if not steep else me.visual.rotation.y
	if steep:
		# face the ladder (it leans against the house, which is towards -z)
		me.visual.rotation.y = 0.0 if b.y > a.y else 0.0
	if me.rig:
		var s := sin(Time.get_ticks_msec() / 1000.0 * 9.0)
		me.rig.set_live(0.0, 0.0, 2.4 + s * 0.5, 2.4 - s * 0.5)


# ---------- the swing ----------

func _swing_tick(_dt: float, chill_on: bool) -> void:
	if house.swing_seat == null:
		return
	var me: Player = main.me
	var busy := false
	var my_seat := -1
	if chill_on and me.sitting and me.has_meta("seat"):
		var si: int = me.get_meta("seat")
		if si < chill.seats.size() and chill.seats[si].has("swing"):
			busy = true
			my_seat = chill.seats[si]["swing"]
	var partner: Node3D = main._partner()
	var her_seat := -1
	if chill_on and partner is RemotePlayer and (partner as RemotePlayer).anim_name == "sit" and _flat((partner as RemotePlayer)._target, House.SWING_POS) < 1.6:
		busy = true
		# which of the two places is she in? (the closer one, and never the one I'm in)
		var t: Vector3 = (partner as RemotePlayer)._target
		her_seat = 0 if _flat(t, house.swing_seat_point(0).origin) < _flat(t, house.swing_seat_point(1).origin) else 1
		if her_seat == my_seat:
			her_seat = 1 - my_seat
	# both phones use the clock, so the swing moves the same way on each
	var t := Time.get_unix_time_from_system()
	var amp := 0.42 if busy else 0.05
	house.swing_seat.rotation.x = lerpf(house.swing_seat.rotation.x, amp * sin(t * TAU / 2.8), 0.15)
	if my_seat >= 0:
		var xf := house.swing_seat_point(my_seat)
		me.global_position = xf.origin + Vector3(0, -0.02, 0)
		me.visual.rotation.y = PI
		me.visual.rotation.x = -house.swing_seat.rotation.x
	# draw her exactly on her seat on this phone too, so you swing together, not one behind
	if partner is RemotePlayer:
		var r := partner as RemotePlayer
		if her_seat >= 0:
			r.pinned = true
			r.global_position = house.swing_seat_point(her_seat).origin + Vector3(0, -0.02, 0)
			r._visual.rotation.y = PI
			r._visual.rotation.x = -house.swing_seat.rotation.x
		elif r.pinned:
			r.pinned = false
			r._visual.rotation.x = 0.0


# ---------- holding hands ----------

func start_hands(leader: Node3D, follower: Node3D) -> void:
	hands = {"leader": leader, "follower": follower}
	Build.burst(main, follower.global_position, "hearts")
	if follower == main.me:
		main.ui.toast("🤝 Holding hands, %s leads the way" % main._player_name(main._partner_id()), 3.0)
	else:
		main.ui.toast("🤝 Holding hands! Walk anywhere together", 3.0)


func _hands_tick(_dt: float) -> void:
	var me: Player = main.me
	var leader: Node3D = hands.get("leader")
	var follower: Node3D = hands.get("follower")
	if not is_instance_valid(leader) or not is_instance_valid(follower):
		hands.clear()
		return
	if follower != me:
		return
	# the follower walks beside the leader, on their right, hand in hand
	var yaw: float = leader.visual.rotation.y if leader is Player else (leader as RemotePlayer)._visual.rotation.y
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var target: Vector3 = leader.global_position + right * 0.62
	me.frozen = true
	me.held = true
	me.global_position = me.global_position.lerp(target, 0.35)
	me.visual.rotation.y = lerp_angle(me.visual.rotation.y, yaw, 0.3)
	var moving: bool = (leader as RemotePlayer).moving if leader is RemotePlayer else (leader as Player).is_moving()
	me.anim_hold = "walk" if moving else ""
	if me.move_input.length() > 0.5:
		main._fx({"k": "letgo"})


func _let_go() -> void:
	if hands.is_empty():
		return
	if hands.get("follower") == main.me:
		main.me.frozen = false
		main.me.held = false
		main.me.anim_hold = ""
	hands.clear()


# ---------- stargazing on the picnic blanket ----------

func _start_gaze() -> void:
	var me: Player = main.me
	var ids: Array = Net.players.keys()
	ids.sort()
	var spot := maxi(0, ids.find(Net.my_id)) % 2
	var x := -0.36 if spot == 0 else 0.36
	me.lie_at(House.PICNIC + Vector3(x, 0.19, -0.78))
	gazing = true
	_gaze_cam.global_position = House.PICNIC + Vector3(0, 0.75, -1.25)
	_gaze_cam.look_at(House.PICNIC + Vector3(-5.5, 9.0, 8.0))
	_gaze_cam.make_current()
	main.ui.hud.modulate.a = 0.35
	chill.set_heart(true)
	main.ui.toast("🌌 Look at the stars together... push the stick to get up", 3.5)


func _gaze_tick(_dt: float) -> void:
	var me: Player = main.me
	if not me.lying:
		_stop_gaze()
		return
	var t := Time.get_ticks_msec() / 1000.0
	var look := House.PICNIC + Vector3(-5.5 + sin(t * 0.07) * 1.5, 9.0, 8.0 + cos(t * 0.05) * 1.2)
	_gaze_cam.look_at(look)
	if chill._next_star > 7.0:
		chill._next_star = 7.0


func _stop_gaze() -> void:
	gazing = false
	main.me.cam.make_current()
	main.ui.hud.modulate.a = 1.0
	chill.set_heart(false)


# ---------- messages written in the sky ----------

## A tiny 5x7 dot-matrix alphabet for messages in the sky (works the same on every phone).
const DOTS := {
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
	"D": ["11100", "10010", "10001", "10001", "10001", "10010", "11100"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
	"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
	"J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
	"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"N": ["10001", "10001", "11001", "10101", "10011", "10001", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
	"W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
	"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
	"Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	"5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
	"6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
	"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
	"9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
	"!": ["00100", "00100", "00100", "00100", "00100", "00000", "00100"],
	"?": ["01110", "10001", "00001", "00010", "00100", "00000", "00100"],
	".": ["00000", "00000", "00000", "00000", "00000", "00000", "00100"],
	",": ["00000", "00000", "00000", "00000", "00100", "00100", "01000"],
	"'": ["00100", "00100", "01000", "00000", "00000", "00000", "00000"],
	"+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
	"&": ["01100", "10010", "10100", "01000", "10101", "10010", "01101"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	"#": ["00000", "01010", "11111", "11111", "01110", "00100", "00000"],
}


var last_sky := ""


func _sky_text(text: String) -> void:
	text = text.strip_edges().to_upper()
	last_sky = text
	if text == "":
		return
	# lay the letters out as dots; anything we don't have a letter for becomes a heart
	var cell := 0.44
	var pts := PackedVector3Array()
	var cam: Camera3D = get_viewport().get_camera_3d()
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var width := text.length() * 6 - 1
	for i in text.length():
		var ch := text[i]
		if ch == " ":
			continue
		var rows: Array = DOTS.get(ch, DOTS["#"])
		for ry in 7:
			var row: String = rows[ry]
			for rx in 5:
				if row[rx] == "1":
					var gx := i * 6 + rx - width / 2.0
					var gy := 3.0 - ry
					for k in 2:
						var j := Vector2(randf_range(-0.12, 0.12), randf_range(-0.12, 0.12))
						pts.append(right * (gx + j.x) * cell + Vector3.UP * (gy + j.y) * cell)
	if pts.is_empty():
		return
	var centre := Vector3(13.0, 15.0, 33.0)
	chill._rocket(centre)
	await get_tree().create_timer(1.3).timeout
	var p := chill._particles(centre, 1.25, mini(pts.size(), 1500), 7.5)
	p.one_shot = true
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	p.emission_points = pts
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.06
	p.gravity = Vector3(0, -0.05, 0)
	p.color_ramp = chill._ramp(Color("#ffc2e4"), 0.88)
	p.emitting = true
	get_tree().create_timer(9.0).timeout.connect(p.queue_free)
	Sfx.play("fw_bang", -2.0)
	# a couple of fireworks once the words have had their moment
	await get_tree().create_timer(5.5).timeout
	var half := width * cell * 0.5 + 4.0
	chill._burst(centre + right * -half + Vector3(0, 3, 0), Color("#ffd166"))
	chill._burst(centre + right * half + Vector3(0, 3, 0), Color("#b388ff"))


# ---------- couple selfie ----------

func _take_selfie() -> void:
	var me: Player = main.me
	if OS.get_name() == "Android":
		OS.request_permissions()
	main.ui.toast("📸 3...", 0.9)
	await get_tree().create_timer(1.0).timeout
	main.ui.toast("📸 2...", 0.9)
	await get_tree().create_timer(1.0).timeout
	main.ui.toast("📸 1... smile! 😁", 0.9)
	await get_tree().create_timer(1.0).timeout
	# frame both of you: camera in front, at arm's length, a little above
	var partner: Node3D = main._partner()
	var focus := me.global_position + Vector3(0, 1.15, 0)
	if partner != null and partner.global_position.distance_to(me.global_position) < 3.5:
		focus = (me.global_position + partner.global_position) * 0.5 + Vector3(0, 1.15, 0)
	var fwd := Vector3(-sin(me.visual.rotation.y), 0, -cos(me.visual.rotation.y))
	var cam := Camera3D.new()
	cam.fov = 58.0
	add_child(cam)
	cam.global_position = focus + fwd * 2.3 + Vector3(0, 0.45, 0)
	cam.look_at(focus, Vector3.UP)
	cam.make_current()
	main.ui.hud.visible = false
	var d := Time.get_date_dict_from_system()
	overlays.show_frame("💜 %s & %s  ·  %02d/%02d/%d" % [main.my_name, main._player_name(main._partner_id()) if partner else "PekaBoo", d["day"], d["month"], d["year"]])
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	overlays.frame.visible = false
	overlays.do_flash()
	Sfx.play("shutter")
	main.ui.hud.visible = true
	me.cam.make_current()
	cam.queue_free()
	var saved := _save_photo(img)
	main.ui.toast("📸 Saved to " + saved if saved != "" else "📸 Couldn't save the photo", 3.5)


func _save_photo(img: Image) -> String:
	var name := "PekaBoo_%d.png" % int(Time.get_unix_time_from_system())
	if OS.get_name() == "Android":
		var g := _save_to_gallery(img, name)
		if g != "":
			return g
	var dirs := []
	var pics := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if pics != "":
		dirs.append([pics + "/PekaBoo", "Pictures/PekaBoo"])
	var dcim := OS.get_system_dir(OS.SYSTEM_DIR_DCIM)
	if dcim != "":
		dirs.append([dcim + "/PekaBoo", "DCIM/PekaBoo"])
	dirs.append([OS.get_user_data_dir() + "/selfies", "the game's folder"])
	for dpair in dirs:
		DirAccess.make_dir_recursive_absolute(dpair[0])
		if img.save_png(dpair[0] + "/" + name) == OK:
			return dpair[1]
	return ""


## Android: hand the picture to the system's MediaStore, so it shows up in the Gallery / Google
## Photos straight away (plain files in Pictures/ aren't indexed, or can't be written at all).
func _save_to_gallery(img: Image, name: String) -> String:
	var tmp := OS.get_user_data_dir() + "/" + name
	if img.save_png(tmp) != OK:
		return ""
	var rt = Engine.get_singleton("AndroidRuntime") if Engine.has_singleton("AndroidRuntime") else null
	if rt == null:
		return ""
	var act = rt.getActivity()
	var media = JavaClassWrapper.wrap("android.provider.MediaStore$Images$Media")
	if act == null or media == null:
		return ""
	var url = media.insertImage(act.getContentResolver(), tmp, name.get_basename(), "PekaBoo selfie")
	DirAccess.remove_absolute(tmp)
	print("selfie: MediaStore -> ", url)
	return "Gallery" if url != null and str(url) != "" else ""


# ---------- weather ----------

func set_weather(w: String) -> void:
	weather = w
	if _rain == null:
		_rain = _make_precip(false)
		_snow = _make_precip(true)
		_rain_snd = AudioStreamPlayer.new()
		_rain_snd.stream = Sfx._ogg("amb_rain")
		if _rain_snd.stream is AudioStreamOggVorbis:
			(_rain_snd.stream as AudioStreamOggVorbis).loop = true
		_rain_snd.bus = "SFX"
		add_child(_rain_snd)
	_rain.emitting = w == "rain"
	_snow.emitting = w == "snow"
	if w == "rain":
		_rain_snd.play()
	else:
		_rain_snd.stop()
	chill.set_cloud({"clear": 0.0, "rain": 0.85, "snow": 0.55}[w])
	if w != "clear":
		main.ui.toast({"rain": "🌧 It's raining... cosy time", "snow": "❄️ It's snowing!"}[w], 2.5)


func _make_precip(snow: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 260 if not snow else 220
	p.lifetime = 1.1 if not snow else 7.0
	p.preprocess = 1.0 if not snow else 6.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(8, 0.5, 8)
	p.direction = Vector3.DOWN
	p.spread = 4.0 if not snow else 25.0
	p.initial_velocity_min = 14.0 if not snow else 0.6
	p.initial_velocity_max = 17.0 if not snow else 1.2
	p.gravity = Vector3(0, -2.0, 0) if not snow else Vector3(0, -0.25, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.45) if not snow else Vector2(0.11, 0.11)
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if snow:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = chill._glow_texture()
		m.albedo_color = Color(0.92, 0.94, 1.0, 0.95)
	else:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.albedo_color = Color(0.75, 0.8, 0.95, 0.35)
	p.material_override = m
	add_child(p)
	return p


func _weather_tick(_dt: float) -> void:
	if weather == "clear" or _rain == null:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	var outside: bool = Sfx.outdoors > 0.5 or main.me.global_position.y > 7.0
	var at := cam.global_position + Vector3(0, 9.0 if weather == "rain" else 7.0, 0)
	for p in [_rain, _snow]:
		p.global_position = at
		p.visible = outside
	_rain_snd.volume_db = -6.0 if outside else -17.0


# ---------- pillow fight ----------

func _start_pf() -> void:
	pf = {"t": 60.0, "me": 0, "them": 0}
	main.ui.toast("🛏 PILLOW FIGHT! 60 seconds, most hits wins!", 3.0)
	Sfx.say("go")


func _pf_tick(dt: float) -> void:
	pf["t"] -= dt
	var nm: String = main._player_name(main._partner_id())
	main.ui.set_timer("🛏 You %d – %d %s  ·  %ds" % [pf["me"], pf["them"], nm, ceili(maxf(pf["t"], 0.0))])
	if pf["t"] <= 0.0:
		_end_pf()


func _end_pf() -> void:
	if pf.is_empty():
		return
	var a: int = pf["me"]
	var b: int = pf["them"]
	pf.clear()
	var nm: String = main._player_name(main._partner_id())
	var title := "You win! 🏆" if a > b else ("%s wins! 🏆" % nm if b > a else "It's a tie! 🤝")
	overlays.show_card("🛏", "Pillow fight", "%s\n\nYou %d  –  %d %s" % [title, a, b, nm])
	if a >= b:
		Build.burst(main, main.me.global_position, "confetti")
	Sfx.play("cheer", -8.0)


# ---------- cooking together: pick a dish, watch it cook, eat it together ----------

func _open_menu() -> void:
	var items := []
	for i in DISHES.size():
		items.append([DISHES[i][0], DISHES[i][1]])
	overlays.show_grid("🍳 What shall we cook?", items, func(i: int): main._fx({"k": "cookstart", "r": i}))


func _start_cook(r: int, _seed_v: int, _starter: int) -> void:
	var dish: Array = DISHES[r % DISHES.size()]
	cook = {"r": r % DISHES.size(), "t": 0.0, "next": 0, "ready": false, "bites": 0}
	if _dish:
		_dish.queue_free()
		_dish = null
	_make_pot()
	Sfx.play("sizzle", -8.0)
	main.ui.toast("%s Cooking %s..." % [dish[0], dish[1]], 2.5)


func _cook_tick(dt: float) -> void:
	if cook.get("ready", false):
		return
	cook["t"] += dt
	var t: float = cook["t"]
	var dish: Array = DISHES[cook["r"]]
	var ings: Array = dish[2]
	# ingredients hop into the pot one by one, then it simmers, then it's ready
	var n: int = cook["next"]
	if n < ings.size() and t > 0.6 + n * 1.0:
		cook["next"] = n + 1
		_ingredient(ings[n])
	var total := 0.6 + ings.size() * 1.0 + 1.6
	main.ui.set_timer("%s Cooking %s  %d%%" % [dish[0], dish[1], int(minf(t / total, 1.0) * 100)])
	if t >= total:
		cook["ready"] = true
		main.ui.set_timer("")
		if _pot:
			_pot.queue_free()
			_pot = null
		_make_dish(dish[0])
		Sfx.play("win")
		Build.burst(main, Vector3(DISH_AT.x, 0.4, DISH_AT.z), "hearts")
		overlays.show_card(dish[0], "Ready!", "%s is ready! 😋\nGo to the table and tap Eat together." % dish[1])


func _cook_pick(_i: int) -> void:
	pass


func _cook_step(_i: int, _ok: bool) -> void:
	pass


## One bite (either of you); the dish gets smaller until it's all gone.
func bite(from: int) -> void:
	if cook.is_empty() or not cook.get("ready", false) or _dish == null:
		return
	cook["bites"] += 1
	var left := 1.0 - float(cook["bites"]) / BITES
	var who: Node3D = main._actor(from)
	if who:
		main._bubble_for(who, "😋")
	Sfx.play("pop", -2.0, randf_range(0.7, 0.85))
	Build.burst(main, Vector3(DISH_AT.x, 0.2, DISH_AT.z), "poof")
	if left <= 0.0:
		var dish: Array = DISHES[cook["r"]]
		_dish.queue_free()
		_dish = null
		cook.clear()
		Sfx.play("burp", -4.0)
		overlays.show_card("🍽", "All gone!", "You finished the %s together! 😋\n(Who burped? 😂)" % dish[1])
	else:
		create_tween().tween_property(_dish, "scale", Vector3.ONE * (0.35 + 0.65 * left), 0.2)


func can_eat(p: Vector3) -> bool:
	return not cook.is_empty() and cook.get("ready", false) and _dish != null and _flat(p, DISH_AT) < 2.4 and p.y < 1.5


func _end_cook(_done: bool) -> void:
	if cook.is_empty():
		return
	cook.clear()
	main.ui.set_timer("")
	if _pot:
		_pot.queue_free()
		_pot = null


var _pot: Node3D


func _make_pot() -> void:
	var y := house.surface_y(DISH_AT.x, DISH_AT.z, 1.5)
	_pot = Node3D.new()
	_pot.position = Vector3(DISH_AT.x, y, DISH_AT.z)
	add_child(_pot)
	Build.cyl(_pot, 0.2, 0.17, 0.2, Vector3(0, 0.1, 0), Color("#3c3a44"), 18)
	Build.cyl(_pot, 0.18, 0.18, 0.02, Vector3(0, 0.19, 0), Color("#e8b35a"), 18)
	Build.cube(_pot, Vector3(0.28, 0.03, 0.04), Vector3(0.3, 0.17, 0), Color("#3c3a44"))
	Kit.set_probe_light(Kit.apply_probe_look(_pot, 0.4), house.light_at(_pot.position + Vector3(0, 0.5, 0)))
	var steam := CPUParticles3D.new()
	steam.amount = 14
	steam.lifetime = 1.6
	steam.direction = Vector3.UP
	steam.spread = 12.0
	steam.initial_velocity_min = 0.3
	steam.initial_velocity_max = 0.6
	steam.gravity = Vector3.ZERO
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.18)
	steam.mesh = q
	var m := chill._glow_mat(Color(0.8, 0.8, 0.85, 0.35))
	steam.material_override = m
	steam.position = Vector3(0, 0.25, 0)
	_pot.add_child(steam)


## An ingredient (as a big emoji) hops up and drops into the pot.
func _ingredient(e: String) -> void:
	if _pot == null:
		return
	var l := Label3D.new()
	l.text = e
	l.font = Kit.ui_font()
	l.font_size = 96
	l.pixel_size = 0.004
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	_pot.add_child(l)
	l.position = Vector3(randf_range(-0.5, 0.5), 0.3, 0.6)
	var tw := l.create_tween()
	tw.tween_property(l, "position", Vector3(0, 1.0, 0), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(l, "position", Vector3(0, 0.25, 0), 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(l.queue_free)
	Sfx.play("pop", -6.0, randf_range(1.0, 1.3))


func _make_dish(kind: String) -> void:
	var y := house.surface_y(DISH_AT.x, DISH_AT.z, 1.5)
	_dish = Node3D.new()
	_dish.position = Vector3(DISH_AT.x, y, DISH_AT.z)
	add_child(_dish)
	Build.cyl(_dish, 0.22, 0.22, 0.015, Vector3(0, 0.008, 0), Color("#f6f1ea"), 20)
	match kind:
		"🍰":
			Build.cyl(_dish, 0.16, 0.16, 0.12, Vector3(0, 0.075, 0), Color("#fbe3ea"), 20)
			Build.cyl(_dish, 0.165, 0.165, 0.025, Vector3(0, 0.14, 0), Color("#e36f97"), 20)
			for k in 6:
				Build.ball(_dish, 0.025, Vector3(cos(k) * 0.1, 0.16, sin(k) * 0.1), Color("#d1222f"))
		"🍕":
			Build.cyl(_dish, 0.2, 0.2, 0.025, Vector3(0, 0.03, 0), Color("#e8b35a"), 20)
			Build.cyl(_dish, 0.18, 0.18, 0.01, Vector3(0, 0.045, 0), Color("#d2442f"), 20)
			for k in 7:
				Build.ball(_dish, 0.025, Vector3(cos(k * 2.3) * 0.11, 0.05, sin(k * 2.3) * 0.11), Color("#ffe27a") if k % 2 == 0 else Color("#3f8a3a"), Vector3(1, 0.4, 1))
		"☕":
			Build.cyl(_dish, 0.07, 0.06, 0.12, Vector3(-0.05, 0.075, 0), Color("#fffaf5"), 14)
			Build.cyl(_dish, 0.062, 0.062, 0.01, Vector3(-0.05, 0.13, 0), Color("#b8834e"), 14)
			Build.cyl(_dish, 0.07, 0.06, 0.12, Vector3(0.1, 0.075, 0), Color("#fffaf5"), 14)
			Build.cyl(_dish, 0.062, 0.062, 0.01, Vector3(0.1, 0.13, 0), Color("#b8834e"), 14)
		"🍜":
			Build.cyl(_dish, 0.16, 0.11, 0.1, Vector3(0, 0.06, 0), Color("#e8434f"), 18)
			Build.cyl(_dish, 0.15, 0.15, 0.02, Vector3(0, 0.1, 0), Color("#f6d27a"), 18)
			for k in 6:
				Build.cube(_dish, Vector3(0.2, 0.012, 0.02), Vector3(0, 0.115, -0.08 + k * 0.03), Color("#f2c45a"), Vector3(0, k * 0.5, 0))
		"🍔":
			Build.cyl(_dish, 0.14, 0.14, 0.05, Vector3(0, 0.04, 0), Color("#d9964a"), 16)
			Build.cyl(_dish, 0.15, 0.15, 0.04, Vector3(0, 0.085, 0), Color("#6b3b22"), 16)
			Build.cyl(_dish, 0.155, 0.155, 0.015, Vector3(0, 0.112, 0), Color("#ffcc33"), 16)
			Build.cyl(_dish, 0.155, 0.155, 0.015, Vector3(0, 0.125, 0), Color("#5fb04a"), 16)
			Build.ball(_dish, 0.145, Vector3(0, 0.15, 0), Color("#e0a050"), Vector3(1, 0.55, 1))
		_:
			Build.cyl(_dish, 0.07, 0.055, 0.22, Vector3(0, 0.12, 0), Color(0.9, 0.95, 1.0, 0.6), 14)
			Build.cyl(_dish, 0.062, 0.05, 0.18, Vector3(0, 0.1, 0), Color("#7a4a2c"), 14)
			Build.ball(_dish, 0.06, Vector3(0, 0.24, 0), Color("#fff6ee"))
	Kit.set_probe_light(Kit.apply_probe_look(_dish, 0.4), house.light_at(_dish.position + Vector3(0, 0.5, 0)))
