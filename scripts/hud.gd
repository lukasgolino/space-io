extends Control
## Screen overlay: fleet size, fire/boost recharge, leaderboard, minimap, death screen.

const MAP_SIZE := 190.0
const TEXT := Color(0.85, 0.9, 1.0)
const DIM := Color(0.55, 0.6, 0.8, 0.8)
const PANEL := Color(0.02, 0.03, 0.08, 0.65)

var world: World
var _killer := ""
var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	world.player_died.connect(func(k: String) -> void: _killer = k)
	world.player_spawned.connect(func() -> void: _killer = "")


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	_net_line(vp)
	var p := world.player
	if p == null:
		_centred("connecting to host...", vp.y / 2, 28, TEXT)
		return

	# Fleet size + kills, top-left
	draw_string(_font, Vector2(28, 58), "%d" % p.ships.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Art.color(p.team))
	draw_string(_font, Vector2(28 + 26 * str(p.ships.size()).length() + 10, 58), "SHIPS", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, DIM)
	draw_string(_font, Vector2(28, 88), "%d kills" % p.kills, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, DIM)

	# Recharge bars, bottom centre
	var w := 220.0
	var y := vp.y - 46.0
	_bar(Vector2(vp.x / 2 - w - 12, y), w, p.fire_ready(), "FIRE  [click]", Art.color(p.team))
	_bar(Vector2(vp.x / 2 + 12, y), w, p.boost_ready(), "BOOST  [space]", Color("#ffee22"))
	var forms := PackedStringArray()
	for k in Fleet.FORMATION_NAMES.size():
		var nm: String = Fleet.FORMATION_NAMES[k]
		forms.append(("[%d %s]" if k == p.formation else "%d %s") % [k + 1, nm.to_lower()])
	_centred("   ".join(forms) + "      hold right-click: swivel (aim without steering)", vp.y - 72.0, 15, DIM)

	# Tuning file status (F5), fades after a few seconds
	var age := Time.get_ticks_msec() / 1000.0 - Tune.status_time
	if Tune.status != "" and age < 5.0:
		_centred(Tune.status, 120.0, 16, Color(TEXT, clampf(5.0 - age, 0.0, 1.0)))

	# Leaderboard, top-right
	var board := world.leaderboard()
	var bx := vp.x - 270.0
	var rows := mini(board.size(), 10)
	draw_rect(Rect2(bx - 14, 16, 262, 44 + rows * 26), PANEL)
	draw_string(_font, Vector2(bx, 44), "LEADERBOARD", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, DIM)
	var player_rank := board.find(p)
	for i in rows:
		_board_row(bx, 74 + i * 26, i + 1, board[i])
	if player_rank >= rows:
		_board_row(bx, 74 + rows * 26 + 8, player_rank + 1, p)

	# Minimap, bottom-right
	var mo := Vector2(vp.x - MAP_SIZE - 24, vp.y - MAP_SIZE - 24)
	draw_rect(Rect2(mo, Vector2(MAP_SIZE, MAP_SIZE)), PANEL)
	draw_rect(Rect2(mo, Vector2(MAP_SIZE, MAP_SIZE)), Color(1.0, 0.25, 0.45, 0.8), false, 2.0)
	var k := MAP_SIZE / (2.0 * Tune.arena_half)
	for f in world.fleets:
		if not f.alive:
			continue
		var at := mo + (f.anchor + Vector2.ONE * Tune.arena_half) * k
		var r := 2.0 + sqrt(f.ships.size()) * 1.3
		if f == p:
			draw_circle(at, r + 2.0, Color.WHITE)
		else:
			draw_circle(at, r, Art.color(f.team))
			if f.is_human():
				draw_circle(at, r + 2.5, Color.WHITE, false, 1.5)

	# Death screen
	if not p.alive:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.45))
		_centred("DESTROYED", vp.y / 2 - 30, 64, Color("#ff3a5c"))
		_centred("by %s   ·   %d kills" % [_killer, p.kills], vp.y / 2 + 20, 24, TEXT)
		if world.can_respawn():
			_centred("click or space to respawn", vp.y / 2 + 70, 22, DIM)


func _bar(at: Vector2, w: float, fill: float, label: String, col: Color) -> void:
	draw_rect(Rect2(at, Vector2(w, 12)), PANEL)
	var c := col if fill >= 1.0 else col.darkened(0.45)
	draw_rect(Rect2(at, Vector2(w * fill, 12)), c)
	draw_rect(Rect2(at, Vector2(w, 12)), col.darkened(0.2), false, 1.5)
	draw_string(_font, at + Vector2(0, -8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, DIM)


## Host: who's connected and where to join; client: ping.
func _net_line(vp: Vector2) -> void:
	if world.net == null:
		return
	var text := ""
	if world.mode == World.Mode.HOST:
		var ips := world.net.lan()
		text = "HOSTING  ·  %d joined  ·  port %d  ·  LAN %s" % [world.net.client_count(), world.net.port,
			", ".join(ips) if not ips.is_empty() else "?"]
	else:
		var ms := world.net.ping_ms()
		text = "ONLINE  ·  ping %s" % ("%d ms" % ms if ms >= 0 else "-")
	draw_string(_font, Vector2(28, vp.y - 20), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DIM)


func _board_row(x: float, y: float, rank: int, f: Fleet) -> void:
	var col := Color.WHITE if f == world.player else Art.color(f.team)
	draw_string(_font, Vector2(x, y), "%d." % rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, DIM)
	draw_string(_font, Vector2(x + 34, y), f.name, HORIZONTAL_ALIGNMENT_LEFT, 150, 18, col)
	draw_string(_font, Vector2(x + 190, y), str(f.ships.size()), HORIZONTAL_ALIGNMENT_RIGHT, 40, 18, col)


func _centred(text: String, y: float, fs: int, col: Color) -> void:
	draw_string(_font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, get_viewport_rect().size.x, fs, col)
