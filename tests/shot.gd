extends Node
## --shot=PATH[,SECONDS[,KEYS]]: after SECONDS, save the window to PATH and quit (visual checks).
## KEYS: "f12" opens the tuning panel first.

var spec := ""
var main: Node
var _t := 0.0


func _process(dt: float) -> void:
	var parts := spec.split(",")
	var secs := float(parts[1]) if parts.size() > 1 else 3.0
	if parts.size() > 2 and parts[2] == "f12" and main.get("_panel") and _t == 0.0:
		main._panel.visible = true
	_t += dt
	if _t < secs:
		return
	set_process(false)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(parts[0])
	print("SHOT ", parts[0])
	get_tree().quit()
