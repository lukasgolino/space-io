class_name World
extends Node2D
## The match: fleets, lasers, collisions, kills -> recruits, camera, respawns.
## SOLO and HOST run the simulation; CLIENT only mirrors the host (see Net) and sends its controls.

signal player_died(killer_name: String)
signal player_spawned

enum Mode { SOLO, HOST, CLIENT }

const CELL := 64.0
const BOT_NAMES: Array[String] = [
	"Nova", "Vex", "Orion", "Kestrel", "Raptor", "Zenith", "Echo", "Pulsar", "Quasar", "Talon",
	"Drift", "Comet", "Specter", "Halo", "Ion", "Viper", "Nebula", "Flux", "Rogue", "Astra",
	"Blitz", "Corsair", "Wraith", "Nyx", "Solaris", "Vortex", "Arc", "Phantom", "Shard", "Helix",
]


## What a human's input asks for this tick (read from the mouse, or received from a client).
class Controls:
	var move_to := Vector2.ZERO
	var face_to := Vector2.ZERO
	var fire := false
	var swivel := false
	var formation := 0
	var boost_seq := 0   # bumps on each boost press, so a lost packet can't eat a boost
	var steer := false   # false: keep the previous move_to / face_to (mouse over a panel)


## One human player (local or remote) on the simulating side.
class Human:
	var peer := 0
	var name := ""
	var team := 0
	var fleet: Fleet
	var dead_for := 0.0
	var autopilot := false
	var ctl := Controls.new()
	var boost_seen := 0


var mode := Mode.SOLO
## Tests/demo: this machine's fleet is driven by a bot brain instead of the mouse.
var autopilot := false
## Demo/capture: every fleet uses this formation (-1 = blob default).
var force_formation := -1
var local_name := "You"
var my_peer := 1

var fleets: Array[Fleet] = []
var player: Fleet   # this machine's fleet; null on a client until the host sends it
var humans := {}    # peer id -> Human (SOLO/HOST only)
var lasers: Lasers
var ship_layer: Node2D
var fx_layer: Node2D
var camera: Camera2D
var net: Net
var tick := 0
var local_ctl := Controls.new()

var _next_id := 1
var _next_ship_uid := 1
var _bot_respawns: Array[float] = []
var _local_dead_for := 0.0
var _shake := 0.0
var _explosions: Array[AnimatedSprite2D] = []
var _tags := {}   # fleet id -> NameTag
var _arena: Node2D


func _ready() -> void:
	_arena = preload("res://scripts/arena.gd").new()
	add_child(_arena)
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
	Tune.changed.connect(_on_tune_changed)
	local_ctl.formation = maxi(force_formation, 0)

	if mode != Mode.SOLO:
		net = Net.new()
		net.name = "Net"
		net.world = self
		add_child(net)
	if mode == Mode.CLIENT:
		return
	add_human(1, local_name, autopilot)
	for i in Tune.bot_count:
		spawn_bot()


func _on_tune_changed() -> void:
	for f in fleets:
		for s in f.ships:
			s.refresh_look()
	for e in _explosions:
		e.scale = Vector2.ONE * Tune.ship_scale * 1.2
	lasers.refresh_look()
	_arena.queue_redraw()


func _exit_tree() -> void:
	for f in fleets:
		f.brain = null
	fleets.clear()
	humans.clear()


func is_sim() -> bool:
	return mode != Mode.CLIENT


func next_ship_uid() -> int:
	_next_ship_uid += 1
	return _next_ship_uid - 1


# --- humans -------------------------------------------------------------------------------------

func add_human(peer: int, human_name: String, auto := false) -> Human:
	var h := Human.new()
	h.peer = peer
	h.name = human_name
	h.autopilot = auto
	h.team = _free_human_team(peer)
	humans[peer] = h
	_spawn_human(h)
	return h


## Host is cyan; each other human gets a colour no other human has (bots may share it).
func _free_human_team(peer: int) -> int:
	if peer == 1:
		return 0
	var used := {}
	for h: Human in humans.values():
		used[h.team] = true
	for t in range(1, Art.TEAMS.size()):
		if not used.has(t):
			return t
	return 1 + randi() % (Art.TEAMS.size() - 1)


func remove_human(peer: int) -> void:
	var h: Human = humans.get(peer)
	if h == null:
		return
	humans.erase(peer)
	if h.fleet:
		for s in h.fleet.ships:
			explode(s.pos, h.fleet.team)
			if net:
				net.ev_boom(s.pos, h.fleet.team, h.fleet.id)
		h.fleet.free_ships()
		h.fleet.brain = null
		fleets.erase(h.fleet)


func _spawn_human(h: Human) -> void:
	if h.fleet:
		h.fleet.brain = null
		h.fleet.free_ships()
		fleets.erase(h.fleet)
	h.fleet = _make_fleet(h.team, h.name, h.peer, _free_spot(0.0), 1)
	h.dead_for = 0.0
	if h.autopilot:
		h.fleet.brain = BotBrain.new(h.fleet)
	if h.peer == my_peer:
		_set_player(h.fleet)


func _set_player(f: Fleet) -> void:
	player = f
	_local_dead_for = 0.0
	camera.global_position = f.centre()
	camera.reset_physics_interpolation()
	player_spawned.emit()


## Client side: the host replaced our fleet (first join or respawn).
func client_set_player(f: Fleet) -> void:
	_set_player(f)


func can_respawn() -> bool:
	return player != null and not player.alive and _local_dead_for > Tune.respawn_delay


func request_respawn() -> void:
	if not can_respawn():
		return
	if mode == Mode.CLIENT:
		net.send_respawn()
	else:
		respawn_human(my_peer)


## Sim side: respawn if that human is dead long enough.
func respawn_human(peer: int) -> void:
	var h: Human = humans.get(peer)
	if h and not h.fleet.alive and h.dead_for > Tune.respawn_delay:
		_spawn_human(h)


# --- spawning -----------------------------------------------------------------------------------

func spawn_bot() -> void:
	var size: int = Tune.bot_start_sizes.pick_random() if not Tune.bot_start_sizes.is_empty() else 1
	# Bots avoid the human players' colours while any are left.
	var teams := range(1, Art.TEAMS.size()).filter(func(t: int) -> bool:
		return humans.values().all(func(h: Human) -> bool: return h.team != t))
	var team: int = teams.pick_random() if not teams.is_empty() else 1 + randi() % (Art.TEAMS.size() - 1)
	var used := fleets.map(func(f: Fleet) -> String: return f.name)
	var names := BOT_NAMES.filter(func(n: String) -> bool: return not used.has(n))
	var bot_name: String = names.pick_random() if not names.is_empty() else "Bot"
	var f := _make_fleet(team, bot_name, 0, _free_spot(900.0), size)
	f.brain = BotBrain.new(f)


func _make_fleet(team: int, fleet_name: String, peer: int, at: Vector2, size: int) -> Fleet:
	var f := Fleet.new()
	f.world = self
	f.id = _next_id
	_next_id += 1
	f.team = team
	f.name = fleet_name
	f.peer = peer
	f.anchor = at
	f.move_to = at
	f.face_to = at + Vector2.RIGHT
	f.heading = randf() * TAU
	for i in mini(size, Tune.max_ships):
		f.add_ship(at + Vector2.from_angle(randf() * TAU) * sqrt(randf() * size) * Tune.separation * 0.8)
	f.centroid = at
	if force_formation >= 0:
		f.formation = force_formation as Fleet.Formation
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
				d = minf(d, p.distance_to(f.centre()))
		if d >= clearance:
			return p
		if d > best_d:
			best_d = d
			best = p
	return best


# --- tick ---------------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	tick += 1
	_read_local_controls()
	if mode == Mode.CLIENT:
		net.client_tick(dt)
		lasers.step(dt)
	else:
		_sim_tick(dt)
		if mode == Mode.HOST:
			net.host_tick()
	if player and not player.alive:
		_local_dead_for += dt
	_update_camera(dt)
	_update_tags()


func _sim_tick(dt: float) -> void:
	for h: Human in humans.values():
		if h.peer == my_peer and not h.autopilot:
			h.ctl = local_ctl
		if h.fleet.alive and not h.autopilot:
			_apply_controls(h)
	for f in fleets:
		if f.alive:
			if f.brain:
				f.brain.step(dt)
			f.step(dt)
	lasers.step(dt)
	_collide()
	_reap(dt)


func _read_local_controls() -> void:
	var c := local_ctl
	if autopilot:
		# Headless client tests: copy what a bot brain would do with our mirror fleet.
		if mode == Mode.CLIENT and can_respawn():
			request_respawn()
		if mode == Mode.CLIENT and player and player.alive:
			if player.brain == null:
				player.brain = BotBrain.new(player)
			player.brain.step(get_physics_process_delta_time())
			c.steer = true
			c.move_to = player.move_to
			c.face_to = player.face_to
			c.fire = player.want_fire
			c.swivel = player.coast
			if player.want_boost:
				c.boost_seq += 1
				player.want_boost = false
		return
	# Mouse over an open panel (F12): keep course, don't fire.
	c.steer = get_viewport().gui_get_hovered_control() == null
	if c.steer:
		var mouse := get_global_mouse_position()
		c.move_to = mouse
		c.face_to = mouse
	c.fire = c.steer and Input.is_action_pressed("fire")
	c.swivel = Input.is_action_pressed("swivel")
	if Input.is_action_just_pressed("boost"):
		c.boost_seq += 1
	for k in Fleet.FORMATION_NAMES.size():
		if Input.is_action_just_pressed("formation_%d" % (k + 1)):
			c.formation = k


func _apply_controls(h: Human) -> void:
	var f := h.fleet
	var c := h.ctl
	if c.steer:
		f.move_to = c.move_to
		f.face_to = c.face_to
	f.want_fire = c.fire
	f.coast = c.swivel
	f.formation = clampi(c.formation, 0, Fleet.FORMATION_NAMES.size() - 1) as Fleet.Formation
	if c.boost_seq != h.boost_seen:
		h.boost_seen = c.boost_seq
		f.want_boost = true


func fire_laser(at: Vector2, v: Vector2, f: Fleet) -> void:
	var id := lasers.spawn(at, v, f.id, f.team, Tune.laser_life)
	if id >= 0 and net:
		net.ev_laser(id, f.id, f.team, at, v)


func _collide() -> void:
	var grid := {}
	for f in fleets:
		for s in f.ships:
			var key := _cell_key(floori(s.pos.x / CELL), floori(s.pos.y / CELL))
			var cell: Variant = grid.get(key)
			if cell == null:
				grid[key] = [s]
			else:
				cell.append(s)
	var r := Tune.hit_radius
	var r2 := r * r
	var hl := Tune.laser_length * 0.5
	var i := 0
	while i < lasers.pos.size():
		var p := lasers.pos[i]
		var half := lasers.vel[i].normalized() * hl
		var a := p - half
		var ab := half * 2.0
		var ab2 := maxf(ab.length_squared(), 0.0001)
		var fid := lasers.fleet_id[i]
		var hit: Ship = null
		# Only the cells the segment (+ hit radius) can touch: usually 1-4, not 9.
		var x0 := floori((minf(a.x, a.x + ab.x) - r) / CELL)
		var x1 := floori((maxf(a.x, a.x + ab.x) + r) / CELL)
		var y0 := floori((minf(a.y, a.y + ab.y) - r) / CELL)
		var y1 := floori((maxf(a.y, a.y + ab.y) + r) / CELL)
		for gx in range(x0, x1 + 1):
			for gy in range(y0, y1 + 1):
				var cell: Variant = grid.get(_cell_key(gx, gy))
				if cell == null:
					continue
				for s: Ship in cell:
					if s.dead or s.fleet.id == fid:
						continue
					var t := clampf((s.pos - a).dot(ab) / ab2, 0.0, 1.0)
					if s.pos.distance_squared_to(a + ab * t) < r2:
						hit = s
						break
				if hit:
					break
			if hit:
				break
		if hit:
			if net:
				net.ev_hit(lasers.uid[i])
			_kill(hit, fid)
			lasers.remove(i)
		else:
			i += 1


static func _cell_key(cx: int, cy: int) -> int:
	return (cx + 32768) * 65536 + (cy + 32768)


func _kill(s: Ship, killer_id: int) -> void:
	var victim := s.fleet
	var at := s.pos
	explode(at, victim.team)
	if net:
		net.ev_boom(at, victim.team, victim.id)
	victim.remove_ship(s)
	if victim == player:
		_shake = Tune.shake_on_loss
	var killer := fleet_by_id(killer_id)
	if killer and killer.alive:
		killer.kills += 1
		# The victim's ship is destroyed; a fresh one joins the killer from behind its fleet.
		var r := killer.add_ship(killer.rear_spot())
		if r:
			r.vel = killer.anchor_vel
			r.pop_in()
	if not victim.alive and victim.is_human():
		var by := killer.name if killer else "?"
		if victim == player:
			player_died.emit(by)
		if net:
			net.ev_died(victim.id, by)


func fleet_by_id(fid: int) -> Fleet:
	for f in fleets:
		if f.id == fid:
			return f
	return null


func _reap(dt: float) -> void:
	for f in fleets.duplicate():
		if not f.alive and not f.is_human():
			f.brain = null   # break the fleet <-> brain reference cycle
			fleets.erase(f)
			_bot_respawns.append(Tune.bot_respawn_delay)
	for k in range(_bot_respawns.size() - 1, -1, -1):
		_bot_respawns[k] -= dt
		if _bot_respawns[k] <= 0.0:
			_bot_respawns.remove_at(k)
			spawn_bot()
	for h: Human in humans.values():
		if not h.fleet.alive:
			h.dead_for += dt
			if h.autopilot and h.dead_for > Tune.respawn_delay:
				_spawn_human(h)


func _unhandled_input(event: InputEvent) -> void:
	if can_respawn() and (event.is_action_pressed("fire") or event.is_action_pressed("boost")):
		request_respawn()
		get_viewport().set_input_as_handled()


func _update_camera(dt: float) -> void:
	if player == null:
		return
	var z := lerpf(Tune.zoom_one_ship, Tune.zoom_full_fleet, player.size_t())
	camera.zoom = camera.zoom.lerp(Vector2(z, z), 1.0 - exp(-3.0 * dt))
	camera.global_position = camera.global_position.lerp(player.centre(), 1.0 - exp(-10.0 * dt))
	_shake = maxf(0.0, _shake - 30.0 * dt)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake


## Shake the camera (client: our ship was hit).
func shake() -> void:
	_shake = Tune.shake_on_loss


## Names above human fleets (bots have none). Updated per physics tick so they interpolate.
func _update_tags() -> void:
	var seen := {}
	for f in fleets:
		if not f.is_human() or f.ships.is_empty():
			continue
		seen[f.id] = true
		var tag: NameTag = _tags.get(f.id)
		var top := INF
		for s in f.ships:
			top = minf(top, s.pos.y)
		var at := Vector2(f.centroid.x, top - 26.0)
		if tag == null:
			tag = NameTag.new()
			tag.text = f.name
			tag.color = Color.WHITE if f == player else Art.color(f.team)
			fx_layer.add_child(tag)
			_tags[f.id] = tag
			tag.position = at
			tag.reset_physics_interpolation()
		tag.position = at
		tag.scale = Vector2.ONE / camera.zoom.x
	for id: int in _tags.keys():
		if not seen.has(id):
			_tags[id].queue_free()
			_tags.erase(id)


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
