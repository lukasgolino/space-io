"""Generates the procedural sprites (ship, laser, explosion, stars). Run from art/: ../.venv/bin/python tools/gen_art.py

Everything is drawn in the cyan fleet ramp (a b c d); team colours are PAGAN variants that swap that ramp.
Sprites are authored at 2x their on-screen size; the game draws them at 0.5 scale with linear filtering.
"""

import math

from pagan import api

TEAMS = ["red", "orange", "yellow", "lime", "magenta", "violet", "blue"]
VARIANTS = {team: {"ramp_swap": {"cyan": team}} for team in TEAMS}


def inside(poly, x, y):
    """Even-odd point-in-polygon test (PAGAN's Canvas has no polygon fill)."""
    hit = False
    for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            hit = not hit
    return hit


def edge_distance(poly, x, y):
    best = 1e9
    for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
        dx, dy = x1 - x0, y1 - y0
        t = max(0.0, min(1.0, ((x - x0) * dx + (y - y0) * dy) / (dx * dx + dy * dy)))
        best = min(best, math.hypot(x - (x0 + t * dx), y - (y0 + t * dy)))
    return best


# ---------------------------------------------------------------- ship (64x64, nose to the right)

# Plain isosceles triangle, like space1.io: nose right, flat back.
SHIP_HULL = [(60, 32), (6, 9), (6, 55)]


def ship_frame() -> list[str]:
    c = api.Canvas(64, 64)
    for y in range(64):
        for x in range(64):
            px, py = x + 0.5, y + 0.5
            if inside(SHIP_HULL, px, py):
                c.put(x, y, "d" if edge_distance(SHIP_HULL, px, py) < 2.2 else "c")
    return c.rows()


def ship() -> None:
    api.write(
        "sprites/ship.sprite.yaml",
        api.sprite_yaml(
            "ship",
            (64, 64),
            {"main": ship_frame()},
            description="Fighter, straight top-down, nose pointing right (+x). space1.io style: a flat solid "
            "triangle in the fleet colour with a pale 2px rim; the engine adds the neon glow. Drawn at 2x, shown at 0.5x.",
            pivot=[32, 32],
            outline="none",
            tags=["ship"],
            variants=VARIANTS,
        ),
    )


# ---------------------------------------------------------------- laser (128x8, travelling right)


def laser() -> None:
    c = api.Canvas(128, 8)
    c.rect(3, 1, 124, 6, "b")
    c.rect(1, 2, 126, 5, "c")
    c.rect(2, 3, 125, 4, "d")
    c.rect(40, 3, 123, 4, "w")
    for x, y in ((3, 1), (124, 1), (3, 6), (124, 6)):
        c.put(x, y, ".")
    api.write(
        "sprites/laser.sprite.yaml",
        api.sprite_yaml(
            "laser",
            (128, 8),
            {"bolt": c.rows()},
            description="Laser streak travelling right: long thin line, white-hot front, pale core, fleet-colour glow. "
            "Drawn at 2x (64x4 on screen).",
            pivot=[64, 4],
            outline="none",
            tags=["fx"],
            variants=VARIANTS,
        ),
    )


# ---------------------------------------------------------------- explosion (64x64, 7 frames)


def explosion() -> None:
    frames = {}
    steps = 7
    for i in range(steps):
        t = (i + 1) / steps
        c = api.Canvas(64, 64)
        r = 6 + 24 * t
        thick = max(1.5, 5 * (1 - t))
        if i < 3:
            c.circle(32, 32, r - thick / 2 + 0.8, "d" if i else "w")
            c.circle(32, 32, r * (0.55 - 0.15 * i), "w")
        c.ring(32, 32, r, r, thick, "c" if i < 4 else "b")
        # sparks flying outward
        for k in range(10):
            ang = k * math.tau / 10 + 0.3 * (k % 3)
            dist = r * (1.05 + 0.25 * api.hash01(k, 0, 7)) + 2
            sx, sy = 32 + math.cos(ang) * dist, 32 + math.sin(ang) * dist
            key = "w" if i < 2 else ("d" if i < 4 else "c")
            if i < steps - 1:
                c.rect(round(sx) - 1, round(sy) - 1, round(sx), round(sy), key)
        if i >= 4:
            c.fade(0.25 * (i - 3), seed=i)
        frames[f"burst_{i}"] = c.rows()
    api.write(
        "sprites/explosion.sprite.yaml",
        api.sprite_yaml(
            "explosion",
            (64, 64),
            frames,
            {"burst": {"frames": list(frames), "fps": 20, "loop": False}},
            description="Ship explosion: white flash, expanding neon shock ring and sparks, fading out. Drawn at 2x.",
            pivot=[32, 32],
            outline="none",
            tags=["fx"],
            variants=VARIANTS,
            lint={"disable": ["W001", "W005", "W007"]},
        ),
    )


# ---------------------------------------------------------------- starfield (two seamless 256px parallax layers)


def starfield() -> None:
    far = api.Canvas(512, 512)
    far.scatter(40, "2", seed=11)
    far.scatter(22, "3", seed=12)
    far.scatter(10, "g", seed=13)
    near = api.Canvas(512, 512)
    near.scatter(9, "g", seed=21, size=2)
    near.scatter(4, "w", seed=22, size=2)
    for name, canvas, desc in (
        ("stars_far", far, "Far parallax star layer: sparse dim 1px stars, seamless 512px tile."),
        ("stars_near", near, "Near parallax star layer: a few 2px stars, seamless 512px tile."),
    ):
        api.write(
            f"tiles/{name}.tiles.yaml",
            api.tileset_yaml(name, (512, 512), {"main": canvas.rows()}, description=desc, columns=1,
                             lint={"disable": ["W001"]}),
        )


if __name__ == "__main__":
    ship()
    laser()
    explosion()
    starfield()
