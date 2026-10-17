extends Node
## Headless match on autopilot: checks the core rules hold over ~60 s of simulated play.
## godot --headless --path . --fixed-fps 60 res://tests/sim_test.tscn

const FRAMES := 3600
var world: World
var frame := 0
var max_fleet := 0
var total_kills := 0
var player_deaths := 0
var fails: Array[String] = []


func _ready() -> void:
	seed(1234)
	world = World.new()
	world.autopilot = true
	add_child(world)
	world.player_died.connect(func(_k: String) -> void: player_deaths += 1)


func _physics_process(_dt: float) -> void:
	frame += 1
	for f in world.fleets:
		max_fleet = maxi(max_fleet, f.ships.size())
		if f.ships.size() > Tune.max_ships:
			fails.append("fleet %s over cap: %d" % [f.name, f.ships.size()])
		for s in f.ships:
			if absf(s.global_position.x) > Tune.arena_half + 200 or absf(s.global_position.y) > Tune.arena_half + 200:
				fails.append("ship outside arena at %s" % s.global_position)
	if frame < FRAMES and fails.is_empty():
		return
	total_kills = 0
	for f in world.fleets:
		total_kills += f.kills
	var alive := world.fleets.filter(func(f: Fleet) -> bool: return f.alive).size()
	print("frames=%d fleets_alive=%d biggest=%d kills(alive fleets)=%d player_deaths=%d lasers=%d" % [
		frame, alive, max_fleet, total_kills, player_deaths, world.lasers.pos.size()])
	if total_kills == 0:
		fails.append("nobody killed anything")
	if alive < Tune.bot_count / 2:
		fails.append("bot respawn not keeping population")
	for msg in fails.slice(0, 5):
		printerr("FAIL: ", msg)
	print("SIM_TEST ", "PASS" if fails.is_empty() else "FAIL")
	world.queue_free()
	get_tree().quit(0 if fails.is_empty() else 1)
	set_physics_process(false)
