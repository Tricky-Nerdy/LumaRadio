extends RefCounted
## Offline planning and codecs using the same format data as Forge's producer.

static func make_plan(request: Dictionary) -> Dictionary:
    var formats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://station/formats.json"))
    var show: String = str(request.get("show", "mars_news"))
    if not formats.has(show):
        return {"error": "Choose a station format."}
    var topic: String = str(request.get("topic", "")).strip_edges()
    if topic.is_empty() or topic.length() > 240:
        return {"error": "Enter a central topic (up to 240 characters)."}
    var mode: String = str(request.get("mode", "simulation"))
    var sources: Array = request.get("sources", [])
    if mode not in ["simulation", "sourced"]:
        return {"error": "Choose simulation or sourced mode."}
    if mode == "sourced" and sources.is_empty():
        return {"error": "Add source notes before creating factual news."}
    var host: String = str(request.get("host", "Luma")).strip_edges()
    var guest: String = str(request.get("guest", "Guest")).strip_edges()
    if host.is_empty() or guest.is_empty() or host == guest:
        return {"error": "Host and guest need different, non-empty names."}
    if host.length() > 60 or guest.length() > 60 or str(request.get("direction", "")).length() > 4000:
        return {"error": "Use names up to 60 characters and direction up to 4000 characters."}
    for source: Dictionary in sources:
        if str(source.get("title", "")).strip_edges().is_empty() or str(source.get("notes", "")).strip_edges().is_empty():
            return {"error": "Add a source title and substantive notes."}
    var spec: Dictionary = formats[show]
    var minutes: int = int(request.get("minutes", spec["minutes"]))
    if minutes < 1 or minutes > 120:
        return {"error": "Target duration must be 1–120 minutes."}
    var total: int = minutes * 60
    var weight: int = 0
    for beat: Array in spec["beats"]:
        weight += int(beat[2])
    var allocations: Array[int] = []
    var order: Array[int] = []
    var allocated: int = 0
    for i: int in range(spec["beats"].size()):
        var seconds: int = int(float(total * int(spec["beats"][i][2])) / weight)
        allocations.append(seconds)
        allocated += seconds
        order.append(i)
    order.sort_custom(func(a: int, b: int) -> bool:
        var ar: int = total * int(spec["beats"][a][2]) % weight
        var br: int = total * int(spec["beats"][b][2]) % weight
        return ar > br if ar != br else a < b
    )
    for i: int in range(total - allocated):
        allocations[order[i]] += 1
    var beats: Array = []
    var start: int = 0
    for i: int in range(spec["beats"].size()):
        var beat: Array = spec["beats"][i]
        beats.append({"id": beat[0], "title": beat[1], "start_seconds": start,
            "target_seconds": allocations[i], "direction": beat[3]})
        start += allocations[i]
    return {"station": "Luma Forge Solar", "show": show, "title": spec["title"], "purpose": spec["purpose"],
        "topic": topic, "direction": str(request.get("direction", "")).strip_edges(), "host": host, "guest": guest,
        "mode": mode, "map_context": request.get("map_context", {}), "sources": sources,
        "target_seconds": total, "beats": beats,
        "duration_note": "Planned running order; text cues are not a measured full-duration performance.",
        "label": "FICTIONAL SIMULATION" if mode == "simulation" else "SOURCE-BASED DRAFT — REVIEW REQUIRED", "audio": false}

static func prompt(plan: Dictionary) -> String:
    return FileAccess.get_file_as_string("res://station/instructions.txt") + "\n\nPROGRAM PLAN\n" + JSON.stringify(plan, "  ")

static func preview(text: String, format: String) -> Dictionary:
    if text.is_empty() or text.length() > 160:
        return {"error": "Signal text needs 1–160 characters."}
    if format == "morse":
        for i: int in range(text.length()):
            if text.unicode_at(i) > 127:
                return {"error": "Morse supports ASCII text only."}
        var alphabet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://station/morse.json"))
        var words: PackedStringArray = text.to_upper().replace("\t", " ").replace("\n", " ").replace("\r", " ").split(" ", false)
        var codes: PackedStringArray = []
        var pulses: Array = []
        for wi: int in range(words.size()):
            if wi > 0:
                pulses.append({"on": false, "units": 7})
            var letters: PackedStringArray = []
            for ci: int in range(words[wi].length()):
                var ch: String = words[wi][ci]
                if not alphabet.has(ch):
                    return {"error": "Morse supports A–Z, digits, and standard punctuation."}
                if ci > 0:
                    pulses.append({"on": false, "units": 3})
                var symbols: String = alphabet[ch]
                letters.append(symbols)
                for si: int in range(symbols.length()):
                    if si > 0:
                        pulses.append({"on": false, "units": 1})
                    pulses.append({"on": true, "units": 1 if symbols[si] == "." else 3})
            codes.append(" ".join(letters))
        if codes.is_empty():
            return {"error": "Enter a Morse message."}
        return {"format": "morse", "code": " / ".join(codes), "pulses": pulses, "audio": false}
    if format not in ["u8", "u16"]:
        return {"error": "Choose Morse, 8-bit, or 16-bit data."}
    var values: Array[int] = []
    var hex: String = ""
    if format == "u8":
        for value: int in text.to_utf8_buffer():
            values.append(value)
            hex += "%02x" % value
    else:
        for i: int in range(text.length()):
            var value: int = text.unicode_at(i)
            if value > 0xffff:
                var upper: int = 0xd800 + ((value - 0x10000) >> 10)
                var lower: int = 0xdc00 + ((value - 0x10000) & 0x3ff)
                values.append(upper)
                values.append(lower)
                hex += "%04x%04x" % [upper, lower]
            else:
                values.append(value)
                hex += "%04x" % value
    return {"format": format, "values": values, "hex": hex, "audio": false}
