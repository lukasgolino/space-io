class_name Lasers
extends Node2D
## All laser bolts, stored in packed arrays and drawn with one MultiMesh per team colour.

const MAX := 4096

var pos := PackedVector2Array()
var vel := PackedVector2Array()
var life := PackedFloat32Array()
var fleet_id := PackedInt32Array()
var team := PackedInt32Array()

var _mm: Array[MultiMesh] = []
var _counts := PackedInt32Array()


func _ready() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for t in Art.TEAMS.size():
		var tex := Art.sheet("laser", t)
		var quad := QuadMesh.new()
		quad.size = tex.get_size() * (Tune.laser_length / tex.get_size().x)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.mesh = quad
		mm.instance_count = MAX
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance2D.new()
		mmi.multimesh = mm
		mmi.texture = tex
		mmi.material = mat
		mmi.modulate = Color(Tune.laser_hdr, Tune.laser_hdr, Tune.laser_hdr)   # HDR: blooms
		mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(mmi)
		_mm.append(mm)
	_counts.resize(Art.TEAMS.size())


func spawn(at: Vector2, v: Vector2, f: Fleet) -> void:
	if pos.size() >= MAX:
		return
	pos.append(at)
	vel.append(v)
	life.append(Tune.laser_life)
	fleet_id.append(f.id)
	team.append(f.team)


func remove(i: int) -> void:
	var last := pos.size() - 1
	pos[i] = pos[last]
	vel[i] = vel[last]
	life[i] = life[last]
	fleet_id[i] = fleet_id[last]
	team[i] = team[last]
	pos.resize(last)
	vel.resize(last)
	life.resize(last)
	fleet_id.resize(last)
	team.resize(last)


func step(dt: float) -> void:
	var i := 0
	while i < pos.size():
		life[i] -= dt
		if life[i] <= 0.0:
			remove(i)
			continue
		pos[i] += vel[i] * dt
		i += 1


func _process(_dt: float) -> void:
	# Draw at the interpolated position so bolts are as smooth as the (interpolated) ships.
	var lag := (1.0 - Engine.get_physics_interpolation_fraction()) / Engine.physics_ticks_per_second
	_counts.fill(0)
	for i in pos.size():
		var t := team[i]
		var n := _counts[t]
		_mm[t].set_instance_transform_2d(n, Transform2D(vel[i].angle(), pos[i] - vel[i] * lag))
		_counts[t] = n + 1
	for t in _mm.size():
		_mm[t].visible_instance_count = _counts[t]
