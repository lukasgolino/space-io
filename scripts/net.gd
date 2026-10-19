class_name Net
extends Node
## Host-authoritative networking over ENet (UDP). The host runs the whole match (bots included);
## clients send their controls every tick and draw the host's snapshots DELAY_TICKS in the past,
## interpolated, replaying laser / hit / explosion events at the tick they happened.
## Wire format: hand-packed StreamPeerBuffer (see encode_snapshot / the ev_* writers).

signal failed(message: String)

const DEFAULT_PORT := 24565
const PROTOCOL := 1            # bump on any wire change; mismatched clients are turned away
const MAX_CLIENTS := 7         # 8 humans = 8 distinct colours
const SEND_EVERY := 2          # physics ticks per snapshot (30 Hz at 60 ticks/s)
const DELAY_TICKS := 6.0       # client view lag behind the newest snapshot (100 ms)
const CONNECT_TIMEOUT := 10.0
const TUNE_INTERVAL := 0.2     # host re-sends changed settings at most this often, s
const MAX_NAME := 16

enum Ev { LASER, HIT, BOOM, DIED }

var world: World
var port := 0

# Host
var _peers := {}                        # peers that said hello and get state
var _ev := StreamPeerBuffer.new()
var _ev_count := 0
var _tune_dirty := false
var _tune_wait := 0.0

# Client
var connected := false
var snapshots_received := 0
var events_received := 0
var render_tick := -1.0
var _snaps: Array[Dictionary] = []      # decoded, oldest first
var _pending: Array = []                # [tick, Ev, ...], in tick order
var _pending_head := 0
var _latest := -1
var _mirror := {}                       # fleet id -> Fleet
var _ships := {}                        # ship uid -> Ship
var _connect_left := 0.0
var _own_tune := {}                     # our settings, restored when we leave
var _failed := false
var _lan := PackedStringArray()


# --- setup --------------------------------------------------------------------------------------

func host(listen_port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(listen_port, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	port = listen_port
	_lan = lan_addresses()
	multiplayer.peer_disconnected.connect(_on_peer_left)
	Tune.changed.connect(_on_tune_changed)
	world.my_peer = 1
	return OK


func join(address: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_left)
	world.my_peer = multiplayer.get_unique_id()
	_connect_left = CONNECT_TIMEOUT
	_own_tune = Tune.values()
	return OK


func _exit_tree() -> void:
	for pair: Array in [
		[multiplayer.peer_disconnected, _on_peer_left], [multiplayer.connected_to_server, _on_connected],
		[multiplayer.connection_failed, _on_connection_failed], [multiplayer.server_disconnected, _on_server_left],
		[Tune.changed, _on_tune_changed]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	if not _own_tune.is_empty():
		Tune.locked = false
		Tune.apply_values(_own_tune)


## Round trip to the host in ms (client), or -1.
func ping_ms() -> int:
	var p := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if p == null or not connected:
		return -1
	var host_peer := p.get_peer(1)
	return int(host_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if host_peer else -1


func lan() -> PackedStringArray:
	return _lan


func client_count() -> int:
	return _peers.size()


## IPv4 addresses friends on the same network can use (host HUD).
static func lan_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


## "host", "host:port" -> [host, port].
static func parse_address(text: String) -> Array:
	var t := text.strip_edges()
	var port := DEFAULT_PORT
	var i := t.rfind(":")
	if i > 0 and t.count(":") == 1 and t.substr(i + 1).is_valid_int():
		port = t.substr(i + 1).to_int()
		t = t.substr(0, i)
	return [t if t != "" else "127.0.0.1", port]


static func clean_name(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges():
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			out += ch
	out = out.strip_edges().left(MAX_NAME)
	return out if out != "" else "Pilot"


# --- host ---------------------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _hello(protocol: int, player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		_kick.rpc_id(peer, "version mismatch (host v%d, you v%d): use the same build" % [PROTOCOL, protocol])
		get_tree().create_timer(0.5).timeout.connect(_drop.bind(peer))
		return
	if _peers.has(peer):
		return
	_peers[peer] = true
	world.add_human(peer, _unique_name(clean_name(player_name)))
	_tune.rpc_id(peer, Tune.values())
	# Bolts already in flight, so the newcomer sees them too.
	var b := StreamPeerBuffer.new()
	var lz := world.lasers
	for i in lz.pos.size():
		_put_laser(b, lz.uid[i], lz.fleet_id[i], lz.team[i], lz.pos[i], lz.vel[i], lz.life[i])
	if lz.pos.size() > 0:
		_events.rpc_id(peer, _batch(world.tick, lz.pos.size(), b.data_array))


func _unique_name(n: String) -> String:
	var taken := {}
	for h: World.Human in world.humans.values():
		taken[h.name] = true
	var out := n
	var k := 2
	while taken.has(out):
		out = "%s %d" % [n.left(MAX_NAME - 3), k]
		k += 1
	return out


func _drop(peer: int) -> void:
	var p := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if p:
		p.disconnect_peer(peer)


func _on_peer_left(peer: int) -> void:
	_peers.erase(peer)
	world.remove_human(peer)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _ctl(move_to: Vector2, face_to: Vector2, bits: int, boost_seq: int) -> void:
	var h: World.Human = world.humans.get(multiplayer.get_remote_sender_id())
	if h == null or not move_to.is_finite() or not face_to.is_finite():
		return
	var lim := Tune.arena_half * 2.0
	var c := h.ctl
	c.move_to = move_to.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	c.face_to = face_to.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	c.fire = bits & 1 != 0
	c.swivel = bits & 2 != 0
	c.steer = bits & 4 != 0
	c.formation = (bits >> 3) & 3
	c.boost_seq = boost_seq


@rpc("any_peer", "call_remote", "reliable")
func _respawn() -> void:
	if multiplayer.is_server():
		world.respawn_human(multiplayer.get_remote_sender_id())


func _on_tune_changed() -> void:
	_tune_dirty = true


## After each host sim tick: events of this tick, a snapshot every SEND_EVERY ticks, settings.
func host_tick() -> void:
	if _peers.is_empty():
		_ev.clear()
		_ev_count = 0
		return
	if _ev_count > 0:
		var data := _batch(world.tick, _ev_count, _ev.data_array)
		for p: int in _peers:
			_events.rpc_id(p, data)
		_ev.clear()
		_ev_count = 0
	if world.tick % SEND_EVERY == 0:
		var snap := encode_snapshot(world)
		for p: int in _peers:
			_snapshot.rpc_id(p, snap)
	_tune_wait -= get_physics_process_delta_time()
	if _tune_dirty and _tune_wait <= 0.0:
		_tune_dirty = false
		_tune_wait = TUNE_INTERVAL
		var v := Tune.values()
		for p: int in _peers:
			_tune.rpc_id(p, v)


static func _batch(tick: int, count: int, body: PackedByteArray) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(tick)
	b.put_u32(count)
	b.put_data(body)
	return b.data_array


func _recording() -> bool:
	return not _peers.is_empty()


func ev_laser(uid: int, fid: int, team: int, at: Vector2, v: Vector2) -> void:
	if _recording():
		_put_laser(_ev, uid, fid, team, at, v, Tune.laser_life)
		_ev_count += 1


static func _put_laser(b: StreamPeerBuffer, uid: int, fid: int, team: int, at: Vector2, v: Vector2, life: float) -> void:
	b.put_u8(Ev.LASER)
	b.put_u32(uid)
	b.put_u32(fid)
	b.put_u8(team)
	b.put_float(at.x)
	b.put_float(at.y)
	b.put_float(v.x)
	b.put_float(v.y)
	b.put_float(life)


func ev_hit(laser_uid: int) -> void:
	if _recording():
		_ev.put_u8(Ev.HIT)
		_ev.put_u32(laser_uid)
		_ev_count += 1


func ev_boom(at: Vector2, team: int, victim_fid: int) -> void:
	if _recording():
		_ev.put_u8(Ev.BOOM)
		_ev.put_float(at.x)
		_ev.put_float(at.y)
		_ev.put_u8(team)
		_ev.put_u32(victim_fid)
		_ev_count += 1


func ev_died(fid: int, by: String) -> void:
	if _recording():
		_ev.put_u8(Ev.DIED)
		_ev.put_u32(fid)
		_ev.put_utf8_string(by)
		_ev_count += 1


## Every fleet: header + ships. Ships go in uid order as u16 uid deltas (escape 0xFFFF + u32) and
## an offset from the anchor in 1/4 px as int16 pairs: ~6 bytes a ship.
static func encode_snapshot(w: World) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(w.tick)
	b.put_u16(w.fleets.size())
	for f in w.fleets:
		b.put_u32(f.id)
		b.put_u8(f.team)
		b.put_u32(f.peer)
		b.put_u8((1 if f.alive else 0) | (f.formation << 1))
		b.put_u16(mini(f.kills, 65535))
		b.put_utf8_string(f.name)
		b.put_float(f.anchor.x)
		b.put_float(f.anchor.y)
		b.put_u16(int(fposmod(f.heading, TAU) / TAU * 65535.0))
		b.put_u8(roundi(clampf(f.fire_cd / maxf(Tune.fire_cooldown, 0.001), 0.0, 1.0) * 255.0))
		b.put_u8(roundi(clampf(f.boost_cd / maxf(Tune.boost_cooldown, 0.001), 0.0, 1.0) * 255.0))
		b.put_u8(1 if f.boosting() else 0)
		var order := PackedInt64Array()
		for i in f.ships.size():
			order.append(f.ships[i].uid * 1024 + i)
		order.sort()
		b.put_u16(order.size())
		var prev := 0
		for key in order:
			var s := f.ships[key % 1024]
			var d := s.uid - prev
			if d >= 0 and d < 65535:
				b.put_u16(d)
			else:
				b.put_u16(65535)
				b.put_u32(s.uid)
			prev = s.uid
			var o := (s.pos - f.anchor) * 4.0
			b.put_16(clampi(roundi(o.x), -32767, 32767))
			b.put_16(clampi(roundi(o.y), -32767, 32767))
	return b.data_array


static func decode_snapshot(data: PackedByteArray) -> Dictionary:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var snap := {"tick": b.get_u32(), "fleets": {}}
	for k in b.get_u16():
		var f := {}
		f.id = b.get_u32()
		f.team = clampi(b.get_u8(), 0, Art.TEAMS.size() - 1)
		f.peer = b.get_u32()
		var flags := b.get_u8()
		f.alive = flags & 1 != 0
		f.formation = (flags >> 1) & 3
		f.kills = b.get_u16()
		f.name = b.get_utf8_string()
		f.anchor = Vector2(b.get_float(), b.get_float())
		f.heading = b.get_u16() / 65535.0 * TAU
		f.fire_cd = b.get_u8() / 255.0 * Tune.fire_cooldown
		f.boost_cd = b.get_u8() / 255.0 * Tune.boost_cooldown
		f.boost_left = Tune.boost_time if b.get_u8() != 0 else 0.0
		var ships := {}
		var uid := 0
		for i in b.get_u16():
			var d := b.get_u16()
			uid = b.get_u32() if d == 65535 else uid + d
			ships[uid] = f.anchor + Vector2(b.get_16(), b.get_16()) * 0.25
		f.ships = ships
		snap.fleets[f.id] = f
	return snap


# --- client -------------------------------------------------------------------------------------

## First reason wins (a kick is followed by a disconnect).
func _fail(message: String) -> void:
	if not _failed:
		_failed = true
		failed.emit(message)


func _on_connected() -> void:
	connected = true
	_hello.rpc_id(1, PROTOCOL, world.local_name)


func _on_connection_failed() -> void:
	_fail("could not connect: wrong address, host not running, port blocked, or game full")


func _on_server_left() -> void:
	_fail("the host left the game")


@rpc("authority", "call_remote", "reliable")
func _kick(message: String) -> void:
	_fail(message)


@rpc("authority", "call_remote", "reliable")
func _tune(values: Dictionary) -> void:
	Tune.locked = true
	Tune.apply_values(values)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _snapshot(data: PackedByteArray) -> void:
	var s := decode_snapshot(data)
	if s.tick <= _latest:
		return
	_latest = s.tick
	_snaps.append(s)
	snapshots_received += 1
	if render_tick < 0.0:
		render_tick = _latest - DELAY_TICKS


@rpc("authority", "call_remote", "reliable")
func _events(data: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var tick := b.get_u32()
	for k in b.get_u32():
		var type := b.get_u8()
		match type:
			Ev.LASER:
				_pending.append([tick, type, b.get_u32(), b.get_u32(), clampi(b.get_u8(), 0, Art.TEAMS.size() - 1),
					Vector2(b.get_float(), b.get_float()), Vector2(b.get_float(), b.get_float()), b.get_float()])
			Ev.HIT:
				_pending.append([tick, type, b.get_u32()])
			Ev.BOOM:
				_pending.append([tick, type, Vector2(b.get_float(), b.get_float()), clampi(b.get_u8(), 0, Art.TEAMS.size() - 1), b.get_u32()])
			Ev.DIED:
				_pending.append([tick, type, b.get_u32(), b.get_utf8_string()])
			_:
				push_warning("bad event type %d" % type)
				return
		events_received += 1


func send_respawn() -> void:
	if connected:
		_respawn.rpc_id(1)


## Each client physics tick: send controls, advance the view clock, apply state and due events.
func client_tick(dt: float) -> void:
	if not connected:
		_connect_left -= dt
		if _connect_left <= 0.0:
			_connect_left = INF
			_fail("no answer from the host")
		return
	var c := world.local_ctl
	var bits := (1 if c.fire else 0) | (2 if c.swivel else 0) | (4 if c.steer else 0) | (c.formation << 3)
	_ctl.rpc_id(1, c.move_to, c.face_to, bits, c.boost_seq)

	if _snaps.is_empty():
		return
	var tps := float(Engine.physics_ticks_per_second)
	render_tick += dt * tps
	var err := (_latest - DELAY_TICKS) - render_tick
	render_tick += err if absf(err) > 20.0 else err * 0.05
	while _snaps.size() >= 2 and _snaps[1].tick <= render_tick:
		_snaps.pop_front()
	var a := _snaps[0]
	var b := _snaps[1] if _snaps.size() >= 2 else a
	var alpha := 0.0 if b == a else clampf((render_tick - a.tick) / float(b.tick - a.tick), 0.0, 1.0)
	_apply(a, b, alpha)
	_run_events(tps)


## Mirror fleets/ships = snapshot a, positions lerped towards b.
func _apply(a: Dictionary, b: Dictionary, alpha: float) -> void:
	var seen := {}
	for id: int in a.fleets:
		var fa: Dictionary = a.fleets[id]
		var fb: Dictionary = b.fleets.get(id, fa)
		var f: Fleet = _mirror.get(id)
		var fresh := f == null
		if fresh:
			f = Fleet.new()
			f.world = world
			f.id = id
			f.team = fa.team
			f.name = fa.name
			f.peer = fa.peer
			_mirror[id] = f
			world.fleets.append(f)
		seen[id] = true
		f.alive = fa.alive
		f.kills = fa.kills
		f.formation = fa.formation
		f.fire_cd = fa.fire_cd
		f.boost_cd = fa.boost_cd
		f.boost_left = fa.boost_left
		f.anchor = fa.anchor.lerp(fb.anchor, alpha)
		f.heading = lerp_angle(fa.heading, fb.heading, alpha)

		var sa: Dictionary = fa.ships
		var sb: Dictionary = fb.ships
		for uid: int in sa:
			var p: Vector2 = sa[uid]
			if sb.has(uid):
				p = p.lerp(sb[uid], alpha)
			var s: Ship = _ships.get(uid)
			if s == null:
				s = f.add_ship(p, uid)
				_ships[uid] = s
				if not fresh:
					s.pop_in()
			s.pos = p
			s.position = p
			s.rotation = f.heading
		var centroid := Vector2.ZERO
		for i in range(f.ships.size() - 1, -1, -1):
			var s := f.ships[i]
			if sa.has(s.uid):
				centroid += s.pos
			else:
				f.ships.remove_at(i)
				_ships.erase(s.uid)
				s.queue_free()
		f.centroid = centroid / f.ships.size() if not f.ships.is_empty() else f.anchor
		if f.peer == world.my_peer and f != world.player:
			world.client_set_player(f)

	for id: int in _mirror.keys():
		if not seen.has(id):
			var f: Fleet = _mirror[id]
			for s in f.ships:
				_ships.erase(s.uid)
			f.brain = null
			f.free_ships()
			world.fleets.erase(f)
			_mirror.erase(id)


func _run_events(tps: float) -> void:
	var lz := world.lasers
	while _pending_head < _pending.size() and _pending[_pending_head][0] <= render_tick:
		var e: Array = _pending[_pending_head]
		_pending_head += 1
		match e[1]:
			Ev.LASER:
				var age: float = (render_tick - e[0]) / tps
				if e[7] - age > 0.0:
					lz.spawn(e[5] + e[6] * age, e[6], e[3], e[4], e[7] - age, e[2])
			Ev.HIT:
				lz.remove_uid(e[2])
			Ev.BOOM:
				world.explode(e[2], e[3])
				if world.player and e[4] == world.player.id:
					world.shake()
			Ev.DIED:
				if world.player and e[2] == world.player.id:
					world.player_died.emit(e[3])
	if _pending_head > 512:
		_pending = _pending.slice(_pending_head)
		_pending_head = 0
