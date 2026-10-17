extends Node
## Root: world + glow environment + HUD.


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
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var world := World.new()
	world.autopilot = OS.get_cmdline_user_args().has("--autopilot")   # demo / capture mode
	add_child(world)

	var layer := CanvasLayer.new()
	var hud := preload("res://scripts/hud.gd").new()
	hud.world = world
	layer.add_child(hud)
	add_child(layer)
