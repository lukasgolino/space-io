extends Node
## Root: glow environment, title screen, and the running match (world + HUD + F12 panel).
## Command line (after `--`): --autopilot, --formation=N, --name=X, --host[=port], --join=addr[:port],
## --net-test=seconds (headless network check, see tests/net_check.gd), --shot=path[,s[,f12]] (screenshot).

var world: World
var _layer: CanvasLayer
var _title: Title
var _panel: TunePanel


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = Tune.glow_intensity
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for level in 7:
		env.set_glow_level(level, level in [1, 2])
	Tune.changed.connect(func() -> void: env.glow_intensity = Tune.glow_intensity)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var args := _args()
	var player_name: String = args.get("name", "You")
	if args.has("host"):
		var port: String = args["host"]
		start(World.Mode.HOST, player_name, "127.0.0.1:%s" % (port if port.is_valid_int() else str(Net.DEFAULT_PORT)))
	elif args.has("join"):
		start(World.Mode.CLIENT, player_name, args["join"])
	elif args.has("autopilot"):
		start(World.Mode.SOLO, player_name, "")
	else:
		_show_title("")
	if args.has("shot"):
		var shot: Node = load("res://tests/shot.gd").new()
		shot.set("spec", args["shot"])
		shot.set("main", self)
		add_child(shot)
	if args.has("net-test"):
		var check: Node = load("res://tests/net_check.gd").new()
		check.set("seconds", float(args["net-test"]))
		check.set("main", self)
		add_child(check)


## --key=value / --flag user args -> {key: value or ""}.
func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else ""
	return out


func start(mode: World.Mode, player_name: String, address: String) -> void:
	_clear()
	var args := _args()
	world = World.new()
	world.name = "World"   # same node path on every machine, so RPCs line up
	world.mode = mode
	world.local_name = Net.clean_name(player_name)
	world.autopilot = args.has("autopilot")
	if args.has("formation"):
		world.force_formation = int(args["formation"]) - 1
	add_child(world)

	if world.net:
		world.net.failed.connect(_back_to_title)
		var hp := Net.parse_address(address)
		var err := world.net.host(hp[1]) if mode == World.Mode.HOST else world.net.join(hp[0], hp[1])
		if err != OK:
			var what := "host on port %d" % hp[1] if mode == World.Mode.HOST else "join %s:%d" % hp
			_back_to_title("could not %s (%s)" % [what, error_string(err)])
			return

	_layer = CanvasLayer.new()
	var hud := preload("res://scripts/hud.gd").new()
	hud.world = world
	_layer.add_child(hud)
	_panel = TunePanel.new()
	_layer.add_child(_panel)
	add_child(_layer)


func _clear() -> void:
	for n: Node in [world, _layer, _title]:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)   # now, so a new "World" gets the same node path
			n.queue_free()
	world = null
	_layer = null
	_title = null
	_panel = null


func _back_to_title(message: String) -> void:
	if world == null and _title != null:
		return
	if DisplayServer.get_name() == "headless" and message != "":
		printerr("NET: ", message)
	_show_title.call_deferred(message)   # not from inside the world's own tick


func _show_title(message: String) -> void:
	_clear()
	_title = Title.new()
	_title.message = message
	_title.chosen.connect(start)
	var layer := CanvasLayer.new()
	layer.add_child(_title)
	add_child(layer)
	_layer = layer


func _unhandled_input(event: InputEvent) -> void:
	if world == null or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_ESCAPE:
		if _panel and _panel.visible:
			_panel.hide()
		else:
			_show_title("")
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_F12 and _panel:
		_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()
