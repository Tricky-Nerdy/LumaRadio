extends SceneTree

var failures: Array[String] = []
var signals: Array[Dictionary] = []
var contexts: Array[Dictionary] = []
var programs: Array[Dictionary] = []

func _initialize() -> void:
    call_deferred("run")

func check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
        printerr("FAIL: " + message)

func until(condition: Callable) -> bool:
    var deadline: int = Time.get_ticks_msec() + 5000
    while Time.get_ticks_msec() < deadline:
        if condition.call():
            return true
        await create_timer(0.01).timeout
    return false

func run() -> void:
    var bridge: Script = load("res://scripts/forge_station.gd")
    var solar: Node = bridge.new()
    var radio: Node = bridge.new()
    root.add_child(solar)
    root.add_child(radio)
    radio.signal_received.connect(func(event: Dictionary) -> void: signals.append(event))
    radio.context_received.connect(func(event: Dictionary) -> void: contexts.append(event))
    solar.program_received.connect(func(program: Dictionary) -> void: programs.append(program))
    var address: String = OS.get_environment("STATION_TEST_URL")
    var key: String = OS.get_environment("STATION_TEST_KEY")
    check(solar.connect_station(address, "engine-solar", key) == OK, "Solar connection starts")
    check(radio.connect_station(address, "engine-radio", key) == OK, "Radio connection starts")
    check(await until(func() -> bool: return solar.paired and radio.paired), "Both actual Godot peers pair")
    if solar.paired and radio.paired:
        check(solar.send_morse("CQ MARS") == OK, "Send Morse")
        check(await until(func() -> bool: return signals.size() >= 1), "Receive Morse")
        if signals.size() > 0:
            check(signals[0]["payload"]["code"] == "-.-. --.- / -- .- .-. ...", "Morse data matches")
        check(solar.send_data("🌍", 16) == OK, "Send Unicode words")
        check(await until(func() -> bool: return signals.size() >= 2), "Receive Unicode words")
        if signals.size() > 1:
            check(signals[1]["payload"]["hex"] == "d83cdf0d", "16-bit wire encoding")
        check(solar.publish_map_context({"body": "Saturn"}) == OK, "Send selected world")
        check(await until(func() -> bool: return contexts.size() >= 1), "Receive selected world")
        if contexts.size() > 0:
            check(contexts[0]["payload"]["body"] == "Saturn", "Selection snapshot matches")
        check(solar.request_program({"show": "interview", "topic": "Fictional Saturn observatory"}) == OK, "Request station program")
        check(await until(func() -> bool: return programs.size() >= 1), "Receive program from Python producer")
        if programs.size() > 0:
            check(programs[0]["status"] == "prompt_ready", "Unconfigured model does not fake a draft")
            check(programs[0]["plan"]["show"] == "interview", "Requested format retained")
        check(solar._key.is_empty() and radio._key.is_empty(), "Pairing secrets cleared from adapter")
    solar.disconnect_station()
    radio.disconnect_station()
    solar.queue_free()
    radio.queue_free()
    await process_frame
    print("ENGINE_NETWORK_SMOKE failures: ", failures.size())
    quit(0 if failures.is_empty() else 1)
