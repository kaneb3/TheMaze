extends Node3D
## Look-dev scene: walk a real 12x12 patch of the vertical-slice Ring 1 in fog, to settle the
## art direction (spec §16.0) before the gameplay milestones. Open this scene and press F6.
##   WASD walk · mouse look · Shift sprint · F lantern · F11 fullscreen · Esc menu
## Look-dev only: the real client never builds maze geometry itself (spec §0.6).
##
## Optional: `-- --shot=<path.png>` saves a screenshot after a few seconds and quits.
## `--menu[=options|leave]` opens the Esc menu at that page (for screenshots).

const CELL := 4.0
const WALL_HEIGHT := 7.0
const ASSETS := "res://client/assets/ring1/"
const MAZE_JSON := "res://client/lookdev/maze_sample.json"

# Hook on the lantern post (Blender (0.67, 0, 2.837) -> Godot) and the lantern's chain length.
const POST_HOOK := Vector3(0.67, 2.837, 0.0)
const LANTERN_CHAIN := 0.49
const LANTERN_FLAME := 0.098
const CAMP_FIRE := Vector3(1.15, 1.25, 1.05)

var _walls := {}  # Vector3i(x, y, 0=E/1=S) -> true for closed edges
var _w := 0
var _h := 0
var _flickers: Array = []  # [OmniLight3D, base_energy, phase]
var _noise := FastNoiseLite.new()
var _time := 0.0
var _shot_path := ""
var _shot_frames := 0
var _args := {}  # look-dev camera overrides: --cell=x,y --yaw=deg --pitch=deg --offset=dx,dz


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			_args[arg.substr(2, arg.find("=") - 2)] = arg.substr(arg.find("=") + 1)
	_shot_path = _args.get("shot", "")
	if _shot_path == "":
		# Play maximised rather than in Godot's small default window; F11 toggles fullscreen.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	_noise.frequency = 1.0
	var maze := _load_maze()
	_build_environment(maze)
	if _args.has("nomaze"):
		var ground := StaticBody3D.new()
		_box(ground, Vector3(0, -0.5, 0), 0.0, Vector3(400, 1, 400))
		add_child(ground)
	else:
		_build_maze(maze)
		_bake_floor_wall_distance()
		_place_props(maze)
	_spawn_player(maze)
	var menu := PauseMenu.new()
	add_child(menu)
	if _args.has("menu") or "--menu" in OS.get_cmdline_user_args():
		menu.open.call_deferred(_args.get("menu", "main"))


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F11:
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if full else DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


var _fps_t := 0.0


func _process(delta: float) -> void:
	if _args.has("fps"):  # look-dev: --fps prints the frame rate once a second
		_fps_t += delta
		if _fps_t >= 1.0:
			_fps_t = 0.0
			print("fps ", Engine.get_frames_per_second(), "  draws ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), "  prims ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	_time += delta
	for f in _flickers:
		var light: OmniLight3D = f[0]
		light.light_energy = f[1] * (1.0 + 0.10 * _noise.get_noise_1d(_time * 7.0 + f[2]) + 0.04 * _noise.get_noise_1d(_time * 23.0 + f[2]))
	if _shot_path != "":
		_shot_frames += 1
		var shot_at := float(_args.get("shot_at", "-1"))
		if (shot_at < 0.0 and _shot_frames == 180) or (shot_at >= 0.0 and _time >= shot_at):
			get_viewport().get_texture().get_image().save_png(_shot_path)
			get_tree().quit()


# ---------------------------------------------------------------------------------------------
# data

func _load_maze() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAZE_JSON))
	_w = int(data.width)
	_h = int(data.height)
	for e in data.walls:
		_walls[Vector3i(int(e[0]), int(e[1]), 0 if e[2] == "E" else 1)] = true
	return data


func _is_open(x: int, y: int, dir: Vector2i) -> bool:
	# dir: (1,0)=E (0,1)=S (-1,0)=W (0,-1)=N, from cell (x, y)
	var nx := x + dir.x
	var ny := y + dir.y
	if nx < 0 or ny < 0 or nx >= _w or ny >= _h:
		return false
	if dir == Vector2i(1, 0):
		return not _walls.has(Vector3i(x, y, 0))
	if dir == Vector2i(-1, 0):
		return not _walls.has(Vector3i(x - 1, y, 0))
	if dir == Vector2i(0, 1):
		return not _walls.has(Vector3i(x, y, 1))
	return not _walls.has(Vector3i(x, y - 1, 1))


func _cell_center(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, 0.0, (c.y + 0.5) * CELL)


func _hash(a: int, b: int) -> int:
	return absi(a * 73856093 ^ b * 19349663)


# ---------------------------------------------------------------------------------------------
# environment: dusk sky, moon, volumetric fog, ground mist

func _build_environment(maze: Dictionary) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	# the sky's radiance now also drives the (directional) ambient light
	sky_mat.sky_top_color = Color(0.16, 0.24, 0.31)
	sky_mat.sky_horizon_color = Color(0.12, 0.18, 0.23)
	sky_mat.ground_horizon_color = Color(0.06, 0.09, 0.11)
	sky_mat.ground_bottom_color = Color(0.02, 0.03, 0.035)
	sky_mat.sun_angle_max = 2.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# directional sky ambient (tops see the zenith, sides the horizon); the shaders occlude it by
	# depth in the corridor, so walls read as forms instead of flat silhouettes
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.7
	# grade: desaturated and cool, a little contrast (shadows stay readable, never crushed)
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.8
	env.adjustment_contrast = 1.1
	# teal grade (sampled from the film's maze frames): red pulled hard down at every level, a
	# lifted blue-black floor (never pure black), highlights rolling off to pale steel-blue
	var ramp := Gradient.new()
	# per-channel curves (each channel looks up its own value): red bent well below identity,
	# green slightly, blue near identity, all with a small lifted floor
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color(0.004, 0.012, 0.018), Color(0.15, 0.24, 0.27), Color(0.36, 0.48, 0.53),
		Color(0.6, 0.73, 0.78), Color(0.86, 0.95, 1.0)])
	var grade := GradientTexture1D.new()
	grade.gradient = ramp
	grade.width = 256
	env.adjustment_color_correction = grade
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 2.5
	env.ssao_power = 1.6
	env.ssao_detail = 1.0
	env.ssao_light_affect = 0.25  # joints occlude the lantern too
	env.ssao_ao_channel_affect = 1.0
	# AgX: more contrast and a lower white point for a night scene, so the lantern's hotspot keeps
	# its texture instead of washing to a pale sheen
	if "tonemap_agx_contrast" in env:
		env.set("tonemap_agx_contrast", 1.4)
		env.set("tonemap_agx_white", 9.0)
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.0  # no blurred copy of the whole frame: only real highlights glow
	env.glow_hdr_threshold = 1.0
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.6)
	env.set_glow_level(2, 0.6)
	env.set_glow_level(3, 0.3)
	env.set_glow_level(4, 0.0)
	env.set_glow_level(5, 0.0)
	env.set_glow_level(6, 0.0)
	env.volumetric_fog_enabled = true
	# thick, cold, backlit fog: the brightest thing in frame looking towards the moon; things vanish
	# at ~30-40 m
	env.volumetric_fog_density = 0.05
	env.volumetric_fog_albedo = Color(0.66, 0.76, 0.84)  # #A9C2D6
	env.volumetric_fog_emission = Color(0.043, 0.1, 0.14)  # #0B1A24
	env.volumetric_fog_emission_energy = 0.3
	env.volumetric_fog_anisotropy = 0.4
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_temporal_reprojection_amount = 0.85
	env.volumetric_fog_ambient_inject = 0.3
	env.volumetric_fog_sky_affect = 1.0  # the sky fogs like the walls in front of it: no step at the crown
	# backstop beyond the volumetric fog's range: distant walls dissolve into the same cold mist
	# instead of standing out as dark blocks
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.12, 0.2, 0.26)
	env.fog_light_energy = 1.0
	env.fog_density = 1.0  # (the default 0.01 capped depth fog at 1%)
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 70.0
	env.fog_depth_curve = 1.5
	env.fog_sky_affect = 1.0
	env.fog_sun_scatter = 0.25
	get_viewport().positional_shadow_atlas_size = 8192
	if _args.has("sdfgi"):  # look-dev A/B: Godot's real-time GI (sky occlusion + bounce)
		env.sdfgi_enabled = true
		env.sdfgi_cascades = 3
		env.sdfgi_min_cell_size = 0.2
		env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_50_PERCENT
		env.sdfgi_use_occlusion = true
		env.sdfgi_read_sky_light = true
		env.sdfgi_bounce_feedback = 0.3
		env.volumetric_fog_gi_inject = 1.0
	if _args.has("nofog"):  # look-dev: --nofog shows the bare geometry and lighting (debugging)
		env.volumetric_fog_enabled = false
		env.fog_enabled = false
	if not _args.has("nograin"):
		var grain_layer := CanvasLayer.new()
		grain_layer.layer = 100
		var grain := ColorRect.new()
		grain.set_anchors_preset(Control.PRESET_FULL_RECT)
		grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var grain_mat := ShaderMaterial.new()
		grain_mat.shader = load("res://client/world/film_grain.gdshader")
		grain.material = grain_mat
		grain_layer.add_child(grain)
		add_child(grain_layer)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.75, 0.87)  # #9EC0DD steel-teal, not lavender
	moon.light_energy = 0.4
	moon.shadow_opacity = 0.85
	moon.light_specular = 0.15  # moonlight on wet leaves read as a glossy sheet
	moon.light_volumetric_fog_energy = 2.2
	moon.shadow_enabled = true
	# 45 deg: rakes the upper half of the walls and backlights the fog at eye level
	moon.rotation_degrees = Vector3(-45.0, 150.0, 0.0)
	moon.light_angular_distance = 6.0  # moonlight through thick mist: soft-edged, diffuse shadows
	moon.directional_shadow_max_distance = 60.0
	moon.directional_shadow_blend_splits = true
	add_child(moon)

	# Patchy ground mist hugging the floor (client/world/ground_mist.gdshader).
	var noise := FastNoiseLite.new()
	noise.frequency = 0.06
	var tex := NoiseTexture3D.new()
	tex.width = 64
	tex.height = 64
	tex.depth = 64
	tex.seamless = true
	tex.noise = noise
	var fog_mat := ShaderMaterial.new()
	fog_mat.shader = load("res://client/world/ground_mist.gdshader")
	fog_mat.set_shader_parameter("noise_tex", tex)
	var mist := FogVolume.new()
	mist.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	mist.size = Vector3(maze.width * CELL + 8.0, 6.0, maze.height * CELL + 8.0)
	mist.position = Vector3(maze.width * CELL * 0.5, 2.5, maze.height * CELL * 0.5)
	mist.material = fog_mat
	add_child(mist)

	# A soft, faintly glowing layer above the walls: the crowns silhouette against it, as in the film.
	var high_mat := FogMaterial.new()
	high_mat.density = 0.02
	high_mat.albedo = Color(0.66, 0.76, 0.84)
	high_mat.emission = Color(0.10, 0.16, 0.21)
	high_mat.edge_fade = 0.4
	var high := FogVolume.new()
	high.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	high.size = Vector3(maze.width * CELL + 40.0, 13.5, maze.height * CELL + 40.0)
	high.position = Vector3(maze.width * CELL * 0.5, 13.25, maze.height * CELL * 0.5)
	high.material = high_mat
	add_child(high)


# ---------------------------------------------------------------------------------------------
# maze: walls on closed edges, pillars on every grid corner they touch, a floor tile per cell

func _build_maze(maze: Dictionary) -> void:
	var wall_scenes: Array[PackedScene] = [load(ASSETS + "wall2_a.glb"), load(ASSETS + "wall2_b.glb"), load(ASSETS + "wall2_c.glb")]
	var pillar_scene: PackedScene = load(ASSETS + "pillar2.glb")
	var root := Node3D.new()
	root.name = "Maze"
	add_child(root)
	var body := StaticBody3D.new()
	body.name = "Collision"
	root.add_child(body)

	var pillars := {}
	for key in _walls:
		var x: int = key.x
		var y: int = key.y
		var wall := wall_scenes[_hash(x * 13 + 1, y * 7 + key.z * 3) % wall_scenes.size()].instantiate() as Node3D
		var pos: Vector3
		var yaw := 0.0
		if key.z == 0:  # east edge: runs along Z
			pos = Vector3((x + 1) * CELL, 0.0, (y + 0.5) * CELL)
			yaw = PI / 2.0
			pillars[Vector2i(x + 1, y)] = true
			pillars[Vector2i(x + 1, y + 1)] = true
		else:  # south edge: runs along X
			pos = Vector3((x + 0.5) * CELL, 0.0, (y + 1) * CELL)
			pillars[Vector2i(x, y + 1)] = true
			pillars[Vector2i(x + 1, y + 1)] = true
		if _hash(x, y + 7 * key.z) % 2 == 1:
			yaw += PI  # show the other face for variety
		wall.position = pos
		wall.rotation.y = yaw
		root.add_child(wall)
		_box(body, pos, yaw, Vector3(CELL, WALL_HEIGHT, 0.62))
		WallMaterials.apply(wall)
		if _args.has("hide"):  # look-dev: --hide=<mesh name prefix> hides that wall part (debugging)
			for mi in wall.find_children(_args["hide"] + "*", "MeshInstance3D", true, false):
				mi.visible = false
		_occluder(root, pos, yaw, Vector3(CELL - 1.0, WALL_HEIGHT - 0.4, 0.3))
		var hm := _hash(x * 5 + 3, y * 11 + key.z)
		if hm % 5 == 0:  # roughly one wall in five carries a mark
			var kinds := ["tally", "tally", "daisy", "daisy", "burn", "burn", "initials", "arrow"]
			var mark := WallMarkings.add(wall, kinds[(hm / 5) % kinds.size()], 1 if (hm / 40) % 2 == 0 else -1,
				((hm / 80) % 100) / 100.0 * 2.0 - 1.0, 0.8 + ((hm / 8000) % 50) / 100.0, (hm / 3) % 2 == 0)
			if _args.has("marks"):  # look-dev: --marks lists where the marks are, for screenshots
				print("mark ", mark.name, " at ", mark.global_position, " facing ", mark.global_basis.y)

	for p in pillars:
		var pillar := pillar_scene.instantiate() as Node3D
		pillar.position = Vector3(p.x * CELL, 0.0, p.y * CELL)
		pillar.rotation.y = (_hash(p.x, p.y) % 4) * PI / 2.0
		root.add_child(pillar)
		_box(body, pillar.position, 0.0, Vector3(0.95, WALL_HEIGHT, 0.95))
		if _args.get("hide", "") == "pillar":
			pillar.visible = false
		_occluder(root, pillar.position, 0.0, Vector3(0.8, WALL_HEIGHT - 0.4, 0.8))
		WallMaterials.apply(pillar)

	# One world-mapped plane for the whole floor (photoscan setts, stone_floor.gdshader), with a
	# margin so the entrance approach isn't a void.
	var ground := MeshInstance3D.new()
	ground.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(_w * CELL + 24.0, _h * CELL + 24.0)
	ground.mesh = plane
	ground.position = Vector3(_w * CELL * 0.5, 0.0, _h * CELL * 0.5)
	ground.material_override = WallMaterials.floor_material()
	root.add_child(ground)
	_box(body, Vector3(_w * CELL * 0.5, -0.5, _h * CELL * 0.5), 0.0, Vector3(_w * CELL + 40.0, 1.0, _h * CELL + 40.0))


## The floor shader needs to know where the walls actually stand (grime gathers at their bases):
## a distance field to the nearest wall face, 0.25 m per texel, 0..2 m.
func _bake_floor_wall_distance() -> void:
	const PX := 4  # texels per metre
	var sw := int(_w * CELL) * PX
	var sh := int(_h * CELL) * PX
	var far := 999.0
	var d := PackedFloat32Array()
	d.resize(sw * sh)
	d.fill(far)
	var mark := func(x0: float, z0: float, x1: float, z1: float) -> void:
		for z in range(maxi(0, int(z0 * PX)), mini(sh, int(ceil(z1 * PX)))):
			for x in range(maxi(0, int(x0 * PX)), mini(sw, int(ceil(x1 * PX)))):
				d[z * sw + x] = 0.0
	for key in _walls:
		if key.z == 0:  # east edge at x = (x+1)*CELL, spanning z
			mark.call((key.x + 1) * CELL - 0.31, key.y * CELL, (key.x + 1) * CELL + 0.31, (key.y + 1) * CELL)
		else:
			mark.call(key.x * CELL, (key.y + 1) * CELL - 0.31, (key.x + 1) * CELL, (key.y + 1) * CELL + 0.31)
	# two-pass chamfer distance (in texels)
	for z in sh:
		for x in sw:
			var i := z * sw + x
			if x > 0: d[i] = minf(d[i], d[i - 1] + 1.0)
			if z > 0: d[i] = minf(d[i], d[i - sw] + 1.0)
			if x > 0 and z > 0: d[i] = minf(d[i], d[i - sw - 1] + 1.414)
			if x < sw - 1 and z > 0: d[i] = minf(d[i], d[i - sw + 1] + 1.414)
	for z in range(sh - 1, -1, -1):
		for x in range(sw - 1, -1, -1):
			var i := z * sw + x
			if x < sw - 1: d[i] = minf(d[i], d[i + 1] + 1.0)
			if z < sh - 1: d[i] = minf(d[i], d[i + sw] + 1.0)
			if x < sw - 1 and z < sh - 1: d[i] = minf(d[i], d[i + sw + 1] + 1.414)
			if x > 0 and z < sh - 1: d[i] = minf(d[i], d[i + sw - 1] + 1.414)
	var img := Image.create(sw, sh, false, Image.FORMAT_L8)
	for z in sh:
		for x in sw:
			var m := d[z * sw + x] / PX
			img.set_pixel(x, z, Color(clampf(m / 2.0, 0.0, 1.0), 0, 0))
	var mat := WallMaterials.floor_material()
	mat.set_shader_parameter("wall_dist_tex", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("maze_size", Vector2(_w * CELL, _h * CELL))


## Occlusion culling: a box inside the wall's core (clear of the stone faces and the foliage, so
## nothing on the surface culls itself) hides everything behind it.
func _occluder(parent: Node3D, pos: Vector3, yaw: float, size: Vector3) -> void:
	var occ := OccluderInstance3D.new()
	var box := BoxOccluder3D.new()
	box.size = size
	occ.occluder = box
	occ.position = pos + Vector3(0.0, size.y * 0.5, 0.0)
	occ.rotation.y = yaw
	parent.add_child(occ)


func _box(body: StaticBody3D, pos: Vector3, yaw: float, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos + Vector3(0.0, size.y * 0.5 if pos.y >= 0.0 else 0.0, 0.0)
	cs.rotation.y = yaw
	body.add_child(cs)


## glTF import gives us StandardMaterial3D; switch leaf cards to alpha-scissor and make glass/flame
## not block the lantern light.
func _fix_materials(node: Node) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if mat == null:
				continue
			if mat.resource_name.begins_with("LeafCards"):
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mat.alpha_scissor_threshold = 0.45
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				mat.albedo_color = Color(0.45, 0.62, 0.42)  # deeper, greener foliage than the flat-lit atlas
				mat.roughness = 0.65
		if mi.name.begins_with("Glass") or mi.name.begins_with("Flame") or mi.name.begins_with("Coals"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------------------------------------
# props: lantern posts along the way in, a camp in a nearby dead end

func _place_props(maze: Dictionary) -> void:
	var start := Vector2i(int(maze.entrances[0][0]), 0)
	var dist := {start: 0}
	var order := [start]
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var head := 0
	while head < order.size():
		var c: Vector2i = order[head]
		head += 1
		for d in dirs:
			if _is_open(c.x, c.y, d) and not dist.has(c + d):
				dist[c + d] = dist[c] + 1
				order.append(c + d)

	# Camp: the nearest dead end at least 4 cells in.
	for c in order:
		if dist[c] < 4:
			continue
		var exits := dirs.filter(func(d): return _is_open(c.x, c.y, d))
		if exits.size() == 1:
			var camp := (load(ASSETS + "camp.glb") as PackedScene).instantiate() as Node3D
			var d: Vector2i = exits[0]
			camp.position = _cell_center(c)
			camp.rotation.y = atan2(float(d.x), float(d.y))
			add_child(camp)
			_fix_materials(camp)
			_add_light(camp, CAMP_FIRE, Color(0.7, 0.82, 0.95), 2.2, 9.0, 0.8)
			LanternLighting.chill(camp)
			break

	# Lantern posts: every few cells along the route in, against a wall, arm towards the cell centre.
	var post_scene: PackedScene = load(ASSETS + "lantern_post.glb")
	var lantern_scene: PackedScene = load(ASSETS + "lantern.glb")
	for c in order:
		if dist[c] == 0 or dist[c] % 3 != 0 or dist[c] > 10:
			continue
		var wall_dir := Vector2i.ZERO
		for d in dirs:
			if not _is_open(c.x, c.y, d):
				wall_dir = d
				break
		if wall_dir == Vector2i.ZERO:
			continue
		var post := post_scene.instantiate() as Node3D
		post.position = _cell_center(c) + Vector3(wall_dir.x, 0.0, wall_dir.y) * 1.35
		post.rotation.y = atan2(float(wall_dir.y), float(-wall_dir.x))  # local +X (the arm) points back to the centre
		add_child(post)
		_fix_materials(post)
		var lantern := lantern_scene.instantiate() as Node3D
		lantern.position = POST_HOOK - Vector3(0.0, LANTERN_CHAIN, 0.0)
		post.add_child(lantern)
		_fix_materials(lantern)
		var light := _add_light(post, lantern.position + Vector3(0.0, LANTERN_FLAME, 0.0), LanternLighting.COLD_LIGHT, 1.3, 8.0, 1.2)
		LanternLighting.rig(lantern, light, Vector3(0.0, LANTERN_FLAME, 0.0))


func _add_light(parent: Node3D, pos: Vector3, color: Color, energy: float, rng: float, fog: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.3
	l.shadow_enabled = true
	l.shadow_normal_bias = 1.5
	# Static lights: stone and props cast, foliage doesn't (an omni shadow redraws every caster six
	# times; the player's lantern keeps the leaf shadows, where they matter).
	l.shadow_caster_mask = 0xFFFFF & ~WallMarkings.FOLIAGE_LAYER
	l.light_size = 0.08
	l.light_volumetric_fog_energy = fog
	parent.add_child(l)
	_flickers.append([l, energy, randf() * 100.0])
	return l


# ---------------------------------------------------------------------------------------------
# player

func _spawn_player(maze: Dictionary) -> void:
	var player := CharacterBody3D.new()
	player.name = "Player"
	player.set_script(load("res://client/player/fp_controller.gd"))
	var start := Vector2i(int(maze.entrances[0][0]), 0)
	player.position = _cell_center(start) + Vector3(0.0, 0.05, -1.2)
	player.rotation.y = PI  # face +Z (south), into the maze
	if _args.has("cell"):
		var c: PackedStringArray = _args["cell"].split(",")
		player.position = _cell_center(Vector2i(int(c[0]), int(c[1]))) + Vector3(0.0, 0.05, 0.0)
	if _args.has("offset"):
		var o: PackedStringArray = _args["offset"].split(",")
		player.position += Vector3(float(o[0]), 0.0, float(o[1]))
	if _args.has("yaw"):
		player.rotation.y = deg_to_rad(float(_args["yaw"]))
	add_child(player)
	if _args.has("pitch"):
		player.get_node("Head").rotation.x = deg_to_rad(float(_args["pitch"]))
	_flickers.append([player.get_node("Head/Camera3D/Hand/LanternRig/LanternLight"), player.lantern_energy, 3.0])
