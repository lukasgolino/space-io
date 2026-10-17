"""After `pagan build`: turn on mipmaps for every generated sprite so 2x-authored art downsamples smoothly.

PAGAN v0.4.0 can't set Godot import options (see ../PAGAN/SPACIO_USEREPORT.MD S4). Godot keeps [params]
in existing .import files, so this only needs to run when a new sheet appears; it's idempotent.
"""

import pathlib
import sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "assets/generated")
TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

mipmaps/generate=true
"""
for png in sorted(root.rglob("*.png")):
    imp = png.with_name(png.name + ".import")
    if not imp.exists():
        imp.write_text(TEMPLATE)
        continue
    text = imp.read_text()
    if "mipmaps/generate=false" in text:
        imp.write_text(text.replace("mipmaps/generate=false", "mipmaps/generate=true"))
