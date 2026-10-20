extends Control

const VERSION := "0.2.0"
const SIGNALS := ["SQUAWK", "MORSE SOS", "MORSE CQ", "ROGER", "QSL", "73", "88", "STATIC", "BLASTER", "WALKIE"]
const POINTS := ["ALPHA", "BRAVO", "CHARLIE", "DELTA", "ECHO"]
const INK := Color("e7eee7")
const MUTED := Color("98aaa5")
const AMBER := Color("f2b85a")
const GREEN := Color("a5e2af")

var player: AudioStreamPlayer
var socket := WebSocketPeer.new()
var radio_url := "ws://127.0.0.1:8765"
var radio_link_enabled := false
var reconnect_at := 0
var status: Label
var connection: Label
var link_detail: Label
var ptt: Button
var mute_button: Button
var volume_knob: Button
var volume_label: Label
var settings_error: Label
var holding_ptt := false
var muted := false
var volume := 70.0
var last_link_state := -1
var rng := RandomNumberGenerator.new()
var telemetry_path := "user://lumaradio-telemetry.jsonl"
var session_id := str(Time.get_unix_time_from_system())

func _ready() -> void:
    if OS.has_feature("solar_station"):
        get_tree().change_scene_to_file.call_deferred("res://scenes/solar_map.tscn")
        return
    rng.randomize()
    var saved := ConfigFile.new()
    if saved.load("user://radio-settings.cfg") == OK:
        radio_url = str(saved.get_value("radio", "url", radio_url))
        volume = clampf(float(saved.get_value("radio", "volume", volume)), 0, 100)
    _build_ui()
    player = AudioStreamPlayer.new()
    add_child(player)
    _apply_volume()
    _event("session_start", {"platform": OS.get_name(), "version": VERSION})

func _surface(fill: Color, edge: Color, radius: int = 16) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = fill
    box.border_color = edge
    box.set_border_width_all(2)
    box.set_corner_radius_all(radius)
    box.content_margin_left = 18
    box.content_margin_right = 18
    box.content_margin_top = 14
    box.content_margin_bottom = 14
    return box

func _label(parent: Node, value: String, size: int = 22, color: Color = INK) -> Label:
    var label := Label.new()
    label.text = value
    label.add_theme_font_size_override("font_size", size)
    label.add_theme_color_override("font_color", color)
    parent.add_child(label)
    return label

func _button(parent: Node, title: String, action: Callable) -> Button:
    var button := Button.new()
    button.text = title
    button.custom_minimum_size.y = 62
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.add_theme_font_size_override("font_size", 21)
    button.pressed.connect(action)
    parent.add_child(button)
    return button

func _build_ui() -> void:
    var theme := Theme.new()
    theme.default_font_size = 22
    theme.set_color("font_color", "Label", INK)
    theme.set_color("font_color", "Button", INK)
    theme.set_color("font_hover_color", "Button", Color.WHITE)
    theme.set_color("font_pressed_color", "Button", Color.WHITE)
    theme.set_stylebox("normal", "Button", _surface(Color("202d37"), Color("3b4d58")))
    theme.set_stylebox("hover", "Button", _surface(Color("2c3b45"), AMBER))
    theme.set_stylebox("pressed", "Button", _surface(Color("40534c"), GREEN))
    theme.set_stylebox("focus", "Button", _surface(Color(0, 0, 0, 0), AMBER))
    self.theme = theme
    var background := ColorRect.new()
    background.color = Color("0a1019")
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(background)
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 20)
    add_child(margin)
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    margin.add_child(scroll)
    var shell := VBoxContainer.new()
    shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    shell.add_theme_constant_override("separation", 0)
    scroll.add_child(shell)
    var hardware := HBoxContainer.new()
    hardware.custom_minimum_size.y = 64
    hardware.add_theme_constant_override("separation", 28)
    shell.add_child(hardware)
    var antenna := PanelContainer.new()
    antenna.custom_minimum_size = Vector2(36, 64)
    antenna.add_theme_stylebox_override("panel", _surface(Color("1c2a35"), Color("52616b"), 12))
    hardware.add_child(antenna)
    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    hardware.add_child(spacer)
    volume_knob = _button(hardware, "VOL\n" + str(int(volume)), _toggle_mute)
    volume_knob.name = "VolumeKnob"
    volume_knob.custom_minimum_size = Vector2(64, 64)
    volume_knob.size_flags_horizontal = Control.SIZE_SHRINK_END
    volume_knob.add_theme_font_size_override("font_size", 17)
    volume_knob.add_theme_stylebox_override("normal", _surface(Color("263940"), AMBER, 36))
    volume_knob.tooltip_text = "Toggle sound; use the volume slider below to adjust."
    var casing := PanelContainer.new()
    var casing_style := _surface(Color("15212c"), Color("4c5e6a"), 32)
    casing_style.shadow_color = Color(0, 0, 0, 0.5)
    casing_style.shadow_size = 8
    casing_style.content_margin_top = 10
    casing_style.content_margin_bottom = 10
    casing.add_theme_stylebox_override("panel", casing_style)
    shell.add_child(casing)
    var body := VBoxContainer.new()
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 12)
    casing.add_child(body)
    var header := HBoxContainer.new()
    body.add_child(header)
    var brand := _label(header, "LUMA / RADIO", 30)
    brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _label(header, "V" + VERSION, 19, AMBER)
    var grille := HBoxContainer.new()
    grille.add_theme_constant_override("separation", 7)
    body.add_child(grille)
    for i in 24:
        var bar := ColorRect.new()
        bar.color = Color("293640")
        bar.custom_minimum_size.y = 12
        bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        grille.add_child(bar)
    var screen := PanelContainer.new()
    screen.add_theme_stylebox_override("panel", _surface(Color("172c27"), Color("50745d"), 20))
    body.add_child(screen)
    var display := VBoxContainer.new()
    display.add_theme_constant_override("separation", 8)
    screen.add_child(display)
    var top := HBoxContainer.new()
    display.add_child(top)
    connection = _label(top, "LOCAL MODE", 20, AMBER)
    connection.name = "ConnectionStatus"
    connection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _label(top, "CH 01", 20, GREEN)
    _label(display, "LUMA ACTUAL", 40, GREEN)
    _label(display, "GRACIE ZERO ONE", 21, MUTED)
    var rule := HSeparator.new()
    display.add_child(rule)
    status = _label(display, "READY / LOCAL TONES", 23, GREEN)
    status.name = "ActionStatus"
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    link_detail = _label(display, "Control link disconnected / connect under Link", 17, MUTED)
    link_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    ptt = Button.new()
    ptt.name = "PushToSignal"
    ptt.text = "HOLD TO SIGNAL\nPTT PREVIEW"
    ptt.custom_minimum_size.y = 128
    ptt.focus_mode = Control.FOCUS_NONE
    ptt.add_theme_font_size_override("font_size", 30)
    ptt.add_theme_color_override("font_color", Color("17201e"))
    ptt.add_theme_color_override("font_hover_color", Color("17201e"))
    ptt.add_theme_color_override("font_pressed_color", Color("102017"))
    ptt.add_theme_stylebox_override("normal", _surface(AMBER, Color("ffd997"), 24))
    ptt.add_theme_stylebox_override("hover", _surface(Color("ffcc79"), Color("ffe0a5"), 24))
    ptt.add_theme_stylebox_override("pressed", _surface(GREEN, Color("d0f4d5"), 24))
    ptt.button_down.connect(_press_ptt)
    ptt.button_up.connect(_release_ptt)
    body.add_child(ptt)
    var boundary := _label(body, "Tones + desktop controls. Microphone audio is not sent in this preview.", 17, MUTED)
    boundary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var volume_row := HBoxContainer.new()
    volume_row.add_theme_constant_override("separation", 14)
    body.add_child(volume_row)
    mute_button = _button(volume_row, "SOUND ON", _toggle_mute)
    mute_button.name = "SoundToggle"
    mute_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    var slider := HSlider.new()
    slider.name = "Volume"
    slider.min_value = 0
    slider.max_value = 100
    slider.value = volume
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.custom_minimum_size.x = 120
    slider.value_changed.connect(_set_volume)
    volume_row.add_child(slider)
    volume_label = _label(volume_row, str(int(volume)) + "%", 20, MUTED)
    var tabs := TabContainer.new()
    tabs.name = "RadioControls"
    tabs.add_theme_font_size_override("font_size", 23)
    tabs.add_theme_stylebox_override("panel", _surface(Color("111b26"), Color("293b47")))
    body.add_child(tabs)
    var signals := GridContainer.new()
    signals.name = "Signals"
    signals.columns = 3
    signals.add_theme_constant_override("h_separation", 10)
    signals.add_theme_constant_override("v_separation", 10)
    tabs.add_child(signals)
    for title in SIGNALS:
        var button := _button(signals, title, Callable(self, "_signal").bind(title))
        button.name = title.replace(" ", "_")
    var objectives := GridContainer.new()
    objectives.name = "Objectives"
    objectives.columns = 2
    objectives.add_theme_constant_override("h_separation", 10)
    objectives.add_theme_constant_override("v_separation", 10)
    tabs.add_child(objectives)
    for point in POINTS:
        var captured := _button(objectives, point + "\nCAPTURED", Callable(self, "_objective").bind(point, true))
        captured.name = point + "_CAPTURED"
        captured.add_theme_color_override("font_color", GREEN)
        captured.add_theme_stylebox_override("normal", _surface(Color("1c3b31"), Color("528468")))
        captured.add_theme_stylebox_override("pressed", _surface(Color("3e7455"), GREEN))
        var lost := _button(objectives, point + "\nLOST", Callable(self, "_objective").bind(point, false))
        lost.name = point + "_LOST"
        lost.add_theme_color_override("font_color", Color("ffb5a5"))
        lost.add_theme_stylebox_override("normal", _surface(Color("422c30"), Color("97625d")))
        lost.add_theme_stylebox_override("pressed", _surface(Color("7d4246"), Color("ffc8ae")))
    var link := VBoxContainer.new()
    link.name = "Link"
    link.add_theme_constant_override("separation", 12)
    tabs.add_child(link)
    var explanation := _label(link, "Connect to your desktop radio receiver over Wi-Fi. Sound effects work without a connection.", 20, MUTED)
    explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _button(link, "SET DESKTOP LINK", _show_link_settings)
    _button(link, "RECONNECT", _connect_radio)
    _button(link, "DISCONNECT", func() -> void:
        _release_ptt()
        radio_link_enabled = false
        socket.close()
    )
    tabs.current_tab = 1
    _label(body, "COMMAND CENTER / OFFLINE SOUNDBOARD", 16, MUTED)

func _press_ptt() -> void:
    if holding_ptt:
        return
    holding_ptt = true
    _signal("WALKIE")
    var sent := _send_radio("ptt", "down")
    ptt.text = "RELEASE TO END\nSIGNAL ACTIVE"
    status.text = "PTT CONTROL SENT" if sent else "LOCAL TONE ONLY"
    _event("ptt", {"pressed": true, "sent": sent})

func _release_ptt() -> void:
    if not holding_ptt:
        return
    holding_ptt = false
    var sent := _send_radio("ptt", "up")
    ptt.text = "HOLD TO SIGNAL\nPTT PREVIEW"
    status.text = "READY / CONTROL LINK" if socket.get_ready_state() == WebSocketPeer.STATE_OPEN else "READY / LOCAL TONES"
    _event("ptt", {"pressed": false, "sent": sent})

func _toggle_mute() -> void:
    muted = not muted
    mute_button.text = "MUTED" if muted else "SOUND ON"
    volume_knob.text = "VOL\nOFF" if muted else "VOL\n" + str(int(volume))
    _apply_volume()

func _set_volume(value: float) -> void:
    volume = value
    volume_label.text = str(int(volume)) + "%"
    volume_knob.text = "VOL\nOFF" if muted else "VOL\n" + str(int(volume))
    _apply_volume()
    _save_settings()

func _apply_volume() -> void:
    if is_instance_valid(player):
        player.volume_db = linear_to_db(volume / 100.0) if volume > 0 and not muted else -80.0

func _save_settings() -> void:
    var saved := ConfigFile.new()
    saved.set_value("radio", "url", radio_url)
    saved.set_value("radio", "volume", volume)
    var error := saved.save("user://radio-settings.cfg")
    if error != OK:
        status.text = "SETTINGS NOT SAVED / " + str(error)

func _show_link_settings() -> void:
    var dialog := ConfirmationDialog.new()
    dialog.title = "Desktop control link"
    dialog.ok_button_text = "Connect"
    var form := VBoxContainer.new()
    form.add_theme_constant_override("separation", 14)
    dialog.add_child(form)
    _label(form, "Desktop WebSocket address", 21)
    var entry := LineEdit.new()
    entry.text = radio_url
    entry.custom_minimum_size = Vector2(500, 60)
    entry.add_theme_font_size_override("font_size", 21)
    form.add_child(entry)
    settings_error = _label(form, "", 18, AMBER)
    dialog.dialog_hide_on_ok = false
    dialog.confirmed.connect(func():
        var url := entry.text.strip_edges()
        if not (url.begins_with("ws://") or url.begins_with("wss://")):
            settings_error.text = "Use a ws:// or wss:// desktop address."
            return
        _release_ptt()
        socket.close()
        radio_url = url
        _save_settings()
        _connect_radio()
        dialog.queue_free()
    )
    dialog.canceled.connect(dialog.queue_free)
    add_child(dialog)
    dialog.popup_centered(Vector2i(560, 240))

func _objective(point: String, captured: bool) -> void:
    status.text = point + (" CAPTURED" if captured else " LOST")
    _event("objective", {"point": point, "captured": captured})
    _send_radio("button", point + (" CAPTURED" if captured else " LOST"))
    var pitch := 880 + POINTS.find(point) * 110
    _play_pattern([pitch, pitch * 1.335, pitch * 1.782] if captured else [pitch * 1.782, pitch * 0.891, pitch * 0.445], 0.13)

func _signal(title: String) -> void:
    status.text = title
    _event("sound_pressed", {"name": title})
    _send_radio("button", title)
    var patterns := {"SQUAWK":[880,660,920], "MORSE SOS":[650,650,650,0,650,650,650], "MORSE CQ":[650,0,650,0,650], "ROGER":[900,1150], "QSL":[1000,700,1000], "73":[650,900,650], "88":[850,850,1100], "STATIC":[100,120,90,130], "BLASTER":[1300,800,400], "WALKIE":[400,1200,500]}
    _play_pattern(patterns.get(title, [600]), 0.12)

func _play_pattern(tones: Array, duration: float) -> void:
    var sample_rate := 22050
    var samples := PackedByteArray()
    var phase := 0.0
    for tone in tones:
        for i in int(sample_rate * duration):
            var value := 0.0
            if tone > 0:
                phase += TAU * float(tone) / sample_rate
                value = sin(phase) * 0.35 * minf(1.0, float(i)/160.0) * minf(1.0, float(int(sample_rate*duration)-i)/160.0)
                if tone < 150:
                    value = rng.randf_range(-0.3,0.3)
            var pcm := int(clampf(value,-1,1)*32767)
            samples.append(pcm & 255)
            samples.append((pcm >> 8) & 255)
    var sound := AudioStreamWAV.new()
    sound.format = AudioStreamWAV.FORMAT_16_BITS
    sound.mix_rate = sample_rate
    sound.data = samples
    player.stop()
    player.stream = sound
    player.play()

func _event(kind: String, details: Dictionary = {}) -> void:
    if not OS.is_debug_build():
        return
    var record := {"timestamp": Time.get_datetime_string_from_system(true), "session": session_id, "event": kind, "data": details}
    var file := FileAccess.open(telemetry_path, FileAccess.READ_WRITE)
    if file == null:
        file = FileAccess.open(telemetry_path, FileAccess.WRITE)
    if file == null:
        push_warning("Telemetry file unavailable: " + str(FileAccess.get_open_error()))
        return
    file.seek_end()
    file.store_line(JSON.stringify(record))
    file.close()

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        _release_ptt()
        _event("session_end")
    elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
        if is_instance_valid(ptt):
            _release_ptt()

func _connect_radio() -> void:
    radio_link_enabled = true
    if is_instance_valid(ptt):
        _release_ptt()
    socket.close()
    socket = WebSocketPeer.new()
    var error := socket.connect_to_url(radio_url)
    reconnect_at = Time.get_ticks_msec() + 5000
    if error != OK and is_instance_valid(status):
        status.text = "LOCAL TONES / CHECK DESKTOP LINK"
    last_link_state = -1

func _process(_delta: float) -> void:
    if OS.has_feature("solar_station") or OS.get_environment("LUMARADIO_TEST_OFFLINE") == "1":
        return
    socket.poll()
    var state := socket.get_ready_state()
    if state != last_link_state and is_instance_valid(connection):
        last_link_state = state
        var online := state == WebSocketPeer.STATE_OPEN
        connection.text = "CONTROL LINK ONLINE" if online else "LOCAL MODE"
        connection.add_theme_color_override("font_color", GREEN if online else AMBER)
        link_detail.text = "Desktop controls connected / microphone off" if online else "Desktop offline / local sound effects available"
        if not online:
            _release_ptt()
    if radio_link_enabled and state == WebSocketPeer.STATE_CLOSED and Time.get_ticks_msec() >= reconnect_at:
        _connect_radio()
    while socket.get_ready_state() == WebSocketPeer.STATE_OPEN and socket.get_available_packet_count() > 0:
        socket.get_packet()

func _send_radio(kind: String, value: String) -> bool:
    if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
        return socket.send_text(JSON.stringify({"type": kind, "value": value})) == OK
    return false

