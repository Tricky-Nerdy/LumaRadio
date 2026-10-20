"""Visual Morse timing and unsigned 8/16-bit data. Never PCM or sound."""
from __future__ import annotations

MORSE = dict(zip(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,?'/!-()&:;=+_\"$@",
    ".- -... -.-. -.. . ..-. --. .... .. .--- -.- .-.. -- -. --- .--. --.- .-. ... - ..- ...- .-- -..- -.-- --.. "
    "----- .---- ..--- ...-- ....- ..... -.... --... ---.. ----. .-.-.- --..-- ..--.. .----. -..-. -.-.-- -....- -.--. -.--.- .-... ---... -.-.-. -...- .-.-. ..--.- .-..-. ...-..- .--.-.".split(),
    strict=True,
))


def encode_morse(text: str) -> dict:
    if not isinstance(text, str) or not 1 <= len(text) <= 160:
        raise ValueError("Morse text must contain 1–160 characters")
    if not text.isascii():
        raise ValueError("Morse supports ASCII text only")
    words = text.upper().split()
    if not words or any(ch not in MORSE for word in words for ch in word):
        raise ValueError("Morse supports A–Z, digits, and standard punctuation")
    code = " / ".join(" ".join(MORSE[ch] for ch in word) for word in words)
    pulses = []
    for wi, word in enumerate(words):
        if wi:
            pulses.append({"on": False, "units": 7})
        for ci, ch in enumerate(word):
            if ci:
                pulses.append({"on": False, "units": 3})
            for si, symbol in enumerate(MORSE[ch]):
                if si:
                    pulses.append({"on": False, "units": 1})
                pulses.append({"on": True, "units": 1 if symbol == "." else 3})
    return {"format": "morse", "text": " ".join(words), "code": code,
            "pulses": pulses, "audio": False}


def encode_words(width: int, *, text: str | None = None, values: list | None = None) -> dict:
    if type(width) is not int or width not in (8, 16):
        raise ValueError("Data width must be 8 or 16")
    if (text is None) == (values is None):
        raise ValueError("Supply text or values, exactly one")
    if text is not None:
        if not isinstance(text, str) or not 1 <= len(text) <= 160:
            raise ValueError("Signal text must contain 1–160 characters")
        data = text.encode("utf-8" if width == 8 else "utf-16-be")
        step = width // 8
        words = [int.from_bytes(data[i:i + step], "big") for i in range(0, len(data), step)]
        encoding = "utf-8" if width == 8 else "utf-16-be"
    else:
        if not isinstance(values, list) or not 1 <= len(values) <= 512:
            raise ValueError("Supply 1–512 unsigned data words")
        if any(type(v) is not int or not 0 <= v < (1 << width) for v in values):
            raise ValueError("Data word outside unsigned range")
        words, encoding = values[:], "unsigned"
        data = b"".join(v.to_bytes(width // 8, "big") for v in words)
    return {"format": f"u{width}", "width": width, "encoding": encoding,
            "values": words, "hex": data.hex(), "audio": False}


def encode_signal(request: dict) -> dict:
    if request.get("format") == "morse":
        return encode_morse(request.get("text"))
    if request.get("format") in ("u8", "u16"):
        return encode_words(int(request["format"][1:]), text=request.get("text"), values=request.get("values"))
    raise ValueError("Signal format must be morse, u8, or u16")
