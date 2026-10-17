extends Node2D
## Background: parallax PAGAN star layers, faint grid, neon arena wall.

const WALL_COLOR := Color(0.5, 0.15, 0.3, 0.8)


func _ready() -> void:
	z_index = -10
	_add_stars("stars_far", 0.25, Color(1, 1, 1, 0.9))
	_add_stars("stars_near", 0.55, Color(1, 1, 1, 1))


func _add_stars(asset: String, factor: float, tint: Color) -> void:
	var par := Parallax2D.new()
	par.scroll_scale = Vector2(factor, factor)
	par.repeat_size = Vector2(512, 512)
	par.z_index = -20
	var spr := Sprite2D.new()
	spr.texture = load(Art.sheet_path(asset))
	spr.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	spr.region_enabled = true
	spr.region_rect = Rect2(0, 0, 6144, 6144)
	spr.modulate = tint
	par.add_child(spr)
	add_child(par)


func _draw() -> void:
	var h := Tune.arena_half
	draw_rect(Rect2(-h, -h, 2 * h, 2 * h), WALL_COLOR, false, 6.0)
