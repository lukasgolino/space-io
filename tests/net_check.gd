extends Node
## Network check, attached by main.gd for --net-test=SECONDS. Run a host and a client (both
## --autopilot) as two processes; each prints NET_HOST / NET_CLIENT PASS or FAIL and quits.
## See tools/test.sh.

const TUNED_LASER_SPEED := 333.0

var seconds := 10.0
var main: Node

var _t := 0.0
var _role := ""
var _start := {}         # peer -> spawn anchor of their first fleet
var _moved := {}         # peer -> furthest distance from spawn
var _fired := {}         # peer -> true once a bolt of theirs was seen
var _tuned := false
var _spawns := 0


func _physics_process(dt: float) -> void:
	_t += dt
	var w: World = main.world
	if w == null:
		_finish(["left the match (connection failed or host gone)"])
		return
	if _role == "":
		_role = "HOST" if w.mode == World.Mode.HOST else "CLIENT"
		w.player_spawned.connect(func() -> void: _spawns += 1)
	_observe(w)
	if _role == "HOST" and not _tuned and _t > seconds * 0.3:
		_tuned = true
		Tune.apply_values({"laser_speed": TUNED_LASER_SPEED})   # what F12 does
	if _t >= seconds:
		_finish(_verdict(w))


func _observe(w: World) -> void:
	for f in w.fleets:
		if not f.is_human() or f.ships.is_empty():
			continue
		if not _start.has(f.peer):
			_start[f.peer] = f.centre()
		_moved[f.peer] = maxf(_moved.get(f.peer, 0.0), f.centre().distance_to(_start[f.peer]))
	var lz := w.lasers
	for i in lz.pos.size():
		var f := w.fleet_by_id(lz.fleet_id[i])
		if f and f.is_human():
			_fired[f.peer] = true


func _verdict(w: World) -> Array[String]:
	var fails: Array[String] = []
	if _role == "HOST":
		var remote := _start.keys().filter(func(p: int) -> bool: return p != 1)
		if remote.is_empty():
			fails.append("no client joined")
		for p: int in remote:
			if _moved.get(p, 0.0) < 100.0:
				fails.append("client %d's fleet never moved (controls not arriving?)" % p)
			if not _fired.get(p, false):
				fails.append("client %d never fired" % p)
		print("host: humans=%d fleets=%d" % [w.humans.size(), w.fleets.size()])
	else:
		var n := w.net
		print("client: snapshots=%d events=%d fleets=%d ping=%d spawns=%d" % [
			n.snapshots_received, n.events_received, w.fleets.size(), n.ping_ms(), _spawns])
		if n.snapshots_received < seconds * 10:
			fails.append("too few snapshots: %d" % n.snapshots_received)
		if n.events_received == 0:
			fails.append("no events (lasers/explosions)")
		if w.player == null:
			fails.append("never got our own fleet")
		elif _moved.get(w.my_peer, 0.0) < 100.0:
			fails.append("our fleet never moved on screen")
		if w.fleets.size() < Tune.bot_count / 2:
			fails.append("mirror has only %d fleets" % w.fleets.size())
		if not _fired.get(1, false):
			fails.append("never saw the host's bolts")
		if not Tune.locked or Tune.laser_speed != TUNED_LASER_SPEED:
			fails.append("host settings not applied (locked=%s laser_speed=%f)" % [Tune.locked, Tune.laser_speed])
		for f in w.fleets:
			for s in f.ships:
				if s.fleet != f or not is_instance_valid(s):
					fails.append("ship bookkeeping broken in %s" % f.name)
	return fails


func _finish(fails: Array[String]) -> void:
	set_physics_process(false)
	for f in fails:
		printerr("FAIL: ", f)
	print("NET_%s %s" % [_role if _role != "" else "?", "PASS" if fails.is_empty() else "FAIL"])
	get_tree().quit(0 if fails.is_empty() else 1)
