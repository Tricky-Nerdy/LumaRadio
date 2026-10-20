"""Exercise the real HTTP model client against a local fake LM Studio API."""
import json
import os
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from station.programming import generate_program


class ModelHTTPTests(unittest.TestCase):
    def setUp(self):
        self.requests = []
        self.reply_mode = "valid"
        case = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                case.requests.append({"path": self.path, "body": body})
                if case.reply_mode == "redirect":
                    self.send_response(302)
                    self.send_header("Location", "http://127.0.0.1:1/should-not-follow")
                    self.end_headers()
                    return
                plan = json.loads(body["messages"][1]["content"])
                script = {"title": plan["topic"], "producer_note": "Simulated cue draft.", "segments": [
                    {"id": beat["id"], "cues": [{"speaker": plan["host"], "text": "Fictional report: " + beat["title"],
                                                "kind": "fiction", "source_ids": []}]} for beat in plan["beats"]]}
                output = {"choices": [{"finish_reason": "length" if case.reply_mode == "truncated" else "stop",
                                       "message": {"content": json.dumps(script)}}]}
                data = json.dumps(output).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.env = {"LUMA_STATION_LLM_URL": f"http://127.0.0.1:{self.server.server_port}/v1", "LUMA_STATION_MODEL": "test-model"}

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def test_real_client_composes_prompt_and_receives_validated_script(self):
        with patch.dict(os.environ, self.env, clear=True):
            result = generate_program({"show": "star_news", "topic": "A fictional observatory"})
        self.assertEqual(result["status"], "draft_ready")
        self.assertEqual(self.requests[0]["path"], "/v1/chat/completions")
        self.assertEqual(self.requests[0]["body"]["model"], "test-model")
        self.assertEqual(len(result["script"]["segments"]), 5)

    def test_redirect_is_rejected_and_does_not_leave_local_endpoint(self):
        self.reply_mode = "redirect"
        with patch.dict(os.environ, self.env, clear=True):
            result = generate_program({"topic": "Fictional Mars weather"})
        self.assertEqual(result["status"], "needs_review")
        self.assertEqual(len(self.requests), 1)

    def test_token_limit_truncation_is_never_published_as_ready(self):
        self.reply_mode = "truncated"
        with patch.dict(os.environ, self.env, clear=True):
            result = generate_program({"topic": "Fictional Mars weather"})
        self.assertEqual(result["status"], "needs_review")
        self.assertNotIn("script", result)


if __name__ == "__main__":
    unittest.main()
