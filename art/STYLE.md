# Style bible

## 1. Palette
- `palettes/neon.pal.yaml`, strict. `ink` (background only), `light`, and one 4-step ramp per fleet colour: dark, mid, bright, pale.
- Every fleet-coloured asset is drawn in `cyan` (a b c d); other teams are `ramp_swap` variants.

## 2. Scale
- Authored at 2x on-screen size; the game draws at 0.5 with linear filtering + mipmaps (smooth rotation).

## 3. Outlines
- None. Contrast comes from the black background and the pale rim.

## 4. Light / shading
- Flat. No light direction (sprites rotate freely). Glow is done by the engine (HDR modulate + bloom).

## 5. Do / Don't
- Do: simple geometric silhouettes, bright fills, pale rims.
- Don't: pixel detail, shading ramps across a shape, dark outlines.

## Changelog
- v1: initial style
