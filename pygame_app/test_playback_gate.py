import unittest
from playback_gate import PlaybackGate


class PlaybackGateTests(unittest.TestCase):
    def test_waits_until_last_half_second(self):
        gate = PlaybackGate()
        gate.enqueue("A")
        self.assertEqual(gate.pop_ready(0, lambda _: 2), "A")
        gate.enqueue("B")
        self.assertIsNone(gate.pop_ready(1.49, lambda _: 1))
        self.assertEqual(gate.pop_ready(1.5, lambda _: 1), "B")

    def test_short_clip_minimum_interval(self):
        gate = PlaybackGate()
        gate.enqueue("A")
        gate.enqueue("B")
        self.assertEqual(gate.pop_ready(0, lambda _: .1), "A")
        self.assertIsNone(gate.pop_ready(.05, lambda _: .1))
        self.assertEqual(gate.pop_ready(.15, lambda _: .1), "B")


if __name__ == "__main__":
    unittest.main()
