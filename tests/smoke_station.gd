extends SceneTree
## Engine parse/API smoke check for the opt-in adapter. No network or audio.

var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    if not value:
        failures.append(message)
        printerr("FAIL: " + message)

func run() -> void:
    var source: Script = load("res://scripts/forge_station.gd")
    check(source != null and source.can_instantiate(), "Adapter must parse")
    if source == null or not source.can_instantiate():
        quit(1)
        return
    var adapter: Node = source.new()
    root.add_child(adapter)
    check(adapter.state == "OFFLINE" and not adapter.paired, "No automatic connection")
    check(adapter.get_child_count() == 0, "No audio nodes or hidden services")
    check(adapter.send_morse("SOS") == ERR_UNAVAILABLE, "Offline signal is not queued or sent")
    check(adapter.send_data("Mars", 32) == ERR_INVALID_PARAMETER, "Reject unsupported width")
    check(not adapter._local_url("ws://192.168.1.2:8765"), "LAN pairing needs TLS")
    check(not adapter._local_url("wss://8.8.8.8:8765"), "Public endpoints rejected")
    check(not adapter._local_url("ws://localhost.evil.example"), "Reject misleading local hostname")
    check(adapter._local_url("ws://127.0.0.1:8765"), "Loopback receiver permitted")
    check(adapter._local_url("wss://192.168.1.2:8765"), "TLS LAN receiver permitted")
    adapter._receive({"type": "forge.ready", "protocol": "forge.station/1"})
    check(adapter.state == "PAIRED" and adapter.paired, "Ready follows station handshake")
    adapter.disconnect_station()
    check(adapter.state == "OFFLINE" and not adapter.paired, "Disconnect clears paired state")
    adapter.queue_free()
    await process_frame
    print("STATION_ADAPTER_SMOKE failures: ", failures.size())
    quit(0 if failures.is_empty() else 1)
