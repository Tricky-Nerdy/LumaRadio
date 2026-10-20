extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    if not value:
        failures.append(message)
        printerr("FAIL: " + message)

func run() -> void:
    root.size = Vector2i(450, 800)
    root.content_scale_size = Vector2i(720, 1280)
    root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
    var app: Control = load("res://scenes/main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    await process_frame
    app.socket.close()
    app.socket = WebSocketPeer.new()
    await process_frame
    check(app.connection.text == "LOCAL MODE", "Offline link must not appear connected")
    var waveforms: Dictionary = {}
    for point in app.POINTS:
        for captured in [true, false]:
            var button_name: String = point + ("_CAPTURED" if captured else "_LOST")
            var button: Button = app.find_child(button_name, true, false)
            check(button != null, "Missing " + button_name)
            if button == null:
                continue
            button.pressed.emit()
            check(app.status.text == point + (" CAPTURED" if captured else " LOST"), "Wrong action " + button_name)
            var waveform: PackedByteArray = app.player.stream.data
            var digest: String = waveform.hex_encode().sha256_text()
            check(not waveforms.has(digest), "Objective tones must differ: " + button_name)
            waveforms[digest] = true
    check(waveforms.size() == 10, "All ten objective tones required")
    var ptt: Button = app.find_child("PushToSignal", true, false)
    ptt.button_down.emit()
    check(app.holding_ptt, "PTT press state")
    check(app.status.text == "LOCAL TONE ONLY", "PTT must disclose offline mode")
    ptt.button_up.emit()
    check(not app.holding_ptt, "PTT release state")
    ptt.button_down.emit()
    app._notification(Control.NOTIFICATION_APPLICATION_PAUSED)
    check(not app.holding_ptt, "PTT must release when app pauses")
    app._toggle_mute()
    check(app.player.volume_db == -80.0, "Mute must affect playback")
    app._toggle_mute()
    app._set_volume(35.0)
    check(absf(app.player.volume_db - linear_to_db(0.35)) < 0.001, "Volume must affect playback")
    app._set_volume(70.0)
    app._show_link_settings()
    await process_frame
    var dialog: ConfirmationDialog = app.get_child(app.get_child_count() - 1)
    var entry: LineEdit = dialog.find_children("*", "LineEdit", true, false)[0]
    entry.text = "https://invalid.example"
    dialog.confirmed.emit()
    check(is_instance_valid(dialog) and not app.settings_error.text.is_empty(), "Invalid desktop URL must stay in settings")
    dialog.canceled.emit()
    await process_frame
    if OS.get_cmdline_user_args().has("--capture"):
        await RenderingServer.frame_post_draw
        var error: Error = root.get_texture().get_image().save_png("/home/trickynerdy/.local/state/luma-radio-ui-20261020/command-center.png")
        check(error == OK, "Save visual review")
    print("UI_SMOKE: 10 distinct objective controls and tones; PTT release/pause; offline status; volume/mute; URL validation. Failures: ", failures.size())
    app.queue_free()
    await process_frame
    quit(0 if failures.is_empty() else 1)
