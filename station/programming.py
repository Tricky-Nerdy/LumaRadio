"""Coherent text-only running orders for the existing Forge Broadcast controls.

Creative direction is input to a producer, never treated as a finished script.
No model configured: return an honest prompt/outline, not pretend generated news.
"""
from __future__ import annotations

import ipaddress
import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import ProxyHandler, Request, build_opener

FORMATS = json.loads(Path(__file__).with_name("formats.json").read_text(encoding="utf-8"))
MAX_MODEL_BYTES = 131072


def _text(value, name, limit, *, required=True):
    if not isinstance(value, str) or len(value) > limit or (required and not value.strip()):
        raise ValueError(f"{name} must be text with {'1' if required else '0'}–{limit} characters")
    return value.strip()


def make_plan(request: dict) -> dict:
    if not isinstance(request, dict):
        raise ValueError("Program request must be an object")
    show_id = request.get("show", "mars_news")
    if not isinstance(show_id, str) or show_id not in FORMATS:
        raise ValueError("Choose Mars News, Star News, Talk Hour, or Interviews")
    spec = FORMATS[show_id]
    mode = request.get("mode", "simulation")
    if mode not in ("simulation", "sourced"):
        raise ValueError("Mode must be simulation or sourced")
    topic = _text(request.get("topic"), "Topic", 240)
    direction = _text(request.get("direction", ""), "Creative direction", 4000, required=False)
    host = _text(request.get("host", "Luma"), "Host", 60)
    guest = _text(request.get("guest", "Guest"), "Guest", 60)
    if host == guest:
        raise ValueError("Host and guest must have different names")
    minutes = request.get("minutes", spec["minutes"])
    if type(minutes) is not int or not 1 <= minutes <= 120:
        raise ValueError("Target duration must be 1–120 whole minutes")
    context = request.get("map_context", {})
    if not isinstance(context, dict) or len(json.dumps(context, allow_nan=False)) > 2000:
        raise ValueError("Map context must be an object of at most 2000 characters")
    sources = request.get("sources", [])
    if not isinstance(sources, list) or len(sources) > 12:
        raise ValueError("Supply at most 12 source notes")
    cleaned, ids = [], set()
    for source in sources:
        if not isinstance(source, dict):
            raise ValueError("Source notes must be objects")
        sid = _text(source.get("id"), "Source ID", 40)
        if not re.fullmatch(r"[a-zA-Z0-9_-]+", sid) or sid in ids:
            raise ValueError("Source IDs must be unique letters, digits, underscores, or hyphens")
        ids.add(sid)
        cleaned.append({"id": sid, "title": _text(source.get("title"), "Source title", 200),
                        "notes": _text(source.get("notes"), "Source notes", 2500),
                        "url": _text(source.get("url", ""), "Source URL", 500, required=False),
                        "published_at": _text(source.get("published_at", ""), "Source date", 80, required=False),
                        "guest_transcript": source.get("guest_transcript") is True})
    if mode == "sourced" and not cleaned:
        raise ValueError("Sourced news needs source notes; use simulation for fictional stories")
    total = minutes * 60
    weight = sum(beat[2] for beat in spec["beats"])
    allocations = [total * beat[2] // weight for beat in spec["beats"]]
    # Largest remainders keep the clock exact without distorting short segments.
    order = sorted(range(len(allocations)), key=lambda i: -(total * spec["beats"][i][2] % weight))
    for i in order[:total - sum(allocations)]:
        allocations[i] += 1
    beats, start = [], 0
    for beat, seconds in zip(spec["beats"], allocations):
        beats.append({"id": beat[0], "title": beat[1], "start_seconds": start,
                      "target_seconds": seconds, "direction": beat[3]})
        start += seconds
    return {"station": "Luma Forge Solar", "show": show_id, "title": spec["title"],
            "purpose": spec["purpose"], "topic": topic, "direction": direction,
            "host": host, "guest": guest, "mode": mode, "map_context": context,
            "sources": cleaned, "target_seconds": total, "beats": beats,
            "duration_note": "Planned running order; text cues are not a measured full-duration performance.",
            "label": "FICTIONAL SIMULATION" if mode == "simulation" else "SOURCE-BASED DRAFT — REVIEW REQUIRED",
            "audio": False}


SYSTEM_PROMPT = Path(__file__).with_name("instructions.txt").read_text(encoding="utf-8").strip()


def build_prompt(plan: dict) -> list[dict]:
    return [{"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": json.dumps(plan, ensure_ascii=False, allow_nan=False)}]


def validate_script(value: dict, plan: dict) -> dict:
    if not isinstance(value, dict):
        raise ValueError("Model output must be a JSON object")
    title = _text(value.get("title"), "Generated title", 240)
    note = _text(value.get("producer_note", ""), "Producer note", 2000, required=False)
    segments = value.get("segments")
    if not isinstance(segments, list) or len(segments) != len(plan["beats"]):
        raise ValueError("Generated script does not match the running order")
    known_sources = {s["id"] for s in plan["sources"]}
    transcript_sources = {s["id"] for s in plan["sources"] if s["guest_transcript"]}
    clean = []
    seen_cues = set()
    normalized_direction = " ".join(plan["direction"].lower().split())
    for part, beat in zip(segments, plan["beats"]):
        if not isinstance(part, dict) or part.get("id") != beat["id"]:
            raise ValueError("Generated segment order changed")
        cues = part.get("cues")
        if not isinstance(cues, list) or not 1 <= len(cues) <= 6:
            raise ValueError("Each beat needs 1–6 text cues")
        checked = []
        for cue in cues:
            if not isinstance(cue, dict) or cue.get("speaker") not in (plan["host"], plan["guest"]):
                raise ValueError("Speaker drift in generated script")
            text = _text(cue.get("text"), "Cue text", 2000)
            normalized_text = " ".join(text.lower().split())
            if len(normalized_direction) >= 40 and normalized_direction in normalized_text:
                raise ValueError("Creative direction was copied into the script")
            if len(normalized_text) >= 40 and normalized_text in seen_cues:
                raise ValueError("Repeated cue instead of connected progression")
            seen_cues.add(normalized_text)
            if "[" in text or "]" in text or re.search(r"<(?:audio|speak|voice|break)\b", text, re.I):
                raise ValueError("Production/audio markup belongs outside reader-facing text")
            kind, refs = cue.get("kind"), cue.get("source_ids", [])
            if kind not in ("fact", "question", "transition", "fiction"):
                raise ValueError("Cue kind is required")
            if not isinstance(refs, list) or any(not isinstance(ref, str) or ref not in known_sources for ref in refs):
                raise ValueError("Unknown source reference")
            if plan["mode"] == "sourced":
                if kind == "fiction" or (kind == "fact" and not refs):
                    raise ValueError("Factual news needs citations and cannot contain fictional cues")
                if plan["show"] == "interview" and cue["speaker"] == plan["guest"]:
                    if not refs or not set(refs).issubset(transcript_sources) or kind != "fact":
                        raise ValueError("Guest answers need supplied guest transcript evidence")
            checked.append({"speaker": cue["speaker"], "text": text, "kind": kind, "source_ids": refs})
        clean.append({**beat, "cues": checked})
    return {"title": title, "producer_note": note, "segments": clean, "audio": False}


def _local_endpoint(url: str) -> str:
    parsed = urlsplit(url)
    if parsed.scheme not in ("http", "https") or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError("Use a local LM Studio base URL without credentials or query parameters")
    host = parsed.hostname
    if host != "localhost":
        try:
            address = ipaddress.ip_address(host or "")
        except ValueError as exc:
            raise ValueError("Model host must be localhost or a literal local-network address") from exc
        if not (address.is_loopback or address.is_private) or address.is_unspecified or address.is_multicast:
            raise ValueError("Model endpoint must stay on the local network")
    return url.rstrip("/") + ("/chat/completions" if parsed.path.rstrip("/").endswith("/v1") else "/v1/chat/completions")


def local_completion(messages: list[dict]) -> dict:
    url = _local_endpoint(os.environ["LUMA_STATION_LLM_URL"])
    model = _text(os.environ.get("LUMA_STATION_MODEL"), "Local model ID", 200)
    body = json.dumps({"model": model, "messages": messages, "temperature": 0.65,
                       "max_tokens": 6000, "response_format": {"type": "json_object"}}).encode()
    headers = {"Content-Type": "application/json"}
    if os.environ.get("LUMA_STATION_LLM_KEY"):
        headers["Authorization"] = "Bearer " + os.environ["LUMA_STATION_LLM_KEY"]
    request = Request(url, body, headers=headers, method="POST")
    # No proxy or redirect may turn a local request into an internet request.
    from urllib.request import HTTPRedirectHandler

    class NoRedirect(HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, hdrs, newurl):
            return None

    with build_opener(ProxyHandler({}), NoRedirect()).open(request, timeout=55) as response:
        raw = response.read(MAX_MODEL_BYTES + 1)
    if len(raw) > MAX_MODEL_BYTES:
        raise ValueError("Local model response exceeded the size limit")
    envelope = json.loads(raw)
    if envelope["choices"][0].get("finish_reason") != "stop":
        raise ValueError("Local model did not finish its script")
    return json.loads(envelope["choices"][0]["message"]["content"])


def generate_program(request: dict, completion=None) -> dict:
    plan = make_plan(request)
    messages = build_prompt(plan)
    result = {"plan": plan, "messages": messages, "audio": False,
              "created_utc": datetime.now(timezone.utc).isoformat()}
    if completion is None and not os.environ.get("LUMA_STATION_LLM_URL"):
        return {**result, "status": "prompt_ready", "note": "Prompt and running order ready; no local model configured."}
    try:
        script = validate_script((completion or local_completion)(messages), plan)
    except (ValueError, KeyError, IndexError, TypeError, OSError) as exc:
        # No malformed/partial script is promoted to ready; the producer can remix.
        return {**result, "status": "needs_review", "note": "Generation failed validation or the local model was unavailable.",
                "error_type": type(exc).__name__}
    return {**result, "status": "draft_ready", "script": script,
            "note": "Text cue script ready for editorial review; factual accuracy and performance duration are not automatically verified."}
