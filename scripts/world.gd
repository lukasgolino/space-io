class_name World
extends Node2D
## The match: fleets, lasers, collisions, kills -> recruits, camera, respawns.

signal player_died(killer_name: String)
signal player_spawned

const CELL := 64.0
const BOT_NAMES: Array[String] = [
	"Nova", "Vex", "Orion", "Kestrel", "Raptor", "Zenith", "Echo", "Pulsar", "Quasar", "Talon",
	"Drift", "Comet", "Specter", "Halo", "Ion", "Viper", "Nebula", "Flux", "Rogue", "Astra",
	"Blitz", "Corsair", "Wraith", "Nyx", "Solaris", "Vortex", "Arc", "Phantom", "Shard", "Helix",
]

## Headless tests set this: the player fleet is driven by a bot brain instead of the mouse.
var autopilot := false

var fleets: Array[Fleet] = []
var player: Fleet
var lasers: Lasers
var ship_layer: Node2D
var fx_layer: Node2D
var camera: Camera2D

var _next_id := 1
var _bot_respawns: Array[float] = []
var _player_dead_for := 0.0
var _shake := 0.0
var _explosions: Array[AnimatedSprite2D] = []


func _ready() -> void:
	add_child(preload("res://scripts/arena.gd").new())
	ship_layer = Node2D.new()
	add_child(ship_layer)
	lasers = Lasers.new()
	add_child(lasers)
	fx_layer = Node2D.new()
	add_child(fx_layer)
	camera = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	add_child(camera)
	camera.make_current()

	spawn_player()
	for i in Tune.bot_count:
		spawn_bot()


func _exit_tree() -> void:
	for f in fleets:
		f.brain = null
	fleets.clear()


func spawn_player() -> void:
	player = _make_fleet(0, "You", true, _free_spot(0.0), 1)
	if autopilot:
		player.brain = BotBrain.new(player)
	camera.global_position = player.anchor
	camera.reset_physics_interpolation()
	_player_dead_for = 0.0
	player_spawned.emit()


func spawn_bot() -> void:
	var size: int = Tune.bot_start_sizes.pick_random()
	var team := 1 + randi() % (Art.TEAMS.size() - 1)
	var used := fleets.map(func(f: Fleet) -> String: return f.name)
	var names := BOT_NAMES.filter(func(n: String) -> bool: return not used.has(n))
	var bot_name: String = names.pick_random() if not names.is_empty() else "Bot"
	var f := _make_fleet(team, bot_name, false, _free_spot(900.0), size)
	f.brain = BotBrain.new(f)


func _make_fleet(team: int, fleet_name: String, is_player: bool, at: Vector2, size: int) -> Fleet:
	var f := Fleet.new()
	f.world = self
	f.id = _next_id
	_next_id += 1
	f.team = team
	f.name = fleet_name
	f.is_player = is_player
	f.anchor = at
	f.move_to = at
	f.face_to = at + Vector2.RIGHT
	f.heading = randf() * TAU
	for i in size:
		f.add_ship(at + Fleet.wedge_slot(i, size).rotated(f.heading))
	fleets.append(f)
	return f


## A random point at least `clearance` from every fleet (best of a few tries).
func _free_spot(clearance: float) -> Vector2:
	var h := Tune.arena_half - 400.0
	var best := Vector2.ZERO
	var best_d := -1.0
	for attempt in 24:
		var p := Vector2(randf_range(-h, h), randf_range(-h, h))
		var d := INF
		for f in fleets:
			if f.alive:
				d = minf(d, p.distance_to(f.anchor))
		if d >= clearance:
			return p
		if d > best_d:
			best_d = d
			best = p
	return best


func _physics_process(dt: float) -> void:
	if player.alive and not autopilot:
		var mouse := get_global_mouse_position()
		player.move_to = mouse
		player.face_to = mouse
		player.want_fire = Input.is_action_pressed("fire")
		if Input.is_action_just_pressed("boost"):
			player.want_boost = true

	for f in fleets:
		if f.alive:
			if f.brain:
				f.brain.step(dt)
			f.step(dt)
	lasers.step(dt)
	_collide()
	_reap(dt)
	_update_camera(dt)


func _collide() -> void:
	var grid := {}
	for f in fleets:
		for s in f.ships:
			var c := Vector2i(floori(s.global_position.x / CELL), floori(s.global_position.y / CELL))
			if grid.has(c):
				grid[c].append(s)
			else:
				grid[c] = [s]
	var r2 := Tune.hit_radius * Tune.hit_radius
	var i := 0
	while i < lasers.pos.size():
		var p := lasers.pos[i]
		var half := lasers.vel[i].normalized() * (Tune.laser_length * 0.5)
		var cx := floori(p.x / CELL)
		var cy := floori(p.y / CELL)
		var hit: Ship = null
		for gx in range(cx - 1, cx + 2):
			for gy in range(cy - 1, cy + 2):
				var cell: Variant = grid.get(Vector2i(gx, gy))
				if cell == null:
					continue
				for s: Ship in cell:
					if not s.is_queued_for_deletion() and s.fleet.id != lasers.fleet_id[i] \
							and s.global_position.distance_squared_to(
								Geometry2D.get_closest_point_to_segment(s.global_position, p - half, p + half)) < r2:
						hit = s
						break
				if hit:
					break
			if hit:
				break
		if hit:
			_kill(hit, lasers.fleet_id[i])
			lasers.remove(i)
		else:
			i += 1


func _kill(s: Ship, killer_id: int) -> void:
	var victim := s.fleet
	var at := s.global_position
	explode(at, victim.team)
	victim.remove_ship(s)
	if victim.is_player:
		_shake = Tune.shake_on_loss
	var killer := fleet_by_id(killer_id)
	if killer and killer.alive:
		killer.kills += 1
		killer.add_ship(at)
	if not victim.alive and victim.is_player:
		player_died.emit(killer.name if killer else "?")


func fleet_by_id(fid: int) -> Fleet:
	for f in fleets:
		if f.id == fid:
			return f
	return null


func _reap(dt: float) -> void:
	for f in fleets.duplicate():
		if not f.alive and not f.is_player:
			f.brain = null   # break the fleet <-> brain reference cycle
			fleets.erase(f)
			_bot_respawns.append(Tune.bot_respawn_delay)
	for k in range(_bot_respawns.size() - 1, -1, -1):
		_bot_respawns[k] -= dt
		if _bot_respawns[k] <= 0.0:
			_bot_respawns.remove_at(k)
			spawn_bot()
	if not player.alive:
		_player_dead_for += dt
		if autopilot and _player_dead_for > Tune.respawn_delay:
			respawn_player()


func can_respawn() -> bool:
	return not player.alive and _player_dead_for > Tune.respawn_delay


func respawn_player() -> void:
	player.brain = null
	fleets.erase(player)
	spawn_player()


func _unhandled_input(event: InputEvent) -> void:
	if can_respawn() and (event.is_action_pressed("fire") or event.is_action_pressed("boost")):
		respawn_player()
		get_viewport().set_input_as_handled()


func _update_camera(dt: float) -> void:
	var n := player.ships.size()
	var t := clampf((n - 1.0) / (Tune.max_ships - 1.0), 0.0, 1.0)
	var z := lerpf(Tune.zoom_one_ship, Tune.zoom_full_fleet, t)
	camera.zoom = camera.zoom.lerp(Vector2(z, z), 1.0 - exp(-3.0 * dt))
	camera.global_position = camera.global_position.lerp(player.anchor, 1.0 - exp(-10.0 * dt))
	_shake = maxf(0.0, _shake - 30.0 * dt)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake


func explode(at: Vector2, team: int) -> void:
	var e: AnimatedSprite2D = null
	for x in _explosions:
		if not x.visible:
			e = x
			break
	if e == null:
		e = AnimatedSprite2D.new()
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		e.material = mat
		e.modulate = Color(1.5, 1.5, 1.5)
		e.scale = Vector2.ONE * Tune.ship_scale * 1.2
		e.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		e.animation_finished.connect(func() -> void: e.visible = false)
		fx_layer.add_child(e)
		_explosions.append(e)
	e.sprite_frames = Art.frames("explosion", team)
	e.global_position = at
	e.rotation = randf() * TAU
	e.visible = true
	e.play("burst")
	e.frame = 0


## Fleets sorted by size, biggest first.
func leaderboard() -> Array[Fleet]:
	var alive_fleets: Array[Fleet] = []
	for f in fleets:
		if f.alive:
			alive_fleets.append(f)
	alive_fleets.sort_custom(func(a: Fleet, b: Fleet) -> bool:
		return a.ships.size() > b.ships.size() or (a.ships.size() == b.ships.size() and a.kills > b.kills))
	return alive_fleets
