"""Reliable local event journal for radio commands.

Transport adapters can call pending() and mark_delivered() after an actual
remote acknowledgement. Local recording is not proof of remote delivery.
"""
import json
import sqlite3
import time
from pathlib import Path


class RadioJournal:
    def __init__(self, path=None):
        self.path = Path(path or (Path.home() / ".lumaradio" / "events.sqlite3"))
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(self.path))
        self.db.execute("""CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at REAL NOT NULL,
            kind TEXT NOT NULL,
            payload TEXT NOT NULL,
            delivered_at REAL
        )""")
        self.db.commit()

    def record(self, kind, payload):
        if not isinstance(kind, str) or not kind.strip():
            raise ValueError("kind must be nonempty")
        data = json.dumps(payload, ensure_ascii=False)
        cur = self.db.execute(
            "INSERT INTO events(created_at, kind, payload) VALUES (?, ?, ?)",
            (time.time(), kind, data),
        )
        self.db.commit()
        return cur.lastrowid

    def pending(self, limit=100):
        if not 1 <= limit <= 1000:
            raise ValueError("limit must be 1..1000")
        rows = self.db.execute(
            "SELECT id, created_at, kind, payload FROM events "
            "WHERE delivered_at IS NULL ORDER BY id LIMIT ?", (limit,)
        ).fetchall()
        return [
            {"id": row[0], "created_at": row[1], "kind": row[2],
             "payload": json.loads(row[3])}
            for row in rows
        ]

    def mark_delivered(self, event_id):
        self.db.execute(
            "UPDATE events SET delivered_at=? WHERE id=? AND delivered_at IS NULL",
            (time.time(), event_id),
        )
        self.db.commit()

    def close(self):
        self.db.close()
