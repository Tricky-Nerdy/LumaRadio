extends Control
var player: AudioStreamPlayer
var status: Label
var rng := RandomNumberGenerator.new()
const SIGNALS := ["SQUAWK", "MORSE SOS", "MORSE CQ", "ROGER", "QSL", "73", "88", "STATIC", "BLASTER", "WALKIE"]
const POINTS := ["ALPHA", "BRAVO", "CHARLIE", "DELTA", "ECHO"]
func _ready() -> void:
    rng.randomize()
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
    for label in SIGNALS:
        _button(panel, label, Callable(self, "_signal").bind(label))
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
    _play_pattern([880, 1175, 1568] if captured else [1568, 784, 392], 0.13)
func _signal(label: String) -> void:
    status.text = label
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
