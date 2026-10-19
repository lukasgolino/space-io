class_name NameTag
extends Node2D
## A player's name above their fleet. World scales it by 1/zoom so it stays one size on screen.

const SIZE := 17

var text := ""
var color := Color.WHITE


func _ready() -> void:
	z_index = 5


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
	draw_string_outline(font, Vector2(-w / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, 4, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(-w / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, color)
