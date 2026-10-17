class_name BotBrain
extends RefCounted
## Computer fleet: wander, hunt fleets it can beat, run from ones it can't, dodge incoming bolts.

var fleet: Fleet
var think_left := 0.0
var wander := Vector2.ZERO
var strafe_sign := 1.0
var dodge_left := 0.0
var dodge_dir := Vector2.ZERO


func _init(f: Fleet) -> void:
	fleet = f
	strafe_sign = 1.0 if randf() < 0.5 else -1.0
	_new_wander()


func _new_wander() -> void:
	var h := Tune.arena_half - 300.0
	wander = Vector2(randf_range(-h, h), randf_range(-h, h))


func step(dt: float) -> void:
	fleet.want_fire = false
	dodge_left -= dt
	think_left -= dt
	if think_left > 0.0:
		return
	think_left = Tune.bot_think * randf_range(0.8, 1.2)
	_think()


func _think() -> void:
	var me := fleet.centre()
	var n := fleet.ships.size()

	var target: Fleet = null
	var threat: Fleet = null
	var best := INF
	for other in fleet.world.fleets:
		if other == fleet or not other.alive:
			continue
		var d := me.distance_to(other.centre())
		if d > Tune.bot_sense:
			continue
		var m := other.ships.size()
		if m > n * 1.5 + 2 and d < 700.0:
			if threat == null or d < me.distance_to(threat.centre()):
				threat = other
		elif d - (200.0 if other.is_player else 0.0) < best:
			best = d
			target = other

	if dodge_left <= 0.0 and randf() < Tune.bot_dodge_chance:
		var incoming := _incoming_bolt()
		if incoming != Vector2.ZERO:
			dodge_left = 0.5
			dodge_dir = incoming.orthogonal().normalized() * (1.0 if randf() < 0.5 else -1.0)

	if threat != null:
		var away := (me - threat.centre()).normalized()
		fleet.move_to = me + away * 500.0
		fleet.face_to = fleet.move_to
		if me.distance_to(threat.centre()) < 420.0:
			fleet.want_boost = true
	elif target != null:
		var d := me.distance_to(target.centre())
		var lead := target.centre() + target.anchor_vel * (d / Tune.laser_speed)
		fleet.face_to = lead
		var to := (target.centre() - me).normalized()
		if d > 520.0:
			fleet.move_to = target.centre()
		else:
			# Hold range and circle so they have to dodge too.
			if randf() < 0.05:
				strafe_sign = -strafe_sign
			fleet.move_to = me + to.orthogonal() * strafe_sign * 260.0 - to * (420.0 - d)
		var aim := absf(angle_difference(fleet.heading, (lead - me).angle()))
		if d < Tune.bot_fire_range and aim < deg_to_rad(Tune.bot_aim_tolerance_deg) and randf() < Tune.bot_fire_chance:
			fleet.want_fire = true
	else:
		if me.distance_to(wander) < 200.0:
			_new_wander()
		fleet.move_to = wander
		fleet.face_to = wander

	if dodge_left > 0.0:
		fleet.move_to = me + dodge_dir * 300.0

	# Stay off the walls.
	var h := Tune.arena_half - 250.0
	fleet.move_to = fleet.move_to.clamp(Vector2(-h, -h), Vector2(h, h))


## Velocity of the nearest enemy bolt heading at us, or ZERO.
func _incoming_bolt() -> Vector2:
	var lz := fleet.world.lasers
	var me := fleet.centre()
	var best := 260.0 * 260.0
	var found := Vector2.ZERO
	for i in lz.pos.size():
		if lz.fleet_id[i] == fleet.id:
			continue
		var rel := me - lz.pos[i]
		var d2 := rel.length_squared()
		if d2 < best and rel.dot(lz.vel[i]) > 0.0 and absf(rel.cross(lz.vel[i].normalized())) < 90.0:
			best = d2
			found = lz.vel[i]
	return found
