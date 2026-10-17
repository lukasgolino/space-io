extends Node
## Every gameplay feel number. Defaults live here; the owner overrides them in tuning.cfg
## (next to the exe, or the project root when run from source). F5 in game reloads the file.

signal changed

const FILE_NAME := "tuning.cfg"
## Bump when defaults change: an older tuning.cfg is moved to tuning.cfg.old and rewritten,
## so stale values never silently override new defaults.
const DEFAULTS_VERSION := 2

# Arena (square, centred on the origin)
var arena_half := 2600.0

# Fleet movement: an invisible leader chases the cursor; ships follow it
var max_speed := 320.0
var size_slowdown := 0.35
var accel := 2200.0
var slow_radius := 140.0
var boost_mult := 2.2
var boost_time := 0.45
var boost_cooldown := 3.5
var fleet_turn_rate := 0.0

# Ships
var ship_scale := 0.5
var ship_accel := 1800.0
var ship_speed_mult := 1.6
var turn_rate := 0.0
var hit_radius := 11.0
var max_ships := 30

# Formations
var blob_pull := 2.2
var blob_cohesion := 0.6
var separation := 30.0
var separation_push := 420.0
var formation_strength := 4.0
var slot_spacing := 30.0
var jitter := 0.08

# Lasers
var fire_cooldown := 0.8
var fire_stagger := 0.06
var laser_speed := 300.0
var laser_life := 2.6
var nose_offset := 14.0
var laser_length := 64.0

# Look
var glow_intensity := 0.55
var ship_hdr := 1.1
var laser_hdr := 1.35

# Camera
var zoom_one_ship := 1.0
var zoom_full_fleet := 0.62
var shake_on_loss := 7.0

# Bots
var bot_count := 14
var bot_think := 0.15
var bot_sense := 1150.0
var bot_fire_range := 800.0
var bot_aim_tolerance_deg := 10.0
var bot_fire_chance := 0.55
var bot_dodge_chance := 0.5
var bot_respawn_delay := 2.0
var bot_start_sizes: Array[int] = [1, 1, 2, 2, 3, 3, 4, 5, 6, 8, 10, 13, 17]

# Player
var respawn_delay := 1.2

## [section, name, explanation] - the order and comments of tuning.cfg.
const DOCS := [
	["arena", "arena_half", "half the arena width, px"],
	["movement", "max_speed", "top speed of a 1-ship fleet, px/s (keep a bit above laser_speed so small fleets can outrun bullets)"],
	["movement", "size_slowdown", "fraction of top speed lost at the fleet cap (0.35 = a full fleet moves at 65%), linear in fleet size"],
	["movement", "accel", "how fast the fleet leader reaches top speed, px/s^2 (higher = snappier)"],
	["movement", "slow_radius", "leader eases to a stop when the cursor is this close, px"],
	["movement", "boost_mult", "speed multiplier while boosting"],
	["movement", "boost_time", "boost duration, s"],
	["movement", "boost_cooldown", "boost recharge, s (counted from boost start)"],
	["movement", "fleet_turn_rate", "how fast the fleet heading turns to the cursor, rad/s (0 = instant)"],
	["ships", "ship_scale", "sprite scale (art is drawn at 2x, so 0.5 = native)"],
	["ships", "ship_accel", "how fast each ship changes velocity, px/s^2 (lower = more drifty)"],
	["ships", "ship_speed_mult", "ships may go this much faster than the leader to catch up"],
	["ships", "turn_rate", "how fast each ship turns to the fleet heading, rad/s (0 = instant)"],
	["ships", "hit_radius", "laser hit radius around a ship centre, px"],
	["ships", "max_ships", "fleet size cap"],
	["formation", "blob_pull", "BLOB: pull of each ship towards the fleet leader, 1/s (higher = tighter, snappier)"],
	["formation", "blob_cohesion", "BLOB: extra gravity towards the fleet's own centre, 1/s"],
	["formation", "separation", "ships closer than this push apart, px (bigger = looser blob)"],
	["formation", "separation_push", "how hard they push apart, px/s at full overlap"],
	["formation", "formation_strength", "TRIANGLE/SQUARE/LINE: pull towards each ship's slot, 1/s (higher = more rigid)"],
	["formation", "slot_spacing", "TRIANGLE/SQUARE/LINE: distance between slots, px"],
	["formation", "jitter", "per-ship random speed variation (0.08 = +-8%), keeps shapes organic"],
	["lasers", "fire_cooldown", "seconds between volleys (holding the button repeats)"],
	["lasers", "fire_stagger", "random per-ship delay inside one volley, s"],
	["lasers", "laser_speed", "px/s (lower = easier to dodge)"],
	["lasers", "laser_life", "seconds before a laser fades (range = speed x life)"],
	["lasers", "nose_offset", "where the streak starts in front of the ship, px"],
	["lasers", "laser_length", "streak length on screen, px"],
	["look", "glow_intensity", "bloom strength"],
	["look", "ship_hdr", "ship brightness; above 1 glows"],
	["look", "laser_hdr", "laser brightness; above 1 glows"],
	["camera", "zoom_one_ship", "zoom with 1 ship (1 = 100%)"],
	["camera", "zoom_full_fleet", "zoom at the fleet cap"],
	["camera", "shake_on_loss", "screen shake when you lose a ship, px"],
	["bots", "bot_count", "computer fleets in the arena"],
	["bots", "bot_think", "seconds between bot decisions"],
	["bots", "bot_sense", "how far bots see, px"],
	["bots", "bot_fire_range", "bots fire when the target is this close, px"],
	["bots", "bot_aim_tolerance_deg", "how well lined up bots must be to fire, degrees"],
	["bots", "bot_fire_chance", "chance to fire per decision when lined up (0..1)"],
	["bots", "bot_dodge_chance", "chance to dodge an incoming laser per decision (0..1)"],
	["bots", "bot_respawn_delay", "seconds before a destroyed bot fleet is replaced"],
	["bots", "bot_start_sizes", "a new bot fleet starts with a random size from this list"],
	["player", "respawn_delay", "seconds after death before you can respawn"],
]

var status := ""            # shown briefly by the HUD
var status_time := 0.0


## Headless tests skip the file so they always run on the defaults.
func _ready() -> void:
	if not DisplayServer.get_name() == "headless":
		load_file()


func file_path() -> String:
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join(FILE_NAME)
	return ProjectSettings.globalize_path("res://").path_join(FILE_NAME)


func load_file() -> void:
	var path := file_path()
	if not FileAccess.file_exists(path):
		_write_defaults(path)
		_say("wrote default settings to %s" % path)
		return
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		_say("tuning.cfg has an error (%s): kept previous values" % error_string(err))
		push_warning(status)
		return
	if cfg.get_value("meta", "defaults_version", 1) != DEFAULTS_VERSION:
		DirAccess.rename_absolute(path, path + ".old")
		_write_defaults(path)
		_say("defaults changed: old settings moved to %s.old, wrote new %s" % [path, path])
		return
	var n := 0
	for entry: Array in DOCS:
		var key: String = entry[1]
		if not cfg.has_section_key(entry[0], key):
			continue
		var value: Variant = cfg.get_value(entry[0], key)
		var current: Variant = get(key)
		if current is Array:
			(current as Array).assign(value)
		else:
			set(key, type_convert(value, typeof(current)))
		n += 1
	_say("loaded %d settings from %s" % [n, path])
	changed.emit()


func _say(msg: String) -> void:
	status = msg
	status_time = Time.get_ticks_msec() / 1000.0


func _write_defaults(path: String) -> void:
	var lines: PackedStringArray = [
		"; Space IO tuning. Edit, save, press F5 in game to apply (arena/bot sizes apply on new spawns).",
		"; Delete this file to get the defaults back.",
		"",
		"[meta]",
		"; written by the game; don't edit",
		"defaults_version=%d" % DEFAULTS_VERSION,
	]
	var section := ""
	for entry: Array in DOCS:
		if entry[0] != section:
			section = entry[0]
			lines.append("")
			lines.append("[%s]" % section)
		lines.append("; " + entry[2])
		lines.append("%s=%s" % [entry[1], var_to_str(get(entry[1]))])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F5:
		load_file()
