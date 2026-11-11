"""Pure scheduling policy for non-overlapping radio button audio.

A press may start when the previous clip has <= 0.5 seconds remaining.
A minimum start-to-start interval avoids rapid retriggers on short clips.
The caller must route playback through a single mixer channel and use
pop_ready() once per frame.
"""
from collections import deque


class PlaybackGate:
    def __init__(self, lead_seconds=0.5, minimum_interval=0.15):
        self.lead_seconds = lead_seconds
        self.minimum_interval = minimum_interval
        self._queue = deque()
        self._last_start = float("-inf")
        self._end = float("-inf")

    def enqueue(self, label):
        self._queue.append(label)

    def pop_ready(self, now, duration_for):
        if not self._queue:
            return None
        if now - self._last_start < self.minimum_interval:
            return None
        if now < self._end - self.lead_seconds:
            return None
        label = self._queue.popleft()
        duration = max(0.0, float(duration_for(label)))
        self._last_start = now
        self._end = now + duration
        return label

    @property
    def queued(self):
        return len(self._queue)
