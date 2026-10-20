extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("run")

func check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
        printerr("FAIL: " + message)

func run() -> void:
    root.content_scale_size = Vector2i(1280, 820)
    root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
    root.size = Vector2i(1280, 820)
    var scene: PackedScene = load("res://scenes/solar_map.tscn")
    check(scene != null, "Solar scene loads")
    if scene == null:
        quit(1)
        return
    var app: Node3D = scene.instantiate()
    root.add_child(app)
    await process_frame
    await process_frame
    if DisplayServer.get_name() != "headless":
        DisplayServer.window_set_size(Vector2i(1280, 820))
        root.size = Vector2i(1280, 820)
        await process_frame
    check(app.planets.size() == 9, "Sun and eight worlds")
    check(app.selected == "Mars", "Initial selection")
    check(not app.bridge.paired, "No automatic network connection")
    check(app.audio_node_count() == 0, "No audio nodes")
    app.select_body("Saturn")
    check(app.selected == "Saturn", "World selection")
    app.focus_selected()
    check(app.camera.global_position.distance_to(app.planets["Saturn"].global_position) < 4, "Focus selected world")
    for i: int in range(app.show_select.item_count):
        app.show_select.select(i)
        app.minutes.value = int(app.formats[str(app.show_select.get_item_metadata(i))]["minutes"])
        app.build_outline()
        check(app.program_status.text.begins_with("PROMPT READY"), "Offline format " + str(i))
    var producer: Script = load("res://scripts/station_plan.gd")
    var signal_data: Dictionary = producer.preview("🌍", "u16")
    check(signal_data.get("hex", "") == "d83cdf0d", "16-bit surrogate pairs")
    check(producer.preview("SOS A", "morse")["code"] == "... --- ... / .-", "Morse text")
    var units: int = 0
    for pulse: Dictionary in producer.preview("SOS A", "morse")["pulses"]:
        units += int(pulse["units"])
    check(units == 39, "Morse timing")
    app.mode_select.select(1)
    app.build_outline()
    check(not app.program_status.text.begins_with("PROMPT READY"), "Factual drafts require source notes")
    app.mode_select.select(0)
    app.build_outline()
    if OS.get_cmdline_user_args().has("--capture"):
        DirAccess.make_dir_recursive_absolute("res://build/ui")
        app.tabs.current_tab = 0
        await process_frame
        await RenderingServer.frame_post_draw
        check(root.get_texture().get_image().get_width() >= 1000, "Capture desktop viewport at a readable width")
        check(root.get_texture().get_image().save_png("res://build/ui/solar-map-desktop.png") == OK, "Capture map layout")
        app.tabs.current_tab = 1
        await process_frame
        await RenderingServer.frame_post_draw
        check(root.get_texture().get_image().save_png("res://build/ui/solar-station-desktop.png") == OK, "Capture producer layout")
    print("SOLAR_SCENE_SMOKE failures: ", failures.size())
    app.queue_free()
    await process_frame
    quit(0 if failures.is_empty() else 1)
