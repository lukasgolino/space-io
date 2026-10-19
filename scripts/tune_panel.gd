class_name TunePanel
extends PanelContainer
## F12: live sliders for the fleet-feel numbers (all fleets). Host-only in multiplayer; the host's
## changes reach every client. "Save" writes tuning.cfg.

## [Tune key, label, min, max, step]
const ROWS := [
	["max_speed", "fleet speed (px/s, 1 ship)", 50.0, 1000.0, 5.0],
	["size_slowdown", "fleet speed scale (speed lost at cap)", 0.0, 0.95, 0.01],
	["accel", "acceleration (px/s²)", 100.0, 8000.0, 50.0],
	["accel_slowdown", "accel scale (accel lost at cap)", 0.0, 0.95, 0.01],
	["laser_speed", "bullet speed (px/s, constant)", 50.0, 1500.0, 5.0],
]

var _sliders := {}   # key -> HSlider
var _values := {}    # key -> Label
var _note: Label
var _buttons: Array[Button] = []


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_CENTER_LEFT)
	position = Vector2(24, 140)
	custom_minimum_size = Vector2(420, 0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.03, 0.08, 0.88)
	bg.border_color = Color(0.3, 0.4, 0.7, 0.8)
	bg.set_border_width_all(1)
	bg.set_content_margin_all(14)
	add_theme_stylebox_override("panel", bg)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	box.add_child(_label("TUNING  (F12)", 18, Color(0.85, 0.9, 1.0)))
	for row: Array in ROWS:
		var key: String = row[0]
		var head := HBoxContainer.new()
		var name_l := _label(row[1], 14, Color(0.55, 0.6, 0.8))
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name_l)
		var val := _label("", 14, Color(0.85, 0.9, 1.0))
		head.add_child(val)
		box.add_child(head)
		var s := HSlider.new()
		s.min_value = row[2]
		s.max_value = row[3]
		s.step = row[4]
		s.focus_mode = Control.FOCUS_NONE   # Space must keep meaning "boost"
		s.value_changed.connect(_on_slider.bind(key))
		box.add_child(s)
		_sliders[key] = s
		_values[key] = val
	var buttons := HBoxContainer.new()
	for spec: Array in [["Save to tuning.cfg", _save], ["Reset these", _reset]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(spec[1])
		buttons.add_child(b)
		_buttons.append(b)
	box.add_child(buttons)
	_note = _label("", 13, Color(0.55, 0.6, 0.8))
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_note)
	Tune.changed.connect(_refresh)
	visibility_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not visible:
		return
	for key: String in _sliders:
		var s: HSlider = _sliders[key]
		s.set_value_no_signal(Tune.get(key))
		s.editable = not Tune.locked
		_values[key].text = _fmt(Tune.get(key))
	for b in _buttons:
		b.disabled = Tune.locked
	_note.text = "the host controls these" if Tune.locked else "applies to every fleet, live; bullets fly at a constant speed"


func _on_slider(v: float, key: String) -> void:
	if Tune.locked:
		return
	_values[key].text = _fmt(v)
	Tune.apply_values({key: v})


func _save() -> void:
	Tune.save_file()
	_note.text = Tune.status


## Only this panel's values; everything else stays as tuning.cfg set it.
func _reset() -> void:
	var d := {}
	for row: Array in ROWS:
		d[row[0]] = Tune.default_value(row[0])
	Tune.apply_values(d)


static func _fmt(v: float) -> String:
	return "%.2f" % v if absf(v) < 10.0 else "%d" % roundi(v)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
