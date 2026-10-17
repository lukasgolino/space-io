class_name Fleet
extends RefCounted
## A fleet: an anchor point that steers like one craft, plus the ships swarming around it.
## Controllers (player input or bot brain) only set move_to / face_to / want_fire / want_boost.

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

var fire_cd := 0.0
var boost_cd := 0.0
var boost_left := 0.0

var brain: BotBrain


func boosting() -> bool:
	return boost_left > 0.0


func speed_cap() -> float:
	return Tune.max_speed * (Tune.boost_mult if boosting() else 1.0)


func fire_ready() -> float:
	return 1.0 - clampf(fire_cd / Tune.fire_cooldown, 0.0, 1.0)


func boost_ready() -> float:
	return 1.0 - clampf(boost_cd / Tune.boost_cooldown, 0.0, 1.0)


## Slot i of a packed wedge (apex = slot 0 at the anchor, rows trailing behind), in world space.
## Row r holds r + 1 ships; a partial last row is centred.
func slot_offset(i: int) -> Vector2:
	return wedge_slot(i, ships.size()).rotated(heading)


static func wedge_slot(i: int, total: int) -> Vector2:
	var row := int((sqrt(8.0 * i + 1.0) - 1.0) / 2.0)
	var first := row * (row + 1) / 2
	var in_row := mini(row + 1, total - first)
	return Vector2(-row * Tune.slot_back, (i - first - (in_row - 1) * 0.5) * Tune.slot_side)


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
		heading = rotate_toward(heading, face.angle(), Tune.fleet_turn_rate * dt)

	if want_fire and fire_cd <= 0.0 and not ships.is_empty():
		fire_cd = Tune.fire_cooldown
		for s in ships:
			s.fire_timer = randf() * Tune.fire_stagger

	for i in ships.size():
		ships[i].step(dt, anchor + slot_offset(i), ships)


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


func centre() -> Vector2:
	return anchor
