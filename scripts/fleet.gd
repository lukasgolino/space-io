class_name Fleet
extends RefCounted
## A fleet: an invisible leader (anchor) that steers like one craft, plus ships that follow it,
## either as a free blob or pulled (softly) into a formation.
## Controllers (player input, network input or bot brain) only set move_to / face_to / want_fire /
## want_boost / coast / formation. On a network client fleets are mirrors filled from snapshots.

enum Formation { BLOB, TRIANGLE, SQUARE, LINE }
const FORMATION_NAMES: Array[String] = ["BLOB", "TRIANGLE", "SQUARE", "LINE"]

var world: World
var id := 0
var team := 0
var name := ""
var peer := 0          # human player's network peer id (1 = host / solo); 0 = bot
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


func is_human() -> bool:
	return peer != 0


func boosting() -> bool:
	return boost_left > 0.0


## 0 for one ship, 1 at the fleet cap.
func size_t() -> float:
	return clampf((ships.size() - 1.0) / maxf(1.0, Tune.max_ships - 1.0), 0.0, 1.0)


## Top speed: bigger fleets are slower (size_slowdown), boost multiplies.
func speed_cap() -> float:
	return Tune.max_speed * (1.0 - Tune.size_slowdown * size_t()) * (Tune.boost_mult if boosting() else 1.0)


## Leader acceleration: bigger fleets accelerate slower (accel_slowdown), boost doubles.
func accel_cap() -> float:
	return Tune.accel * (1.0 - Tune.accel_slowdown * size_t()) * (2.0 if boosting() else 1.0)


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
	var cap := speed_cap()
	var target_speed := cap * clampf(dist / Tune.slow_radius, 0.0, 1.0)
	if boosting():
		target_speed = cap
	var desired := to.normalized() * target_speed if dist > 1.0 else Vector2.ZERO
	if coast:
		desired = anchor_vel.limit_length(cap)
	anchor_vel = anchor_vel.move_toward(desired, accel_cap() * dt)
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

	var n := ships.size()
	if want_fire and fire_cd <= 0.0 and n > 0:
		fire_cd = Tune.fire_cooldown
		for s in ships:
			s.fire_timer = randf() * Tune.fire_stagger
	if n == 0:
		return
	_step_ships(dt, n, cap)


## All ships in one pass: pull to target (leader or slot), pairwise separation, inertia, firing.
func _step_ships(dt: float, n: int, cap: float) -> void:
	var pts := PackedVector2Array()
	pts.resize(n)
	centroid = Vector2.ZERO
	for i in n:
		var p := ships[i].pos
		pts[i] = p
		centroid += p
	centroid /= n

	var want := PackedVector2Array()
	want.resize(n)
	if formation == Formation.BLOB:
		var pull := Tune.blob_pull
		var coh := Tune.blob_cohesion
		for i in n:
			want[i] = (anchor - pts[i]) * pull + (centroid - pts[i]) * coh
	else:
		var slots := _slots(n)
		var k := Tune.formation_strength
		for i in n:
			want[i] = (anchor + slots[i].rotated(heading) - pts[i]) * k

	# Separation, each pair once.
	var sep := Tune.separation
	var sep2 := sep * sep
	var push := Tune.separation_push
	for i in n:
		var pi := pts[i]
		var acc := Vector2.ZERO
		for j in range(i + 1, n):
			var d := pi - pts[j]
			var l2 := d.length_squared()
			if l2 < sep2 and l2 > 0.0001:
				var l := sqrt(l2)
				var f := d * ((1.0 - l / sep) * push / l)
				acc += f
				want[j] -= f
		want[i] += acc

	var vcap := cap * Tune.ship_speed_mult
	var dv := Tune.ship_accel * (2.0 if boosting() else 1.0) * dt
	var turn := Tune.turn_rate
	for i in n:
		var s := ships[i]
		s.vel = s.vel.move_toward(want[i].limit_length(vcap * s.speed_k), dv)
		s.pos = pts[i] + s.vel * dt
		s.position = s.pos
		s.rotation = heading if turn <= 0.0 else rotate_toward(s.rotation, heading, turn * dt)
		if s.fire_timer >= 0.0:
			s.fire_timer -= dt
			if s.fire_timer < 0.0:
				var fwd := Vector2.from_angle(s.rotation)
				world.fire_laser(s.pos + fwd * (Tune.nose_offset + Tune.laser_length * 0.5), fwd * Tune.laser_speed, self)


func add_ship(at: Vector2, uid := -1) -> Ship:
	if uid < 0 and ships.size() >= Tune.max_ships:
		return null
	var s := Ship.new()
	s.uid = uid if uid >= 0 else world.next_ship_uid()
	world.ship_layer.add_child(s)
	s.setup(self, at)
	s.reset_physics_interpolation()
	ships.append(s)
	return s


## Just behind the fleet (relative to its heading), where a recruit joins.
func rear_spot() -> Vector2:
	var fwd := Vector2.from_angle(heading)
	var back := 0.0
	for s in ships:
		back = minf(back, (s.pos - centroid).dot(fwd))
	var side := randf_range(-0.5, 0.5) * Tune.separation
	return centroid + fwd * (back - Tune.separation) + fwd.orthogonal() * side


## Swap-remove so only one ship changes slot.
func remove_ship(s: Ship) -> void:
	var i := ships.find(s)
	if i < 0:
		return
	ships[i] = ships.back()
	ships.pop_back()
	s.dead = true
	s.queue_free()
	if ships.is_empty():
		alive = false


func free_ships() -> void:
	for s in ships:
		s.queue_free()
	ships.clear()


## Where the fleet actually is (its ships' centre); the anchor can run ahead of it.
func centre() -> Vector2:
	return centroid if not ships.is_empty() else anchor
