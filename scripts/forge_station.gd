extends Node
## Reusable, opt-in bridge for Forge's existing UI and the solar/VR scene.
## No audio nodes, tones, voice, microphone, or automatic network discovery.

signal state_changed(state: String)
signal signal_received(event: Dictionary)
signal context_received(event: Dictionary)
signal program_received(program: Dictionary)
signal receipt_received(receipt: Dictionary)
signal station_error(message: String)

const PROTOCOL := "forge.station/1"
var peer := WebSocketPeer.new()
var paired := false
var state := "OFFLINE"
var _app_id := ""
var _key := ""
var _sequence := 0
var _hello_sent := false
var _deadline := 0

func connect_station(url: String, app_id: String, key: String, tls: TLSOptions = null) -> Error:
    if key.length() < 16 or app_id.is_empty() or app_id.length() > 64:
        return ERR_INVALID_PARAMETER
    if not _local_url(url):
        return ERR_INVALID_PARAMETER
    disconnect_station()
    _app_id = app_id
    _key = key
    _sequence = 0
    _hello_sent = false
    peer = WebSocketPeer.new()
    peer.inbound_buffer_size = 262144
    peer.outbound_buffer_size = 65536
    var error := peer.connect_to_url(url, tls)
    if error == OK:
        _deadline = Time.get_ticks_msec() + 10000
        _set_state("CONNECTING")
    else:
        _key = ""
        _set_state("OFFLINE")
    return error

func _local_url(url: String) -> bool:
    var pattern := RegEx.new()
    pattern.compile("^(ws|wss)://(\\[[0-9a-fA-F:]+\\]|[a-zA-Z0-9.-]+)(:[0-9]{1,5})?(/[^\\s]*)?$")
    var match_url := pattern.search(url)
    if match_url == null:
        return false
    var host := match_url.get_string(2).trim_prefix("[").trim_suffix("]").to_lower()
    var loopback := host == "localhost" or host == "127.0.0.1" or host == "::1"
    if loopback:
        return true
    if match_url.get_string(1) != "wss" or not host.is_valid_ip_address():
        return false
    if host.contains(":"):
        return host.begins_with("fc") or host.begins_with("fd")
    var octets := host.split(".")
    return octets[0] == "10" or (octets[0] == "192" and octets[1] == "168") or (octets[0] == "172" and int(octets[1]) >= 16 and int(octets[1]) <= 31)

func disconnect_station() -> void:
    paired = false
    _key = ""
    _hello_sent = false
    _deadline = 0
    peer.close()
    _set_state("OFFLINE")

func _set_state(next: String) -> void:
    if state != next:
        state = next
        state_changed.emit(state)

func _process(_delta: float) -> void:
    peer.poll()
    var ready_state := peer.get_ready_state()
    if ready_state == WebSocketPeer.STATE_OPEN and not _hello_sent:
        _hello_sent = true
        var error := peer.send_text(JSON.stringify({"type": "forge.hello", "app_id": _app_id, "key": _key}))
        _key = ""
        if error != OK:
            disconnect_station()
            station_error.emit("Pairing message could not be sent")
            return
        _set_state("PAIRING")
    if not paired and _deadline > 0 and Time.get_ticks_msec() > _deadline:
        disconnect_station()
        station_error.emit("Station connection timed out")
        return
    if ready_state == WebSocketPeer.STATE_CLOSED:
        paired = false
        _key = ""
        _set_state("OFFLINE")
    var count := 0
    while ready_state == WebSocketPeer.STATE_OPEN and peer.get_available_packet_count() > 0 and count < 20:
        count += 1
        var packet := peer.get_packet()
        if packet.size() > 262144 or not peer.was_string_packet():
            station_error.emit("Invalid station frame")
            continue
        var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
        if parsed is Dictionary:
            _receive(parsed)

func _receive(event: Dictionary) -> void:
    var kind := str(event.get("type", ""))
    if kind == "forge.error":
        station_error.emit(str(event.get("message", "Station input rejected")))
        return
    if kind == "forge.ack":
        receipt_received.emit(event)
        return
    if event.get("protocol", "") != PROTOCOL:
        station_error.emit("Station protocol mismatch")
        return
    if kind == "forge.ready":
        paired = true
        _deadline = 0
        _set_state("PAIRED")
    elif kind == "forge.signal":
        signal_received.emit(event)
    elif kind == "forge.context":
        context_received.emit(event)
    elif kind == "forge.program.result" and event.get("program") is Dictionary:
        program_received.emit(event["program"])

func _send(event: Dictionary) -> Error:
    if not paired or peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
        return ERR_UNAVAILABLE
    _sequence += 1
    event["seq"] = _sequence
    event["id"] = "evt." + str(Time.get_ticks_usec()) + "." + str(_sequence)
    return peer.send_text(JSON.stringify(event))

func send_morse(text: String, target: String = "*") -> Error:
    return _send({"type": "forge.signal", "format": "morse", "text": text, "target": target})

func send_data(text: String, width: int = 8, target: String = "*") -> Error:
    if width != 8 and width != 16:
        return ERR_INVALID_PARAMETER
    return _send({"type": "forge.signal", "format": "u" + str(width), "text": text, "target": target})

func send_words(values: Array, width: int = 8, target: String = "*") -> Error:
    if width != 8 and width != 16:
        return ERR_INVALID_PARAMETER
    return _send({"type": "forge.signal", "format": "u" + str(width), "values": values, "target": target})

func publish_map_context(context: Dictionary, target: String = "*") -> Error:
    return _send({"type": "forge.context", "map_context": context, "target": target})

func request_program(settings: Dictionary) -> Error:
    return _send({"type": "forge.program", "request": settings})

func _exit_tree() -> void:
    disconnect_station()
