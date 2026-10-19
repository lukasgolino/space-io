extends Node
## Rule-level checks, each on a fresh world with no bots. Prints UNIT_TEST PASS/FAIL.
## godot --headless --path . res://tests/unit_test.tscn

var fails: Array[String] = []
var _current := ""


func _ready() -> void:
	seed(7)
	var saved := Tune.values()
	for t: String in [
		"test_slots", "test_speed_and_accel_scale", "test_recruit_spawns_behind_killer",
		"test_recruit_respects_cap", "test_collision_hits_enemy_not_self", "test_kill_credit_and_death",
		"test_laser_pool", "test_tune_values_roundtrip", "test_tune_file_adds_missing_keys",
		"test_snapshot_codec", "test_address_and_names", "test_human_respawn_delay",
		"test_remove_human", "test_controls_boost_once", "test_tune_panel_reset_only_its_keys"]:
		_current = t
		Tune.apply_values(saved)
		call(t)
	Tune.apply_values(saved)
	for f in fails:
		printerr("FAIL: ", f)
	print("UNIT_TEST ", "PASS" if fails.is_empty() else "FAIL")
	get_tree().quit(0 if fails.is_empty() else 1)


func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append("%s: %s" % [_current, what])


## A world with no bots and no human fleet: tests add exactly what they need.
func make_world() -> World:
	var w := World.new()
	var bots := Tune.bot_count
	Tune.bot_count = 0
	add_child(w)
	Tune.bot_count = bots
	w.remove_human(1)
	w.player = null
	w.set_physics_process(false)
	return w


func done(w: World) -> void:
	remove_child(w)
	w.free()


func test_slots() -> void:
	var f := Fleet.new()
	for form in [Fleet.Formation.TRIANGLE, Fleet.Formation.SQUARE, Fleet.Formation.LINE]:
		f.formation = form
		for n in range(1, 31):
			var s := f._slots(n)
			check(s.size() == n, "%s n=%d gave %d slots" % [Fleet.FORMATION_NAMES[form], n, s.size()])
			var mean := Vector2.ZERO
			var uniq := {}
			for p in s:
				mean += p
				uniq[p.snapped(Vector2(0.01, 0.01))] = true
			check((mean / n).length() < 0.01, "%s n=%d not centred" % [Fleet.FORMATION_NAMES[form], n])
			check(uniq.size() == n, "%s n=%d has overlapping slots" % [Fleet.FORMATION_NAMES[form], n])


func test_speed_and_accel_scale() -> void:
	var w := make_world()
	Tune.size_slowdown = 0.4
	Tune.accel_slowdown = 0.5
	var one := w._make_fleet(1, "one", 0, Vector2(-1000, 0), 1)
	var full := w._make_fleet(2, "full", 0, Vector2(1000, 0), Tune.max_ships)
	check(is_equal_approx(one.speed_cap(), Tune.max_speed), "1-ship speed %f" % one.speed_cap())
	check(is_equal_approx(full.speed_cap(), Tune.max_speed * 0.6), "full speed %f" % full.speed_cap())
	check(is_equal_approx(one.accel_cap(), Tune.accel), "1-ship accel %f" % one.accel_cap())
	check(is_equal_approx(full.accel_cap(), Tune.accel * 0.5), "full accel %f" % full.accel_cap())
	# The leader really is limited by accel_cap: one tick from rest moves at most accel*dt.
	full.move_to = full.anchor + Vector2(2000, 0)
	full.step(1.0 / 60.0)
	check(full.anchor_vel.length() <= Tune.accel * 0.5 / 60.0 + 0.01, "full fleet accelerated too fast")
	done(w)


func test_recruit_spawns_behind_killer() -> void:
	var w := make_world()
	var killer := w._make_fleet(1, "K", 0, Vector2(0, 0), 5)
	killer.heading = 0.0   # facing +x
	for i in killer.ships.size():
		killer.ships[i].pos = Vector2(0, (i - 2) * 30.0)
	killer.centroid = Vector2.ZERO
	var victim := w._make_fleet(2, "V", 0, Vector2(1500, 0), 3)
	var dead := victim.ships[0]
	var victim_pos := dead.pos
	w._kill(dead, killer.id)
	check(victim.ships.size() == 2, "victim should lose the ship, has %d" % victim.ships.size())
	check(not victim.ships.has(dead) and dead.is_queued_for_deletion(), "victim ship should be destroyed, not transferred")
	check(killer.ships.size() == 6, "killer should gain one, has %d" % killer.ships.size())
	var newest: Ship = killer.ships.back()
	check(newest != dead, "recruit must be a new ship")
	check(newest.pos.x < -Tune.separation * 0.5, "recruit should spawn behind (x<0), at %s" % newest.pos)
	check(newest.pos.distance_to(victim_pos) > 1000.0, "recruit spawned at the victim")
	check(killer.kills == 1, "kill not counted")
	done(w)


func test_recruit_respects_cap() -> void:
	var w := make_world()
	var killer := w._make_fleet(1, "K", 0, Vector2(0, 0), Tune.max_ships)
	var victim := w._make_fleet(2, "V", 0, Vector2(1500, 0), 2)
	w._kill(victim.ships[0], killer.id)
	check(killer.ships.size() == Tune.max_ships, "cap exceeded: %d" % killer.ships.size())
	check(victim.ships.size() == 1, "victim should still lose the ship")
	done(w)


func test_collision_hits_enemy_not_self() -> void:
	var w := make_world()
	var a := w._make_fleet(1, "A", 0, Vector2(0, 0), 1)
	var b := w._make_fleet(2, "B", 0, Vector2(800, 0), 1)
	var target := b.ships[0].pos
	w.lasers.spawn(target, Vector2(300, 0), b.id, b.team, 1.0)   # own bolt on own ship
	w._collide()
	check(b.ships.size() == 1, "own laser killed own ship")
	check(w.lasers.pos.size() == 1, "own laser should keep flying")
	w.lasers.spawn(target + Vector2(Tune.laser_length * 0.4, 3.0), Vector2(300, 0), a.id, a.team, 1.0)
	w._collide()
	check(not b.alive, "enemy laser should kill (segment overlaps ship)")
	check(w.lasers.pos.size() == 1, "the hitting laser should be removed")
	check(a.ships.size() == 2, "killer should recruit")
	done(w)


func test_kill_credit_and_death() -> void:
	var w := make_world()
	var h := w.add_human(1, "Me")
	var died := [""]
	w.player_died.connect(func(by: String) -> void: died[0] = by)
	var bot := w._make_fleet(3, "Nova", 0, Vector2(2000, 0), 1)
	w._kill(h.fleet.ships[0], bot.id)
	check(not h.fleet.alive, "human fleet should be dead")
	check(died[0] == "Nova", "player_died should name the killer, got '%s'" % died[0])
	check(w.fleets.has(h.fleet), "dead human fleet stays until respawn (HUD reads it)")
	done(w)


func test_laser_pool() -> void:
	var w := make_world()
	var lz := w.lasers
	var ids: Array[int] = []
	for i in 5:
		ids.append(lz.spawn(Vector2(i, 0), Vector2(1, 0), 9, 1, 1.0))
	lz.remove_uid(ids[1])
	lz.remove_uid(12345)
	check(lz.pos.size() == 4 and lz.uid.size() == 4 and lz.team.size() == 4, "arrays out of step")
	check(not lz.uid.has(ids[1]), "removed uid still present")
	for i in lz.uid.size():
		check(lz.pos[i].x == ids.find(lz.uid[i]), "pos/uid mismatch after swap-remove")
	lz.step(2.0)
	check(lz.pos.is_empty(), "expired lasers should be gone")
	done(w)


func test_tune_values_roundtrip() -> void:
	var v := Tune.values()
	for entry: Array in Tune.DOCS:
		check(v.has(entry[1]), "values() missing %s" % entry[1])
	Tune.apply_values({"max_speed": 123, "laser_speed": "456.5", "nonsense": 1})
	check(Tune.max_speed == 123.0 and typeof(Tune.max_speed) == TYPE_FLOAT, "int not coerced to float")
	check(Tune.laser_speed == 456.5, "string not coerced")
	Tune.apply_values(v)
	check(Tune.max_speed == v.max_speed, "restore failed")


func test_tune_file_adds_missing_keys() -> void:
	var path := ProjectSettings.globalize_path("user://unit_tuning.cfg")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[meta]\ndefaults_version=%d\n[movement]\nmax_speed=777.0\n" % Tune.DEFAULTS_VERSION)
	f.close()
	Tune.load_file(path)
	check(Tune.max_speed == 777.0, "value not loaded")
	var text := FileAccess.get_file_as_string(path)
	check(text.contains("accel_slowdown=") and text.contains("max_speed=777.0"), "file not completed with missing keys")
	Tune.max_speed = 555.0
	check(Tune.save_file(path), "save failed")
	Tune.max_speed = 1.0
	Tune.load_file(path)
	check(Tune.max_speed == 555.0, "save/load roundtrip got %f" % Tune.max_speed)
	DirAccess.remove_absolute(path)
	Tune.locked = true
	check(not Tune.save_file(path), "locked (client) must not save")
	Tune.locked = false


func test_snapshot_codec() -> void:
	var w := make_world()
	w.tick = 4242
	var a := w._make_fleet(4, "Zoë ✦", 7, Vector2(-1234.5, 987.25), 30)
	a.kills = 70000
	a.formation = Fleet.Formation.LINE
	a.fire_cd = 0.3
	var b := w._make_fleet(2, "Vex", 0, Vector2(2000, -2000), 1)
	b.free_ships()
	b.alive = false
	var snap := Net.decode_snapshot(Net.encode_snapshot(w))
	check(snap.tick == 4242, "tick")
	check(snap.fleets.size() == 2, "fleet count")
	var fa: Dictionary = snap.fleets[a.id]
	check(fa.name == "Zoë ✦" and fa.peer == 7 and fa.team == 4 and fa.alive, "header fields")
	check(fa.kills == 65535, "kills should saturate")
	check(fa.formation == Fleet.Formation.LINE, "formation")
	check(absf(fa.fire_cd - 0.3) < Tune.fire_cooldown / 200.0, "fire_cd")
	check(absf(angle_difference(fa.heading, a.heading)) < 0.001, "heading")
	check(fa.ships.size() == 30, "ship count")
	for s in a.ships:
		check(fa.ships.has(s.uid) and (fa.ships[s.uid] as Vector2).distance_to(s.pos) <= 0.2, "ship %d position" % s.uid)
	check(not snap.fleets[b.id].alive and snap.fleets[b.id].ships.is_empty(), "dead fleet")
	check(Net.encode_snapshot(w).size() < 260, "30-ship snapshot unexpectedly large: %d" % Net.encode_snapshot(w).size())
	# uid gaps beyond u16 use the escape
	a.ships[3].uid = 1 << 20
	a.ships[4].uid = (1 << 20) + 70000
	var again: Dictionary = Net.decode_snapshot(Net.encode_snapshot(w)).fleets[a.id]
	for s in a.ships:
		check(again.ships.has(s.uid), "uid %d lost in delta coding" % s.uid)
	done(w)


func test_address_and_names() -> void:
	check(Net.parse_address("1.2.3.4") == ["1.2.3.4", Net.DEFAULT_PORT], "bare ip")
	check(Net.parse_address(" host.lan:4000 ") == ["host.lan", 4000], "host:port")
	check(Net.parse_address("") == ["127.0.0.1", Net.DEFAULT_PORT], "empty")
	check(Net.parse_address("::1")[0] == "::1", "ipv6 left alone")
	check(Net.clean_name("  ") == "Pilot", "blank name")
	check(Net.clean_name("a\nb\tc") == "abc", "control chars")
	check(Net.clean_name("x".repeat(40)).length() == Net.MAX_NAME, "length cap")
	var w := make_world()
	var n := Net.new()
	n.world = w
	w.add_human(5, "Sam")
	check(n._unique_name("Sam") == "Sam 2", "duplicate names get a number")
	n.free()
	done(w)


func test_human_respawn_delay() -> void:
	var w := make_world()
	var h := w.add_human(5, "Bob")
	var first := h.fleet
	check(h.team != 0, "remote human should not get the host colour")
	first.remove_ship(first.ships[0])
	w.respawn_human(5)
	check(h.fleet == first, "respawned before the delay")
	h.dead_for = Tune.respawn_delay + 0.1
	w.respawn_human(5)
	check(h.fleet != first and h.fleet.alive and h.fleet.ships.size() == 1, "no respawn after the delay")
	check(not w.fleets.has(first), "old fleet not removed")
	done(w)


func test_remove_human() -> void:
	var w := make_world()
	var h := w.add_human(9, "Gone")
	var f := h.fleet
	w.remove_human(9)
	check(not w.humans.has(9) and not w.fleets.has(f), "human not removed")
	check(f.ships.is_empty(), "ships not freed")
	done(w)


func test_controls_boost_once() -> void:
	var w := make_world()
	var h := w.add_human(5, "B")
	h.ctl.boost_seq = 1
	w._apply_controls(h)
	check(h.fleet.want_boost, "boost press lost")
	h.fleet.want_boost = false
	w._apply_controls(h)
	check(not h.fleet.want_boost, "one press boosted twice")
	h.ctl.steer = false
	h.fleet.move_to = Vector2(1, 1)
	h.ctl.move_to = Vector2(500, 500)
	w._apply_controls(h)
	check(h.fleet.move_to == Vector2(1, 1), "steer=false (mouse over panel) must keep course")
	done(w)


func test_tune_panel_reset_only_its_keys() -> void:
	var p := TunePanel.new()
	add_child(p)
	Tune.max_speed = 999.0
	Tune.bot_count = 3
	p._reset()
	check(Tune.max_speed == Tune.default_value("max_speed"), "panel key not reset")
	check(Tune.bot_count == 3, "reset touched a key outside the panel")
	p.visible = true
	p._on_slider(444.0, "laser_speed")
	check(Tune.laser_speed == 444.0, "slider did not apply")
	Tune.locked = true
	p._on_slider(10.0, "laser_speed")
	check(Tune.laser_speed == 444.0, "locked panel still applied")
	Tune.locked = false
	p.free()
