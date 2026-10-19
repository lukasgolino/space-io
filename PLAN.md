# space-io — plan

Replica of space1.io in Godot 4.7.2. Art generated with PAGAN v0.4.0 (pinned), high-contrast arcade look
(not traditional pixel art). PAGAN friction is logged in `../PAGAN/SPACIO_USEREPORT.MD`.

## Core loop (owner answers 2026-10-17)
- Offline vs computer fleets first; sim kept controller-driven so multiplayer can come later.
- Fleet steers toward the mouse. Click fires a volley (every ship, straight out of its nose) with a
  recharge; holding repeats at the recharge rate. Space = boost, longer cooldown.
- One laser hit destroys a ship. Every kill destroys the victim's ship and spawns a new one just behind
  the killer's fleet (cap 30). Last ship → respawn with 1.
- Tight packed wedge formation (apex forward, matches space1.io screenshots). One hull, colour per fleet.
- Look: space1.io — flat neon triangles, long thin laser streaks, black space, sparse stars, bloom.
- Desktop 1920x1080 (Linux/Windows); web later. SFX in the juice milestone.

## Architecture
- `scripts/tune.gd` (autoload `Tune`): every feel number. Tuning = edit one file, or F12 live panel
  (`tune_panel.gd`: speed, speed scale, accel, accel scale, bullet speed) with "Save to tuning.cfg".
- `Fleet`: anchor that steers like one craft (human: `World.Controls`; bot: `BotBrain`); integrates all its
  ships in one pass (pull/slots, pairwise separation, inertia, firing). `Ship` is just the sprite + state.
- `Lasers`: packed arrays + one MultiMesh per team; segment-vs-ship collision on a spatial hash in `World`.
- `World`: modes SOLO / HOST / CLIENT; humans by peer id, spawning, kills → recruits, respawns, camera,
  name tags above human fleets (bots: leaderboard only). `hud.gd`: counts, bars, leaderboard, minimap, net line.
- `Net` (multiplayer): ENet/UDP, host-authoritative, bots run on the host. Clients send controls every tick;
  host sends 30 Hz snapshots (hand-packed, ~6 B/ship) + reliable events (laser, hit, explosion, death).
  Clients render 100 ms in the past, interpolated, and replay events at their tick. No client-side
  prediction yet: own-fleet input lag = RTT + 100 ms. `Net.PROTOCOL` must match; bump on wire changes.
- `main.gd` + `title.gd`: title (name, solo, host on a UDP port, join address). Esc leaves, F12 tuning.
- `Art` autoload reads `assets/generated/manifest.json` (the PAGAN contract).
- Verify: `tools/test.sh` (unit, smoke, 60 s sim, host+client over localhost, perf bench; timeouts and
  any ERROR line fail it), `tools/check.sh` = art build + test.sh. CI (`.github/workflows/ci.yml`) runs
  test.sh and checks committed art equals a fresh PAGAN build.
  Demo: `godot --path . -- --autopilot`; two-machine test: `-- --host` / `-- --join=IP`.

## Art pipeline (PAGAN)
- `requirements.txt` pins `pagan @ git+ssh://git@github.com/lukasgolino/PAGAN.git@v0.4.0`; local `.venv`.
- `pagan init art --godot .` → output to `assets/generated/`, `.gdignore` in `art/`.
- Look: small strict palette of saturated neons on near-black, hard dark outlines, `glow` keys for
  engines/cockpits. Fleet colours via palette-swap variants of one hull.
- Godot adds the arcade finish: WorldEnvironment glow/bloom, additive lasers, hit flash, particles,
  screen shake.
- Risk: PAGAN is pixel-art by design (palette keys, nearest-neighbour, no anti-aliasing). Smooth
  free rotation of a top-down sprite needs linear filtering at a higher native size (≈48–64 px).
  This is the main PAGAN stress test; findings go to the report.

## Milestones (each ends playable, committed, for you to try)
Status 2026-10-19: milestones 1–5 first pass done, plus host/join multiplayer (with bots) and F12 tuning.

1. **Scaffold** — Godot project, PAGAN install + art home, placeholder shapes, report file.
2. **Feel** — one ship, movement, camera, auto-fire lasers, arena bounds, starfield. Tune with you.
3. **Fleets** — formation, damage/HP, kill → +ship, death/respawn.
4. **Bots** — AI fleets (wander, chase smaller, flee bigger), spawning, HUD: fleet size, leaderboard, minimap.
5. **Art** — PAGAN ships ×fleet colours, lasers, explosions, background; replace placeholders.
6. **Juice** — bloom, shake, hit flash, particles, SFX.
7. **Shell** — title/name entry, game over, export (desktop; web optional).
