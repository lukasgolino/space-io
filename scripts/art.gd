extends Node
## Team colours and access to PAGAN-built art via manifest.json (the art <-> game contract).

const TEAMS: Array[String] = ["cyan", "red", "orange", "yellow", "lime", "magenta", "violet", "blue"]
const BASE_TEAM := "cyan"   # PAGAN can't name the base variant (SPACIO_USEREPORT S6)
const COLORS: Array[Color] = [
	Color("#22e8ff"), Color("#ff3a5c"), Color("#ff9a1a"), Color("#ffee22"),
	Color("#66ff22"), Color("#ff3aff"), Color("#9a70ff"), Color("#4a8aff"),
]
const MANIFEST := "res://assets/generated/manifest.json"

var _assets: Dictionary = {}
var _cache: Dictionary = {}


func _ready() -> void:
	var text := FileAccess.get_file_as_string(MANIFEST)
	var data: Variant = JSON.parse_string(text)
	assert(data is Dictionary, "missing or bad %s" % MANIFEST)
	_assets = data["assets"]


func frames(asset: String, team: int) -> SpriteFrames:
	var key := "%s/%d" % [asset, team]
	if not _cache.has(key):
		var entry: Dictionary = _assets[asset]
		var name := TEAMS[team]
		var path: String = entry["godot_sprite_frames"] if name == BASE_TEAM else entry["variants"][name]["godot_sprite_frames"]
		_cache[key] = load(path)
	return _cache[key]


## The whole sheet texture (for single-frame assets drawn by MultiMesh).
func sheet(asset: String, team: int) -> Texture2D:
	var sf := frames(asset, team)
	var tex := sf.get_frame_texture(sf.get_animation_names()[0], 0)
	return (tex as AtlasTexture).atlas if tex is AtlasTexture else tex


func color(team: int) -> Color:
	return COLORS[team]


func sheet_path(asset: String) -> String:
	return _assets[asset]["sheet"]
