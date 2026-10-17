class_name Fleet
extends RefCounted
## A fleet: an invisible leader (anchor) that steers like one craft, plus ships that follow it,
## either as a free blob or pulled (softly) into a formation.
## Controllers (player input or bot brain) only set move_to / face_to / want_fire / want_boost / formation.

enum Formation { BLOB, TRIANGLE, SQUARE, LINE }
const FORMATION_NAMES: Array[String] = ["BLOB", "TRIANGLE", "SQUARE", "LINE"]

var world: World
var id := 0
var team := 0
var name := ""
var is_player := false
var ships: Array[Ship] = []
var kills := 0
var alive := true

var anchor := Vector2.ZERO
var anchor_vel := Vector2.ZERO
var heading := 0.0

var move_to := Vector2.ZERO
var face_to := Vector2.ZERO
var want_fire := false
var want_boost := false
var coast := false   # swivel: face face_to but don't steer; momentum carries the fleet

var fire_cd := 0.0
var boost_cd := 0.0
var boost_left := 0.0

var formation := Formation.BLOB
var centroid := Vector2.ZERO

var brain: BotBrain


func boosting() -> bool:
	return boost_left > 0.0


## Top speed: bigger fleets are slower (size_slowdown), boost multiplies.
func speed_cap() -> float:
	var t := clampf((ships.size() - 1.0) / maxf(1.0, Tune.max_ships - 1.0), 0.0, 1.0)
	return Tune.max_speed * (1.0 - Tune.size_slowdown * t) * (Tune.boost_mult if boosting() else 1.0)


func fire_ready() -> float:
	return 1.0 - clampf(fire_cd / Tune.fire_cooldown, 0.0, 1.0)


func boost_ready() -> float:
	return 1.0 - clampf(boost_cd / Tune.boost_cooldown, 0.0, 1.0)


## Formation slots for n ships, local space (x = forward), centred on the origin.
func _slots(n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var sp := Tune.slot_spacing
	match formation:
		Formation.TRIANGLE:   # apex forward, row r holds r + 1 ships
			for i in n:
				var row := int((sqrt(8.0 * i + 1.0) - 1.0) / 2.0)
				var first := row * (row + 1) / 2
				var in_row := mini(row + 1, n - first)
				out.append(Vector2(-row * sp, (i - first - (in_row - 1) * 0.5) * sp))
		Formation.SQUARE:
			var cols := ceili(sqrt(float(n)))
			for i in n:
				var row := i / cols
				var in_row := mini(cols, n - row * cols)
				out.append(Vector2(-row * sp, (i % cols - (in_row - 1) * 0.5) * sp))
		Formation.LINE:       # side by side, all guns forward
			for i in n:
				out.append(Vector2(0.0, (i - (n - 1) * 0.5) * sp))
	var mean := Vector2.ZERO
	for p in out:
		mean += p
	if n > 0:
		mean /= n
	for k in out.size():
		out[k] -= mean
	return out


func step(dt: float) -> void:
	fire_cd = maxf(0.0, fire_cd - dt)
	boost_cd = maxf(0.0, boost_cd - dt)
	boost_left = maxf(0.0, boost_left - dt)

	if want_boost and boost_cd <= 0.0:
		boost_left = Tune.boost_time
		boost_cd = Tune.boost_cooldown
	want_boost = false

	# Anchor: accelerate hard towards move_to, ease to a stop inside slow_radius.
	var to := move_to - anchor
	var dist := to.length()
	var target_speed := speed_cap() * clampf(dist / Tune.slow_radius, 0.0, 1.0)
	if boosting():
		target_speed = speed_cap()
	var desired := to.normalized() * target_speed if dist > 1.0 else Vector2.ZERO
	if coast:
		desired = anchor_vel.limit_length(speed_cap())
	var a := Tune.accel * (2.0 if boosting() else 1.0)
	anchor_vel = anchor_vel.move_toward(desired, a * dt)
	anchor += anchor_vel * dt
	var lim := Tune.arena_half - 60.0
	if absf(anchor.x) > lim:
		anchor.x = clampf(anchor.x, -lim, lim)
		anchor_vel.x = 0.0
	if absf(anchor.y) > lim:
		anchor.y = clampf(anchor.y, -lim, lim)
		anchor_vel.y = 0.0

	var face := face_to - anchor
	if face.length() > 6.0:
		heading = face.angle() if Tune.fleet_turn_rate <= 0.0 else rotate_toward(heading, face.angle(), Tune.fleet_turn_rate * dt)

	if want_fire and fire_cd <= 0.0 and not ships.is_empty():
		fire_cd = Tune.fire_cooldown
		for s in ships:
			s.fire_timer = randf() * Tune.fire_stagger

	centroid = Vector2.ZERO
	for s in ships:
		centroid += s.global_position
	if not ships.is_empty():
		centroid /= ships.size()
	var blob := formation == Formation.BLOB
	var slots := PackedVector2Array() if blob else _slots(ships.size())
	for i in ships.size():
		var target := anchor if blob else anchor + slots[i].rotated(heading)
		ships[i].step(dt, target, centroid, blob, ships)


func add_ship(at: Vector2) -> Ship:
	if ships.size() >= Tune.max_ships:
		return null
	var s := Ship.new()
	world.ship_layer.add_child(s)
	s.setup(self)
	s.global_position = at
	s.reset_physics_interpolation()
	ships.append(s)
	return s


## Swap-remove so only one ship changes slot.
func remove_ship(s: Ship) -> void:
	var i := ships.find(s)
	if i < 0:
		return
	ships[i] = ships.back()
	ships.pop_back()
	s.queue_free()
	if ships.is_empty():
		alive = false


## Where the fleet actually is (its ships' centre); the anchor can run ahead of it.
func centre() -> Vector2:
	return centroid if not ships.is_empty() else anchor
