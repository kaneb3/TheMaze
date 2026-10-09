class_name WallMarkings
extends RefCounted
## Marks left on the Ring 1 walls (decals from art/scripts/build_markings.py): tally marks, daisy
## wheels, carved initials, taper burns and chalk arrows. Kept rare and at hand height so they read
## as found details. Foliage sits on FOLIAGE_LAYER, which the decals skip, so a mark never paints
## onto ivy hanging in front of it.

const FOLIAGE_LAYER := 1 << 3
const KINDS := {
	"tally": [0.46, 0.46], "daisy": [0.36, 0.36], "initials": [0.42, 0.42],
	"burn": [0.32, 0.32], "arrow": [0.5, 0.5],
}
const DIR := "res://client/assets/ring1/markings/mark_%s_%s.png"
const CARVED := ["tally", "daisy", "initials"]  # these come fresh (pale) or old (grime-filled)
const FACE_Z := 0.30  # stone face plane, either side of the wall (glb local space)


## Adds a mark to a wall instance. side: +1 or -1 (which face), x along the wall, y height.
static func add(wall: Node3D, kind: String, side: int, x: float, y: float, old := false) -> Decal:
	var d := Decal.new()
	d.name = "Mark_" + kind
	var size: Array = KINDS[kind]
	d.size = Vector3(size[0], 0.24, size[1])
	var albedo_name := (kind + ("_old" if old else "_fresh")) if kind in CARVED else kind
	d.texture_albedo = load(DIR % [albedo_name, "albedo"])
	d.texture_normal = load(DIR % [kind, "normal"])
	d.cull_mask = 0xFFFFF & ~FOLIAGE_LAYER
	d.normal_fade = 0.35
	d.distance_fade_enabled = true
	d.distance_fade_begin = 14.0
	d.distance_fade_length = 4.0
	d.albedo_mix = (0.75 if old else 0.6) if kind in CARVED else 0.8  # cuts stay part of the stone; chalk sits on top
	# Decals project along their local -Y: point +Y out of the face, keep the texture upright.
	var basis := Basis(Vector3.RIGHT, PI / 2.0)
	if side < 0:
		basis = Basis(Vector3.UP, PI) * basis
	d.transform = Transform3D(basis, Vector3(x, y, FACE_Z * side))
	wall.add_child(d)
	return d
