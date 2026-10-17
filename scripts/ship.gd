class_name Ship
extends AnimatedSprite2D
## One fighter. Steers (with inertia) towards where its fleet's formation wants it, faces the fleet
## heading, fires from its nose.

var fleet: Fleet
var vel := Vector2.ZERO
var fire_timer := -1.0   # >= 0: fires when it reaches 0 (volley stagger)
var speed_k := 1.0       # per-ship speed variation, keeps the swarm organic


func setup(f: Fleet) -> void:
	fleet = f
	sprite_frames = Art.frames("ship", f.team)
	centered = true
	rotation = f.heading
	speed_k = 1.0 + randf_range(-Tune.jitter, Tune.jitter)
	refresh_look()
	play(sprite_frames.get_animation_names()[0])


func refresh_look() -> void:
	scale = Vector2.ONE * Tune.ship_scale
	modulate = Color(Tune.ship_hdr, Tune.ship_hdr, Tune.ship_hdr)   # HDR above 1 blooms


## target: the slot (formations) or the fleet leader (blob); centroid: the fleet's centre.
func step(dt: float, target: Vector2, centroid: Vector2, blob: bool, mates: Array[Ship]) -> void:
	var pos := global_position
	var want: Vector2
	if blob:
		want = (target - pos) * Tune.blob_pull + (centroid - pos) * Tune.blob_cohesion
	else:
		want = (target - pos) * Tune.formation_strength
	for m in mates:
		if m == self:
			continue
		var d := pos - m.global_position
		var l := d.length()
		if l < Tune.separation and l > 0.01:
			want += d / l * (1.0 - l / Tune.separation) * Tune.separation_push
	want = want.limit_length(fleet.speed_cap() * Tune.ship_speed_mult * speed_k)
	vel = vel.move_toward(want, Tune.ship_accel * (2.0 if fleet.boosting() else 1.0) * dt)
	global_position = pos + vel * dt
	rotation = fleet.heading if Tune.turn_rate <= 0.0 else rotate_toward(rotation, fleet.heading, Tune.turn_rate * dt)

	if fire_timer >= 0.0:
		fire_timer -= dt
		if fire_timer < 0.0:
			var fwd := Vector2.from_angle(rotation)
			fleet.world.lasers.spawn(global_position + fwd * (Tune.nose_offset + Tune.laser_length * 0.5), fwd * Tune.laser_speed, fleet)
