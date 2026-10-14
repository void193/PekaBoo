class_name Chill
extends Node3D
## Chill mode: the house at night. Candles, fairy lights, fireflies, a picnic under the stars,
## love songs, and things to do together: kiss, hug, slow dance, sky lanterns, fireworks, wishes.

const KISS_GAP := 0.86   # distance between the two of you while kissing
const HUG_GAP := 0.34     # bodies close, heads past each other (cheek to cheek)
const HUG_SIDE := 0.25    # each of you steps this far to the side so the heads don't bump
const DANCE_GAP := 0.92   # arm's length, holding hands
const SEAT_H := 0.38      # the sit animation's hips land on the sofa cushion at this height
const DUR := {"kiss": 5.0, "hug": 6.0, "dance": 20.0}

var main: Node
var house: House
var on := false
var seats: Array = []      # [{pos, yaw, name}]
var pending := {}          # partner asked for something: {w, from, t}
var asked := {}            # I asked: {w, t}
var seq := {}              # a together moment in progress

var _decor: Node3D
var _flames: Array = []    # [flame quad, halo quad, base scale]
var _sky_mat: ShaderMaterial
var _saved := {}
var _shoot := -1.0
var _next_star := 20.0
var _cam: Camera3D
var _lanterns: Array = []  # [node, age]
var _fw_queue: Array = []  # [time, pos, color]
var _fw_t := 0.0
var _bars: Array = []      # cinema bars
var _glow_tex: ImageTexture


func setup(m: Node, h: House) -> void:
	main = m
	house = h
	_cam = Camera3D.new()
	_cam.fov = 48.0
	_cam.near = 0.05
	add_child(_cam)
	# seats: the living-room sofa and the garden loveseat
	# seats side by side and close, so the two of you sit cuddled up
	for x in [7.58, 8.42]:
		seats.append({"pos": Vector3(x, 0.0, 12.45), "yaw": 0.0, "h": SEAT_H, "name": "Sofa"})
	for x in [-0.36, 0.36]:
		seats.append({"pos": House.PICNIC + Vector3(x, 0.0, -1.5), "yaw": PI, "h": SEAT_H, "name": "Loveseat"})


# ---------- on / off ----------

func enter() -> void:
	if on:
		return
	on = true
	if not house.set_night(true):
		House.dim(0.3)
	elif RenderingServer.get_current_rendering_method() == "gl_compatibility":
		# phones draw the same light a bit darker than the PC: lift it so you can see
		House.dim(1.4)
	var env: Environment = main.env
	_saved = {"sky": env.sky.sky_material, "glow": env.glow_enabled, "sat": env.adjustment_saturation, "con": env.adjustment_contrast,
		"exp": env.tonemap_exposure, "amb": env.ambient_light_energy, "amb_src": env.ambient_light_source,
		"refl": env.reflected_light_source, "proc": env.sky.process_mode}
	# the night sky twinkles every frame; don't rebuild sky lighting from it (nothing here uses it)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.sky.process_mode = Sky.PROCESS_MODE_QUALITY
	if _sky_mat == null:
		_sky_mat = ShaderMaterial.new()
		_sky_mat.shader = load("res://scripts/night_sky.gdshader")
		_sky_mat.set_shader_parameter("moon_dir", (-House.MOON_DIR).normalized())
		_sky_mat.set_shader_parameter("star_tex", _star_texture())
	if not _cx("nosky"):
		env.sky.sky_material = _sky_mat
	# no screen-wide glow: it cost ~12 FPS on the phone; the halo sprites give the soft light instead
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.06
	env.ambient_light_energy = 0.2
	if main.sun:
		main.sun.visible = false
	if _decor == null:
		_build_decor()
	_decor.visible = not _cx("nodecor")
	_relight()
	Sfx.night = true
	# the host (or you alone) picks the song and tells both phones; the other waits for it
	if not Music.song_ended.is_connected(_on_song_ended):
		Music.song_ended.connect(_on_song_ended)
	_song_wait = 3.0
	if _song_leader():
		main.send_song(randi() % maxi(1, Music.songs.size()))
	_next_star = 12.0
	pending.clear()
	asked.clear()


var _song_wait := -1.0  # follower: seconds to wait for the host's song before playing one alone


func _song_leader() -> bool:
	return not Net.is_online() or Net.is_host()


func _on_song_ended() -> void:
	if not on:
		return
	if _song_leader():
		main.send_song(Music.song_index() + 1)
	else:
		_song_wait = 4.0


func exit() -> void:
	if not on:
		return
	_end_seq()
	on = false
	house.set_night(false)
	House.dim(1.0)
	var env: Environment = main.env
	env.sky.sky_material = _saved.get("sky", env.sky.sky_material)
	env.glow_enabled = _saved.get("glow", false)
	env.adjustment_saturation = _saved.get("sat", 1.12)
	env.adjustment_contrast = _saved.get("con", 1.04)
	env.tonemap_exposure = _saved.get("exp", 1.05)
	env.ambient_light_energy = _saved.get("amb", 0.6)
	env.ambient_light_source = _saved.get("amb_src", Environment.AMBIENT_SOURCE_SKY)
	env.reflected_light_source = _saved.get("refl", Environment.REFLECTION_SOURCE_SKY)
	env.sky.process_mode = _saved.get("proc", Sky.PROCESS_MODE_AUTOMATIC)
	if main.sun:
		main.sun.visible = true
	if _decor:
		_decor.visible = false
	_relight()
	for l in _lanterns:
		(l[0] as Node).queue_free()
	_lanterns.clear()
	_fw_queue.clear()
	Sfx.night = false
	main._apply_settings()


# ---------- decorations ----------

func _glow_texture() -> ImageTexture:
	if _glow_tex == null:
		# soft round glow, premultiplied (fades to black too: additive blending ignores alpha)
		var img := Image.create(64, 64, true, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
				var v := clampf(1.0 - d, 0.0, 1.0)
				v = v * v * (0.35 + 0.65 * v)
				img.set_pixel(x, y, Color(v, v, v, v))
		img.generate_mipmaps()
		_glow_tex = ImageTexture.create_from_image(img)
	return _glow_tex


func _glow_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _glow_texture()
	m.albedo_color = Color(c.r * c.a, c.g * c.a, c.b * c.a, 1.0)
	m.disable_receive_shadows = true
	if not _cx("nodither"):
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		m.distance_fade_min_distance = 0.4
		m.distance_fade_max_distance = 1.6
	return m


## Benchmark experiments: --cx=nodecor,nosky,nodither (comma list; use ':' on the phone)
func _cx(k: String) -> bool:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--cx=") and k in a.substr(5).replace(":", ",").split(","):
			return true
	return false


func _quad(parent: Node3D, size: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Built-from-shapes objects get the same night light as the characters.
func _light_up(node: Node3D, at: Vector3) -> void:
	var mats := Kit.apply_probe_look(node, 0.45)
	Kit.set_probe_light(mats, house.light_at(at))
	_lit.append([mats, at])


var _lit: Array = []


## Day <-> night: everything built from shapes picks up the new light.
func _relight() -> void:
	for l in _lit:
		Kit.set_probe_light(l[0], house.light_at(l[1]))


func _flame(parent: Node3D, pos: Vector3, halo := 0.7) -> void:
	var f := _quad(parent, 0.07, pos, _glow_mat(Color(1.0, 0.78, 0.4, 1.0)))
	f.scale = Vector3(0.8, 1.4, 1.0)
	var h := _quad(parent, halo * 1.25, pos, _glow_mat(Color(1.0, 0.55, 0.22, 0.4)))
	_flames.append([f, h, randf() * 10.0])


func _build_decor() -> void:
	_decor = Node3D.new()
	add_child(_decor)
	for l in house.night_lights():
		var p: Vector3 = l["pos"]
		match l["kind"]:
			"candle":
				var base := p - Vector3(0, 0.2, 0)
				var c := Node3D.new()
				_decor.add_child(c)
				for k in 3:
					var off := Vector3(cos(k * 2.1) * 0.06, 0, sin(k * 2.1) * 0.06) if k > 0 else Vector3.ZERO
					var hgt: float = [0.16, 0.11, 0.08][k]
					Build.cyl(c, 0.032, 0.034, hgt, base + off + Vector3(0, hgt / 2.0, 0), Color("#f4e6d0"), 10)
					_flame(_decor, base + off + Vector3(0, hgt + 0.035, 0), 0.55 if k == 0 else 0.35)
				_light_up(c, p)
			"lantern":
				var g := p - Vector3(0, 0.3, 0)
				var lt := Node3D.new()
				_decor.add_child(lt)
				Build.cube(lt, Vector3(0.2, 0.03, 0.2), g + Vector3(0, 0.015, 0), Color("#2b2420"))
				Build.cube(lt, Vector3(0.2, 0.03, 0.2), g + Vector3(0, 0.33, 0), Color("#2b2420"))
				for k in 4:
					var o := Vector3(0.09 * (1 if k % 2 == 0 else -1), 0.17, 0.09 * (1 if k < 2 else -1))
					Build.cube(lt, Vector3(0.02, 0.3, 0.02), g + o, Color("#2b2420"))
				Build.cyl(lt, 0.02, 0.12, 0.08, g + Vector3(0, 0.38, 0), Color("#2b2420"), 8)
				_light_up(lt, p)
				var glass := Build.cube(_decor, Vector3(0.16, 0.28, 0.16), g + Vector3(0, 0.17, 0), Color(1.0, 0.72, 0.42, 0.5))
				var gm := StandardMaterial3D.new()
				gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				gm.albedo_color = Color(1.0, 0.7, 0.4, 0.42)
				glass.material_override = gm
				_flame(_decor, g + Vector3(0, 0.15, 0), 1.3)
	_fairy_lights()
	_picnic()
	_petals()
	_fireflies()


func _fairy_lights() -> void:
	var pts: Array[Vector3] = []
	for st in House.fairy_strings():
		var n: int = st[3]
		var wire := ImmediateMesh.new()
		wire.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for i in n + 1:
			wire.surface_add_vertex(House.string_point(st, float(i) / n))
		wire.surface_end()
		var wm := StandardMaterial3D.new()
		wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wm.albedo_color = Color(0.06, 0.05, 0.05)
		var wi := MeshInstance3D.new()
		wi.mesh = wire
		wi.material_override = wm
		_decor.add_child(wi)
		for i in n:
			pts.append(House.string_point(st, (i + 0.5) / n) - Vector3(0, 0.05, 0))
	# bulbs: little warm spheres that twinkle, plus a soft halo each
	var bulb := SphereMesh.new()
	bulb.radius = 0.028
	bulb.height = 0.056
	bulb.radial_segments = 8
	bulb.rings = 4
	var bs := Shader.new()
	bs.code = """shader_type spatial;
render_mode unshaded;
varying float tw;
void vertex() {
	float ph = INSTANCE_CUSTOM.x * 6.283;
	tw = 0.8 + 0.2 * sin(TIME * (1.2 + INSTANCE_CUSTOM.y) + ph);
}
void fragment() {
	// fade out when the camera is right next to a bulb
	float d = length(VERTEX);
	if (fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) > smoothstep(0.4, 1.4, d)) {
		discard;
	}
	ALBEDO = vec3(1.0, 0.88, 0.62) * tw;
}"""
	var bm := ShaderMaterial.new()
	bm.shader = bs
	var halo := QuadMesh.new()
	halo.size = Vector2(0.34, 0.34)
	for pair in [[bulb, bm], [halo, _glow_mat(Color(1.0, 0.75, 0.4, 0.38))]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = pair[0]
		mm.instance_count = pts.size()
		for i in pts.size():
			mm.set_instance_transform(i, Transform3D(Basis(), pts[i]))
			mm.set_instance_custom_data(i, Color(randf(), randf() * 1.5, 0, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = pair[1]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_decor.add_child(mmi)


func _gingham() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	var a := Color("#f2d7dc")
	var b := Color("#c9576f")
	for y in 32:
		for x in 32:
			var cx := (x / 8) % 2 == 0
			var cy := (y / 8) % 2 == 0
			var c := a
			if cx and cy:
				c = b
			elif cx or cy:
				c = a.lerp(b, 0.5)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _picnic() -> void:
	var p := House.PICNIC
	var blanket := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 0.025, 1.7)
	blanket.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _gingham()
	mat.uv1_scale = Vector3(3, 2, 1)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	blanket.material_override = mat
	blanket.position = p + Vector3(0, 0.015, 0)
	blanket.rotation.y = 0.06
	_decor.add_child(blanket)
	_light_up(blanket, p + Vector3(0, 0.3, 0))
	var stuff := Node3D.new()
	_decor.add_child(stuff)
	Build.ball(stuff, 0.3, p + Vector3(-0.62, 0.1, 0.25), Color("#e7a4b8"), Vector3(1, 0.42, 0.85))
	Build.ball(stuff, 0.3, p + Vector3(0.6, 0.1, 0.3), Color("#b9a6e3"), Vector3(1, 0.42, 0.85))
	# basket with a lid, a plate of strawberries, two glasses
	Build.cube(stuff, Vector3(0.44, 0.24, 0.3), p + Vector3(0.15, 0.14, -0.45), Color("#a8743f"))
	Build.cube(stuff, Vector3(0.46, 0.04, 0.32), p + Vector3(0.15, 0.27, -0.45), Color("#8c5d30"))
	Build.cyl(stuff, 0.17, 0.15, 0.02, p + Vector3(-0.2, 0.04, -0.05), Color("#f6f1ea"), 16)
	for k in 7:
		var a := k * 0.9
		Build.ball(stuff, 0.035, p + Vector3(-0.2 + cos(a) * 0.08 * (k % 2 + 0.3), 0.07, -0.05 + sin(a) * 0.08 * (k % 2 + 0.3)), Color("#d1222f"), Vector3(1, 1.2, 1))
	for x in [0.32, 0.44]:
		Build.cyl(stuff, 0.04, 0.025, 0.1, p + Vector3(x, 0.16, 0.05), Color(0.85, 0.9, 1.0, 0.5), 10)
		Build.cyl(stuff, 0.005, 0.005, 0.1, p + Vector3(x, 0.06, 0.05), Color(0.85, 0.9, 1.0, 0.6), 6)
	_light_up(stuff, p + Vector3(0, 0.4, 0))


## Rose petals: a heart on the grass by the picnic, and a scatter on the living-room rug.
func _petals() -> void:
	var xforms: Array[Transform3D] = []
	var hc := House.PICNIC + Vector3(0, 0.012, 1.55)
	for i in 140:
		var t := TAU * i / 140.0
		var hx := 16.0 * pow(sin(t), 3)
		var hz := 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
		var pos := hc + Vector3(-hx, 0, hz) * 0.042 + Vector3(randf_range(-0.03, 0.03), 0, randf_range(-0.03, 0.03))
		xforms.append(Transform3D(Basis(Vector3.UP, randf() * TAU), pos))
	for i in 90:
		var pos := Vector3(randf_range(5.6, 9.6), 0.025, randf_range(10.9, 11.9))
		xforms.append(Transform3D(Basis(Vector3.UP, randf() * TAU), pos))
	# RUBIN ♥ BABITA, spelled in petals either side of the heart, reading from the loveseat
	# (sitting there you face +z, so "right" is -x and the tops of the letters point away)
	var cell := 0.1
	for word in [["RUBIN", 1.0], ["BABITA", -1.0]]:
		var w: String = word[0]
		var side: float = word[1]
		var width := w.length() * 6 - 1
		var start_x := hc.x + side * (0.95 + width * cell) if side > 0.0 else hc.x - 0.95
		for i in w.length():
			var rows: Array = Extras.DOTS.get(w[i], Extras.DOTS["#"])
			for ry in 7:
				var row: String = rows[ry]
				for rx in 5:
					if row[rx] != "1":
						continue
					var gx := float(i * 6 + rx)
					var gz := 3.0 - ry
					for k in 2:
						var pos := Vector3(start_x - gx * cell + randf_range(-0.025, 0.025), 0.013, hc.z + gz * cell + randf_range(-0.025, 0.025))
						xforms.append(Transform3D(Basis(Vector3.UP, randf() * TAU), pos))
	var q := PlaneMesh.new()
	q.size = Vector2(0.07, 0.05)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = q
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		var night := house.light_at(xforms[i].origin + Vector3.UP * 0.5) if house.is_night else Color(0.4, 0.35, 0.4)
		var base := Color("#b3122e").lerp(Color("#e0405f"), randf())
		mm.set_instance_color(i, Color(base.r * night.r * 1.6, base.g * night.g * 1.6, base.b * night.b * 1.6))
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = pm
	_decor.add_child(mmi)


func _fireflies() -> void:
	var p := CPUParticles3D.new()
	p.amount = 80
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(13, 0.9, 7)
	p.position = Vector3(12, 1.2, 24.5)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	p.gravity = Vector3.ZERO
	p.orbit_velocity_min = 0.0
	p.angular_velocity_min = 0.0
	var g := Gradient.new()
	g.set_color(0, Color(0.85, 1.0, 0.45, 0.0))
	g.add_point(0.2, Color(0.85, 1.0, 0.45, 0.9))
	g.add_point(0.5, Color(0.85, 1.0, 0.45, 0.25))
	g.add_point(0.75, Color(0.85, 1.0, 0.45, 0.9))
	g.set_color(1, Color(0.85, 1.0, 0.45, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	p.mesh = q
	var m := _glow_mat(Color(1, 1, 1, 1))
	m.vertex_color_use_as_albedo = true
	p.material_override = m
	_decor.add_child(p)


# ---------- every frame ----------

func _process(dt: float) -> void:
	if not _balloons.is_empty():
		_bob_balloons(dt)
	if not on:
		if not _flames.is_empty() and not _balloons.is_empty():
			_flicker(dt)
		return
	_flicker(dt)
	# shooting stars every now and then
	_next_star -= dt
	if _next_star <= 0.0 and _shoot < 0.0:
		shooting_star()
		_next_star = randf_range(25.0, 50.0)
	if _shoot >= 0.0:
		_shoot += dt / 1.4
		_sky_mat.set_shader_parameter("shoot_t", _shoot)
		if _shoot > 1.0:
			_shoot = -1.0
			_sky_mat.set_shader_parameter("shoot_t", -1.0)
	if _song_wait > 0.0:
		_song_wait -= dt
		if _song_wait <= 0.0:
			# never heard from the host: keep the music going on our own
			Music.play_song(Music.song_index() + 1 if Music.current == "songs" else randi())
	_tick_lanterns(dt)
	_tick_fireworks(dt)
	if not seq.is_empty():
		_tick_seq(dt)
	_tick_cuddle()
	if not pending.is_empty() and Time.get_ticks_msec() / 1000.0 - float(pending["t"]) > 9.0:
		pending.clear()
	if not asked.is_empty() and Time.get_ticks_msec() / 1000.0 - float(asked["t"]) > 9.0:
		asked.clear()


func _flicker(dt: float) -> void:
	for f in _flames:
		f[2] += dt * 9.0
		var k: float = 1.0 + sin(f[2]) * 0.06 + sin(f[2] * 2.3) * 0.05
		(f[0] as Node3D).scale = Vector3(0.8 * k, 1.4 * k * k, 1.0)
		(f[1] as Node3D).scale = Vector3.ONE * (0.92 + 0.08 * k)


## A panorama of stars (equirectangular), drawn once.
func _star_texture() -> ImageTexture:
	var w := 2048
	var h := 1024
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for i in 5200:
		# uniform over the sphere, then into panorama pixels
		var y := rng.randf_range(-0.05, 1.0)
		var a := rng.randf() * TAU
		var r := sqrt(maxf(0.0, 1.0 - y * y))
		var d := Vector3(r * cos(a), y, r * sin(a))
		var u := atan2(d.x, -d.z) / TAU + 0.5
		var v := acos(clampf(d.y, -1.0, 1.0)) / PI
		var px := int(u * w) % w
		var py := clampi(int(v * h), 0, h - 1)
		var b := pow(rng.randf(), 3.0) * 0.9 + 0.1
		var tint := Color(1.0, 0.95, 0.88).lerp(Color(0.8, 0.88, 1.0), rng.randf())
		var phase := rng.randf()
		img.set_pixel(px, py, Color(tint.r * b, tint.g * b, tint.b * b, phase))
		if b > 0.55:
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := Vector2i((px + o.x + w) % w, clampi(py + o.y, 0, h - 1))
				img.set_pixel(q.x, q.y, Color(tint.r * b * 0.35, tint.g * b * 0.35, tint.b * b * 0.35, phase))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


var _heart_tw: Tween


var _heart: Node3D
var _heart_mats: Array = []


## The heart constellation: 15 stars joined by faint pink lines, far up over the garden.
func set_heart(on_: bool) -> void:
	if _heart == null:
		_heart = Node3D.new()
		add_child(_heart)
		var dir := Vector3(-0.42, 0.66, 0.62).normalized()
		var centre := House.PICNIC + dir * 300.0
		var right := dir.cross(Vector3.UP).normalized()
		var up := right.cross(dir).normalized()
		var pts: Array[Vector3] = []
		for i in 15:
			var t := TAU * i / 14.0
			var p := Vector2(16.0 * pow(sin(t), 3.0), 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)) / 17.0 * 52.0
			pts.append(centre + right * p.x + up * p.y)
		var star_m := _glow_mat(Color(1.0, 0.8, 0.92, 1.0))
		star_m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED
		_heart_mats.append(star_m)
		for p in pts:
			var q := _quad(_heart, 15.0, Vector3.ZERO, star_m)
			q.global_position = p
		var lines := ImmediateMesh.new()
		lines.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for p in pts:
			lines.surface_add_vertex(p)
		lines.surface_end()
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		lm.albedo_color = Color(0.5, 0.25, 0.4)
		_heart_mats.append(lm)
		var li := MeshInstance3D.new()
		li.mesh = lines
		li.material_override = lm
		_heart.add_child(li)
		_heart.visible = false
	if _heart_tw:
		_heart_tw.kill()
	_heart.visible = true
	_heart_tw = create_tween().set_parallel(true)
	var star_c := Color(1.0, 0.8, 0.92) if on_ else Color(0, 0, 0)
	var line_c := Color(0.5, 0.25, 0.4) if on_ else Color(0, 0, 0)
	_heart_tw.tween_property(_heart_mats[0], "albedo_color", star_c, 2.5)
	_heart_tw.tween_property(_heart_mats[1], "albedo_color", line_c, 2.5)
	if not on_:
		_heart_tw.chain().tween_callback(func(): _heart.visible = false)


func set_cloud(v: float) -> void:
	if _sky_mat:
		_sky_mat.set_shader_parameter("cloud", v)


func shooting_star() -> void:
	var a := Vector3(randf_range(-0.9, 0.9), randf_range(0.45, 0.75), randf_range(-0.9, 0.9)).normalized()
	var b := (a + Vector3(randf_range(-0.5, 0.5), -0.28, randf_range(-0.5, 0.5))).normalized()
	_sky_mat.set_shader_parameter("shoot_from", a)
	_sky_mat.set_shader_parameter("shoot_to", b)
	_shoot = 0.0


## A wish: a shooting star right where you are looking, a twinkle and a little message.
func wish(look: Vector3) -> void:
	var f := look
	f.y = 0.0
	f = f.normalized()
	var side := f.cross(Vector3.UP)
	_sky_mat.set_shader_parameter("shoot_from", (f + side * 0.45 + Vector3(0, 0.55, 0)).normalized())
	_sky_mat.set_shader_parameter("shoot_to", (f - side * 0.35 + Vector3(0, 0.28, 0)).normalized())
	_shoot = 0.0
	_next_star = 30.0
	Sfx.play("twinkle", -4.0)


# ---------- sky lanterns ----------

func lantern(from: Vector3) -> void:
	var n := Node3D.new()
	add_child(n)
	n.global_position = from + Vector3(0, 1.4, 0)
	var body := Build.cyl(n, 0.17, 0.12, 0.34, Vector3.ZERO, Color(1.0, 0.62, 0.32), 12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.66, 0.34)
	body.material_override = m
	_quad(n, 1.4, Vector3(0, -0.05, 0), _glow_mat(Color(1.0, 0.55, 0.2, 0.5)))
	_lanterns.append([n, 0.0, randf() * TAU])
	Sfx.play_at("whoosh", from + Vector3.UP, -8.0, 0.7)


func _tick_lanterns(dt: float) -> void:
	for l in _lanterns.duplicate():
		l[1] += dt
		var n: Node3D = l[0]
		var t: float = l[1]
		n.global_position += Vector3(sin(t * 0.4 + l[2]) * 0.18, minf(t * 0.6, 0.85), cos(t * 0.3 + l[2]) * 0.14) * dt
		n.rotation.z = sin(t * 0.9 + l[2]) * 0.08
		if t > 45.0:
			n.queue_free()
			_lanterns.erase(l)


# ---------- fireworks ----------

const FW_COLORS := [Color("#ff5c9a"), Color("#ffd166"), Color("#b388ff"), Color("#ffffff"), Color("#ff8fb1"), Color("#7fdbff")]


## A show over the back garden; seed keeps both phones' shows the same. Every third one is a heart.
func fireworks(seed_v: int, count := 9) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var t := 1.5
	for i in count:
		var pos := Vector3(rng.randf_range(7, 19), rng.randf_range(14, 19), rng.randf_range(30, 37))
		var shape := "heart" if i % 3 == 2 else ("ring" if i % 4 == 1 else "ball")
		_fw_queue.append([_fw_t + t, pos, FW_COLORS[rng.randi() % FW_COLORS.size()], false, shape])
		t += rng.randf_range(0.7, 1.4)


func _tick_fireworks(dt: float) -> void:
	_fw_t += dt
	for f in _fw_queue.duplicate():
		var pos: Vector3 = f[1]
		if not f[3] and _fw_t >= f[0] - 1.3:
			f[3] = true
			_rocket(pos)
		if _fw_t >= f[0]:
			_burst(pos, f[2], f[4])
			_fw_queue.erase(f)


## Particles that only start once they're in place (CPUParticles3D starts emitting the moment
## it enters the tree, which put the first explosions at the world origin).
func _particles(pos: Vector3, size: float, amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	p.mesh = q
	var m := _glow_mat(Color(1, 1, 1, 1))
	m.vertex_color_use_as_albedo = true
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED
	p.material_override = m
	add_child(p)
	p.global_position = pos
	return p


## Additive colours fade by going dark (alpha is ignored), so ramps end in black.
func _ramp(c: Color, hold := 0.55) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1))
	g.add_point(0.1, c.lightened(0.25))
	g.add_point(hold, c)
	g.set_color(1, Color(0, 0, 0))
	return g


func _rocket(to: Vector3) -> void:
	var from := Vector3(to.x, 0.5, to.z)
	var p := _particles(from, 0.6, 36, 0.7)
	p.direction = Vector3.DOWN
	p.spread = 10.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.5
	p.gravity = Vector3(0, -1.0, 0)
	p.color_ramp = _ramp(Color(1.0, 0.75, 0.4), 0.3)
	p.emitting = true
	var tw := create_tween()
	tw.tween_property(p, "global_position", to, 1.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func(): p.emitting = false)
	tw.tween_interval(0.8)
	tw.tween_callback(p.queue_free)
	Sfx.play("fw_launch", _fw_volume(from) - 6.0, randf_range(0.9, 1.1))


func _fw_volume(at: Vector3) -> float:
	var d := at.distance_to(main.me.global_position)
	return lerpf(2.0, -14.0, clampf((d - 15.0) / 45.0, 0.0, 1.0))


func _burst(pos: Vector3, c: Color, shape := "ball") -> void:
	var main_p := _particles(pos, 1.5, 190 if shape != "ring" else 130, 2.8)
	main_p.one_shot = true
	main_p.explosiveness = 1.0
	main_p.gravity = Vector3(0, -1.4, 0)
	main_p.damping_min = 0.9
	main_p.damping_max = 1.1
	main_p.color_ramp = _ramp(c)
	match shape:
		"heart":
			# points on a heart outline, flying outwards, turned to face whoever is watching
			var look: Vector3 = main.me.global_position - pos
			look.y = 0.0
			var right := Vector3.UP.cross(look.normalized()).normalized()
			var pts := PackedVector3Array()
			var nrm := PackedVector3Array()
			for i in 90:
				var t := TAU * i / 90.0
				var hx := 16.0 * pow(sin(t), 3) / 16.0
				var hy := (13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)) / 16.0
				var v := right * hx + Vector3.UP * hy
				pts.append(v * 0.2)
				nrm.append(v)
			main_p.emission_shape = CPUParticles3D.EMISSION_SHAPE_DIRECTED_POINTS
			main_p.emission_points = pts
			main_p.emission_normals = nrm
			main_p.amount = 180
			main_p.direction = Vector3.RIGHT
			main_p.spread = 0.0
			main_p.initial_velocity_min = 7.0
			main_p.initial_velocity_max = 7.3
			main_p.gravity = Vector3(0, -0.4, 0)
			main_p.color_ramp = _ramp(Color("#ff4f8b"), 0.7)
		"ring":
			main_p.direction = Vector3.UP
			main_p.spread = 180.0
			main_p.flatness = 0.92
			main_p.initial_velocity_min = 10.0
			main_p.initial_velocity_max = 10.3
		_:
			main_p.direction = Vector3.UP
			main_p.spread = 180.0
			main_p.initial_velocity_min = 8.0
			main_p.initial_velocity_max = 10.5
	main_p.emitting = true
	# glitter that hangs and twinkles down afterwards
	var gl := _particles(pos, 0.75, 90, 3.6)
	gl.one_shot = true
	gl.explosiveness = 0.85
	gl.direction = Vector3.UP
	gl.spread = 180.0
	gl.initial_velocity_min = 3.0
	gl.initial_velocity_max = 7.0
	gl.damping_min = 1.0
	gl.damping_max = 1.4
	gl.gravity = Vector3(0, -1.2, 0)
	gl.color_ramp = _ramp(Color("#ffe3a3"), 0.4)
	gl.emitting = true
	# a quick flash that lights up the sky
	var fm := _glow_mat(Color(c.r, c.g, c.b, 0.55))
	fm.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED
	var flash := _quad(self, 16.0, Vector3.ZERO, fm)
	flash.global_position = pos
	var tw := flash.create_tween()
	tw.tween_property(flash, "scale", Vector3.ONE * 1.6, 0.4)
	tw.parallel().tween_property(fm, "albedo_color", Color(0, 0, 0), 0.4)
	tw.tween_callback(flash.queue_free)
	get_tree().create_timer(4.0).timeout.connect(main_p.queue_free)
	get_tree().create_timer(4.0).timeout.connect(gl.queue_free)
	Sfx.play("fw_bang", _fw_volume(pos), randf_range(0.85, 1.1))


# ---------- together: kiss, hug, slow dance ----------

## Both phones run this with the same numbers. a asked, b said yes.
func start_together(kind: String, a: Node3D, b: Node3D, centre: Vector3, yaw: float) -> void:
	_end_seq()
	var dir := Vector3(-sin(yaw), 0, -cos(yaw))   # from a towards b
	seq = {"kind": kind, "a": a, "b": b, "c": centre, "dir": dir, "t": 0.0, "dur": DUR.get(kind, 5.0), "spin": 0.0}
	var gap: float = {"kiss": KISS_GAP, "hug": HUG_GAP, "dance": DANCE_GAP}.get(kind, 0.5)
	seq["dipped"] = false
	seq["gap"] = gap
	var hold := "holding-both" if kind in ["hug", "dance"] else ""
	for who in [a, b]:
		var side := 1.0 if who == a else -1.0
		if who is Player:
			var me := who as Player
			me.frozen = true
			me.anim_hold = hold
			me.velocity = Vector3.ZERO
			if me.rig:
				me.rig.set_pose(kind, side)
		elif who is RemotePlayer and (who as RemotePlayer)._rig:
			(who as RemotePlayer)._rig.set_pose(kind, side)
	var mine: bool = a == main.me or b == main.me
	if mine:
		_cinema(true)
	match kind:
		"kiss":
			get_tree().create_timer(1.3).timeout.connect(func():
				if seq.get("kind", "") == "kiss":
					Sfx.play("kiss", -2.0)
					Build.burst(main, centre, "hearts")
					Music.swell(3.0, 3.0))
		"hug":
			Build.burst(main, centre, "hearts")
			Music.swell(2.0, 3.0)
		"dance":
			Music.swell(2.0, 6.0)


## Moves my own character into place (the partner's phone does the same for them).
## side_off: sideways step (hug), extra_yaw: turn on top of facing the partner (twirls).
func _place(who: Node3D, centre: Vector3, dir: Vector3, gap: float, first: bool, side_off := 0.0, extra_yaw := 0.0) -> void:
	if not (who is Player):
		return
	var me := who as Player
	var side := dir.cross(Vector3.UP).normalized()
	var target := centre - dir * (gap * 0.5) + side * side_off if first else centre + dir * (gap * 0.5) - side * side_off
	target.y = me.global_position.y
	me.global_position = me.global_position.lerp(target, 0.2)
	var face := dir if first else -dir
	var y := atan2(-face.x, -face.z) + extra_yaw
	me.visual.rotation.y = lerp_angle(me.visual.rotation.y, y, 0.25 if absf(extra_yaw) < 0.01 else 0.5)


func _rig_of(who: Node3D) -> CharRig:
	if who is Player:
		return (who as Player).rig
	if who is RemotePlayer:
		return (who as RemotePlayer)._rig
	return null


func _tick_seq(dt: float) -> void:
	seq["t"] += dt
	var t: float = seq["t"]
	var kind: String = seq["kind"]
	var dir: Vector3 = seq["dir"]
	var c: Vector3 = seq["c"]
	match kind:
		"hug":
			# cheek to cheek, gently rocking side to side
			var rock := sin(t * 1.6) * 0.07
			_place(seq["a"], c, dir, seq["gap"], true, HUG_SIDE)
			_place(seq["b"], c, dir, seq["gap"], false, HUG_SIDE)
			for who in [seq["a"], seq["b"]]:
				var rg := _rig_of(who)
				if rg:
					rg.set_live(0.0, rock, 0.0, 0.0)
			if fmod(t, 2.0) < dt and t > 1.0:
				Build.burst(main, c, "hearts")
		"dance":
			_dance_step(t, dt, dir, c)
		_:
			_place(seq["a"], c, dir, seq["gap"], true)
			_place(seq["b"], c, dir, seq["gap"], false)
	if kind == "kiss" and fmod(t, 1.4) < dt and t > 1.5:
		Build.burst(main, seq["c"], "hearts")
	# cinematic camera: low, from the side, slowly drifting round
	if _cam.current:
		if kind == "dance":
			dir = dir.rotated(Vector3.UP, seq["spin"] * 0.5)
		var side := dir.cross(Vector3.UP).normalized()
		var ang: float = {"kiss": -0.35, "hug": 0.55}.get(kind, -0.35) + t * (0.05 if kind != "dance" else 0.12)
		var r: float = {"kiss": 2.9, "hug": 3.0}.get(kind, 4.2)
		var look := c + Vector3(0, 1.1 if kind == "kiss" else 0.95, 0)
		if not seq.has("camflip"):
			# film from whichever side of the room has more space
			var f1 := _cam_room(look, side * r)
			var f2 := _cam_room(look, -side * r)
			seq["camflip"] = 1.0 if f1 >= f2 else -1.0
		var offs: Vector3 = (side * cos(ang) + dir * sin(ang)) * r * float(seq["camflip"]) + Vector3(0, 0.15, 0)
		var room := _cam_room(look, offs)
		if room < 0.7:
			# a wall in the way: go up and look down at you instead of squeezing in
			var high := offs * 0.8 + Vector3(0, 1.3, 0)
			var room_h := _cam_room(look, high)
			if room_h > room:
				offs = high
				room = room_h
		var want := look + offs * room
		_cam.global_position = _cam.global_position.lerp(want, 0.08)
		_cam.look_at(look, Vector3.UP)
	if t >= float(seq["dur"]):
		_end_seq()


## Slow dance, about 20 s: hold hands and sway, step round in a circle, she twirls twice,
## a little side step, and a dip with a kiss of hearts at the end.
func _dance_step(t: float, dt: float, dir: Vector3, c: Vector3) -> void:
	var beat := t * TAU / 2.4                 # one sway every 2.4 s
	seq["spin"] += dt * (0.32 + 0.1 * sin(t * 0.4))
	var d := dir.rotated(Vector3.UP, seq["spin"])
	var centre := c + d.cross(Vector3.UP).normalized() * sin(t * TAU / 4.8) * 0.12
	var gap: float = seq["gap"]
	# twirls for b at 6 s and 13 s (1.4 s each, one full turn, arm raised)
	var twirl := 0.0
	var raise := 0.0
	for start in [6.0, 13.0]:
		var k: float = (t - start) / 1.4
		if k > 0.0 and k < 1.0:
			twirl = smoothstep(0.0, 1.0, k) * TAU
			raise = sin(k * PI)
	# the dip at the end: he leans in, she leans back
	var dip := smoothstep(16.5, 17.8, t) * (1.0 - smoothstep(19.0, 19.8, t))
	if dip > 0.0:
		gap = lerpf(gap, 0.62, dip)
	_place(seq["a"], centre, d, gap, true)
	_place(seq["b"], centre, d, gap, false, 0.0, twirl)
	var sway := sin(beat) * 0.09
	var ra := _rig_of(seq["a"])
	var rb := _rig_of(seq["b"])
	if ra:
		ra.set_live(0.03 + dip * 0.25, sway, 0.0, 0.0)
	if rb:
		rb.set_live(-dip * 0.4, -sway, raise * 1.6, 0.0)
	for who in [seq["a"], seq["b"]]:
		if who is Player:
			(who as Player).visual.position.y = absf(sin(beat)) * 0.025
	if dip > 0.9 and not seq.get("dipped", false):
		seq["dipped"] = true
		Build.burst(main, centre, "hearts")
		Sfx.play("kiss", -4.0)


var _cam_q := PhysicsShapeQueryParameters3D.new()


## How much of the way from `from` along `offs` the movie camera can go without entering a wall.
func _cam_room(from: Vector3, offs: Vector3) -> float:
	if _cam_q.shape == null:
		var sph := SphereShape3D.new()
		sph.radius = 0.25
		_cam_q.shape = sph
		_cam_q.collision_mask = 1
		_cam_q.exclude = house.camera_ignore
	_cam_q.transform = Transform3D(Basis(), from)
	_cam_q.motion = offs
	var r: Array = get_world_3d().direct_space_state.cast_motion(_cam_q)
	return clampf(float(r[0]) * 0.95, 0.15, 1.0)


func _end_seq() -> void:
	if seq.is_empty():
		return
	for who in [seq["a"], seq["b"]]:
		if not is_instance_valid(who):
			continue
		if who is Player:
			var me := who as Player
			me.frozen = false
			me.anim_hold = ""
			me.visual.rotation.z = 0.0
			me.visual.position.y = 0.0
			if me.rig:
				me.rig.set_pose("")
		elif who is RemotePlayer and (who as RemotePlayer)._rig:
			(who as RemotePlayer)._rig.set_pose("")
	seq = {}
	_cinema(false)


func busy() -> bool:
	return not seq.is_empty()


## Letterbox bars + a hidden HUD while the camera does its slow movie shot.
func _cinema(on_: bool) -> void:
	var ui: Control = main.ui.hud
	if _bars.is_empty():
		for k in 2:
			var r := ColorRect.new()
			r.color = Color(0, 0, 0, 1)
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			r.anchor_right = 1.0
			if k == 1:
				r.anchor_top = 1.0
				r.anchor_bottom = 1.0
			main.ui.root.add_child(r)
			_bars.append(r)
	var h := 64.0 if on_ else 0.0
	for k in 2:
		var r: ColorRect = _bars[k]
		var tw := create_tween()
		if k == 0:
			tw.tween_property(r, "offset_bottom", h, 0.6)
		else:
			tw.tween_property(r, "offset_top", -h, 0.6)
	create_tween().tween_property(ui, "modulate:a", 0.0 if on_ else 1.0, 0.4)
	if on_:
		_cam.global_transform = main.me.cam.global_transform
		_cam.make_current()
	else:
		main.me.cam.make_current()


# ---------- sitting ----------

func seat_near(p: Vector3) -> int:
	for i in seats.size():
		var s: Vector3 = seats[i]["pos"]
		if Vector2(s.x - p.x, s.z - p.z).length() < (1.45 if seats[i].has("swing") else 1.1) and absf(s.y - p.y) < 1.0:
			return i
	return -1


## Both of you on the same sofa: lean into each other (checked every frame).
func _tick_cuddle() -> void:
	var me: Player = main.me
	var partner: Node3D = main._partner()
	var cuddling := false
	if me.sitting and partner != null and not busy():
		var off := partner.global_position - me.global_position
		var anim := ""
		if partner is RemotePlayer:
			anim = (partner as RemotePlayer).anim_name
		elif partner is Player:
			anim = "sit" if (partner as Player).sitting else ""
		if anim == "sit" and Vector2(off.x, off.z).length() < 1.0 and absf(off.y) < 0.3:
			cuddling = true
			# which way is she, from where I'm facing?
			var right := Vector3(cos(me.visual.rotation.y), 0, -sin(me.visual.rotation.y))
			var s := -1.0 if off.dot(right) > 0.0 else 1.0
			if not _cuddle_on:
				if me.rig:
					me.rig.set_pose("cuddle", s)
				var pr := _rig_of(partner)
				if pr:
					pr.set_pose("cuddle", -s)
	if _cuddle_on and not cuddling and not busy():
		if me.rig:
			me.rig.set_pose("")
		if partner:
			var pr := _rig_of(partner)
			if pr:
				pr.set_pose("")
	_cuddle_on = cuddling


var _cuddle_on := false


func sit(me: Player, i: int) -> void:
	var s: Dictionary = seats[i]
	me.set_meta("seat", i)
	if s.has("swing"):
		me.sit_at(house.swing_seat_point(s["swing"]).origin, s["yaw"])
	else:
		me.sit_at(s["pos"] + Vector3(0, float(s["h"]), 0), s["yaw"])


# ---------- 2 February: our anniversary ----------

var _balloons: Array = []


func build_anniversary() -> void:
	var deco := Node3D.new()
	add_child(deco)
	# a two-tier cake with candles on the dining table
	var ty := house.surface_y(15.0, 9.6, 2.0)
	var cake := Node3D.new()
	cake.position = Vector3(15.0, ty, 9.6)
	deco.add_child(cake)
	Build.cyl(cake, 0.27, 0.27, 0.015, Vector3(0, 0.008, 0), Color("#f4f1ec"), 24)
	Build.cyl(cake, 0.22, 0.22, 0.15, Vector3(0, 0.09, 0), Color("#fbe3ea"), 24)
	Build.cyl(cake, 0.225, 0.225, 0.03, Vector3(0, 0.155, 0), Color("#e36f97"), 24)
	Build.cyl(cake, 0.15, 0.15, 0.12, Vector3(0, 0.23, 0), Color("#fff6f0"), 24)
	Build.cyl(cake, 0.155, 0.155, 0.025, Vector3(0, 0.29, 0), Color("#b48ae0"), 24)
	for k in 8:
		var a := k * TAU / 8.0
		Build.ball(cake, 0.022, Vector3(cos(a) * 0.19, 0.175, sin(a) * 0.19), Color("#d1222f"))
	_light_up(cake, cake.position + Vector3(0, 0.5, 0))
	for k in 5:
		var a := k * TAU / 5.0
		var cp := Vector3(cos(a) * 0.08, 0.3, sin(a) * 0.08)
		var c := Build.cyl(cake, 0.008, 0.008, 0.07, cp + Vector3(0, 0.035, 0), Color("#ffd1e0"), 6)
		_light_up(c, cake.position + Vector3(0, 0.5, 0))
		_flame(cake, cp + Vector3(0, 0.085, 0), 0.25)
	# banner over the TV
	var font: Font = Kit.ui_font()
	var label := Label3D.new()
	label.text = "Happy Anniversary 💜"
	label.font = font
	label.font_size = 96
	label.pixel_size = 0.0042
	label.outline_size = 22
	label.modulate = Color("#fff4fa")
	label.outline_modulate = Color("#8e3fb8")
	label.position = Vector3(8.5, 2.35, 8.16)
	deco.add_child(label)
	# bunting under it
	var colors := [Color("#ff7aa8"), Color("#ffd166"), Color("#b388ff"), Color("#7fdbff")]
	for i in 15:
		var t := (i + 0.5) / 15.0
		var p := Vector3(lerpf(5.4, 11.6, t), 2.83 - 0.35 * 4.0 * t * (1.0 - t), 8.13)
		var flag := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.22, 0.26, 0.01)
		flag.mesh = pm
		flag.rotation.z = PI
		flag.position = p - Vector3(0, 0.13, 0)
		flag.material_override = Build.mat(colors[i % colors.size()])
		deco.add_child(flag)
		_light_up(flag, p + Vector3(0, 0, 1.0))
	# balloons by the sofa, gently bobbing
	var bcol := [Color("#ff7aa8"), Color("#b388ff"), Color("#fff1f6"), Color("#ff9ec0"), Color("#9d7bf0"), Color("#ffffff")]
	var spots := [Vector3(6.2, 0, 12.9), Vector3(6.45, 0, 13.15), Vector3(6.0, 0, 13.2), Vector3(9.8, 0, 12.9), Vector3(10.05, 0, 13.2), Vector3(9.6, 0, 13.2)]
	for i in spots.size():
		var b := Node3D.new()
		b.position = spots[i] + Vector3(0, 1.75 + (i % 3) * 0.18, 0)
		deco.add_child(b)
		Build.ball(b, 0.2, Vector3.ZERO, bcol[i], Vector3(1, 1.18, 1))
		Build.cube(b, Vector3(0.006, b.position.y - 0.2, 0.006), Vector3(0, -(b.position.y - 0.2) / 2.0 - 0.2, 0), Color("#dddddd"))
		_light_up(b, b.position)
		_balloons.append([b, b.position, randf() * TAU])
	set_process(true)


func _bob_balloons(dt: float) -> void:
	for b in _balloons:
		b[2] += dt
		(b[0] as Node3D).position = b[1] + Vector3(sin(b[2] * 0.7) * 0.03, sin(b[2] * 1.1) * 0.04, 0)
		(b[0] as Node3D).rotation.z = sin(b[2] * 0.8) * 0.05
