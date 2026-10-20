extends Node3D
## Standalone OpenXR/desktop preview. The existing installed solar app is untouched.

const Producer = preload("res://scripts/station_plan.gd")
const Bridge = preload("res://scripts/forge_station.gd")
const BG := Color("111610")
const PANEL := Color("1c231b")
const LIME := Color("d6ef83")
const MUTED := Color("b0ba9e")
var bodies: Array = []
var formats: Dictionary = {}
var planets: Dictionary = {}
var selected := "Mars"
var bridge: Node
var camera: Camera3D
var origin: XROrigin3D
var xr_active := false
var controllers: Array[XRController3D] = []
var rays: Array[RayCast3D] = []
var held: Dictionary = {}
var last_pointer := Vector2.ZERO
var viewport_ui: SubViewport
var panel_mesh: MeshInstance3D
var desktop_panel: SubViewportContainer
var tabs: TabContainer
var state_label: Label
var selection_label: Label
var program_status: Label
var show_select: OptionButton
var mode_select: OptionButton
var minutes: SpinBox
var topic: LineEdit
var host_name: LineEdit
var guest_name: LineEdit
var direction: TextEdit
var source_title: LineEdit
var source_notes: TextEdit
var transcript: CheckBox
var program_text: TextEdit
var generate_button: Button
var signal_text: LineEdit
var signal_format: OptionButton
var signal_output: TextEdit
var receiver: LineEdit
var pairing_key: LineEdit
var receiver_certificate: TextEdit
var station_prompt := ""
var pending_generation := false
var scroll_at := 0
var pointer_dots: Array[MeshInstance3D] = []

func _ready() -> void:
    bodies = JSON.parse_string(FileAccess.get_file_as_string("res://station/solar.json"))
    formats = JSON.parse_string(FileAccess.get_file_as_string("res://station/formats.json"))
    bridge = Bridge.new()
    add_child(bridge)
    _build_world()
    _camera_setup()
    _build_ui()
    bridge.state_changed.connect(func(value: String) -> void:
        state_label.text = value + " · TEXT / DATA ONLY"
        generate_button.disabled = not bridge.paired
    )
    bridge.station_error.connect(func(message: String) -> void:
        state_label.text = message
        pending_generation = false
        generate_button.disabled = not bridge.paired
    )
    bridge.receipt_received.connect(func(receipt: Dictionary) -> void:
        state_label.text = "DUPLICATE SUPPRESSED" if receipt.get("duplicate", false) else "Written to %d paired app(s)" % int(receipt.get("delivered", 0))
    )
    bridge.signal_received.connect(func(event: Dictionary) -> void:
        _show_signal(event.get("payload", {}))
        state_label.text = "Signal received from " + str(event.get("source", "peer"))
    )
    bridge.context_received.connect(func(event: Dictionary) -> void:
        var context: Dictionary = event.get("payload", {})
        var name: String = str(context.get("body", ""))
        if planets.has(name):
            select_body(name)
    )
    bridge.program_received.connect(_program_received)
    select_body("Mars")
    build_outline()
    print("SOLAR_PREVIEW_READY bodies=", planets.size(), " audio_nodes=", audio_node_count(), " xr=", xr_active)

func audio_node_count() -> int:
    return find_children("*", "AudioStreamPlayer", true, false).size() + find_children("*", "AudioStreamPlayer2D", true, false).size() + find_children("*", "AudioStreamPlayer3D", true, false).size()

func _build_world() -> void:
    var environment := WorldEnvironment.new()
    var settings := Environment.new()
    settings.background_mode = Environment.BG_COLOR
    settings.background_color = Color("080f12")
    settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    settings.ambient_light_color = Color("d5e0da")
    settings.ambient_light_energy = 0.8
    environment.environment = settings
    add_child(environment)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-50, -20, 0)
    light.light_energy = 1.4
    light.shadow_enabled = false
    add_child(light)
    for i: int in range(bodies.size()):
        var body: Dictionary = bodies[i]
        var angle: float = i * 2.399
        var distance: float = i * 0.52
        var position_body := Vector3(cos(angle) * distance, 1.1, -4.0 + sin(angle) * distance)
        var mesh := MeshInstance3D.new()
        mesh.name = str(body["name"])
        var sphere := SphereMesh.new()
        var radius: float = float(body["size"]) * 0.25
        sphere.radius = radius
        sphere.height = radius * 2.0
        sphere.radial_segments = 24
        sphere.rings = 12
        mesh.mesh = sphere
        var material := StandardMaterial3D.new()
        material.albedo_color = Color(str(body["color"]))
        material.roughness = 1.0
        if i == 0:
            material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mesh.material_override = material
        add_child(mesh)
        mesh.position = position_body
        var collision := StaticBody3D.new()
        collision.set_meta("body", str(body["name"]))
        var shape := CollisionShape3D.new()
        var ball := SphereShape3D.new()
        ball.radius = maxf(radius, 0.1)
        shape.shape = ball
        collision.add_child(shape)
        mesh.add_child(collision)
        planets[str(body["name"])] = mesh
        if i > 0:
            var ring := MeshInstance3D.new()
            var line := ImmediateMesh.new()
            var ink := StandardMaterial3D.new()
            ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            ink.albedo_color = Color("35443d")
            line.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, ink)
            for n: int in range(97):
                var phase: float = n * TAU / 96.0
                line.surface_add_vertex(Vector3(cos(phase) * distance, 1.1, -4.0 + sin(phase) * distance))
            line.surface_end()
            ring.mesh = line
            add_child(ring)
    var caption := Label3D.new()
    caption.text = "LUMA FORGE SOLAR\nSchematic positions and sizes · not live ephemerides"
    caption.font_size = 42
    caption.pixel_size = 0.003
    caption.position = Vector3(0, 3.0, -4.0)
    caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    add_child(caption)

func _camera_setup() -> void:
    origin = XROrigin3D.new()
    origin.name = "TravelOrigin"
    add_child(origin)
    var xr_camera := XRCamera3D.new()
    origin.add_child(xr_camera)
    camera = xr_camera
    camera.current = true
    if DisplayServer.get_name() != "headless":
        var interface: XRInterface = XRServer.find_interface("OpenXR")
        if interface != null:
            xr_active = interface.is_initialized() or interface.initialize()
    if xr_active:
        get_viewport().use_xr = true
        DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
        for hand: String in ["left_hand", "right_hand"]:
            var controller := XRController3D.new()
            controller.tracker = StringName(hand)
            controller.pose = &"aim"
            origin.add_child(controller)
            controllers.append(controller)
            var ray := RayCast3D.new()
            ray.target_position = Vector3(0, 0, -20)
            ray.collision_mask = 3
            controller.add_child(ray)
            rays.append(ray)
            var dot := MeshInstance3D.new()
            var marker := SphereMesh.new()
            marker.radius = 0.008
            marker.height = 0.016
            dot.mesh = marker
            var ink := StandardMaterial3D.new()
            ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            ink.albedo_color = LIME
            dot.material_override = ink
            add_child(dot)
            pointer_dots.append(dot)
    else:
        camera.position = Vector3(0, 7, 11)
        camera.look_at(Vector3(0, 1.1, -4.0))

func _style() -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = PANEL
    box.border_color = Color("354030")
    box.set_border_width_all(1)
    box.set_corner_radius_all(14)
    box.set_content_margin_all(14)
    return box

func _label(parent: Node, title: String, size: int = 24) -> Label:
    var label := Label.new()
    label.text = title
    label.add_theme_font_size_override("font_size", size)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    parent.add_child(label)
    return label

func _button(parent: Node, title: String, action: Callable) -> Button:
    var button := Button.new()
    button.text = title
    button.custom_minimum_size.y = 58
    button.pressed.connect(action)
    parent.add_child(button)
    return button

func _entry(parent: Node, title: String, initial: String = "") -> LineEdit:
    _label(parent, title, 20)
    var entry := LineEdit.new()
    entry.text = initial
    entry.placeholder_text = title
    entry.custom_minimum_size.y = 54
    parent.add_child(entry)
    return entry

func _tab(title: String) -> VBoxContainer:
    var scroll := ScrollContainer.new()
    scroll.name = title
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    tabs.add_child(scroll)
    var column := VBoxContainer.new()
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_theme_constant_override("separation", 12)
    scroll.add_child(column)
    return column

func _build_ui() -> void:
    viewport_ui = SubViewport.new()
    viewport_ui.size = Vector2i(640, 1100)
    viewport_ui.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    if xr_active:
        add_child(viewport_ui)
        panel_mesh = MeshInstance3D.new()
        var quad := QuadMesh.new()
        quad.size = Vector2(1.1, 1.89)
        panel_mesh.mesh = quad
        var material := StandardMaterial3D.new()
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.albedo_texture = viewport_ui.get_texture()
        panel_mesh.material_override = material
        origin.add_child(panel_mesh)
        panel_mesh.position = Vector3(1.2, 1.5, -1.3)
        panel_mesh.look_at(origin.global_position + Vector3(0, 1.6, 0), Vector3.UP, true)
        var target := StaticBody3D.new()
        target.collision_layer = 2
        target.collision_mask = 0
        target.set_meta("station_panel", true)
        var shape := CollisionShape3D.new()
        var box := BoxShape3D.new()
        box.size = Vector3(1.1, 1.89, 0.02)
        shape.shape = box
        target.add_child(shape)
        panel_mesh.add_child(target)
    else:
        var overlay := CanvasLayer.new()
        add_child(overlay)
        desktop_panel = SubViewportContainer.new()
        desktop_panel.position = Vector2(12, 12)
        desktop_panel.size = Vector2(410, maxf(400, get_viewport().get_visible_rect().size.y - 24))
        desktop_panel.stretch = true
        overlay.add_child(desktop_panel)
        desktop_panel.add_child(viewport_ui)
    var panel := PanelContainer.new()
    panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    panel.add_theme_stylebox_override("panel", _style())
    var theme := Theme.new()
    theme.default_font_size = 24
    theme.set_color("font_color", "Label", Color("f2f5e9"))
    theme.set_color("font_color", "Button", Color("f2f5e9"))
    theme.set_stylebox("normal", "Button", _style())
    panel.theme = theme
    viewport_ui.add_child(panel)
    var layout := VBoxContainer.new()
    layout.add_theme_constant_override("separation", 12)
    panel.add_child(layout)
    var brand := _label(layout, "FORGE / SOLAR STATION", 32)
    brand.add_theme_color_override("font_color", LIME)
    state_label = _label(layout, "OFFLINE · TEXT / DATA ONLY", 18)
    tabs = TabContainer.new()
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    layout.add_child(tabs)
    var map := _tab("Map")
    selection_label = _label(map, "Mars", 34)
    _label(map, "Choose a world, focus the map, or share its selection with paired Forge apps.", 22)
    for body: Dictionary in bodies:
        var name_body: String = str(body["name"])
        _button(map, name_body, select_body.bind(name_body))
    _button(map, "Focus selected world", focus_selected)
    _button(map, "Share selection", func() -> void:
        var error: Error = bridge.publish_map_context({"body": selected})
        if error != OK:
            state_label.text = "Pair a receiver to share selections."
    )
    _label(map, "Desktop: click worlds, WASD to travel. VR: point and trigger to select; right stick to travel.", 18)
    var station := _tab("Station")
    show_select = OptionButton.new()
    for key: String in formats:
        show_select.add_item(str(formats[key]["title"]))
        show_select.set_item_metadata(show_select.item_count - 1, key)
    station.add_child(show_select)
    mode_select = OptionButton.new()
    mode_select.add_item("Fictional simulation")
    mode_select.add_item("Source-based draft")
    station.add_child(mode_select)
    minutes = SpinBox.new()
    minutes.min_value = 1
    minutes.max_value = 120
    minutes.value = 5
    minutes.suffix = "min target"
    station.add_child(minutes)
    show_select.item_selected.connect(func(index: int) -> void:
        var key: String = str(show_select.get_item_metadata(index))
        minutes.value = int(formats[key]["minutes"])
    )
    topic = _entry(station, "Central topic", "How a fictional Mars settlement keeps its water flowing")
    topic.max_length = 240
    host_name = _entry(station, "Host", "Luma")
    guest_name = _entry(station, "Guest (for interviews)", "Guest")
    _label(station, "Creative direction", 20)
    direction = TextEdit.new()
    direction.text = "Calm, curious reporting. Follow one story from cause to consequences."
    direction.custom_minimum_size.y = 130
    station.add_child(direction)
    source_title = _entry(station, "Source title (for factual news)")
    source_notes = TextEdit.new()
    source_notes.placeholder_text = "Source notes; required for factual news"
    source_notes.custom_minimum_size.y = 130
    station.add_child(source_notes)
    transcript = CheckBox.new()
    transcript.text = "Notes contain the guest's actual transcript"
    station.add_child(transcript)
    _button(station, "Build running order", build_outline)
    generate_button = _button(station, "Generate / remix with paired model", generate)
    generate_button.disabled = true
    _button(station, "Save template", save_template)
    _button(station, "Load template", load_template)
    program_status = _label(station, "PROMPT READY", 20)
    program_text = TextEdit.new()
    program_text.editable = false
    program_text.custom_minimum_size.y = 400
    station.add_child(program_text)
    _button(station, "Copy prompt / script", func() -> void: DisplayServer.clipboard_set(station_prompt))
    var signals := _tab("Signals")
    signal_text = _entry(signals, "Message", "CQ MARS")
    signal_text.max_length = 160
    signal_format = OptionButton.new()
    for title: String in ["Visual Morse", "8-bit UTF-8 data", "16-bit UTF-16BE data"]:
        signal_format.add_item(title)
    signals.add_child(signal_format)
    _button(signals, "Preview silent signal", preview_signal)
    _button(signals, "Send to paired apps", send_signal)
    signal_output = TextEdit.new()
    signal_output.editable = false
    signal_output.custom_minimum_size.y = 380
    signals.add_child(signal_output)
    _label(signals, "No voice, tones, microphone, or physical RF output.", 20)
    var link := _tab("Link")
    _label(link, "Optional receiver on any supported host. Offline planning and map exploration need no connection.", 22)
    receiver = _entry(link, "wss:// private LAN receiver")
    pairing_key = _entry(link, "Pairing key")
    pairing_key.secret = true
    _label(link, "Trusted receiver certificate (optional PEM)", 20)
    receiver_certificate = TextEdit.new()
    receiver_certificate.placeholder_text = "Paste the public certificate for a private-CA receiver. No private keys."
    receiver_certificate.custom_minimum_size.y = 160
    link.add_child(receiver_certificate)
    _button(link, "Pair station", pair_station)
    _button(link, "Disconnect", func() -> void: bridge.disconnect_station())
    _label(link, "Pairing keys are not saved in templates. LAN connections require a trusted TLS certificate.", 18)

func select_body(name_body: String) -> void:
    if not planets.has(name_body):
        return
    selected = name_body
    if is_instance_valid(selection_label):
        selection_label.text = selected
    for key: String in planets:
        var mesh: MeshInstance3D = planets[key]
        var material: StandardMaterial3D = mesh.material_override
        material.emission_enabled = key == selected
        material.emission = material.albedo_color * 0.35 if key == selected else Color.BLACK

func focus_selected() -> void:
    var target: Vector3 = planets[selected].global_position
    if xr_active:
        origin.global_position = Vector3(target.x, 0, target.z + 1.6)
    else:
        camera.global_position = target + Vector3(0, 1.2, 2.6)
        camera.look_at(target)

func _request() -> Dictionary:
    var sources: Array = []
    if mode_select.selected == 1:
        sources.append({"id": "source_1", "title": source_title.text, "notes": source_notes.text,
            "url": "", "published_at": "", "guest_transcript": transcript.button_pressed})
    return {"show": str(show_select.get_selected_metadata()), "mode": "simulation" if mode_select.selected == 0 else "sourced",
        "minutes": int(minutes.value), "topic": topic.text, "direction": direction.text,
        "host": host_name.text, "guest": guest_name.text, "map_context": {"body": selected}, "sources": sources}

func build_outline() -> void:
    var plan: Dictionary = Producer.make_plan(_request())
    if plan.has("error"):
        program_status.text = str(plan["error"])
        return
    station_prompt = Producer.prompt(plan)
    var text: String = str(plan["label"]) + "\n" + str(plan["title"]) + ": " + str(plan["topic"]) + "\n\n"
    for beat: Dictionary in plan["beats"]:
        text += "%02d:%02d · %s\n%s\n\n" % [int(beat["start_seconds"]) / 60, int(beat["start_seconds"]) % 60, beat["title"], beat["direction"]]
    program_text.text = text + str(plan["duration_note"])
    program_status.text = "PROMPT READY · Running order and generation brief"

func generate() -> void:
    if pending_generation:
        return
    var plan: Dictionary = Producer.make_plan(_request())
    if plan.has("error"):
        program_status.text = str(plan["error"])
        return
    if bridge.request_program(_request()) != OK:
        program_status.text = "Pair a station receiver to generate a text draft."
        return
    pending_generation = true
    generate_button.disabled = true
    program_status.text = "GENERATING TEXT DRAFT…"
    get_tree().create_timer(65).timeout.connect(func() -> void:
        if pending_generation:
            pending_generation = false
            generate_button.disabled = not bridge.paired
            program_status.text = "Model timed out. Your prompt is still available."
    )

func _program_received(program: Dictionary) -> void:
    pending_generation = false
    generate_button.disabled = not bridge.paired
    if program.get("status", "") != "draft_ready":
        build_outline()
        program_status.text = str(program.get("note", "Prompt ready; no model configured."))
        return
    var script: Dictionary = program["script"]
    station_prompt = str(program["plan"]["label"]) + "\n" + str(script["title"]) + "\n\n"
    for segment: Dictionary in script["segments"]:
        station_prompt += str(segment["title"]) + "\n"
        for cue: Dictionary in segment["cues"]:
            station_prompt += str(cue["speaker"]) + ": " + str(cue["text"]) + "\n"
        station_prompt += "\n"
    program_text.text = station_prompt
    program_status.text = "TEXT DRAFT · Review before use"

func _format() -> String:
    return ["morse", "u8", "u16"][signal_format.selected]

func preview_signal() -> void:
    _show_signal(Producer.preview(signal_text.text, _format()))

func _show_signal(value: Dictionary) -> void:
    if value.has("error"):
        signal_output.text = str(value["error"])
    elif value.get("format", "") == "morse":
        signal_output.text = str(value.get("code", "")) + "\n\nVisual timing data, no tones.\n" + JSON.stringify(value.get("pulses", []))
    else:
        signal_output.text = str(value.get("hex", "")) + "\n\nUnsigned words:\n" + str(value.get("values", []))

func send_signal() -> void:
    var value: Dictionary = Producer.preview(signal_text.text, _format())
    _show_signal(value)
    if value.has("error"):
        return
    var error: Error = bridge.send_morse(signal_text.text) if _format() == "morse" else bridge.send_data(signal_text.text, 8 if _format() == "u8" else 16)
    if error != OK:
        state_label.text = "Pair a receiver before sending. Preview remains offline."

func pair_station() -> void:
    var options: TLSOptions = null
    if not receiver_certificate.text.strip_edges().is_empty():
        var certificate := X509Certificate.new()
        if certificate.load_from_string(receiver_certificate.text.strip_edges()) != OK:
            state_label.text = "Use the receiver's public PEM certificate, without a private key."
            return
        options = TLSOptions.client(certificate)
    var error: Error = bridge.connect_station(receiver.text.strip_edges(), "solar-" + str(Time.get_ticks_usec()), pairing_key.text, options)
    if error == OK:
        pairing_key.clear()
    else:
        state_label.text = "Check the local receiver address and pairing key."

func save_template() -> void:
    var config := ConfigFile.new()
    config.set_value("station", "template", _request())
    program_status.text = "Template saved on this device." if config.save("user://solar-station.cfg") == OK else "Template could not be saved."

func load_template() -> void:
    var config := ConfigFile.new()
    if config.load("user://solar-station.cfg") != OK:
        program_status.text = "No saved template yet."
        return
    var request: Dictionary = config.get_value("station", "template", {})
    for i: int in range(show_select.item_count):
        if show_select.get_item_metadata(i) == request.get("show", "mars_news"):
            show_select.select(i)
    mode_select.select(0 if request.get("mode", "simulation") == "simulation" else 1)
    minutes.value = int(request.get("minutes", 5))
    topic.text = str(request.get("topic", ""))
    direction.text = str(request.get("direction", ""))
    host_name.text = str(request.get("host", "Luma"))
    guest_name.text = str(request.get("guest", "Guest"))
    var sources: Array = request.get("sources", [])
    source_title.text = "" if sources.is_empty() else str(sources[0].get("title", ""))
    source_notes.text = "" if sources.is_empty() else str(sources[0].get("notes", ""))
    transcript.button_pressed = not sources.is_empty() and sources[0].get("guest_transcript", false)
    select_body(str(request.get("map_context", {}).get("body", "Mars")))
    build_outline()

func _unhandled_input(event: InputEvent) -> void:
    if xr_active:
        return
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var start: Vector3 = camera.project_ray_origin(event.position)
        var query := PhysicsRayQueryParameters3D.create(start, start + camera.project_ray_normal(event.position) * 100, 1)
        var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
        if not hit.is_empty() and hit["collider"].has_meta("body"):
            select_body(str(hit["collider"].get_meta("body")))

func _process(delta: float) -> void:
    if not is_instance_valid(camera):
        return
    if not xr_active:
        if is_instance_valid(desktop_panel):
            desktop_panel.size = Vector2(minf(410, get_viewport().get_visible_rect().size.x * 0.42), maxf(300, get_viewport().get_visible_rect().size.y - 24))
        var forward := Vector3(camera.global_basis.z.x, 0, camera.global_basis.z.z).normalized()
        var side := Vector3(camera.global_basis.x.x, 0, camera.global_basis.x.z).normalized()
        var move := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
        origin.position += (side * move.x + forward * move.y) * delta * 2.0
        return
    var on_panel := false
    for i: int in range(controllers.size()):
        var controller: XRController3D = controllers[i]
        var ray: RayCast3D = rays[i]
        ray.force_raycast_update()
        pointer_dots[i].visible = ray.is_colliding()
        if ray.is_colliding():
            pointer_dots[i].global_position = ray.get_collision_point()
        var pressed: bool = controller.is_button_pressed("trigger_click")
        var was_pressed: bool = held.get(i, false)
        var panel_hit: bool = ray.is_colliding() and ray.get_collider().has_meta("station_panel")
        if panel_hit:
            on_panel = true
            var local: Vector3 = panel_mesh.to_local(ray.get_collision_point())
            last_pointer = Vector2((local.x / 1.1 + 0.5) * viewport_ui.size.x, (0.5 - local.y / 1.89) * viewport_ui.size.y)
            var motion := InputEventMouseMotion.new()
            motion.position = last_pointer
            motion.global_position = last_pointer
            viewport_ui.push_input(motion, true)
            var scroll: float = controller.get_vector2("primary").y
            if absf(scroll) > 0.4 and Time.get_ticks_msec() > scroll_at:
                scroll_at = Time.get_ticks_msec() + 130
                var wheel := InputEventMouseButton.new()
                wheel.position = last_pointer
                wheel.global_position = last_pointer
                wheel.button_index = MOUSE_BUTTON_WHEEL_UP if scroll > 0 else MOUSE_BUTTON_WHEEL_DOWN
                wheel.pressed = true
                viewport_ui.push_input(wheel, true)
        if pressed != was_pressed and (panel_hit or was_pressed):
            var click := InputEventMouseButton.new()
            click.position = last_pointer
            click.global_position = last_pointer
            click.button_index = MOUSE_BUTTON_LEFT
            click.pressed = pressed
            viewport_ui.push_input(click, true)
        if pressed and not was_pressed and ray.is_colliding() and ray.get_collider().has_meta("body"):
            select_body(str(ray.get_collider().get_meta("body")))
        held[i] = pressed
    if controllers.size() > 1 and not on_panel:
        var axis: Vector2 = controllers[1].get_vector2("primary")
        var forward := Vector3(-camera.global_basis.z.x, 0, -camera.global_basis.z.z).normalized()
        var side := Vector3(camera.global_basis.x.x, 0, camera.global_basis.x.z).normalized()
        origin.position += (side * axis.x + forward * axis.y) * delta * 1.2

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_PAUSED and is_instance_valid(bridge):
        bridge.disconnect_station()
