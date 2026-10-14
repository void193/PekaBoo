class_name House
extends Node3D
## A two-storey family house in a fenced garden.
##
## Ground floor (y 0)          Upper floor (y 3.2)
##   z 0-6 : office | entry+stairs | garage      master | bath | (stairwell) | kids room
##   z 6-8 : hallway                              landing
##   z 8-16: living | kitchen | laundry            bedroom | bath | game room
## Garden: front lawn + driveway, side hedge maze, back patio, trampoline, shed, doghouse.

const H := 3.0     # storey height (floor to ceiling)
const F2 := 3.2    # upper floor level
const T := 0.16    # interior wall thickness
const DOOR := 2.25
const LOT := Rect2(-13, -14, 50, 46)  # fenced garden: x -13..37, z -14..32

var hide_spots := []   # {name, cam, yaw, exit}
var bushes: Array[Vector3] = []
const ROOM_CENTRES := {
	"office": Vector3(4.5, 0, 3.0), "entry hall": Vector3(11.5, 0, 3.0), "garage": Vector3(19.5, 0, 5.0),
	"hallway": Vector3(12, 0, 7), "living room": Vector3(5, 0, 12), "kitchen": Vector3(15, 0, 11), "laundry": Vector3(21.5, 0, 11),
	"master bedroom": Vector3(4.5, 3.2, 4.0), "bathroom": Vector3(11.2, 3.2, 3.0), "kids room": Vector3(19.5, 3.2, 3.5),
	"landing": Vector3(12, 3.2, 7), "guest bedroom": Vector3(4.5, 3.2, 12), "small bathroom": Vector3(10, 3.2, 12),
	"game room": Vector3(16, 3.2, 12), "front garden": Vector3(5, 0, -8), "back garden": Vector3(20, 0, 26),
	"hedge maze": Vector3(-7.9, 0, 6.5), "shed": Vector3(30, 0, 24)}
var camera_ignore: Array[RID] = []  # hedges: the camera looks over these instead of bumping into them
var props := []        # {name, scale, node}
var lights: Array[Light3D] = []
var light_energy := []
var surfaces := []     # {rect: Rect2, level: int, kind: String}
var tv_pos := Vector3.ZERO
var tv_on := false
var hider_spawns: Array[Vector3] = [Vector3(11, 0.1, 2.5), Vector3(12.5, 0.1, 3.5), Vector3(10.5, 0.1, 4.2), Vector3(12, 0.1, 1.6)]
var seeker_spawn := Vector3(6.5, 0.1, 12.5)

var M := {}
var _level_y := 0.0
var _tv_screen: MeshInstance3D
var _tv_glow: MeshInstance3D
var _tv_off_mat: StandardMaterial3D
const TV_CENTER := Vector3(8.5, 1.14, 8.45)
const TV_SCREEN := Vector2(1.44, 0.81)
var _tv_light: OmniLight3D
var _tv_sound: AudioStreamPlayer3D
var _flicker := 0.0


signal baked

var is_baked := false
var light_data := []  # {pos, color, range} used only by the lighting bake
var bake_ms := 0


const BAKED_PATH := "res://baked/house_visual.scn"
const NIGHT_PATH := "res://baked/house_night.scn"

# ---- chill mode (night) layout: candles, fairy lights, the picnic under the stars ----
const PICNIC := Vector3(12.5, 0, 24.6)        # blanket centre in the back garden
const LIVING_CANDLES := [Vector2(8.15, 10.45), Vector2(8.7, 10.7), Vector2(7.55, 8.45), Vector2(9.45, 8.45)]
const MOON_DIR := Vector3(0.5, -0.62, 0.6)   # direction the moonlight travels

# ---- rooftop deck, the ladder up to it, the garden swing and the wishing well ----
const DECK := Rect2(13.5, 9.2, 5.0, 3.4)      # x, z extent of the rooftop deck
const DECK_Y := 8.75
const LADDER_PATH := [Vector3(16.0, 0.05, 17.6), Vector3(16.0, 0.3, 17.25), Vector3(16.0, 6.45, 17.0), Vector3(16.0, 6.75, 16.45), Vector3(16.0, 8.85, 12.75), Vector3(16.0, DECK_Y + 0.05, 12.2)]
const SWING_POS := Vector3(24.5, 0, 18.2)     # swing frame centre, seat faces +z
const SWING_BAR_Y := 2.35
const WELL_POS := Vector3(8.8, 0, 27.6)
var swing_seat: Node3D                          # the part that swings (moved by chill mode)
var dynamic_lit: Array = []                     # [materials, position] for things lit by probes


## Fairy-light strings: [from, to, sag, bulbs]
static func fairy_strings() -> Array:
	var out := []
	# living room, all round just under the ceiling
	var y := H - 0.28
	var c := [Vector3(0.2, y, 8.2), Vector3(10.8, y, 8.2), Vector3(10.8, y, 15.8), Vector3(0.2, y, 15.8)]
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		out.append([a, b, 0.22, int(a.distance_to(b) / 0.55)])
	# garden: between the two back trees, and from the house to the first tree
	out.append([Vector3(14.0, 2.7, 28.8), Vector3(24.0, 2.7, 28.8), 0.5, 22])
	out.append([Vector3(10.9, 2.95, 16.25), Vector3(13.9, 2.7, 28.7), 0.3, 26])
	out.append([Vector3(4.0, 2.95, 16.25), Vector3(13.9, 2.7, 28.7), 0.35, 30])
	# along the rooftop deck railing
	var ry := DECK_Y + 1.05
	out.append([Vector3(DECK.position.x, ry, DECK.end.y), Vector3(DECK.end.x, ry, DECK.end.y), 0.12, 12])
	out.append([Vector3(DECK.position.x, ry, DECK.position.y), Vector3(DECK.position.x, ry, DECK.end.y), 0.1, 8])
	out.append([Vector3(DECK.end.x, ry, DECK.position.y), Vector3(DECK.end.x, ry, DECK.end.y), 0.1, 8])
	return out


static func string_point(st: Array, t: float) -> Vector3:
	var a: Vector3 = st[0]
	var b: Vector3 = st[1]
	return a.lerp(b, t) - Vector3(0, float(st[2]) * 4.0 * t * (1.0 - t), 0)


## Warm little lights that only exist at night (used by the night bake and by chill mode).
func night_lights() -> Array:
	var out := []
	for c in LIVING_CANDLES:
		var y := surface_y(c.x, c.y, 1.4)
		out.append({"pos": Vector3(c.x, y + 0.2, c.y), "color": Color("#ff9446"), "range": 3.4, "energy": 1.0, "kind": "candle"})
	for k in 4:
		var off := Vector3(1.25 * (1 if k % 2 == 0 else -1), 0, 0.95 * (1 if k < 2 else -1))
		out.append({"pos": PICNIC + off + Vector3(0, 0.3, 0), "color": Color("#ff9d4a"), "range": 3.8, "energy": 1.0, "kind": "lantern"})
	for k in 2:
		out.append({"pos": Vector3(DECK.position.x + 0.35 + k * (DECK.size.x - 0.7), DECK_Y + 0.3, DECK.end.y - 0.35), "color": Color("#ff9d4a"), "range": 3.8, "energy": 1.0, "kind": "lantern"})
	for st in fairy_strings():
		var n := 5 if float(st[2]) < 0.5 else 4
		for i in n:
			var t := (i + 0.5) / n
			out.append({"pos": string_point(st, t) - Vector3(0, 0.08, 0), "color": Color("#ffcf8f"), "range": 2.4, "energy": 0.16, "kind": "fairy"})
	return out


## Height of the top surface under (x, z), searching down from below max_y.
func surface_y(x: float, z: float, max_y: float) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, max_y, z), Vector3(x, -0.5, z), 1)
	var hit := space.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else 0.0
const BAKE_VERSION := 18
var bake_out := false  # set by main when run with --bake-out on the PC


func _ready() -> void:
	seed(4242)  # same "random" details every time, so the pre-baked visuals match
	_materials()
	_ground_floor()
	_upper_floor()
	_stairs()
	_roof()
	_garden()
	_furnish_ground()
	_furnish_upper()
	_hang_photos()
	reload_custom()
	_room_lights()
	randomize()
	_setup_navigation()
	if not bake_out and _load_prebaked():
		relight_dynamic.call_deferred()
		is_baked = true
		baked.emit.call_deferred()
		return
	# physics needs a couple of ticks before ray casts can see the colliders we just made
	await get_tree().physics_frame
	await get_tree().physics_frame
	var made := _merge_static()
	_bake_probes()
	if bake_out:
		_save_prebaked(made)
	is_baked = true
	baked.emit()


const NAV_PATH := "res://baked/nav.res"


## Walkable-area map for the bot (stairs, doorways, garden). Baked on the PC with the lighting.
func _setup_navigation() -> void:
	var nm: NavigationMesh
	if not bake_out and ResourceLoader.exists(NAV_PATH):
		nm = load(NAV_PATH)
	else:
		var t0 := Time.get_ticks_msec()
		nm = NavigationMesh.new()
		nm.cell_size = 0.1
		nm.cell_height = 0.1
		nm.agent_radius = 0.3  # nearly a player's size, so "the bot can get there" means you can too
		nm.agent_height = 1.4
		nm.agent_max_climb = 0.3
		nm.agent_max_slope = 45.0
		nm.region_min_size = 4.0
		nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		nm.geometry_collision_mask = 1
		var src := NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(nm, src, self)
		NavigationServer3D.bake_from_source_geometry_data(nm, src)
		print("house: baked navigation (%d polygons) in %d ms" % [nm.get_polygon_count(), Time.get_ticks_msec() - t0])
		if bake_out:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://baked"))
			ResourceSaver.save(nm, NAV_PATH, ResourceSaver.FLAG_COMPRESS)
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, nm.cell_size)
	NavigationServer3D.map_set_cell_height(map, nm.cell_height)
	var region := NavigationRegion3D.new()
	region.navigation_mesh = nm
	add_child(region)


func _static_meshes() -> Array:
	var out := []
	for mi in Kit.meshes(self):
		if (mi as MeshInstance3D).mesh != null and not mi.has_meta("dynamic"):
			out.append(mi)
	return out


## Uses the lighting baked on the PC (shipped inside the app) instead of baking on the phone.
func _load_prebaked() -> bool:
	if not ResourceLoader.exists(BAKED_PATH):
		return false
	var ps: PackedScene = load(BAKED_PATH)
	var root := ps.instantiate()
	if int(root.get_meta("version", 0)) != BAKE_VERSION:
		root.free()
		return false
	var victims := []
	var batches := _collect_batches(victims)
	for m in victims:
		m.queue_free()
	add_child(root)
	_day_root = root
	if root.has_meta("probes"):
		probes = root.get_meta("probes")
	var missing := 0
	for mi in Kit.meshes(root):
		var key := str(mi.get_meta("bkey", ""))
		if batches.has(key):
			var mat: Material = batches[key]["mat"]
			(mi as MeshInstance3D).material_override = _baked_version(_planar_version(mat as BaseMaterial3D) if mat is BaseMaterial3D and (mat as BaseMaterial3D).uv1_world_triplanar else mat)
		else:
			missing += 1
	if missing > 0:
		print("house: %d baked pieces had no matching material" % missing)
	print("house: loaded pre-baked lighting")
	return true


var _day_root: Node3D
var _night_root: Node3D
var _day_probes := PackedColorArray()
var is_night := false


## Chill mode: swap to the moonlit, candle-lit lighting baked on the PC.
func set_night(on: bool) -> bool:
	if on == is_night:
		return true
	if on:
		if _day_root == null or not ResourceLoader.exists(NIGHT_PATH):
			return false
		if _night_root == null:
			var mats := {}
			for mi in Kit.meshes(_day_root):
				mats[str(mi.get_meta("bkey", ""))] = (mi as MeshInstance3D).material_override
			var ps: PackedScene = load(NIGHT_PATH)
			_night_root = ps.instantiate()
			for mi in Kit.meshes(_night_root):
				(mi as MeshInstance3D).material_override = mats.get(str(mi.get_meta("bkey", "")))
			add_child(_night_root)
		_day_probes = probes
		if _night_root.has_meta("probes"):
			probes = _night_root.get_meta("probes")
		_night_root.visible = true
		_day_root.visible = false
	else:
		_night_root.visible = false
		_day_root.visible = true
		probes = _day_probes
	is_night = on
	relight_dynamic()
	return true


func relight_dynamic() -> void:
	for d in dynamic_lit:
		Kit.set_probe_light(d[0], light_at(d[1]))


func _save_prebaked(made: Array) -> void:
	var root := Node3D.new()
	root.name = "Baked"
	root.set_meta("version", BAKE_VERSION)
	root.set_meta("probes", probes)
	add_child(root)
	for mi in made:
		(mi as Node).reparent(root)
		(mi as Node).owner = root
		(mi as MeshInstance3D).material_override = null
	var ps := PackedScene.new()
	ps.pack(root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://baked"))
	var err := ResourceSaver.save(ps, BAKED_PATH, ResourceSaver.FLAG_COMPRESS)
	print("house: saved pre-baked lighting (%s)" % error_string(err))
	# the moonlit version for chill mode
	var nroot := Node3D.new()
	nroot.name = "BakedNight"
	nroot.set_meta("version", BAKE_VERSION)
	_night = true
	var day_probes := probes.duplicate()
	probes = PackedColorArray()
	_bake_probes()
	nroot.set_meta("probes", probes.duplicate())
	probes = day_probes
	_night = false
	for it in _night_meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = it[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("bkey", it[0])
		nroot.add_child(mi)
		mi.owner = nroot
	var nps := PackedScene.new()
	nps.pack(nroot)
	err = ResourceSaver.save(nps, NIGHT_PATH, ResourceSaver.FLAG_COMPRESS)
	print("house: saved night lighting (%s)" % error_string(err))
	nroot.free()

# ---------- materials ----------

func _tex_mat(tex: String, tint := Color.WHITE, uv := 0.5, rough := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/tex/%s_diff.jpg" % tex)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load("res://assets/tex/%s_nor.jpg" % tex)
	m.normal_scale = 0.8
	m.roughness_texture = load("res://assets/tex/%s_rough.jpg" % tex)
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * uv
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Painted plaster: flat colour with the plaster's bumps from its normal map.
func _paint(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	m.normal_enabled = true
	m.normal_texture = load("res://assets/tex/beige_wall_001_nor.jpg")
	m.normal_scale = 0.6
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.35
	return m


func _flat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _materials() -> void:
	M["wall"] = _paint(Color("#fbf3e8"))
	M["wall_up"] = _paint(Color("#f3efff"))
	M["wall_kids"] = _paint(Color("#ddf1ff"))
	M["brick"] = _tex_mat("brick_wall_001", Color("#ffe9dc"), 0.22)
	M["oak"] = _tex_mat("laminate_floor_02", Color.WHITE, 0.4)
	M["oak2"] = _tex_mat("laminate_floor_03", Color.WHITE, 0.4)
	M["parquet"] = _tex_mat("herringbone_parquet", Color.WHITE, 0.5)
	M["tiles"] = _tex_mat("floor_tiles_06", Color.WHITE, 0.5)
	M["marble"] = _tex_mat("marble_01", Color.WHITE, 0.35, 0.6)
	M["carpet"] = _tex_mat("curly_teddy_natural", Color("#ffd3de"), 0.8)
	M["carpet2"] = _tex_mat("curly_teddy_natural", Color("#cfe0ff"), 0.8)
	M["concrete"] = _tex_mat("concrete_floor_painted", Color("#d8d8d8"), 0.3)
	M["grass"] = _tex_mat("leafy_grass", Color("#cfe8a8"), 0.25)
	M["patio"] = _tex_mat("patio_tiles", Color.WHITE, 0.4)
	M["roof"] = _tex_mat("grey_roof_tiles", Color("#c87a64"), 0.35)
	M["ceiling"] = _flat(Color("#fbf8f3"), 0.95)
	M["trim"] = _flat(Color("#ffffff"), 0.6)
	M["wood"] = _flat(Color("#9b6a43"), 0.7)
	M["dark"] = _flat(Color("#4b3a33"), 0.7)
	M["hedge"] = _tex_mat("leafy_grass", Color("#8fd06a"), 0.45)
	M["leaf"] = _flat(Color("#5aa548"), 0.9)
	M["leaf2"] = _flat(Color("#73b84f"), 0.9)
	M["bark"] = _flat(Color("#7a5236"), 0.9)
	M["fence"] = _flat(Color("#fffaf2"), 0.7)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.9, 1.0, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.3
	M["glass"] = glass
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.3, 0.75, 0.95, 0.75)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.05
	M["water"] = water
	var curtain := _flat(Color("#e8a0b4"), 1.0)
	M["curtain"] = curtain


# ---------- building blocks ----------

func _box(size: Vector3, pos: Vector3, mat: Material, collide := true, shadow := true) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	b.subdivide_width = clampi(int(size.x / 0.9), 0, 50)
	b.subdivide_height = clampi(int(size.y / 0.9), 0, 6)
	b.subdivide_depth = clampi(int(size.z / 0.9), 0, 50)
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if collide:
		Build.collider(self, size, pos).set_meta("wall", true)
	return mi


## Axis-aligned wall from a to b (x,z) at floor level y0, height h.
## openings: [[t0, t1, kind]] with t measured along the wall; kind = door | wide | window | garage | high
func _wall(a: Vector2, b: Vector2, y0: float, h: float, openings: Array, mat: Material, thick := T, lining: Material = null, lining_side := 0.0) -> void:
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var length := (b.x - a.x) if along_x else (b.y - a.y)
	var cur := 0.0
	openings.sort_custom(func(p, q): return p[0] < q[0])
	for o in openings:
		var t0: float = o[0] - (a.x if along_x else a.y)
		var t1: float = o[1] - (a.x if along_x else a.y)
		var kind: String = o[2]
		_wall_piece(a, along_x, cur, t0, y0, y0 + h, mat, thick, lining, lining_side)
		var top := y0 + DOOR
		match kind:
			"wide":
				top = y0 + 2.5
			"garage":
				top = y0 + 2.6
			"window", "high":
				var sill := y0 + (0.95 if kind == "window" else 1.4)
				top = y0 + 2.2
				_wall_piece(a, along_x, t0, t1, y0, sill, mat, thick, lining, lining_side)
				_window(a, along_x, t0, t1, sill, top, thick)
		_wall_piece(a, along_x, t0, t1, top, y0 + h, mat, thick, lining, lining_side)
		if kind in ["door", "wide"]:
			_door_frame(a, along_x, t0, t1, y0, top, thick)
		cur = t1
	_wall_piece(a, along_x, cur, length, y0, y0 + h, mat, thick, lining, lining_side)


func _wall_piece(a: Vector2, along_x: bool, t0: float, t1: float, y0: float, y1: float, mat: Material, thick: float, lining: Material, lining_side: float) -> void:
	if t1 - t0 < 0.01 or y1 - y0 < 0.01:
		return
	var mid := (t0 + t1) / 2.0
	var pos := Vector3(a.x + mid, (y0 + y1) / 2.0, a.y) if along_x else Vector3(a.x, (y0 + y1) / 2.0, a.y + mid)
	var size := Vector3(t1 - t0, y1 - y0, thick) if along_x else Vector3(thick, y1 - y0, t1 - t0)
	_box(size, pos, mat)
	if lining != null:
		var off := Vector3(0, 0, lining_side * (thick / 2.0 + 0.011)) if along_x else Vector3(lining_side * (thick / 2.0 + 0.011), 0, 0)
		var lsize := Vector3(size.x, size.y, 0.02) if along_x else Vector3(0.02, size.y, size.z)
		_box(lsize, pos + off, lining, false, false)


func _window(a: Vector2, along_x: bool, t0: float, t1: float, y0: float, y1: float, thick: float) -> void:
	var mid := (t0 + t1) / 2.0
	var pos := Vector3(a.x + mid, (y0 + y1) / 2.0, a.y) if along_x else Vector3(a.x, (y0 + y1) / 2.0, a.y + mid)
	var w := t1 - t0
	var hgt := y1 - y0
	var pane := Vector3(w, hgt, 0.03) if along_x else Vector3(0.03, hgt, w)
	_box(pane, pos, M["glass"], true, false)
	var bar_h := Vector3(w + 0.1, 0.08, thick + 0.06) if along_x else Vector3(thick + 0.06, 0.08, w + 0.1)
	_box(bar_h, Vector3(pos.x, y0, pos.z), M["trim"], false)
	_box(bar_h, Vector3(pos.x, y1, pos.z), M["trim"], false)
	var bar_v := Vector3(0.07, hgt, thick + 0.06) if along_x else Vector3(thick + 0.06, hgt, 0.07)
	for s in [-0.5, 0.0, 0.5]:
		var off := Vector3(w * s, 0, 0) if along_x else Vector3(0, 0, w * s)
		_box(bar_v, pos + off, M["trim"], false)


func _door_frame(a: Vector2, along_x: bool, t0: float, t1: float, y0: float, top: float, thick: float) -> void:
	for t in [t0, t1]:
		var pos := Vector3(a.x + t, (y0 + top) / 2.0, a.y) if along_x else Vector3(a.x, (y0 + top) / 2.0, a.y + t)
		var size := Vector3(0.08, top - y0, thick + 0.05) if along_x else Vector3(thick + 0.05, top - y0, 0.08)
		_box(size, pos, M["trim"], false)
	var mid := (t0 + t1) / 2.0
	var tpos := Vector3(a.x + mid, top, a.y) if along_x else Vector3(a.x, top, a.y + mid)
	var tsize := Vector3(t1 - t0 + 0.16, 0.08, thick + 0.05) if along_x else Vector3(thick + 0.05, 0.08, t1 - t0 + 0.16)
	_box(tsize, tpos, M["trim"], false)


func _floor(r: Rect2, y: float, mat_name: String, surface: String, level: int, ceiling_below := false) -> void:
	var c := r.get_center()
	_box(Vector3(r.size.x, 0.06, r.size.y), Vector3(c.x, y - 0.03, c.y), M[mat_name], true, false)
	if ceiling_below:
		_box(Vector3(r.size.x, 0.18, r.size.y), Vector3(c.x, y - 0.15, c.y), M["ceiling"], true)
	surfaces.append({"rect": r, "level": level, "kind": surface})


# ---------- structure ----------

func _ground_floor() -> void:
	var rooms := [
		[Rect2(0, 0, 9, 6), "oak2", "wood"], [Rect2(9, 0, 6, 6), "marble", "tile"], [Rect2(15, 0, 9, 6), "concrete", "concrete"],
		[Rect2(0, 6, 24, 2), "oak", "wood"], [Rect2(0, 8, 11, 8), "parquet", "wood"], [Rect2(11, 8, 8, 8), "tiles", "tile"],
		[Rect2(19, 8, 5, 8), "tiles", "tile"],
	]
	for r in rooms:
		_floor(r[0], 0.0, r[1], r[2], 0)
	# exterior walls: brick outside, plaster inside, tall enough to hide the slab edge
	var eh := F2
	_wall(Vector2(0, 0), Vector2(24, 0), 0, eh, [[2, 4, "window"], [5.5, 7.5, "window"], [11.4, 12.6, "door"], [16.5, 22.5, "garage"]], M["brick"], 0.24, M["wall"], 1)
	_wall(Vector2(0, 16), Vector2(24, 16), 0, eh, [[3, 6, "wide"], [7.5, 9.5, "window"], [13, 15, "high"], [16.5, 18, "high"], [21, 22.5, "window"]], M["brick"], 0.24, M["wall"], -1)
	_wall(Vector2(0, 0), Vector2(0, 16), 0, eh, [[2, 4, "window"], [10, 13, "window"]], M["brick"], 0.24, M["wall"], 1)
	_wall(Vector2(24, 0), Vector2(24, 16), 0, eh, [[3, 4.2, "door"], [10.5, 12, "window"]], M["brick"], 0.24, M["wall"], -1)
	# interior walls
	_wall(Vector2(0, 6), Vector2(24, 6), 0, H, [[6.5, 7.7, "door"], [9.5, 13.3, "wide"], [19, 20.2, "door"]], M["wall"])
	_wall(Vector2(9, 0), Vector2(9, 6), 0, H, [], M["wall"])
	_wall(Vector2(15, 0), Vector2(15, 6), 0, H, [], M["wall"])
	_wall(Vector2(0, 8), Vector2(24, 8), 0, H, [[2, 6, "wide"], [13, 16, "wide"], [20.5, 21.7, "door"]], M["wall"])
	_wall(Vector2(11, 8), Vector2(11, 16), 0, H, [[11, 14, "wide"]], M["wall"])
	_wall(Vector2(19, 8), Vector2(19, 16), 0, H, [[13, 14.2, "door"]], M["wall"])


func _upper_floor() -> void:
	var y := F2
	var rooms := [
		[Rect2(0, 0, 9, 6), "carpet", "carpet"], [Rect2(9, 0, 4.5, 6), "marble", "tile"], [Rect2(13.5, 0, 1.5, 0.6), "oak", "wood"],
		[Rect2(15, 0, 9, 6), "oak", "wood"], [Rect2(0, 6, 24, 2), "oak", "wood"], [Rect2(0, 8, 8, 8), "carpet2", "carpet"],
		[Rect2(8, 8, 4, 8), "marble", "tile"], [Rect2(12, 8, 12, 8), "parquet", "wood"],
	]
	for r in rooms:
		_floor(r[0], y, r[1], r[2], 1, true)
	var eh := H + 0.15
	_wall(Vector2(0, 0), Vector2(24, 0), y, eh, [[2, 4, "window"], [5.5, 7.5, "window"], [10.5, 12, "high"], [13.8, 14.7, "high"], [17, 19, "window"], [20.5, 22.5, "window"]], M["brick"], 0.24, M["wall_up"], 1)
	_wall(Vector2(0, 16), Vector2(24, 16), y, eh, [[2, 4, "window"], [5, 7, "window"], [9.5, 10.5, "high"], [14, 17, "window"], [19, 22, "window"]], M["brick"], 0.24, M["wall_up"], -1)
	_wall(Vector2(0, 0), Vector2(0, 16), y, eh, [[2, 4, "window"], [10, 13, "window"]], M["brick"], 0.24, M["wall_up"], 1)
	_wall(Vector2(24, 0), Vector2(24, 16), y, eh, [[2, 4, "window"], [10, 13, "window"]], M["brick"], 0.24, M["wall_up"], -1)
	_wall(Vector2(0, 6), Vector2(24, 6), y, H, [[4, 5.2, "door"], [10, 11.2, "door"], [13.3, 15.2, "wide"], [18, 19.2, "door"]], M["wall_up"])
	_wall(Vector2(9, 0), Vector2(9, 6), y, H, [], M["wall_up"])
	_wall(Vector2(13.5, 0), Vector2(13.5, 6), y, H, [], M["wall_up"])
	_wall(Vector2(15, 0), Vector2(15, 6), y, H, [], M["wall_kids"])
	_wall(Vector2(0, 8), Vector2(24, 8), y, H, [[3, 4.2, "door"], [9.4, 10.6, "door"], [15, 17, "wide"]], M["wall_up"])
	_wall(Vector2(8, 8), Vector2(8, 16), y, H, [], M["wall_up"])
	_wall(Vector2(12, 8), Vector2(12, 16), y, H, [], M["wall_up"])
	# top ceiling
	_box(Vector3(24.3, 0.16, 16.3), Vector3(12, F2 + H + 0.08, 8), M["ceiling"])


func _stairs() -> void:
	# 16 steps from the entry hall (z 0.6) up to the landing (z 6)
	var x0 := 13.55
	var x1 := 14.95
	var run := 5.4 / 16.0
	for i in 16:
		var hgt := (i + 1) * 0.2
		var z := 0.6 + run * (i + 0.5)
		_box(Vector3(x1 - x0, hgt, run), Vector3((x0 + x1) / 2.0, hgt / 2.0, z), M["wood"], false)
		_box(Vector3(x1 - x0 + 0.02, 0.03, run + 0.02), Vector3((x0 + x1) / 2.0, hgt + 0.01, z), M["oak"], false, false)
		if hgt > 0.45:
			Build.collider(self, Vector3(x1 - x0, hgt - 0.4, run), Vector3((x0 + x1) / 2.0, (hgt - 0.4) / 2.0, z))
	var length := sqrt(5.4 * 5.4 + F2 * F2)
	var ang := atan2(F2, 5.4)
	var ramp := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(x1 - x0, 0.1, length)
	cs.shape = bs
	ramp.add_child(cs)
	ramp.position = Vector3((x0 + x1) / 2.0, F2 / 2.0 - 0.05, 3.3)
	ramp.rotation.x = -ang
	add_child(ramp)
	# handrail on the open side
	for i in 9:
		var z := 0.9 + i * 0.62
		var yb := (z - 0.6) / 5.4 * F2
		_box(Vector3(0.04, 0.9, 0.04), Vector3(x0 - 0.02, yb + 0.45, z), M["trim"], false)
	var rail := _box(Vector3(0.07, 0.07, length), Vector3(x0 - 0.02, F2 / 2.0 + 0.9, 3.3), M["wood"], false)
	rail.rotation.x = -ang
	# cupboard door under the stairs
	_box(Vector3(0.05, 1.7, 1.2), Vector3(x0 - 0.03, 0.85, 4.9), M["dark"], false)
	Build.ball(self, 0.045, Vector3(x0 - 0.09, 0.9, 4.45), Color("#d8b25a"))
	_spot("the cupboard under the stairs", Vector3(14.25, 0.75, 5.0), PI / 2.0, Vector3(12.9, 0.05, 4.9))


func _roof() -> void:
	var roof := PrismMesh.new()
	roof.size = Vector3(17.6, 2.6, 25.2)
	var mi := MeshInstance3D.new()
	mi.mesh = roof
	mi.material_override = M["roof"]
	mi.position = Vector3(12, F2 + H + 0.16 + 1.3, 8)
	mi.rotation.y = PI / 2.0
	add_child(mi)


# ---------- rooftop deck ----------

func _rooftop() -> void:
	var d := DECK
	var top := DECK_Y
	var wood: Material = M["oak"] if M.has("oak") else M["wood"]
	# deck boards and the frame under them
	_box(Vector3(d.size.x, 0.14, d.size.y), Vector3(d.get_center().x, top - 0.07, d.get_center().y), wood, true, true)
	for px in [d.position.x + 0.15, d.end.x - 0.15]:
		for pz in [d.position.y + 0.15, d.end.y - 0.15]:
			var roof_y := _roof_y(pz)
			var h := top - roof_y + 0.2
			_box(Vector3(0.14, h, 0.14), Vector3(px, top - h / 2.0, pz), M["wood"], false, false)
	# railings (with a gap at the front for the ladder)
	var rail_h := 1.0
	var rails := [[Vector2(d.position.x, d.position.y), Vector2(d.end.x, d.position.y)],
		[Vector2(d.position.x, d.position.y), Vector2(d.position.x, d.end.y)],
		[Vector2(d.end.x, d.position.y), Vector2(d.end.x, d.end.y)],
		[Vector2(d.position.x, d.end.y), Vector2(15.55, d.end.y)],
		[Vector2(16.45, d.end.y), Vector2(d.end.x, d.end.y)]]
	for r in rails:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		var c := (a + b) / 2.0
		var along_x := absf(b.x - a.x) > absf(b.y - a.y)
		var length := a.distance_to(b)
		var sz := Vector3(length, 0.07, 0.07) if along_x else Vector3(0.07, 0.07, length)
		_box(sz, Vector3(c.x, top + rail_h, c.y), M["fence"], false, false)
		_box(sz, Vector3(c.x, top + rail_h * 0.5, c.y), M["fence"], false, false)
		var n := maxi(2, int(length / 0.9) + 1)
		for i in n:
			var p := a.lerp(b, float(i) / (n - 1))
			_box(Vector3(0.06, rail_h, 0.06), Vector3(p.x, top + rail_h / 2.0, p.y), M["fence"], false, false)
		Build.collider(self, Vector3(length, 1.6, 0.2) if along_x else Vector3(0.2, 1.6, length), Vector3(c.x, top + 0.8, c.y))
	# a cushioned bench looking out over the back garden, and a couple of plants
	_level_y = 0.0
	_put("benchCushion", Vector3(16.0, top, 9.75), 0)
	_put("pottedPlant", Vector3(13.9, top, 9.6), 0, {"prop": false})
	_put("pottedPlant", Vector3(18.1, top, 9.6), 0, {"prop": false})
	# the long ladder up the back wall, and a short one along the roof to the deck
	_ladder(LADDER_PATH[1], LADDER_PATH[2])
	_ladder(LADDER_PATH[3], LADDER_PATH[4])
	surfaces.append({"rect": DECK, "level": 1, "kind": "wood"})


## Height of the roof surface at depth z (the roof slopes down both ways from the ridge at z = 8).
func _roof_y(z: float) -> float:
	return F2 + H + 0.16 + 2.6 * (1.0 - absf(z - 8.0) / 8.8)


func _ladder(a: Vector3, b: Vector3) -> void:
	var n := Node3D.new()
	add_child(n)
	var dir := (b - a)
	var length := dir.length()
	var up := dir.normalized()
	var side := Vector3.RIGHT
	var fwd := side.cross(up).normalized()
	var basis := Basis(side, up, fwd)
	for sx in [-0.24, 0.24]:
		var rail := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, length, 0.06)
		rail.mesh = bm
		rail.material_override = M["wood"]
		rail.transform = Transform3D(basis, a + dir / 2.0 + side * sx)
		n.add_child(rail)
	var rungs := int(length / 0.32)
	for i in rungs:
		var rung := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.5, 0.04, 0.05)
		rung.mesh = rm
		rung.material_override = M["wood"]
		rung.transform = Transform3D(basis, a + dir * ((i + 0.5) / rungs))
		n.add_child(rung)


# ---------- garden swing ----------

func _swing() -> void:
	var c := SWING_POS
	var frame := Color("#f2ece4")
	# two A-frames and the top bar
	for sx in [-1.35, 1.35]:
		for sz in [-0.7, 0.7]:
			var leg := MeshInstance3D.new()
			var lm := CylinderMesh.new()
			lm.top_radius = 0.05
			lm.bottom_radius = 0.06
			lm.height = 2.5
			leg.mesh = lm
			leg.material_override = M["fence"]
			leg.position = c + Vector3(sx, SWING_BAR_Y / 2.0, sz * 0.5)
			leg.rotation.x = -sz * 0.29
			add_child(leg)
		Build.collider(self, Vector3(0.2, 2.4, 1.5), c + Vector3(sx, 1.2, 0))
	var bar := MeshInstance3D.new()
	var bmesh := CylinderMesh.new()
	bmesh.top_radius = 0.06
	bmesh.bottom_radius = 0.06
	bmesh.height = 2.9
	bar.mesh = bmesh
	bar.material_override = M["fence"]
	bar.position = c + Vector3(0, SWING_BAR_Y, 0)
	bar.rotation.z = PI / 2.0
	add_child(bar)
	# the seat that swings: ropes + a cushioned bench, hung from the bar
	swing_seat = Node3D.new()
	swing_seat.position = c + Vector3(0, SWING_BAR_Y, 0)
	add_child(swing_seat)
	var parts := Node3D.new()
	swing_seat.add_child(parts)
	Build.cube(parts, Vector3(1.7, 0.08, 0.55), Vector3(0, -1.85, 0), Color("#c98e5d"))
	Build.cube(parts, Vector3(1.7, 0.45, 0.07), Vector3(0, -1.6, -0.26), Color("#c98e5d"))
	Build.cube(parts, Vector3(1.6, 0.07, 0.5), Vector3(0, -1.78, 0.01), Color("#ffb3cf"))
	for rx in [-0.8, 0.8]:
		Build.cube(parts, Vector3(0.025, 1.85, 0.025), Vector3(rx, -0.92, 0.2), Color("#e8dcc4"))
		Build.cube(parts, Vector3(0.025, 1.6, 0.025), Vector3(rx, -0.8, -0.26), Color("#e8dcc4"))
	for mi in Kit.meshes(parts):
		mi.set_meta("dynamic", true)
	dynamic_lit.append([Kit.apply_probe_look(parts, 0.45), c + Vector3(0, 1.0, 0)])


## Where the swing seat is right now (for sitting on it), seat i = 0 / 1.
func swing_seat_point(i: int) -> Transform3D:
	var x := -0.42 if i == 0 else 0.42
	return swing_seat.global_transform * Transform3D(Basis(), Vector3(x, -1.85 - 0.05, 0.02))


# ---------- wishing well ----------

func _well() -> void:
	var c := WELL_POS
	var stone := _tex_mat("brick_wall_001", Color("#b9b2c2"), 0.6)
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.75
	cm.bottom_radius = 0.8
	cm.height = 0.8
	cm.radial_segments = 20
	ring.mesh = cm
	ring.material_override = stone
	ring.position = c + Vector3(0, 0.4, 0)
	add_child(ring)
	var water := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.62
	wm.bottom_radius = 0.62
	wm.height = 0.02
	water.mesh = wm
	water.material_override = M["water"]
	water.position = c + Vector3(0, 0.62, 0)
	add_child(water)
	for sx in [-0.7, 0.7]:
		_box(Vector3(0.1, 1.5, 0.1), c + Vector3(sx, 1.35, 0), M["wood"], false, false)
	var roofm := PrismMesh.new()
	roofm.size = Vector3(1.9, 0.55, 1.2)
	var rf := MeshInstance3D.new()
	rf.mesh = roofm
	rf.material_override = M["roof"]
	rf.position = c + Vector3(0, 2.35, 0)
	add_child(rf)
	_box(Vector3(1.4, 0.06, 0.06), c + Vector3(0, 1.85, 0), M["wood"], false, false)
	Build.cyl(self, 0.12, 0.1, 0.18, c + Vector3(0.2, 1.45, 0), Color("#8a6040"), 10)
	Build.collider(self, Vector3(1.6, 1.0, 1.6), c + Vector3(0, 0.5, 0))


# ---------- garden ----------

func _garden() -> void:
	var lot := LOT
	Build.collider(self, Vector3(lot.size.x + 4, 0.4, lot.size.y + 4), Vector3(lot.get_center().x, -0.2, lot.get_center().y))
	# lawn in tiles so each piece only sees nearby lights
	var tile := 10.0
	var x := lot.position.x
	while x < lot.end.x:
		var z := lot.position.y
		while z < lot.end.y:
			var w := minf(tile, lot.end.x - x)
			var d := minf(tile, lot.end.y - z)
			_box(Vector3(w, 0.04, d), Vector3(x + w / 2.0, -0.045, z + d / 2.0), M["grass"], false, false)
			z += tile
		x += tile
	_paved(Rect2(15.5, -14, 8, 14), "concrete", "concrete")    # driveway
	_paved(Rect2(11, -14, 2, 12), "patio", "concrete")         # front path
	_paved(Rect2(9, -2.4, 6, 2.4), "patio", "concrete")        # porch
	_paved(Rect2(0, 16, 11, 4.5), "patio", "concrete")         # back patio
	# white picket fence around the lot
	var fence_h := 1.1
	for e in [[Vector2(lot.position.x, lot.position.y), Vector2(lot.end.x, lot.position.y)], [Vector2(lot.position.x, lot.end.y), Vector2(lot.end.x, lot.end.y)],
			[Vector2(lot.position.x, lot.position.y), Vector2(lot.position.x, lot.end.y)], [Vector2(lot.end.x, lot.position.y), Vector2(lot.end.x, lot.end.y)]]:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var along_x := absf(b.x - a.x) > 0.1
		var length := a.distance_to(b)
		var c := (a + b) / 2.0
		_box(Vector3(length, 0.08, 0.05) if along_x else Vector3(0.05, 0.08, length), Vector3(c.x, 0.4, c.y), M["fence"], false)
		_box(Vector3(length, 0.08, 0.05) if along_x else Vector3(0.05, 0.08, length), Vector3(c.x, 0.85, c.y), M["fence"], false)
		Build.collider(self, Vector3(length, 3.0, 0.3) if along_x else Vector3(0.3, 3.0, length), Vector3(c.x, 1.5, c.y))
		var n := int(length / 0.35)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var pm := BoxMesh.new()
		pm.size = Vector3(0.09, fence_h, 0.03)
		mm.mesh = pm
		mm.instance_count = n
		for i in n:
			var t := (i + 0.5) / n
			var p := a.lerp(b, t)
			var xf := Transform3D(Basis(), Vector3(p.x, fence_h / 2.0, p.y))
			if not along_x:
				xf.basis = Basis(Vector3.UP, PI / 2.0)
			mm.set_instance_transform(i, xf)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = M["fence"]
		add_child(mmi)
	_hedge_maze()
	_shed()
	# trees
	for p in [Vector2(-6, -9), Vector2(3, -10), Vector2(30, -8), Vector2(32, 6), Vector2(31, 16), Vector2(-9, 27), Vector2(14, 29), Vector2(24, 29), Vector2(5, -5)]:
		_tree(Vector3(p.x, 0, p.y), randf_range(0.85, 1.25))
	# bushes you can crouch inside
	for p in [Vector2(1, -1.2), Vector2(4, -1.2), Vector2(7.5, -1.2), Vector2(16.5, -1.0), Vector2(-1.5, 17.5), Vector2(12.5, 17.2), Vector2(25.5, 2),
			Vector2(25.5, 12), Vector2(34, 22), Vector2(17, 30.5), Vector2(-3, 30), Vector2(8, 30.5), Vector2(28, 30.5), Vector2(34.5, -12)]:
		_bush(Vector3(p.x, 0, p.y))
	_rooftop()
	_swing()
	_well()
	# a loveseat facing the back garden (the chill-mode picnic spot)
	_put("loungeDesignSofa", PICNIC + Vector3(0, 0, -1.6), 0)
	# trampoline
	var tramp := Node3D.new()
	tramp.position = Vector3(20, 0, 23.5)
	add_child(tramp)
	var ring := Build.cyl(tramp, 1.9, 1.9, 0.12, Vector3(0, 0.7, 0), Color("#2f6fd6"), 32)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Build.cyl(tramp, 1.7, 1.7, 0.02, Vector3(0, 0.77, 0), Color("#1e1e26"), 32)
	for i in 6:
		var a := TAU * i / 6.0
		Build.cube(tramp, Vector3(0.08, 0.7, 0.08), Vector3(cos(a) * 1.8, 0.35, sin(a) * 1.8), Color("#9aa4b0"))
	var bouncer := Build.collider(tramp, Vector3(3.4, 0.2, 3.4), Vector3(0, 0.68, 0))
	bouncer.set_meta("bouncy", 11.5)
	bouncer.set_meta("sustain", true)
	surfaces.append({"rect": Rect2(18, 21.5, 4, 4), "level": 0, "kind": "trampoline"})
	# kiddie pool
	var pool := Node3D.new()
	pool.position = Vector3(5, 0, 25)
	add_child(pool)
	Build.cyl(pool, 1.6, 1.6, 0.4, Vector3(0, 0.2, 0), Color("#ff9ac1"), 32)
	var w := Build.cyl(pool, 1.45, 1.45, 0.02, Vector3(0, 0.38, 0), Color.WHITE, 32)
	w.material_override = M["water"]
	Build.collider(pool, Vector3(3.0, 0.4, 3.0), Vector3(0, 0.2, 0))
	# doghouse
	var dog := Node3D.new()
	dog.position = Vector3(-6, 0, 22)
	add_child(dog)
	Build.cube(dog, Vector3(1.6, 1.1, 1.6), Vector3(0, 0.55, 0), Color("#c0623a"))
	var dr := Build.cube(dog, Vector3(1.8, 0.1, 1.2), Vector3(0, 1.32, 0.42), Color("#7c3a22"))
	dr.rotation.x = 0.55
	var dr2 := Build.cube(dog, Vector3(1.8, 0.1, 1.2), Vector3(0, 1.32, -0.42), Color("#7c3a22"))
	dr2.rotation.x = -0.55
	Build.cube(dog, Vector3(0.7, 0.75, 0.05), Vector3(0, 0.38, 0.81), Color("#2a1810"))
	Build.collider(dog, Vector3(1.6, 1.3, 1.6), Vector3(0, 0.65, 0))
	_spot("the doghouse", Vector3(-6, 0.55, 22), PI, Vector3(-6, 0.05, 23.6))
	# outdoor table on the patio
	_put("tableCrossCloth", Vector3(5, 0, 18.3), 0)
	for p in [Vector3(3.6, 0, 18.3), Vector3(6.4, 0, 18.3)]:
		_put("chairCushion", p, 90 if p.x < 5 else -90)
	_put("ph:garden_gnome", Vector3(9.5, 0, 17.0), 200, {"scale": 1.6})
	_put("ph:garden_gnome", Vector3(13.8, 0, -1.6), 160, {"scale": 1.6})
	_put("ph:garden_gnome", Vector3(-4, 0, 30), 30, {"scale": 1.6})
	# mailbox
	Build.cube(self, Vector3(0.1, 1.1, 0.1), Vector3(14, 0.55, -13), Color("#6b4a32"))
	Build.cube(self, Vector3(0.35, 0.3, 0.55), Vector3(14, 1.2, -13), Color("#e8453c"))


func _paved(r: Rect2, mat_name: String, kind: String) -> void:
	var c := r.get_center()
	_box(Vector3(r.size.x, 0.03, r.size.y), Vector3(c.x, -0.01, c.y), M[mat_name], false, false)
	surfaces.append({"rect": r, "level": 0, "kind": kind})


func _tree(p: Vector3, s: float) -> void:
	var t := Node3D.new()
	t.position = p
	t.scale = Vector3.ONE * s
	add_child(t)
	var trunk := Build.cyl(t, 0.22, 0.32, 3.2, Vector3(0, 1.6, 0), Color("#7a5236"), 10)
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for b in [[Vector3(0, 3.8, 0), 1.8], [Vector3(0.9, 3.2, 0.4), 1.2], [Vector3(-0.8, 3.3, -0.5), 1.3], [Vector3(0.2, 4.7, -0.2), 1.2]]:
		var leaf := Build.ball(t, b[1], b[0], Color("#5aa548") if randf() > 0.5 else Color("#6cb34e"))
		leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Build.collider(self, Vector3(0.6, 3, 0.6) * s, p + Vector3(0, 1.5 * s, 0))


func _bush(p: Vector3) -> void:
	bushes.append(p)
	var t := Node3D.new()
	t.position = p
	add_child(t)
	for b in [[Vector3(0, 0.55, 0), 0.85], [Vector3(0.55, 0.45, 0.2), 0.6], [Vector3(-0.5, 0.45, -0.15), 0.65], [Vector3(0.1, 0.4, -0.55), 0.55]]:
		var leaf := Build.ball(t, b[1], b[0], Color("#4f9a3f") if randf() > 0.5 else Color("#62ad49"))
		leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _hedge_maze() -> void:
	# side yard maze, x -12..-1, z -1..15 (2 m grid)
	var rows := [
		"#####.#####",
		"#.....#...#",
		"#.###.#.#.#",
		"#.#...#.#.#",
		"#.#.###.#.#",
		"#...#...#..",
		"###.#.###.#",
		"#...#.....#",
		"#.#####.###",
	]
	# 11 columns x 1.0 m = x -12.4 .. -1.4, so it stays well clear of the house wall at x = 0
	var cw := 1.0
	var cd := 1.75
	var ox := -12.4
	var oz := 0.4
	for r in rows.size():
		for c in rows[r].length():
			if rows[r][c] == "#":
				var pos := Vector3(ox + c * cw + cw / 2.0, 0.9, oz + r * cd + cd / 2.0)
				_box(Vector3(cw, 1.8, cd), pos, M["hedge"], false)
				var hedge := Build.collider(self, Vector3(cw, 1.8, cd), pos)
				hedge.set_meta("wall", true)
				camera_ignore.append(hedge.get_rid())


func _shed() -> void:
	var o := Vector2(27, 21)  # shed spans x 27..33, z 21..27
	var mat := _tex_mat("brick_wall_001", Color("#c9a27a"), 0.5)
	_box(Vector3(6, 0.06, 6), Vector3(o.x + 3, 0.0, o.y + 3), M["concrete"], false, false)
	surfaces.append({"rect": Rect2(o.x, o.y, 6, 6), "level": 0, "kind": "wood"})
	_wall(Vector2(o.x, o.y), Vector2(o.x + 6, o.y), 0, 2.6, [[o.x + 2.4, o.x + 3.6, "door"]], mat, 0.16)
	_wall(Vector2(o.x, o.y + 6), Vector2(o.x + 6, o.y + 6), 0, 2.6, [[o.x + 2, o.x + 4, "window"]], mat, 0.16)
	_wall(Vector2(o.x, o.y), Vector2(o.x, o.y + 6), 0, 2.6, [], mat, 0.16)
	_wall(Vector2(o.x + 6, o.y), Vector2(o.x + 6, o.y + 6), 0, 2.6, [], mat, 0.16)
	var roof := PrismMesh.new()
	roof.size = Vector3(6.8, 1.2, 6.8)
	var mi := MeshInstance3D.new()
	mi.mesh = roof
	mi.material_override = M["roof"]
	mi.position = Vector3(o.x + 3, 2.6 + 0.6, o.y + 3)
	add_child(mi)
	_box(Vector3(6, 0.1, 6), Vector3(o.x + 3, 2.6, o.y + 3), M["wood"], true)
	light_data.append({"pos": Vector3(o.x + 3, 2.2, o.y + 3), "color": Color("#ffd9a0"), "range": 6.0, "energy": 0.9})
	_put("bookcaseOpen", Vector3(o.x + 0.4, 0, o.y + 4.5), 90)
	_put("cardboardBoxClosed", Vector3(o.x + 5.3, 0, o.y + 5.3), 10, {"scale": 2.6})
	_put("cardboardBoxClosed", Vector3(o.x + 4.6, 0, o.y + 5.4), -15, {"scale": 2.6})
	_put("cardboardBoxClosed", Vector3(o.x + 5.3, 0.73, o.y + 5.3), 30, {"scale": 2.6})
	_put("washer", Vector3(o.x + 0.7, 0, o.y + 1.0), 90)
	_put("bookcaseClosedDoors", Vector3(o.x + 5.5, 0, o.y + 2.0), -90, {"scale": 2.6})
	_spot("the shed cabinet", Vector3(o.x + 5.55, 1.4, o.y + 2.0), PI / 2.0, Vector3(o.x + 4.4, 0.05, o.y + 2.0))


# ---------- furniture ----------

## Places a model with collision. rot is in degrees; 0 = front faces +z.
func _put(model_name: String, pos: Vector3, rot := 0.0, opts := {}) -> Node3D:
	var scl: float = opts.get("scale", Kit.SCALE)
	var m := Kit.model(model_name, scl)
	m.position = pos + Vector3(0, _level_y, 0)
	m.rotation.y = deg_to_rad(rot)
	add_child(m)
	var size := Kit.size_of(model_name, scl)
	var col: String = opts.get("col", "box")
	var can_disguise: bool = opts.get("prop", size.y > 0.15 and size.y < 2.4 and maxf(size.x, size.z) < 2.7)
	var bodies := []
	if col == "box":
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(size.x * 0.92, size.y, size.z * 0.92)
		cs.shape = bs
		cs.position.y = size.y / 2.0
		sb.add_child(cs)
		m.add_child(sb)
		bodies.append(sb)
	elif col == "mesh":
		for mi in Kit.meshes(m):
			(mi as MeshInstance3D).create_trimesh_collision()
			for ch in (mi as Node).get_children():
				if ch is StaticBody3D:
					bodies.append(ch)
	if opts.get("bouncy", false):
		for b in bodies:
			b.set_meta("bouncy", 5.2)
	if can_disguise:
		for b in bodies:
			b.set_meta("prop", model_name)
			b.set_meta("pscale", scl)
		props.append({"name": model_name, "scale": scl, "node": m})
	return m


func _spot(spot_name: String, cam: Vector3, yaw: float, exit: Vector3, kind := "hide") -> void:
	hide_spots.append({"name": spot_name, "cam": cam + Vector3(0, _level_y, 0), "yaw": yaw, "exit": exit + Vector3(0, _level_y, 0), "kind": kind})


func _furnish_ground() -> void:
	_level_y = 0.0
	# office
	_put("desk", Vector3(2.5, 0, 0.6), 0)
	_put("computerScreen", Vector3(2.5, 0.8, 0.45), 0, {"col": "none"})
	_put("computerKeyboard", Vector3(2.5, 0.8, 0.85), 0, {"col": "none"})
	_put("chairDesk", Vector3(2.5, 0, 1.7), 180)
	_put("bookcaseOpen", Vector3(0.45, 0, 3.0), 90)
	_put("bookcaseOpen", Vector3(0.45, 0, 3.9), 90)
	_put("books", Vector3(0.5, 0.95, 3.0), 90, {"col": "none"})
	_put("bookcaseClosedDoors", Vector3(8.4, 0, 4.4), -90, {"scale": 2.6})
	_spot("the office closet", Vector3(8.45, 1.4, 4.4), PI / 2.0, Vector3(7.2, 0.05, 4.4))
	_put("loungeChair", Vector3(6.2, 0, 1.3), 0)
	_put("lampRoundFloor", Vector3(7.6, 0, 0.6), 0)
	_put("rugRectangle", Vector3(4.6, 0, 3.6), 0, {"col": "none", "scale": 2.6})
	_put("pottedPlant", Vector3(0.6, 0, 5.4), 0)
	_put("cardboardBoxClosed", Vector3(2.4, 0, 5.45), 20, {"scale": 2.6})
	_put("cardboardBoxOpen", Vector3(3.4, 0, 5.45), -10, {"scale": 2.6})
	# entry
	_put("coatRackStanding", Vector3(9.7, 0, 0.7), 0)
	_put("rugDoormat", Vector3(12, 0, 0.6), 0, {"col": "none", "scale": 3.0})
	_put("bench", Vector3(9.6, 0, 3.0), 90)
	_put("pottedPlant", Vector3(9.6, 0, 5.4), 0)
	_put("lampSquareFloor", Vector3(13.1, 0, 0.4), 0)
	# garage
	_put("ph:covered_car", Vector3(19.5, 0, 2.8), 90, {"scale": 1.0, "prop": false})
	_spot("under the car cover", Vector3(19.5, 0.6, 2.8), 0.0, Vector3(19.5, 0.05, 5.0))
	for p in [Vector3(15.6, 0, 0.6), Vector3(16.3, 0, 0.6), Vector3(15.6, 0, 1.3), Vector3(15.6, 0.73, 0.6)]:
		_put("cardboardBoxClosed", p, randf_range(-20, 20), {"scale": 2.6})
	_put("bookcaseOpen", Vector3(23.5, 0, 4.6), -90)
	_put("trashcan", Vector3(23.5, 0, 5.5), 0)
	_put("washerDryerStacked", Vector3(23.5, 0, 0.6), -90)
	# hallway
	_put("pottedPlant", Vector3(0.5, 0, 7.0), 0)
	_put("pottedPlant", Vector3(23.5, 0, 7.0), 0)
	_put("sideTable", Vector3(4.2, 0, 6.35), 0)
	_put("lampRoundTable", Vector3(4.2, 0.8, 6.35), 0, {"col": "none"})
	_put("coatRack", Vector3(17.0, 1.6, 6.15), 0, {"col": "none"})
	# living room
	_put("rugRounded", Vector3(7.5, 0, 11.6), 0, {"col": "none", "scale": 3.4})
	_put("cabinetTelevision", Vector3(8.5, 0, 8.45), 0)
	tv_pos = Vector3(8.5, 0, 9.5)
	_build_tv()
	_setup_tv_video()
	_tv_light = OmniLight3D.new()
	_tv_light.light_color = Color("#9fd0ff")
	_tv_light.light_energy = 0.0
	_tv_light.omni_range = 6.0
	_tv_light.position = Vector3(8.5, 1.2, 9.4)
	add_child(_tv_light)
	_put("loungeSofaLong", Vector3(8.0, 0, 12.6), 180, {"scale": 2.3})
	_put("tableCoffeeGlass", Vector3(8.4, 0, 10.6), 0)
	_put("loungeChairRelax", Vector3(4.6, 0, 10.6), 90)
	_put("bookcaseClosedWide", Vector3(0.45, 0, 8.9), 90)
	_put("pottedPlant", Vector3(0.6, 0, 15.4), 0)
	_put("pottedPlant", Vector3(10.4, 0, 15.4), 0)
	_put("lampSquareFloor", Vector3(10.5, 0, 8.6), 0)
	_put("speaker", Vector3(6.9, 0, 8.4), 0)
	_put("speaker", Vector3(10.1, 0, 8.4), 0)
	_put("bear", Vector3(1.0, 0, 13.8), 120, {"scale": 2.4})
	_put("pillowBlue", Vector3(7.0, 0.55, 12.7), 0, {"col": "none"})
	_put("pillow", Vector3(9.0, 0.55, 12.7), 0, {"col": "none"})
	# curtains by the patio doors
	for cx in [2.7, 6.3]:
		_box(Vector3(0.6, 2.5, 0.12), Vector3(cx, 1.3, 15.75), M["curtain"], true)
	_box(Vector3(4.4, 0.06, 0.06), Vector3(4.5, 2.6, 15.75), M["dark"], false)
	_spot("behind the curtains", Vector3(2.7, 1.35, 15.86), PI, Vector3(2.7, 0.05, 14.8))
	# kitchen
	for i in 6:
		var kind: String = ["kitchenCabinet", "kitchenCabinetDrawer", "kitchenSink", "kitchenCabinet", "kitchenStove", "kitchenCabinetDrawer"][i]
		_put(kind, Vector3(11.6 + i * 0.92, 0, 15.5), 180)
	_put("kitchenMicrowave", Vector3(14.4, 0.95, 15.6), 180, {"col": "none"})
	_put("kitchenCoffeeMachine", Vector3(12.0, 0.95, 15.6), 180, {"col": "none"})
	_put("toaster", Vector3(16.1, 0.95, 15.6), 180, {"col": "none"})
	_put("hoodModern", Vector3(15.3, 1.9, 15.55), 180, {"col": "none"})
	_put("kitchenFridgeLarge", Vector3(18.3, 0, 15.45), 180)
	_spot("the fridge", Vector3(18.3, 1.3, 15.45), 0.0, Vector3(18.3, 0.05, 14.2))
	for i in 3:
		_put("kitchenBar", Vector3(13.6 + i * 0.92, 0, 12.6), 0)
		_put("stoolBar", Vector3(13.6 + i * 0.92, 0, 11.7), 0)
	_put("tableCloth", Vector3(15.0, 0, 9.6), 0)
	for p in [[Vector3(13.9, 0, 9.6), 90], [Vector3(16.1, 0, 9.6), -90], [Vector3(15.0, 0, 8.7), 0]]:
		_put("chairCushion", p[0], p[1])
	_put("trashcan", Vector3(11.5, 0, 8.6), 0)
	_put("plantSmall2", Vector3(15.0, 0.7, 9.6), 0, {"col": "none"})
	# laundry
	_put("washer", Vector3(19.7, 0, 15.45), 180)
	_spot("the washing machine", Vector3(19.7, 0.5, 15.45), 0.0, Vector3(19.7, 0.05, 14.3))
	_put("dryer", Vector3(20.6, 0, 15.45), 180)
	_put("washerDryerStacked", Vector3(21.5, 0, 15.45), 180)
	_put("bathroomSinkSquare", Vector3(23.5, 0, 9.5), -90)
	_put("toiletSquare", Vector3(23.4, 0, 13.0), -90)
	_put("cardboardBoxOpen", Vector3(19.7, 0, 8.6), 0, {"scale": 2.6})
	_put("trashcan", Vector3(23.5, 0, 14.4), 0)


func _furnish_upper() -> void:
	_level_y = F2
	# master bedroom
	_put("bedDouble", Vector3(4.5, 0, 1.3), 0, {"bouncy": true})
	_spot("under the big bed", Vector3(4.5, 0.25, 1.6), PI, Vector3(4.5, 0.05, 3.2))
	_put("cabinetBedDrawerTable", Vector3(2.95, 0, 0.3), 0)
	_put("cabinetBedDrawerTable", Vector3(6.05, 0, 0.3), 0)
	_put("lampRoundTable", Vector3(2.95, 0.55, 0.3), 0, {"col": "none"})
	_put("lampRoundTable", Vector3(6.05, 0.55, 0.3), 0, {"col": "none"})
	_put("bookcaseClosedDoors", Vector3(8.4, 0, 2.2), -90, {"scale": 2.6})
	_spot("the bedroom wardrobe", Vector3(8.45, 1.4, 2.2), PI / 2.0, Vector3(7.2, 0.05, 2.2))
	_put("rugRound", Vector3(4.5, 0, 4.2), 0, {"col": "none", "scale": 2.6})
	_put("loungeChairRelax", Vector3(1.2, 0, 4.8), 90)
	_put("pottedPlant", Vector3(0.5, 0, 5.5), 0)
	_put("pillowLong", Vector3(4.5, 0.85, 0.5), 0, {"col": "none"})
	# bathroom
	_put("bathtub", Vector3(11.25, 0, 0.75), 0)
	_spot("the bathtub", Vector3(11.25, 0.45, 0.75), PI, Vector3(11.25, 0.05, 2.2))
	_put("shower", Vector3(12.8, 0, 5.3), 180)
	_spot("the shower", Vector3(12.8, 1.4, 5.3), PI / 2.0, Vector3(11.5, 0.05, 5.0))
	_put("toilet", Vector3(9.45, 0, 2.6), 90)
	_put("bathroomSinkSquare", Vector3(9.45, 0, 4.2), 90)
	_put("bathroomMirror", Vector3(9.12, 1.2, 4.2), 90, {"col": "none"})
	_put("trashcan", Vector3(9.4, 0, 5.5), 0)
	# kids room
	_put("bedBunk", Vector3(22.8, 0, 1.3), 0, {"bouncy": true})
	_spot("the top bunk", Vector3(22.8, 1.75, 1.3), PI, Vector3(22.8, 0.05, 3.1))
	_put("cardboardBoxOpen", Vector3(16.2, 0, 0.9), 0, {"scale": 3.6})
	_spot("the toy box", Vector3(16.2, 0.55, 0.9), PI, Vector3(16.2, 0.05, 2.3))
	_put("bear", Vector3(17.6, 0, 5.4), 160, {"scale": 3.0})
	_put("bear", Vector3(20.2, 0, 0.5), 10, {"scale": 2.2})
	_put("bear", Vector3(23.4, 0, 5.3), -120, {"scale": 2.6})
	_put("desk", Vector3(19.2, 0, 0.55), 0)
	_put("chairRounded", Vector3(19.2, 0, 1.6), 180)
	_put("laptop", Vector3(19.2, 0.8, 0.5), 0, {"col": "none"})
	_put("rugRound", Vector3(19.5, 0, 3.6), 0, {"col": "none", "scale": 3.0})
	_put("bookcaseOpenLow", Vector3(15.4, 0, 3.6), 90)
	# landing
	_put("pottedPlant", Vector3(0.5, 0, 7.0), 0)
	_put("bookcaseOpenLow", Vector3(7.0, 0, 6.3), 0)
	_put("pottedPlant", Vector3(23.5, 0, 7.0), 0)
	# second bedroom
	_put("bedSingle", Vector3(1.4, 0, 14.6), 180, {"bouncy": true})
	_put("cabinetBed", Vector3(2.6, 0, 15.6), 180)
	_put("lampSquareTable", Vector3(2.6, 0.48, 15.6), 0, {"col": "none"})
	_put("bookcaseClosedDoors", Vector3(7.4, 0, 14.4), -90, {"scale": 2.6})
	_spot("the guest wardrobe", Vector3(7.45, 1.4, 14.4), PI / 2.0, Vector3(6.2, 0.05, 14.4))
	_put("deskCorner", Vector3(1.1, 0, 9.1), 90)
	_put("chairDesk", Vector3(2.2, 0, 9.8), -90)
	_put("rugSquare", Vector3(4.2, 0, 12), 0, {"col": "none", "scale": 3.0})
	_put("pottedPlant", Vector3(7.5, 0, 8.6), 0)
	# second bathroom
	_put("toiletSquare", Vector3(11.4, 0, 15.4), 180)
	_put("bathroomSink", Vector3(8.6, 0, 15.5), 180)
	_put("showerRound", Vector3(11.3, 0, 9.2), 180)
	_spot("the little shower", Vector3(11.3, 1.4, 9.2), -PI / 2.0, Vector3(9.9, 0.05, 9.6))
	# game room with a ball pit
	_put("cabinetTelevisionDoors", Vector3(12.45, 0, 12), 90)
	_put("televisionVintage", Vector3(12.45, 0.65, 12), 90, {"col": "none"})
	_put("loungeSofa", Vector3(15.6, 0, 12), -90)
	_put("tableCoffeeSquare", Vector3(14.1, 0, 12), 0)
	_put("tableRound", Vector3(18.0, 0, 9.6), 0)
	_put("chairModernCushion", Vector3(17.1, 0, 9.6), 90)
	_put("chairModernCushion", Vector3(18.9, 0, 9.6), -90)
	_put("speakerSmall", Vector3(12.4, 0, 14.0), 90)
	_put("radio", Vector3(18.0, 0.78, 9.6), 0, {"col": "none"})
	_put("bookcaseOpen", Vector3(23.5, 0, 9.0), -90)
	_ball_pit(Rect2(19.5, 12, 4.2, 3.7))


func _ball_pit(r: Rect2) -> void:
	var y := _level_y
	var c := r.get_center()
	var wall_h := 0.6
	for e in [[Vector3(r.size.x, wall_h, 0.12), Vector3(c.x, y + wall_h / 2.0, r.position.y)], [Vector3(r.size.x, wall_h, 0.12), Vector3(c.x, y + wall_h / 2.0, r.end.y)],
			[Vector3(0.12, wall_h, r.size.y), Vector3(r.position.x, y + wall_h / 2.0, c.y)], [Vector3(0.12, wall_h, r.size.y), Vector3(r.end.x, y + wall_h / 2.0, c.y)]]:
		var mi := _box(e[0], e[1], _flat(Color("#ff5c8a"), 0.6), true)
		mi.name = "pit"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 6
	sm.rings = 3
	mm.mesh = sm
	mm.instance_count = 420
	var cols := [Color("#ff5c8a"), Color("#4f8dff"), Color("#ffc23d"), Color("#2fc77a"), Color("#a36bff")]
	for i in mm.instance_count:
		var p := Vector3(randf_range(r.position.x + 0.15, r.end.x - 0.15), y + randf_range(0.08, 0.5), randf_range(r.position.y + 0.15, r.end.y - 0.15))
		mm.set_instance_transform(i, Transform3D(Basis(), p))
		var shade := 0.75 + 0.25 * (p.y - y) / 0.5
		mm.set_instance_color(i, (cols[i % cols.size()] as Color) * shade)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_spot("the ball pit", Vector3(c.x, 0.32, c.y), PI / 2.0, Vector3(r.position.x - 0.7, 0.05, c.y))
	_level_y = y


# ---------- performance: merge everything static ----------

## Combines every static mesh in the house into a few big meshes: one per material per
## 12 m chunk of the map. Phones choke on thousands of small draw calls; this keeps it to a few hundred.
## Groups every static mesh by look + map chunk. Returns {key: {mat, shadow, items}}.
func _collect_batches(victims: Array) -> Dictionary:
	var canon := {}    # material look -> one shared material
	var batches := {}
	for mi in Kit.meshes(self):
		var m := mi as MeshInstance3D
		if m.mesh == null or m.has_meta("dynamic"):
			continue
		var xf := m.global_transform
		var c := Vector3i(floori(xf.origin.x / 8.0), floori(xf.origin.y / 3.0), floori(xf.origin.z / 8.0))
		var shadow := m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for si in m.mesh.get_surface_count():
			var mat := m.get_active_material(si)
			var mk := _mat_key(mat)
			if not canon.has(mk):
				canon[mk] = mat
			var raw: int = (m.mesh as ArrayMesh).surface_get_format(si) if m.mesh is ArrayMesh else (Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_TEX_UV)
			var fmt: int = raw & (Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2)
			var key := "%s|%s|%s|%d" % [_stable_key(mat, mk), c, shadow, fmt]
			if not batches.has(key):
				batches[key] = {"mat": canon[mk], "shadow": shadow, "items": []}
			batches[key]["items"].append([m.mesh, si, xf])
		victims.append(m)
	return batches


var _night_meshes := []


func _merge_static() -> Array:
	var t0 := Time.get_ticks_msec()
	if bake_out:
		_night_extra = night_lights()
	var victims := []
	var made := []
	var batches := _collect_batches(victims)
	for key in batches:
		var b: Dictionary = batches[key]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for it in b["items"]:
			st.append_from(it[0], it[1], it[2])
		var mesh := st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var mat: Material = b["mat"]
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).uv1_world_triplanar:
			mesh = _bake_world_uv(mesh)
		var day_mesh := _bake_light(mesh)
		if bake_out:
			_night = true
			_night_meshes.append([key, _bake_light(mesh), b["shadow"]])
			_night = false
		mesh = day_mesh
		mat = _baked_version(mat)
		var out := MeshInstance3D.new()
		out.mesh = mesh
		out.material_override = mat
		out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if b["shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out.set_meta("bkey", key)
		add_child(out)
		made.append(out)
	for m in victims:
		m.queue_free()
	bake_ms = Time.get_ticks_msec() - t0
	print("house: merged %d meshes into %d, baked %d vertices in %d ms" % [victims.size(), batches.size(), _baked_verts, bake_ms])
	return made


## Triplanar mapping samples every texture three times per pixel. For flat boxes we can
## work out the same world-space UVs once, per vertex, and use plain UV mapping instead.
static func _bake_world_uv(mesh: ArrayMesh) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	for i in verts.size():
		var v := verts[i]
		var n := norms[i].abs()
		if n.y >= n.x and n.y >= n.z:
			uvs[i] = Vector2(v.x, v.z)
		elif n.x >= n.z:
			uvs[i] = Vector2(v.z, -v.y)
		else:
			uvs[i] = Vector2(v.x, -v.y)
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	st.create_from(tmp, 0)
	st.generate_tangents()
	return st.commit()


const SUN_DIR := Vector3(-0.42, -0.74, -0.52)  # direction the sunlight travels
var _baked_verts := 0
var _space: PhysicsDirectSpaceState3D
var _ray := PhysicsRayQueryParameters3D.new()


func _blocked(a: Vector3, b: Vector3) -> bool:
	_ray.from = a
	_ray.to = b
	return not _space.intersect_ray(_ray).is_empty()


## Works out how much sky, sun and lamp light reaches each vertex (with shadows, via
## ray casts) and stores it as the vertex colour. The house then draws with no
## real-time lights at all, which is what makes it fast on phones.
## Fixed set of directions spread over a hemisphere (cosine weighted), used for sky light,
## ambient occlusion and bounce light in the bake.
static func _hemi_dirs(n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var golden := PI * (3.0 - sqrt(5.0))
	for i in n:
		var r := sqrt((i + 0.5) / n)
		var a := golden * i
		out.append(Vector3(r * cos(a), sqrt(maxf(0.0, 1.0 - r * r)), r * sin(a)))
	return out


const SKY_RAYS := 14
var _hemi: Array[Vector3] = []


## Light arriving at point p (facing n): sky through openings, bounce off nearby surfaces,
## sun with shadows and the room lamps with shadows.
func _light_at(p: Vector3, n: Vector3) -> Color:
	if _night:
		return _night_light_at(p, n)
	if _hemi.is_empty():
		_hemi = _hemi_dirs(SKY_RAYS)
	# build a frame around the normal
	var t := Vector3.UP.cross(n)
	if t.length() < 0.01:
		t = Vector3.RIGHT.cross(n)
	t = t.normalized()
	var bt := n.cross(t)
	var sky := Color(0, 0, 0)
	var bounce := 0.0
	for d in _hemi:
		var dir: Vector3 = (t * d.x + n * d.y + bt * d.z).normalized()
		_ray.from = p
		_ray.to = p + dir * 9.0
		var hit := _space.intersect_ray(_ray)
		if hit.is_empty():
			# brighter overhead, warmer near the horizon
			var up := clampf(dir.y, 0.0, 1.0)
			sky += Color(0.78, 0.8, 0.84).lerp(Color(0.62, 0.72, 0.92), up) * (0.75 + 0.5 * up)
		else:
			var dist := p.distance_to(hit["position"])
			bounce += clampf(dist / 1.2, 0.2, 1.0)
	var c := sky * (1.0 / SKY_RAYS) * 0.95
	# light bouncing off walls, floors and furniture (warm), weaker in tight corners
	c += Color(0.5, 0.44, 0.38) * (bounce / SKY_RAYS) * 0.62
	var sun := -SUN_DIR.normalized()
	var ndl := n.dot(sun)
	if ndl > 0.0:
		_ray.from = p
		_ray.to = p + sun * 60.0
		if _space.intersect_ray(_ray).is_empty():
			c += Color(1.0, 0.9, 0.76) * (ndl * 0.95)
	for l in light_data:
		var lp: Vector3 = l["pos"]
		var dl := p.distance_to(lp)
		var rng: float = l["range"]
		if dl >= rng:
			continue
		var to := (lp - p) / maxf(dl, 0.001)
		var lambert := maxf(0.0, n.dot(to)) * 0.85 + 0.15
		var att := pow(1.0 - dl / rng, 1.7)
		if att * lambert < 0.02:
			continue
		_ray.from = p
		_ray.to = lp - to * 0.3
		if not _space.intersect_ray(_ray).is_empty():
			continue
		c += (l["color"] as Color) * (l["energy"] as float) * 0.72 * att * lambert
	return c


var _night := false
var _night_extra := []


## Moonlit night: deep blue sky light, a soft cool moon with shadows, the room lamps turned
## low and warm, and candles / lanterns / fairy lights (all with shadows).
func _night_light_at(p: Vector3, n: Vector3) -> Color:
	if _hemi.is_empty():
		_hemi = _hemi_dirs(SKY_RAYS)
	var t := Vector3.UP.cross(n)
	if t.length() < 0.01:
		t = Vector3.RIGHT.cross(n)
	t = t.normalized()
	var bt := n.cross(t)
	var sky := Color(0, 0, 0)
	var bounce := 0.0
	for d in _hemi:
		var dir: Vector3 = (t * d.x + n * d.y + bt * d.z).normalized()
		_ray.from = p
		_ray.to = p + dir * 9.0
		var hit := _space.intersect_ray(_ray)
		if hit.is_empty():
			var up := clampf(dir.y, 0.0, 1.0)
			sky += Color(0.24, 0.2, 0.42).lerp(Color(0.15, 0.18, 0.4), up)
		else:
			bounce += clampf(p.distance_to(hit["position"]) / 1.2, 0.2, 1.0)
	var c := sky * (1.0 / SKY_RAYS)
	c += Color(0.19, 0.16, 0.17) * (bounce / SKY_RAYS)
	var moon := -MOON_DIR.normalized()
	var ndl := n.dot(moon)
	if ndl > 0.0:
		_ray.from = p
		_ray.to = p + moon * 60.0
		if _space.intersect_ray(_ray).is_empty():
			c += Color(0.42, 0.5, 0.92) * (ndl * 0.46)
	var lights: Array = []
	for l in light_data:
		lights.append({"pos": l["pos"], "color": Color("#ffb070"), "range": l["range"], "energy": 0.32})
	lights.append_array(_night_extra)
	for l in lights:
		var lp: Vector3 = l["pos"]
		var dl := p.distance_to(lp)
		var rng: float = l["range"]
		if dl >= rng:
			continue
		var to := (lp - p) / maxf(dl, 0.001)
		var lambert := maxf(0.0, n.dot(to)) * 0.85 + 0.15
		var att := pow(1.0 - dl / rng, 2.0)
		if att * lambert < 0.015:
			continue
		_ray.from = p
		_ray.to = lp - to * 0.12
		if not _space.intersect_ray(_ray).is_empty():
			continue
		c += (l["color"] as Color) * (l["energy"] as float) * 0.8 * att * lambert
	return c


## Works out the light at each vertex and stores it as the vertex colour (at half brightness so
## it can go above 1.0). The house then draws with no real-time lights at all.
func _bake_light(mesh: ArrayMesh) -> ArrayMesh:
	_space = get_world_3d().direct_space_state
	_ray.collision_mask = 1
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var cols := PackedColorArray()
	cols.resize(verts.size())
	for i in verts.size():
		var n := norms[i]
		var ck := [Vector3i(roundi(verts[i].x * 20), roundi(verts[i].y * 20), roundi(verts[i].z * 20)), Vector3i(roundi(n.x * 4), roundi(n.y * 4), roundi(n.z * 4))]
		var cache: Dictionary = _vcache_n if _night else _vcache
		if cache.has(ck):
			cols[i] = cache[ck]
			continue
		var c := _light_at(verts[i] + n * 0.05, n)
		c = Color(minf(c.r * 0.5, 1.0), minf(c.g * 0.5, 1.0), minf(c.b * 0.5, 1.0), 1.0)
		cols[i] = c
		cache[ck] = c
	_baked_verts += verts.size()
	arrays[Mesh.ARRAY_COLOR] = cols
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


var _vcache := {}
var _vcache_n := {}


# ---------- light probes: how bright it is where people stand (for characters & disguises) ----------

const PROBE_CELL := 1.0
const PROBE_ORIGIN := Vector2(-13.0, -14.0)
const PROBE_SIZE := Vector2i(51, 47)
const PROBE_HEIGHTS := [1.0, F2 + 1.0]
var probes := PackedColorArray()


func _bake_probes() -> void:
	_space = get_world_3d().direct_space_state
	_ray.collision_mask = 1
	probes.resize(PROBE_SIZE.x * PROBE_SIZE.y * PROBE_HEIGHTS.size())
	var i := 0
	for h in PROBE_HEIGHTS:
		for z in PROBE_SIZE.y:
			for x in PROBE_SIZE.x:
				var p := Vector3(PROBE_ORIGIN.x + x * PROBE_CELL, h, PROBE_ORIGIN.y + z * PROBE_CELL)
				# average of "facing up" and "facing sideways" light, like a person's body
				var c := _light_at(p, Vector3.UP) * 0.45
				for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
					c += _light_at(p, d) * 0.1375
				probes[i] = c
				i += 1


## Light at a world position, smoothly blended between probes.
func light_at(pos: Vector3) -> Color:
	if probes.is_empty():
		return Color(0.8, 0.8, 0.8)
	var level := 1 if pos.y > F2 - 0.5 else 0
	var fx := clampf((pos.x - PROBE_ORIGIN.x) / PROBE_CELL, 0.0, PROBE_SIZE.x - 1.001)
	var fz := clampf((pos.z - PROBE_ORIGIN.y) / PROBE_CELL, 0.0, PROBE_SIZE.y - 1.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - x0
	var tz := fz - z0
	var base := level * PROBE_SIZE.x * PROBE_SIZE.y
	var c00 := probes[base + z0 * PROBE_SIZE.x + x0]
	var c10 := probes[base + z0 * PROBE_SIZE.x + x0 + 1]
	var c01 := probes[base + (z0 + 1) * PROBE_SIZE.x + x0]
	var c11 := probes[base + (z0 + 1) * PROBE_SIZE.x + x0 + 1]
	return c00.lerp(c10, tx).lerp(c01.lerp(c11, tx), tz) * dim_amount


static var _baked_mats := {}
static var all_baked: Array[Material] = []
static var dim_amount := 1.0
const BAKED_SHADER := preload("res://scripts/baked.gdshader")


## The look of a material drawn with baked light: a ShaderMaterial that multiplies the texture by
## the vertex light and adds bump detail from the normal map. Glass/water keep a plain material.
static func _baked_version(m: Material) -> Material:
	if not (m is BaseMaterial3D):
		return m
	if _baked_mats.has(m):
		return _baked_mats[m]
	var b := m as BaseMaterial3D
	var out: Material
	var glows := b.emission_enabled and b.emission.get_luminance() * b.emission_energy_multiplier > 0.05
	if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or b.albedo_color.a < 0.99 or not detail_on:
		# lean built-in path (Balanced / Smoothest, and all see-through glass)
		var d: BaseMaterial3D = b.duplicate()
		d.uv1_triplanar = false
		d.uv1_world_triplanar = false
		d.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		d.vertex_color_use_as_albedo = not glows
		d.normal_enabled = false
		d.roughness_texture = null
		d.emission_enabled = false
		var c := d.albedo_color
		d.albedo_color = c * 1.4 if glows else Color(c.r * 2.0, c.g * 2.0, c.b * 2.0, c.a)
		d.set_meta("base_albedo", d.albedo_color)
		out = d
	else:
		var sm := ShaderMaterial.new()
		var has_n := b.normal_enabled and b.normal_texture != null
		var tex := b.albedo_texture != null
		if glows:
			sm.shader = load("res://scripts/baked_glow.gdshader")
			sm.set_shader_parameter("has_tex", tex)
		elif tex:
			sm.shader = load("res://scripts/baked_tex_n.gdshader" if has_n and detail_on else "res://scripts/baked_tex.gdshader")
		else:
			sm.shader = load("res://scripts/baked_flat_n.gdshader" if has_n and detail_on else "res://scripts/baked_flat.gdshader")
		sm.set_shader_parameter("albedo", b.albedo_color * (1.4 if glows else 1.0))
		if tex:
			sm.set_shader_parameter("albedo_tex", b.albedo_texture)
		if has_n:
			sm.set_shader_parameter("normal_tex", b.normal_texture)
			sm.set_meta("detail_pair", [load("res://scripts/baked_tex.gdshader" if tex else "res://scripts/baked_flat.gdshader"), load("res://scripts/baked_tex_n.gdshader" if tex else "res://scripts/baked_flat_n.gdshader")])
		sm.set_shader_parameter("uv_scale", Vector2(b.uv1_scale.x, b.uv1_scale.y))
		out = sm
	_baked_mats[m] = out
	all_baked.append(out)
	return out


static var detail_on := true


## Surface relief from normal maps: lovely but costs a texture read per pixel on phones.
static func set_detail(on: bool) -> void:
	detail_on = on
	for d in all_baked:
		if d is ShaderMaterial and d.has_meta("detail_pair"):
			(d as ShaderMaterial).shader = d.get_meta("detail_pair")[1 if on else 0]


## Lights out: darken everything that uses baked light.
static func dim(amount: float) -> void:
	dim_amount = amount
	for d in all_baked:
		if d is ShaderMaterial:
			(d as ShaderMaterial).set_shader_parameter("dim", amount)
		elif d is BaseMaterial3D:
			var base: Color = d.get_meta("base_albedo", (d as BaseMaterial3D).albedo_color)
			(d as BaseMaterial3D).albedo_color = Color(base.r * amount, base.g * amount, base.b * amount, base.a)


static var _planar := {}


static func _planar_version(m: BaseMaterial3D) -> BaseMaterial3D:
	if not _planar.has(m):
		var d: BaseMaterial3D = m.duplicate()
		d.uv1_triplanar = false
		d.uv1_world_triplanar = false
		_planar[m] = d
	return _planar[m]


## Like _mat_key but the same on every run (no instance ids), so saved batches can be matched up.
static func _stable_key(mat: Material, fallback: String) -> String:
	if mat is BaseMaterial3D:
		var b := mat as BaseMaterial3D
		var tex := b.albedo_texture.resource_path if b.albedo_texture else ""
		return "%s|%s|%.2f|%d|%s|%s" % [b.albedo_color.to_html(true), tex.get_file(), b.roughness, b.transparency, b.uv1_world_triplanar, b.resource_name]
	return fallback


static func _mat_key(mat: Material) -> String:
	if mat is BaseMaterial3D:
		var b := mat as BaseMaterial3D
		var tex := b.albedo_texture.resource_path if b.albedo_texture else ""
		if b.albedo_texture and tex == "":
			tex = str(b.albedo_texture.get_instance_id())
		if b.uv1_triplanar or b.normal_enabled:
			return str(b.get_instance_id())
		return "%s|%s|%.2f|%.2f|%d|%s" % [b.albedo_color.to_html(true), tex, b.roughness, b.metallic, b.transparency, b.emission.to_html() if b.emission_enabled else ""]
	return str(mat.get_instance_id()) if mat else "none"


# ---------- lights ----------

func _room_lights() -> void:
	var rooms := [
		[Rect2(0, 0, 9, 6), 0], [Rect2(9, 0, 6, 6), 0], [Rect2(15, 0, 9, 6), 0], [Rect2(0, 6, 12, 2), 0], [Rect2(12, 6, 12, 2), 0],
		[Rect2(0, 8, 11, 8), 0], [Rect2(11, 8, 8, 8), 0], [Rect2(19, 8, 5, 8), 0],
		[Rect2(0, 0, 9, 6), 1], [Rect2(9, 0, 4.5, 6), 1], [Rect2(15, 0, 9, 6), 1], [Rect2(0, 6, 12, 2), 1], [Rect2(12, 6, 12, 2), 1],
		[Rect2(0, 8, 8, 8), 1], [Rect2(8, 8, 4, 8), 1], [Rect2(12, 8, 12, 8), 1],
	]
	for rr in rooms:
		var r: Rect2 = rr[0]
		var base := 0.0 if rr[1] == 0 else F2
		var c := r.get_center()
		light_data.append({"pos": Vector3(c.x, base + H - 0.5, c.y), "color": Color("#ffdcb0"), "range": maxf(r.size.x, r.size.y) * 0.75 + 2.0, "energy": 1.0})
		_level_y = base
		_put("lampSquareCeiling", Vector3(c.x, H - 0.48, c.y), 0, {"col": "none", "prop": false})
	_level_y = 0.0


func set_room_light_shadows(_on: bool) -> void:
	pass


func set_lights(on: bool) -> void:
	dim(1.0 if on else 0.22)


var _wray := PhysicsRayQueryParameters3D.new()


## True if no wall, floor, ceiling or hedge is between a and b. Furniture doesn't count.
func walls_clear(a: Vector3, b: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	_wray.collision_mask = 1
	_wray.exclude = []
	var from := a
	for i in 8:
		_wray.from = from
		_wray.to = b
		var hit := space.intersect_ray(_wray)
		if hit.is_empty():
			return true
		var c: Object = hit["collider"]
		if c is Node and (c as Node).has_meta("wall"):
			return false
		var ex: Array[RID] = _wray.exclude
		ex.append(hit["rid"])
		_wray.exclude = ex
		from = hit["position"]
	return true


func surface_at(p: Vector3) -> String:
	var level := 1 if p.y > F2 - 0.5 else 0
	var pt := Vector2(p.x, p.z)
	for s in surfaces:
		if s["level"] == level and (s["rect"] as Rect2).has_point(pt):
			return s["kind"]
	return "grass" if level == 0 else "wood"


## A thin flat-screen TV on a stand: black bezel, the picture set inside it, glossy glass.
func _build_tv() -> void:
	var bezel := Color("#141418")
	var c := TV_CENTER
	Build.cube(self, Vector3(TV_SCREEN.x + 0.07, TV_SCREEN.y + 0.07, 0.05), c, bezel)
	Build.cube(self, Vector3(TV_SCREEN.x + 0.02, 0.012, 0.052), c + Vector3(0, -TV_SCREEN.y / 2.0 - 0.03, 0), Color("#2a2a33"))
	Build.cube(self, Vector3(0.09, 0.14, 0.05), Vector3(c.x, 0.73, c.z - 0.02), bezel)
	Build.cube(self, Vector3(0.55, 0.02, 0.24), Vector3(c.x, 0.665, c.z), Color("#22222a"))
	Build.ball(self, 0.008, c + Vector3(0.62, -TV_SCREEN.y / 2.0 - 0.025, 0.027), Color("#ff3b3b"))
	# the screen itself: dark glossy glass when off, the video when on
	var q := QuadMesh.new()
	q.size = TV_SCREEN
	_tv_screen = MeshInstance3D.new()
	_tv_screen.mesh = q
	_tv_screen.position = c + Vector3(0, 0, 0.0262)
	_tv_screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tv_screen.set_meta("dynamic", true)
	var off_grad := Gradient.new()
	off_grad.set_color(0, Color("#1c2230"))
	off_grad.set_color(1, Color("#07080c"))
	var off_tex := GradientTexture2D.new()
	off_tex.gradient = off_grad
	off_tex.fill_from = Vector2(0.1, 0.0)
	off_tex.fill_to = Vector2(0.9, 1.0)
	_tv_off_mat = StandardMaterial3D.new()
	_tv_off_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tv_off_mat.albedo_texture = off_tex
	_tv_screen.material_override = _tv_off_mat
	add_child(_tv_screen)
	# a faint reflection on the glass
	var glare_grad := Gradient.new()
	glare_grad.offsets = PackedFloat32Array([0.0, 0.45, 0.5, 1.0])
	glare_grad.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.0)])
	var glare_tex := GradientTexture2D.new()
	glare_tex.gradient = glare_grad
	glare_tex.fill_from = Vector2(0.0, 0.0)
	glare_tex.fill_to = Vector2(1.0, 0.8)
	var glare := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = TV_SCREEN
	glare.mesh = gq
	glare.position = c + Vector3(0, 0, 0.028)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_texture = glare_tex
	glare.material_override = gm
	glare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glare.set_meta("dynamic", true)
	add_child(glare)
	# soft light spilling onto the wall behind while it plays
	var glow_grad := Gradient.new()
	glow_grad.set_color(0, Color(0.55, 0.75, 1.0, 0.55))
	glow_grad.set_color(1, Color(0.55, 0.75, 1.0, 0.0))
	var glow_tex := GradientTexture2D.new()
	glow_tex.gradient = glow_grad
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(1.0, 0.5)
	_tv_glow = MeshInstance3D.new()
	var wq := QuadMesh.new()
	wq.size = Vector2(3.0, 1.9)
	_tv_glow.mesh = wq
	_tv_glow.position = Vector3(c.x, c.y + 0.05, 8.095)
	var wm := StandardMaterial3D.new()
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	wm.albedo_texture = glow_tex
	_tv_glow.material_override = wm
	_tv_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tv_glow.set_meta("dynamic", true)
	_tv_glow.visible = false
	add_child(_tv_glow)


# ---------- garage: sports car + motorbike ----------

const CAR_POS := Vector3(18.3, 0, 3.0)
const BIKE_POS := Vector3(21.9, 0, 3.2)
var _car_lights: Array[MeshInstance3D] = []
var _bike_lights: Array[MeshInstance3D] = []
var _light_t := 0.0


func _glow_quad(parent: Node3D, size: Vector2, pos: Vector3, color: Color) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.position = pos
	mi.rotation.y = PI  # face -z, out the front
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("dynamic", true)
	mi.visible = false
	parent.add_child(mi)
	return mi


func _vehicles() -> void:
	# --- red sports car, nose toward the garage door ---
	var car := _put("car:sedan-sports", CAR_POS, 180, {"scale": 1.75, "prop": false})
	var cockpit := Node3D.new()
	cockpit.position = CAR_POS
	add_child(cockpit)
	# get in: you're hidden in the car and the camera circles it, starting from the front
	_spot("the sports car", CAR_POS, PI, CAR_POS + Vector3(1.95, 0.05, 0.2), "car")
	for sx in [-1.0, 1.0]:
		_car_lights.append(_glow_quad(cockpit, Vector2(0.42, 0.14), Vector3(0.66 * sx, 0.78, -2.255), Color(1.6, 1.6, 1.4)))
	# --- MT-style naked street bike on its kickstand ---
	var bike := _motorbike()
	bike.position = BIKE_POS
	bike.rotation = Vector3(0, PI, 0)
	add_child(bike)
	var col := Build.collider(self, Vector3(0.7, 1.1, 2.0), BIKE_POS + Vector3(0, 0.55, 0))
	col.set_meta("vehicle", true)
	_spot("the motorbike", BIKE_POS + Vector3(0, 0.0, 0.15), 0.0, BIKE_POS + Vector3(-1.1, 0.05, 0.0), "bike")


## A naked street bike in the style of the Yamaha MT-15: racing-blue tank with cyan
## accents, gold forks, twin LED "eyes", stubby exhaust. Built from simple shapes; faces -z.
func _motorbike() -> Node3D:
	var b := Node3D.new()
	var blue := Color("#1f3fb8")
	var cyan := Color("#16d4ff")
	var dark := Color("#202228")
	var grey := Color("#5b5f68")
	var gold := Color("#d4a63a")
	var black := Color("#0e0e10")
	var r := 0.33
	var wb := 1.36
	for z in [-wb / 2.0, wb / 2.0]:
		var tire := Build.cyl(b, r, r, 0.14, Vector3(0, r, z), black, 24)
		tire.rotation.z = PI / 2.0
		var rim := Build.cyl(b, r * 0.72, r * 0.72, 0.15, Vector3(0, r, z), dark, 18)
		rim.rotation.z = PI / 2.0
		var hub := Build.cyl(b, 0.07, 0.07, 0.17, Vector3(0, r, z), grey, 10)
		hub.rotation.z = PI / 2.0
		var disc := Build.cyl(b, 0.15, 0.15, 0.02, Vector3(0.09, r, z), Color("#9aa0a8"), 18)
		disc.rotation.z = PI / 2.0
		# fender
		Build.cube(b, Vector3(0.16, 0.04, 0.42), Vector3(0, r * 2.0 + 0.04, z + (0.05 if z > 0 else -0.05)), dark)
	var front := Vector3(0, r, wb / 2.0)
	# gold upside-down forks, raked back
	for sx in [-1.0, 1.0]:
		var fork := Build.cyl(b, 0.032, 0.04, 0.7, front + Vector3(0.09 * sx, 0.33, -0.12), gold, 10)
		fork.rotation.x = deg_to_rad(-25)
	# frame, engine, swingarm
	Build.cube(b, Vector3(0.18, 0.12, 0.9), Vector3(0, 0.82, 0.05), grey).rotation.x = deg_to_rad(12)
	Build.cube(b, Vector3(0.3, 0.34, 0.45), Vector3(0, 0.48, 0.05), Color("#3a3d44"))
	Build.cube(b, Vector3(0.26, 0.12, 0.3), Vector3(0, 0.3, 0.12), Color("#2a2c31"))
	Build.cube(b, Vector3(0.12, 0.08, 0.72), Vector3(0.1, 0.4, -0.4), grey).rotation.x = deg_to_rad(-6)
	Build.cube(b, Vector3(0.12, 0.08, 0.72), Vector3(-0.1, 0.4, -0.4), grey).rotation.x = deg_to_rad(-6)
	# tank with cyan side shrouds
	Build.cube(b, Vector3(0.36, 0.24, 0.48), Vector3(0, 0.95, 0.22), blue).rotation.x = deg_to_rad(8)
	for sx in [-1.0, 1.0]:
		var shroud := Build.cube(b, Vector3(0.04, 0.2, 0.36), Vector3(0.2 * sx, 0.86, 0.36), cyan)
		shroud.rotation = Vector3(deg_to_rad(15), deg_to_rad(10 * sx), 0)
		Build.cube(b, Vector3(0.03, 0.14, 0.3), Vector3(0.19 * sx, 0.76, 0.15), dark)
	# seat and tail
	Build.cube(b, Vector3(0.26, 0.09, 0.5), Vector3(0, 0.88, -0.22), black).rotation.x = deg_to_rad(-6)
	Build.cube(b, Vector3(0.2, 0.08, 0.36), Vector3(0, 0.95, -0.6), dark).rotation.x = deg_to_rad(-14)
	Build.cube(b, Vector3(0.12, 0.05, 0.1), Vector3(0, 0.98, -0.8), Color("#ff2a2a"))
	Build.cube(b, Vector3(0.18, 0.12, 0.02), Vector3(0, 0.78, -0.86), Color("#f2f2f2")).rotation.x = deg_to_rad(-20)
	# headlight face: dark mask with twin LED eyes and a projector
	var face := front + Vector3(0, 0.62, 0.02)
	Build.cube(b, Vector3(0.24, 0.16, 0.08), face, dark).rotation.x = deg_to_rad(-20)
	for sx in [-1.0, 1.0]:
		var led := Build.cube(b, Vector3(0.07, 0.02, 0.02), face + Vector3(0.07 * sx, 0.04, 0.045), Color("#bff4ff"))
		led.rotation.z = deg_to_rad(-15 * sx)
		led.material_override = Build.mat(Color("#bff4ff"), 0.3, 2.0)
	Build.ball(b, 0.04, face + Vector3(0, -0.03, 0.04), Color("#e8f6ff"))
	# handlebar, grips, mirrors
	var bar := Build.cyl(b, 0.016, 0.016, 0.66, face + Vector3(0, 0.16, -0.12), black, 8)
	bar.rotation.z = PI / 2.0
	for sx in [-1.0, 1.0]:
		Build.cyl(b, 0.025, 0.025, 0.1, face + Vector3(0.36 * sx, 0.16, -0.12), Color("#2c2c2c"), 8).rotation.z = PI / 2.0
		Build.cyl(b, 0.008, 0.008, 0.18, face + Vector3(0.25 * sx, 0.26, -0.13), black, 6)
		Build.cube(b, Vector3(0.1, 0.06, 0.02), face + Vector3(0.27 * sx, 0.35, -0.13), black)
	# stubby exhaust under the right side
	var pipe := Build.cyl(b, 0.05, 0.06, 0.35, Vector3(0.14, 0.22, -0.08), Color("#2a2a2e"), 12)
	pipe.rotation.x = PI / 2.0
	Build.cyl(b, 0.035, 0.035, 0.02, Vector3(0.14, 0.22, -0.26), Color("#777777"), 10).rotation.x = PI / 2.0
	# kickstand
	Build.cyl(b, 0.012, 0.012, 0.36, Vector3(-0.16, 0.16, -0.05), grey, 6).rotation.z = deg_to_rad(-30)
	for mi in Kit.meshes(b):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_bike_lights.append(_glow_quad(b, Vector2(0.26, 0.18), face + Vector3(0, 0, 0.07), Color(1.4, 1.6, 1.8)))
	_bike_lights[0].rotation.y = 0.0
	return b


func flash_lights(kind: String) -> void:
	for l in (_car_lights if kind == "car" else _bike_lights):
		l.visible = true
	_light_t = 2.2


# ---------- framed photos ----------

## Hangs res://assets/photos/<file> on a wall: wooden frame, white mat, the photo.
## center = middle of the frame, n = direction the picture faces (into the room).
func _photo(file: String, center: Vector3, n: Vector3, height: float, frame_col := Color("#6b4a32")) -> void:
	var path := "res://assets/photos/" + file
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	var aspect := float(tex.get_width()) / float(tex.get_height())
	var ph := height
	var pw := height * aspect
	var mat_border := 0.05
	var frame_w := 0.045
	var holder := Node3D.new()
	holder.transform = Transform3D(Basis.looking_at(-n, Vector3.UP), center + n * 0.012)
	add_child(holder)
	_frame_specs.append({"xf": holder.transform, "pw": pw, "ph": ph})
	var ow := pw + 2.0 * (mat_border + frame_w)
	var oh := ph + 2.0 * (mat_border + frame_w)
	# frame bars
	Build.cube(holder, Vector3(ow, frame_w, 0.04), Vector3(0, oh / 2.0 - frame_w / 2.0, 0.02), frame_col)
	Build.cube(holder, Vector3(ow, frame_w, 0.04), Vector3(0, -oh / 2.0 + frame_w / 2.0, 0.02), frame_col)
	Build.cube(holder, Vector3(frame_w, oh, 0.04), Vector3(-ow / 2.0 + frame_w / 2.0, 0, 0.02), frame_col)
	Build.cube(holder, Vector3(frame_w, oh, 0.04), Vector3(ow / 2.0 - frame_w / 2.0, 0, 0.02), frame_col)
	# white mat behind the photo
	Build.cube(holder, Vector3(ow - frame_w, oh - frame_w, 0.01), Vector3(0, 0, 0.012), Color("#f7f3ec"))
	var q := QuadMesh.new()
	q.size = Vector2(pw, ph)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.position = Vector3(0, 0, 0.019)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)


# ---------- your own pictures in the frames ----------

var _frame_specs: Array = []     # [{xf, pw, ph}] for each framed photo that was hung
var _custom_nodes: Array = []
var _custom_mats: Array = []     # [material, world position] so the pictures get the night light too
var custom_photo_count := 0
var custom_video_count := 0
var _tint_key := ""


## (Re)loads the couple's own pictures from Pictures/PekaBoo and lays them over the frames.
func reload_custom() -> void:
	for n in _custom_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_custom_nodes.clear()
	_custom_mats.clear()
	var files := Custom.photos()
	custom_photo_count = 0
	for i in files.size():
		if custom_photo_count >= _frame_specs.size():
			break
		var tex := Custom.load_photo(files[i])
		if tex == null:
			continue
		var spec: Dictionary = _frame_specs[custom_photo_count]
		custom_photo_count += 1
		var pw: float = spec["pw"]
		var ph: float = spec["ph"]
		var q := QuadMesh.new()
		q.size = Vector2(pw, ph)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.set_meta("dynamic", true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var xf: Transform3D = spec["xf"]
		mi.transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.045))  # clear of the baked photo even at 16-bit depth
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		# fill the frame, cropping the picture's edges rather than squashing it
		var a_t := float(tex.get_width()) / float(tex.get_height())
		var a_f := pw / ph
		var sc := Vector3.ONE
		if a_t > a_f:
			sc.x = a_f / a_t
		else:
			sc.y = a_t / a_f
		m.uv1_scale = sc
		m.uv1_offset = Vector3((1.0 - sc.x) * 0.5, (1.0 - sc.y) * 0.5, 0.0)
		mi.material_override = m
		add_child(mi)
		_custom_nodes.append(mi)
		_custom_mats.append([m, xf.origin])
	_tint_key = ""
	_retint_custom()
	_reload_tv_playlist()


func _retint_custom() -> void:
	var key := "%s|%.2f|%d" % [is_night, dim_amount, probes.size()]
	if key == _tint_key:
		return
	_tint_key = key
	for it in _custom_mats:
		var c := light_at(it[1])
		var lum := clampf(maxf(c.r, maxf(c.g, c.b)), 0.0, 1.0)
		(it[0] as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b).lerp(Color(lum, lum, lum), 0.0) * 1.05


func custom_summary() -> String:
	return "%d picture%s on the walls · %d TV clip%s" % [custom_photo_count, "" if custom_photo_count == 1 else "s", custom_video_count, "" if custom_video_count == 1 else "s"]


func _hang_photos() -> void:
	# master bedroom, above the bed between the two windows
	_photo("photo1.jpg", Vector3(4.75, F2 + 1.75, 0.135), Vector3(0, 0, 1), 0.85, Color("#c9a24a"))
	# living room, the big landscape one by the window
	_photo("photo2.jpg", Vector3(0.135, 1.65, 14.5), Vector3(1, 0, 0), 0.8)
	# entry hall, above the bench: the first thing you see coming in
	_photo("photo3.jpg", Vector3(9.085, 1.75, 3.0), Vector3(1, 0, 0), 0.75, Color("#f2efe9"))
	# up the stairs
	_photo("photo4.jpg", Vector3(14.915, 2.55, 3.6), Vector3(-1, 0, 0), 0.75, Color("#6b4a32"))


# ---------- TV: plays the clips in res://assets/tv ----------

var _tv_clips: Array[String] = []
var _tv_vp: SubViewport
var _tv_video: VideoStreamPlayer
var _tv_mat: StandardMaterial3D
var _tv_index := -1
var _duck: AudioEffectAmplify


var _tv_default: Array[String] = []
var _tv_slide: TextureRect
var _slide_timer: Timer
var _slide_files: Array[String] = []
var _slide_i := 0


func _setup_tv_video() -> void:
	for i in range(1, 100):
		var path := "res://assets/tv/clip%d.ogv" % i
		if ResourceLoader.exists(path):
			_tv_default.append(path)
	_tv_clips = _tv_default.duplicate()
	_tv_vp = SubViewport.new()
	_tv_vp.size = Vector2i(512, 288)
	_tv_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_tv_vp.disable_3d = true
	add_child(_tv_vp)
	_tv_video = VideoStreamPlayer.new()
	_tv_video.size = Vector2(512, 288)
	_tv_video.expand = true
	_tv_video.bus = "TV"
	_tv_video.finished.connect(_tv_next)
	_tv_vp.add_child(_tv_video)
	_tv_slide = TextureRect.new()
	_tv_slide.size = Vector2(512, 288)
	_tv_slide.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tv_slide.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_tv_slide.visible = false
	_tv_vp.add_child(_tv_slide)
	_slide_timer = Timer.new()
	_slide_timer.one_shot = true
	_slide_timer.timeout.connect(_slide_next)
	add_child(_slide_timer)
	var rt := Timer.new()  # keeps the custom pictures lit like the room they hang in
	rt.wait_time = 0.7
	rt.autostart = true
	rt.timeout.connect(_retint_custom)
	add_child(rt)
	_tv_mat = StandardMaterial3D.new()
	_tv_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tv_mat.albedo_texture = _tv_vp.get_texture()
	_tv_mat.albedo_color = Color(1.08, 1.08, 1.08)
	# its own audio bus so it can fade with distance, plus a duck on the music
	if AudioServer.get_bus_index("TV") < 0:
		AudioServer.add_bus()
		var bi := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, "TV")
		AudioServer.set_bus_send(bi, "SFX")
	var mb := AudioServer.get_bus_index("Music")
	if mb >= 0:
		_duck = AudioEffectAmplify.new()
		AudioServer.add_bus_effect(mb, _duck)


func tv_clip_count() -> int:
	return _tv_clips.size()


func set_tv(on: bool, clip := -1) -> void:
	tv_on = on
	_tv_light.light_energy = 0.9 if on else 0.0
	_tv_glow.visible = on
	if on and not _tv_clips.is_empty():
		_tv_screen.material_override = _tv_mat
		_tv_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_play_clip(clip if clip >= 0 else randi() % _tv_clips.size())
	else:
		_tv_video.stop()
		_tv_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_tv_screen.material_override = _tv_off_mat
		if _duck:
			_duck.volume_db = 0.0
	if on and _tv_clips.is_empty():
		_tv_screen.material_override = Build.mat(Color("#8fd3ff"), 0.4, 1.6)


## Your clips (Movies/PekaBoo/*.ogv) replace the built-in ones; with only pictures the TV
## shows them as a slideshow between the built-in clips.
func _reload_tv_playlist() -> void:
	var vids := Custom.videos()
	custom_video_count = vids.size()
	_tv_clips = []
	if not vids.is_empty():
		_tv_clips.assign(vids)
	else:
		_tv_clips = _tv_default.duplicate()
		if custom_photo_count > 0:
			_tv_clips.append("slideshow")
	_slide_files = Custom.photos()
	if tv_on:
		set_tv(true)


func _play_clip(i: int) -> void:
	_tv_index = i % _tv_clips.size()
	var entry := _tv_clips[_tv_index]
	_slide_timer.stop()
	if entry == "slideshow":
		_tv_video.stop()
		_tv_video.visible = false
		_slide_i = 0
		_show_slide()
		return
	_tv_slide.visible = false
	_tv_video.visible = true
	if entry.begins_with("res://"):
		_tv_video.stream = load(entry)
	else:
		var s := VideoStreamTheora.new()
		s.file = entry
		_tv_video.stream = s
	_tv_video.play()


func _show_slide() -> void:
	if _slide_files.is_empty():
		_tv_next()
		return
	var tex := Custom.load_photo(_slide_files[_slide_i % _slide_files.size()])
	if tex != null:
		_tv_slide.texture = tex
		_tv_slide.visible = true
	_slide_timer.start(6.0)


func _slide_next() -> void:
	_slide_i += 1
	if _slide_i >= _slide_files.size():
		_tv_next()
	else:
		_show_slide()


## When a clip ends, play a different random one.
func _tv_next() -> void:
	if not tv_on or _tv_clips.is_empty():
		return
	var n := _tv_clips.size()
	var next := randi() % n
	if n > 1 and next == _tv_index:
		next = (next + 1) % n
	_play_clip(next)


func _process(_dt: float) -> void:
	if _light_t > 0.0:
		_light_t -= _dt
		if _light_t <= 0.0:
			for l in _car_lights + _bike_lights:
				l.visible = false
	if tv_on and not _tv_clips.is_empty():
		# louder as you walk up to it; the game music ducks so you can hear it
		var cam := get_viewport().get_camera_3d()
		if cam:
			var d := cam.global_position.distance_to(Vector3(8.5, 1.2, 8.8))
			var near := clampf(1.0 - (d - 2.0) / 12.0, 0.0, 1.0)
			_tv_video.volume_db = linear_to_db(maxf(near, 0.001)) + 2.0
			if _duck:
				_duck.volume_db = -14.0 * near
		(_tv_glow.material_override as StandardMaterial3D).albedo_color.a = 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.004)
