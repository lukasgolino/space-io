# Art brief

## The game

- **Title / working name:** Space IO (replica of space1.io)
- **Genre and core loop:** .io arena shooter. Your fleet of small fighters flies in a packed wedge; kill ships in other fleets and they join yours (cap 30).
- **Perspective:** straight top-down 2D (`camera.elevation = 90`; no models).
- **Mood / references:** space1.io: flat neon triangles and long thin glowing laser streaks on near-black space, sparse dim stars. High contrast, arcade, *not* traditional pixel art.
- **Target resolution:** 1920x1080 canvas, free camera zoom 1.0 -> 0.62. Sprites rotate freely.

## Key assets

All procedural, from `tools/gen_art.py` (pagan.api). Regenerate, never hand-edit the yaml.

- **ship** — 64x64 at 2x (32 on screen), flat triangle, nose +x, fill = ramp step 3, 2px rim = step 4. Team colours are variants.
- **laser** — 128x8 at 2x (64x4 on screen), streak travelling +x.
- **explosion** — 64x64, 7 frames, flash + ring + sparks.
- **stars_far / stars_near** — 512px seamless tiles, used as repeating parallax layers.

## Asset wishlist

- [ ] UI icons (fire, boost) if the HUD needs them

## Done

- ship, laser, explosion, stars_far, stars_near (all draft, owner reviewing in-game)

## Decisions and feedback log

- 2026-10-17: first pass was a detailed pixel-art fighter; owner: "wrong route", showed space1.io screenshot -> flat triangles, long laser streaks, no grid.
- 2026-10-17: team `mint` replaced by `blue` (too close to the player's cyan).
