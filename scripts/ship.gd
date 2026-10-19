class_name Ship
extends AnimatedSprite2D
## One fighter. Its motion is integrated by its Fleet (one pass over the whole fleet is much cheaper
## than per-ship logic); `pos` is the simulation position, `position` mirrors it for drawing.

var fleet: Fleet
var uid := 0             # stable id across the network (snapshots key ships by it)
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var fire_timer := -1.0   # >= 0: fires when it reaches 0 (volley stagger)
var speed_k := 1.0       # per-ship speed variation, keeps the swarm organic
var dead := false        # hit this tick; skipped by collisions until freed


func setup(f: Fleet, at: Vector2) -> void:
	fleet = f
	pos = at
	position = at
	sprite_frames = Art.frames("ship", f.team)
	centered = true
	rotation = f.heading
	speed_k = 1.0 + randf_range(-Tune.jitter, Tune.jitter)
	refresh_look()
	play(sprite_frames.get_animation_names()[0])


func refresh_look() -> void:
	scale = Vector2.ONE * Tune.ship_scale
	modulate = Color(Tune.ship_hdr, Tune.ship_hdr, Tune.ship_hdr)   # HDR above 1 blooms


## Short grow-in so a recruit visibly arrives instead of popping.
func pop_in() -> void:
	scale = Vector2.ONE * Tune.ship_scale * 0.2
	create_tween().tween_property(self, "scale", Vector2.ONE * Tune.ship_scale, 0.18)
