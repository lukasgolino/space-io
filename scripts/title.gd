class_name Title
extends Control
## Title screen: pilot name, play solo, host a game, or join a friend's. Remembers name + address.

signal chosen(mode: World.Mode, player_name: String, address: String)

const SETTINGS := "user://settings.cfg"

var message := ""

var _name: LineEdit
var _addr: LineEdit
var _port: SpinBox


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 14)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.add_child(box)
	add_child(centre)

	box.add_child(_label("SPACE IO", 72, Art.color(0)))
	if message != "":
		box.add_child(_label(message, 20, Color("#ff3a5c")))
	box.add_child(_label("pilot name", 16, Color(0.55, 0.6, 0.8)))
	_name = _edit(cfg.get_value("player", "name", ""), "your name (shown above your fleet)")
	_name.max_length = Net.MAX_NAME
	box.add_child(_name)

	var solo := _button("PLAY SOLO")
	solo.pressed.connect(func() -> void: _go(World.Mode.SOLO, ""))
	box.add_child(solo)

	box.add_child(_label("host: friends join your address (port must be reachable: same network, VPN, or port-forwarded UDP)", 14, Color(0.55, 0.6, 0.8)))
	var host_row := HBoxContainer.new()
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = cfg.get_value("net", "port", Net.DEFAULT_PORT)
	_port.prefix = "UDP port"
	_port.custom_minimum_size = Vector2(180, 0)
	host_row.add_child(_port)
	var host := _button("HOST GAME")
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.pressed.connect(func() -> void: _go(World.Mode.HOST, "127.0.0.1:%d" % int(_port.value)))
	host_row.add_child(host)
	box.add_child(host_row)

	var join_row := HBoxContainer.new()
	_addr = _edit(cfg.get_value("net", "address", ""), "host address, e.g. 192.168.1.20 or 1.2.3.4:%d" % Net.DEFAULT_PORT)
	_addr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_addr.text_submitted.connect(func(_t: String) -> void: _go(World.Mode.CLIENT, _addr.text))
	join_row.add_child(_addr)
	var join := _button("JOIN")
	join.pressed.connect(func() -> void: _go(World.Mode.CLIENT, _addr.text))
	join_row.add_child(join)
	box.add_child(join_row)

	box.add_child(_label("in game: F12 tuning   ·   Esc leave", 14, Color(0.55, 0.6, 0.8)))
	_name.grab_focus.call_deferred()


func _go(mode: World.Mode, address: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("player", "name", _name.text.strip_edges())
	cfg.set_value("net", "address", _addr.text.strip_edges())
	cfg.set_value("net", "port", int(_port.value))
	cfg.save(SETTINGS)
	chosen.emit.call_deferred(mode, _name.text, address)   # the title is freed by the receiver


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _edit(text: String, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.add_theme_font_size_override("font_size", 20)
	return e


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_size_override("font_size", 20)
	return b
