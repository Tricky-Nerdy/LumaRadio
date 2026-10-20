import copy
import json
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from station.programming import FORMATS, _local_endpoint, generate_program, make_plan, validate_script
from station.signals import encode_morse, encode_signal, encode_words


def valid_script(messages):
    plan = json.loads(messages[1]["content"])
    return {"title": plan["topic"], "producer_note": "Text cue draft, not a measured performance.",
            "segments": [{"id": beat["id"], "cues": [{"speaker": plan["host"],
                "text": f"Fictional segment about {plan['topic']}: {beat['title']}.",
                "kind": "fiction", "source_ids": []}]} for beat in plan["beats"]]}


class SignalTests(unittest.TestCase):
    def test_sos_and_exact_morse_spacing(self):
        value = encode_morse("SOS A")
        self.assertEqual(value["code"], "... --- ... / .-")
        self.assertEqual(sum(p["units"] for p in value["pulses"]), 39)
        self.assertEqual([p["units"] for p in value["pulses"] if not p["on"]].count(7), 1)
        self.assertEqual(value["pulses"][-1], {"on": True, "units": 3})
        self.assertFalse(value["audio"])

    def test_morse_rejects_unsupported_instead_of_silently_dropping(self):
        for text in ("", "   ", "Mars 🌍", "Straße", None, "A" * 161):
            with self.subTest(text=text), self.assertRaises(ValueError):
                encode_morse(text)

    def test_unicode_8_and_16_bit_round_trips(self):
        for text in ("Mars", "Café", "🌍"):
            for width, codec in ((8, "utf-8"), (16, "utf-16-be")):
                with self.subTest(text=text, width=width):
                    encoded = encode_words(width, text=text)
                    self.assertEqual(bytes.fromhex(encoded["hex"]).decode(codec), text)
                    self.assertTrue(all(0 <= n < 2 ** width for n in encoded["values"]))
        self.assertEqual(encode_words(16, text="🌍")["values"], [0xD83C, 0xDF0D])

    def test_unsigned_boundaries_and_ambiguous_inputs(self):
        self.assertEqual(encode_words(8, values=[0, 255])["hex"], "00ff")
        self.assertEqual(encode_words(16, values=[0, 65535])["hex"], "0000ffff")
        for width, values in ((8, [256]), (16, [65536]), (8, [-1]), (8, [True]), (8, [])):
            with self.subTest(width=width, values=values), self.assertRaises(ValueError):
                encode_words(width, values=values)
        with self.assertRaises(ValueError):
            encode_words(16, text="X", values=[1])
        with self.assertRaises(ValueError):
            encode_signal({"format": "pcm"})


class ProgramTests(unittest.TestCase):
    def test_all_clocks_cover_exact_duration_with_one_topic(self):
        for show in FORMATS:
            for minutes in (1, 5, 20, 60, 120):
                with self.subTest(show=show, minutes=minutes):
                    plan = make_plan({"show": show, "topic": "Mars transit", "minutes": minutes})
                    self.assertEqual(sum(b["target_seconds"] for b in plan["beats"]), minutes * 60)
                    self.assertEqual(plan["beats"][0]["start_seconds"], 0)
                    for previous, current in zip(plan["beats"], plan["beats"][1:]):
                        self.assertEqual(current["start_seconds"], previous["start_seconds"] + previous["target_seconds"])
                    self.assertEqual(plan["topic"], "Mars transit")
                    self.assertFalse(plan["audio"])

    def test_offline_is_prompt_ready_not_fake_generated_news(self):
        with patch.dict(os.environ, {}, clear=True):
            result = generate_program({"show": "mars_news", "topic": "Water transport"})
        self.assertEqual(result["status"], "prompt_ready")
        self.assertNotIn("script", result)
        self.assertEqual(result["plan"]["label"], "FICTIONAL SIMULATION")

    def test_generation_is_structured_and_preserves_clock_and_host(self):
        result = generate_program({"show": "talk_hour", "topic": "Mars transit", "host": "Luma"}, valid_script)
        self.assertEqual(result["status"], "draft_ready")
        self.assertEqual(len(result["script"]["segments"]), 6)
        self.assertEqual(sum(s["target_seconds"] for s in result["script"]["segments"]), 3600)
        self.assertTrue(all(s["cues"][0]["speaker"] == "Luma" for s in result["script"]["segments"]))

    def test_drift_partial_output_and_production_markup_are_rejected(self):
        plan = make_plan({"topic": "Mars transit"})
        base = valid_script([{}, {"content": json.dumps(plan)}])
        bad = []
        item = copy.deepcopy(base); item["segments"].reverse(); bad.append(item)
        item = copy.deepcopy(base); item["segments"].pop(); bad.append(item)
        item = copy.deepcopy(base); item["segments"][0]["cues"][0]["speaker"] = "Random person"; bad.append(item)
        item = copy.deepcopy(base); item["segments"][0]["cues"][0]["text"] = "[play tone]"; bad.append(item)
        for value in bad:
            with self.subTest(value=value):
                result = generate_program({"topic": "Mars transit"}, lambda _: value)
                self.assertEqual(result["status"], "needs_review")
                self.assertNotIn("script", result)

    def test_sourced_mode_requires_notes_and_citations(self):
        with self.assertRaises(ValueError):
            make_plan({"topic": "Mars transit", "mode": "sourced"})
        request = {"topic": "Mars transit", "mode": "sourced", "sources": [
            {"id": "s1", "title": "Supplied note", "notes": "Test source, not current news."}]}
        plan = make_plan(request)
        script = valid_script([{}, {"content": json.dumps(plan)}])
        for part in script["segments"]:
            part["cues"][0].update(kind="fact", source_ids=["s1"])
        validate_script(script, plan)
        script["segments"][0]["cues"][0]["source_ids"] = []
        with self.assertRaises(ValueError):
            validate_script(script, plan)

    def test_real_guest_answers_cannot_be_invented(self):
        plan = make_plan({"show": "interview", "topic": "Mars transit", "mode": "sourced", "sources": [
            {"id": "s1", "title": "Article", "notes": "A report, not an interview."}]})
        script = valid_script([{}, {"content": json.dumps(plan)}])
        for part in script["segments"]:
            part["cues"][0].update(kind="fact", source_ids=["s1"])
        script["segments"][1]["cues"][0]["speaker"] = "Guest"
        with self.assertRaises(ValueError):
            validate_script(script, plan)
        plan["sources"][0]["guest_transcript"] = True
        validate_script(script, plan)

    def test_remote_model_proxy_redirect_and_bad_hosts_are_not_selected(self):
        for url in ("https://example.com", "http://8.8.8.8", "http://0.0.0.0", "http://224.0.0.1", "http://user:pass@localhost", "http://127.0.0.1?secret=x"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                _local_endpoint(url)
        self.assertEqual(_local_endpoint("http://127.0.0.1:1234/v1"), "http://127.0.0.1:1234/v1/chat/completions")

    def test_model_failure_returns_review_without_a_script(self):
        def fail(_):
            raise OSError("Local model unavailable")
        result = generate_program({"topic": "Mars transit"}, fail)
        self.assertEqual(result["status"], "needs_review")
        self.assertNotIn("script", result)

    def test_prompt_boxes_are_direction_not_verbatim_script(self):
        direction = "Discuss how the garden crew keeps a steady supply of water across the settlement."
        request = {"topic": "Mars gardens", "direction": direction}
        plan = make_plan(request)
        script = valid_script([{}, {"content": json.dumps(plan)}])
        script["segments"][0]["cues"][0]["text"] = direction
        with self.assertRaises(ValueError):
            validate_script(script, plan)
        script = valid_script([{}, {"content": json.dumps(plan)}])
        script["segments"][1]["cues"][0]["text"] = script["segments"][0]["cues"][0]["text"]
        with self.assertRaises(ValueError):
            validate_script(script, plan)


if __name__ == "__main__":
    unittest.main()
