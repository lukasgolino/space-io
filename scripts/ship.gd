class_name Ship
extends AnimatedSprite2D
## One fighter. Springs to its slot in the fleet swarm, faces the fleet heading, fires from its nose.

var fleet: Fleet
var vel := Vector2.ZERO
var fire_timer := -1.0   # >= 0: fires when it reaches 0 (volley stagger)


func setup(f: Fleet) -> void:
	fleet = f
	sprite_frames = Art.frames("ship", f.team)
	scale = Vector2.ONE * Tune.ship_scale
	centered = true
	rotation = f.heading
	material = null
	modulate = Color(Tune.ship_hdr, Tune.ship_hdr, Tune.ship_hdr)   # HDR: blooms
	play(sprite_frames.get_animation_names()[0])


func step(dt: float, slot_target: Vector2, mates: Array[Ship]) -> void:
	var to_slot := slot_target - global_position
	var want := to_slot * Tune.ship_follow
	for m in mates:
		if m == self:
			continue
		var d := global_position - m.global_position
		var l := d.length()
		if l < Tune.separation and l > 0.01:
			want += d / l * (Tune.separation - l) * Tune.ship_follow
	var cap := fleet.speed_cap() * Tune.ship_speed_mult
	vel = want.limit_length(cap)
	global_position += vel * dt
	rotation = rotate_toward(rotation, fleet.heading, Tune.turn_rate * dt)

	if fire_timer >= 0.0:
		fire_timer -= dt
		if fire_timer < 0.0:
			var fwd := Vector2.from_angle(rotation)
			fleet.world.lasers.spawn(global_position + fwd * (Tune.nose_offset + Tune.laser_length * 0.5), fwd * Tune.laser_speed, fleet)
