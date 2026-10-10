class_name MapScreen
extends Node3D
## The hand-held map (spec §11.4), hung off the first-person camera. Tab brings it up; Tab or Esc
## puts it away (Esc is caught here before the PauseMenu sees it, so a second Esc opens the menu).
## Mouse wheel zooms. The world carries on behind it: you can walk, slowly.
##
## Opening: the sheet, already open (its old fold creases still in it), pops up into view in the right
## hand with a little overshoot, and the ink wells up from where you stand and spreads over it. Its
## creases move live with how it moves through the air (PaperSheet / PaperHinge): it blows back as it
## is whipped up, gives one soft follow-through and settles, then holds still to be read; walking and
## turning only stir its top-left corner, a few millimetres. Closing: the ink drains away and the
## sheet drops out of view. The lantern lights it (fp_controller lifts the
## lantern hand towards it by lift()).
##
## Data: configure() with the area's walls (MapReveal), then add_revealed() / set_lit() as cells are
## revealed. In look-dev that is the player's own lantern; in the game it will be the server (S4).

const READ_POS := Vector3(0.06, -0.005, -0.41)  # sheet centre, relative to the eye (fp_map.py READ_POS)
const READ_ROT := Vector3(-0.24, -0.05, 0.02)  # top tipped away a little, turned towards the left
const STOW_POS := Vector3(0.14, -0.55, -0.3)  # it comes up from below, right, tipped flat
const STOW_ROT := Vector3(1.0, -0.35, -0.3)
const RAISE_S := 0.38
const POP := 1.7  # overshoot of the pop-up (back-out easing): it lands, a touch past, and settles
const LOWER_S := 0.2
const INK_FROM := 0.24  # s after it starts coming up: the ink wells up as it arrives
const INK_S := 0.65  # until it has spread over the whole sheet
const SPREAD_MAX := 0.55  # m: past the far corner from anywhere on the sheet
const WALK_MULT := 0.55  # walking pace while reading (spec mapWalkMultiplier)
const LANTERN_LIFT := Vector3(0.05, 0.03, 0.055)  # the lantern comes up and forward, to light the sheet from in front
const STEP_M := 0.75  # footprint spacing (world metres)
const MAX_FOOTPRINTS := 9
const VIEWPORT := Vector2i(1536, 1152)  # MapInk.CANVAS
const UP_SETTLE_S := 0.3  # after it arrives the air's hold on the big creases fades over this
const BOUNCE_ENERGY := 0.5
const HAND_SCALE := 1.15
const THUMB_CONTACT := Vector3(0.128, -0.122, 0.001)  # map frame (fp_map.py: thumb pad on the sheet)
const VIEWMODEL_LAYER := 1 << 2  # lit by the viewmodel fill, like the lantern arm (fp_controller)

var body: Node3D  # whose footprints and position the map shows (the player)
var ink: MapInk

var _cell_size := 4.0
var _origin := Vector3.ZERO  # world position of the map area's (0, 0) cell corner
var _viewport: SubViewport
var _sheet: MeshInstance3D
var _anim: AnimationPlayer
var _hand: Node3D
var _bounce: OmniLight3D
var _mat: ShaderMaterial

var _want_open := false
var _raise := 0.0  # 0 stowed .. 1 held up to read
var _shown := 0.0  # seconds since it started coming out (the ink wells up a moment in)
var _up := 0.0  # seconds since it reached reading position (the creases stop feeling the air)
var _paper: PaperSheet
var _paper_log := "--paperlog" in OS.get_cmdline_user_args()
var _spread := 0.0
var _fade := 0.0
var _time := 0.0
var _dirty := true
var _last_step := Vector3.INF
var _step_side := 1
var _drawn_pos := Vector2.INF


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = VIEWPORT
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	ink = MapInk.new()
	_viewport.add_child(ink)

	var map := (load("res://client/assets/map/map.glb") as PackedScene).instantiate() as Node3D
	map.name = "Map"
	add_child(map)
	_sheet = map.find_children("MapSheet", "MeshInstance3D", true, false)[0]
	_sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the authored open shape ("rest"), then the creases are driven live (PaperSheet)
	_anim = map.find_children("*", "AnimationPlayer", true, false)[0]
	_anim.play("rest")
	_anim.seek(0.0, true)
	_anim.active = false
	_paper = PaperSheet.new(map.find_children("*", "Skeleton3D", true, false)[0])

	# the right hand (map_hand.glb, posed in the map's frame by art/scripts/fp_map.py)
	_hand = (load("res://client/assets/map/map_hand.glb") as PackedScene).instantiate() as Node3D
	_hand.name = "Hand"
	map.add_child(_hand)
	# This hand sits ~10 cm further from the eye than the lantern hand, so in perspective it looked
	# small next to it. Viewmodel licence: scale it up about the point where the thumb touches the
	# sheet, so the grip's contact stays exactly where it was solved.
	_hand.scale = Vector3.ONE * HAND_SCALE
	_hand.position = THUMB_CONTACT * (1.0 - HAND_SCALE)
	for node in _hand.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		# casts the lantern's shadow: the thumb's shadow on the sheet is the contact cue that sells the grip
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.layers |= VIEWMODEL_LAYER
		ViewmodelLeather.apply(mi, 0.78)  # + the depth trick that keeps walls from cutting through
		var leather := mi.material_override as ShaderMaterial
		if leather:
			# the lantern lights this palm head-on from ~30 cm (you see the lantern hand's shaded back):
			# a darker, warmer base keeps the two gloves reading as one leather
			leather.set_shader_parameter("value", 1.0)
			leather.set_shader_parameter("tint", Color(1.0, 0.8, 0.58))

	_mat = ShaderMaterial.new()
	_mat.shader = load("res://client/ui/map_parchment.gdshader")
	_mat.set_shader_parameter("front_tex", load("res://client/assets/map/parchment_front.png"))
	_mat.set_shader_parameter("back_tex", load("res://client/assets/map/parchment_back.png"))
	_mat.set_shader_parameter("normal_tex", load("res://client/assets/map/parchment_n.png"))
	_mat.set_shader_parameter("ink_tex", _viewport.get_texture())
	_mat.set_shader_parameter("ink_texel", Vector2.ONE / Vector2(VIEWPORT))
	_sheet.material_override = _mat
	# look-dev: --mapparam=name:v[;name:r,g,b] overrides map_parchment uniforms (colour A/B tests)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mapparam="):
			for pair in arg.substr(11).split(";"):
				var kv := pair.split(":")
				var v := kv[1].split(",")
				_mat.set_shader_parameter(kv[0], float(v[0]) if v.size() == 1 else Color(float(v[0]), float(v[1]), float(v[2])))
	# warm bounce: the lantern-lit parchment throws a little warm light back onto the hands
	_bounce = OmniLight3D.new()
	_bounce.name = "PaperBounce"
	_bounce.light_color = Color(1.0, 0.72, 0.42)
	_bounce.omni_range = 0.35
	_bounce.omni_attenuation = 1.5
	_bounce.light_cull_mask = VIEWMODEL_LAYER
	_bounce.shadow_enabled = false
	_bounce.light_volumetric_fog_energy = 0.0
	_bounce.light_specular = 0.0
	_bounce.position = Vector3(0.05, -0.08, 0.06)  # just in front of the sheet's lower half
	map.add_child(_bounce)
	_apply_pose()
	visible = false


## The area this map covers: its walls, where its (0, 0) cell corner is in the world, the cell size,
## and the direction (map space, +y south) of the maze centre for the compass.
func configure(reveal: MapReveal, origin: Vector3, cell_size: float, to_centre := Vector2(0, -1)) -> void:
	ink.reveal = reveal
	ink.to_centre = to_centre
	_origin = origin
	_cell_size = cell_size
	_dirty = true


func add_revealed(cells: Array[Vector2i]) -> void:
	for c in cells:
		if not ink.revealed.has(c):
			# cells revealed while the map is put away are simply there when it opens
			ink.revealed[c] = _time if _fade > 0.0 else -INF
			_dirty = true


func set_lit(cells: Array[Vector2i]) -> void:
	ink.lit.clear()
	for c in cells:
		ink.lit[c] = true
	_dirty = true


func is_reading() -> bool:
	return _want_open or _raise > 0.0


## 0..1: how far the map is up (fp_controller lifts the lantern towards it and slows the walk).
func lift() -> float:
	return _ease_out(_raise)


func toggle() -> void:
	_want_open = not _want_open


func open() -> void:
	_want_open = true


func close() -> void:
	_want_open = false


func _unhandled_input(event: InputEvent) -> void:
	if PauseMenu.is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_TAB:
		toggle()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and _want_open:
		var step := 0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: step = 1
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: step = -1
		if step != 0:
			ink.zoom = clampi(ink.zoom + step, 0, MapInk.ZOOMS.size() - 1)
			_dirty = true
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Esc puts the map away first; the next Esc reaches the PauseMenu
	if _want_open and not PauseMenu.is_open and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_time += delta
	ink.now = _time
	_track_footprints()
	if _want_open:
		_raise = move_toward(_raise, 1.0, delta / RAISE_S)
		_shown += delta
		_up = _up + delta if _raise >= 1.0 else 0.0
		if _shown >= INK_FROM:
			if _spread <= 0.0:
				_dirty = true  # the spread starts from where you are right now
			_spread = minf(_spread + delta * SPREAD_MAX / INK_S, SPREAD_MAX)
			_fade = 1.0
	else:
		_fade = move_toward(_fade, 0.0, delta / 0.15)
		_raise = move_toward(_raise, 0.0, delta / LOWER_S)
		if _raise <= 0.0:
			_shown = 0.0
			_spread = 0.0
	var was_visible := visible
	visible = _raise > 0.0
	if not visible:
		return
	_bounce.light_energy = BOUNCE_ENERGY * lift() * _fade
	_apply_pose()
	if not was_visible:
		_paper.reset()  # it starts flat in the hand; the first frame isn't a jump through the air
	# the creases feel the air while it comes out (and goes away), then hold still to be read; only the
	# top-left corner keeps answering your movement
	var forcing := exp(-_up / UP_SETTLE_S) if _want_open else 1.0
	_paper.update(delta, forcing)
	_mat.set_shader_parameter("corner_lift", _paper.corner_lift())
	if _paper_log and fmod(_time, 0.2) < delta:  # look-dev: --paperlog prints the creases' bend
		print("paper t=%.2f bend=%.1f deg corner=%.1f mm" % [_time, rad_to_deg(_paper.max_bend()), _paper.corner_lift() * 1000.0])
	var here := _cell_pos(body.global_position) if body else Vector2.ZERO
	if here.distance_to(_drawn_pos) > 0.04:
		_dirty = true
	if _dirty or ink.animating():
		ink.player_pos = here
		ink.player_yaw = -body.global_rotation.y if body else 0.0
		ink.queue_redraw()
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_drawn_pos = here
		_dirty = false
	var cell := MapInk.MAZE_RECT.size.x / maxf(1.0, float(ink.reveal.width if ink.reveal else 1)) * MapInk.ZOOMS[ink.zoom]
	var centre := (ink._maze_origin(cell) + here * cell) / MapInk.CANVAS if ink.reveal else Vector2(0.5, 0.5)
	if _spread < SPREAD_MAX * 0.02:
		_mat.set_shader_parameter("spread_centre", centre)
	_mat.set_shader_parameter("spread", _spread)
	_mat.set_shader_parameter("ink_fade", _fade)


func _apply_pose() -> void:
	var k := _back_out(_raise) if _want_open else _ease_in(_raise)
	position = STOW_POS.lerp(READ_POS, k)
	rotation = STOW_ROT.lerp(READ_ROT, k)
	# held up in one hand: it sways a touch, as paper does
	rotation.z += sin(_time * 1.3) * 0.006 * k
	rotation.x += sin(_time * 0.9 + 1.0) * 0.008 * k


func _cell_pos(world: Vector3) -> Vector2:
	var p := (world - _origin) / _cell_size
	return Vector2(p.x, p.z)


## Inked footprints follow you: one every STEP_M of travel, alternating feet, the oldest fading.
func _track_footprints() -> void:
	if body == null:
		return
	var p := body.global_position
	if _last_step == Vector3.INF:
		_last_step = p
		return
	var d := p - _last_step
	d.y = 0.0
	if d.length() < STEP_M:
		return
	var ang := atan2(d.x, -d.z)
	var side := Vector3(-d.z, 0.0, d.x).normalized() * 0.14 * _step_side
	ink.footprints.append([_cell_pos(p + side), ang, _step_side])
	if ink.footprints.size() > MAX_FOOTPRINTS:
		ink.footprints.pop_front()
	_step_side = -_step_side
	_last_step = p
	_dirty = true


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


static func _ease_in(x: float) -> float:
	return x * x * x


## Overshoots a little past 1 and settles (the pop-up).
static func _back_out(x: float) -> float:
	var y := x - 1.0
	return 1.0 + y * y * ((POP + 1.0) * y + POP)
