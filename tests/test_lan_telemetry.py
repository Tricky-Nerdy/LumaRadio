import os
import socket
import sys
import threading
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "pygame_app"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import lan_telemetry
from lan_receiver import Handler, Receiver

class NetworkTests(unittest.TestCase):
    def setUp(self):
        self.key = "local-test-pairing-key-123456"
        self.server = Receiver(("127.0.0.1", 0), Handler)
        self.server.pairing_key = self.key
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
    def test_valid_event(self):
        self.assertTrue(lan_telemetry.send_event("127.0.0.1", self.server.server_address[1], self.key, "sound_pressed:QSL", 1))
    def test_wrong_key_rejected(self):
        self.assertFalse(lan_telemetry.send_event("127.0.0.1", self.server.server_address[1], "incorrect-secret-12345", "sound_pressed:QSL"))
    def test_short_key_rejected(self):
        with self.assertRaises(ValueError):
            lan_telemetry.sign_message("x", "short")
    def test_opt_in_default_off(self):
        old = os.environ.pop("LUMARADIO_LAN_ENABLED", None)
        try:
            self.assertFalse(lan_telemetry.enabled())
        finally:
            if old is not None:
                os.environ["LUMARADIO_LAN_ENABLED"] = old

if __name__ == "__main__":
    unittest.main()
