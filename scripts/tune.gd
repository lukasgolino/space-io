extends Node
## Every gameplay feel number lives here. Tuning = edit this file; nothing else hard-codes these.

# Arena (square, centred on the origin)
var arena_half := 2600.0

# Fleet movement: the fleet's anchor chases the cursor; ships spring to slots around it
var max_speed := 340.0           # px/s
var accel := 2800.0              # px/s^2: high = snappy
var slow_radius := 140.0         # cursor closer than this -> ease to a stop on it
var boost_mult := 2.3
var boost_time := 0.45           # s
var boost_cooldown := 3.5        # s, from boost start

# Ships
var ship_scale := 0.5            # art is authored at 2x
var ship_follow := 14.0          # spring strength towards the slot (1/s)
var ship_speed_mult := 1.7       # ships may exceed the anchor speed by this much to catch up
var turn_rate := 14.0            # rad/s, each ship towards the fleet heading
var fleet_turn_rate := 8.0       # rad/s, the formation itself
var slot_back := 28.0            # wedge row spacing
var slot_side := 30.0            # wedge column spacing
var separation := 22.0           # fleet-mates push apart inside this distance
var hit_radius := 11.0
var max_ships := 30

# Lasers
var fire_cooldown := 0.8         # s between volleys (hold to auto-repeat)
var fire_stagger := 0.06         # s, random per-ship delay inside a volley
var laser_speed := 560.0         # px/s: slow enough to dodge
var laser_life := 1.7            # s
var nose_offset := 14.0          # px in front of the ship centre where the streak starts
var laser_length := 64.0         # px on screen (art is 128 at 2x)

# Look
var glow_intensity := 1.0
var ship_hdr := 1.6              # >1 = brighter than white -> blooms
var laser_hdr := 1.9

# Camera
var zoom_one_ship := 1.0
var zoom_full_fleet := 0.62
var shake_on_loss := 7.0         # px

# Bots
var bot_count := 14
var bot_think := 0.15            # s between decisions
var bot_sense := 1150.0
var bot_fire_range := 820.0
var bot_aim_tolerance_deg := 10.0
var bot_fire_chance := 0.55      # per think while lined up (reaction)
var bot_dodge_chance := 0.5
var bot_respawn_delay := 2.0
var bot_start_sizes: Array[int] = [1, 1, 2, 2, 3, 3, 4, 5, 6, 8, 10, 13, 17]

# Player
var respawn_delay := 1.2
