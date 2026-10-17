extends Control
var player: AudioStreamPlayer
var status: Label
var rng := RandomNumberGenerator.new()
var telemetry_path := "user://lumaradio-telemetry.jsonl"
var session_id := str(Time.get_unix_time_from_system())
const SIGNALS := ["SQUAWK", "MORSE SOS", "MORSE CQ", "ROGER", "QSL", "73", "88", "STATIC", "BLASTER", "WALKIE"]
const POINTS := ["ALPHA", "BRAVO", "CHARLIE", "DELTA", "ECHO"]
func _ready() -> void:
    rng.randomize()
    _event("session_start", {"platform": OS.get_name(), "version": "0.1.1"})
    var panel := VBoxContainer.new()
    panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    panel.add_theme_constant_override("separation", 12)
    add_child(panel)
    var heading := Label.new()
    heading.text = "LUMA RADIO  •  OFFLINE"
    heading.add_theme_font_size_override("font_size", 30)
    panel.add_child(heading)
    status = Label.new()
    status.text = "RADIO READY"
    panel.add_child(status)
    player = AudioStreamPlayer.new()
    add_child(player)
    var mic := Button.new()
    mic.text = "🎙  PUSH TO TALK"
    mic.custom_minimum_size = Vector2(0, 180)
    mic.add_theme_font_size_override("font_size", 34)
    mic.button_down.connect(func(): _signal("WALKIE"))
    panel.add_child(mic)
    var grid := GridContainer.new()
    grid.columns = 3
    grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
    panel.add_child(grid)
    for label in SIGNALS:
        _button(grid, label, Callable(self, "_signal").bind(label))
    for point in POINTS:
        var row := HBoxContainer.new()
        panel.add_child(row)
        _button(row, point + " CAPTURED", Callable(self, "_objective").bind(point, true))
        _button(row, point + " LOST", Callable(self, "_objective").bind(point, false))
func _button(parent: Node, title: String, action: Callable) -> void:
    var b := Button.new()
    b.text = title
    b.custom_minimum_size.y = 52
    b.pressed.connect(action)
    parent.add_child(b)
func _objective(point: String, captured: bool) -> void:
    status.text = point + (" CAPTURED" if captured else " LOST")
    _event("objective", {"point": point, "captured": captured})
    _play_pattern([880, 1175, 1568] if captured else [1568, 784, 392], 0.13)
func _signal(label: String) -> void:
    status.text = label
    _event("sound_pressed", {"name": label})
    var patterns := {"SQUAWK":[880,660,920], "MORSE SOS":[650,650,650,0,650,650,650], "MORSE CQ":[650,0,650,0,650], "ROGER":[900,1150], "QSL":[1000,700,1000], "73":[650,900,650], "88":[850,850,1100], "STATIC":[100,120,90,130], "BLASTER":[1300,800,400], "WALKIE":[400,1200,500]}
    _play_pattern(patterns.get(label, [600]), 0.12)
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
        _event("session_end")
