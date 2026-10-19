extends Node
## Stress bench: every fleet at the cap, everyone firing. Prints mean physics-tick cost.
## godot --headless --path . --fixed-fps 60 res://tests/perf_test.tscn

const WARMUP := 60
const FRAMES := 600
var world: World
var frame := 0
var t0 := 0


func _ready() -> void:
	seed(99)
	Tune.bot_start_sizes.assign([30])
	world = World.new()
	world.autopilot = true
	add_child(world)


func _physics_process(_dt: float) -> void:
	frame += 1
	if frame == WARMUP:
		t0 = Time.get_ticks_usec()
	if frame < WARMUP + FRAMES:
		return
	var per := float(Time.get_ticks_usec() - t0) / FRAMES / 1000.0
	var ships := 0
	for f in world.fleets:
		ships += f.ships.size()
	print("PERF frame_ms=%.3f ships=%d lasers=%d" % [per, ships, world.lasers.pos.size()])
	world.queue_free()
	get_tree().quit(0)
	set_physics_process(false)
