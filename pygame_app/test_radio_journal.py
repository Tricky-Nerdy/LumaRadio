import tempfile
import unittest
from pathlib import Path
from radio_journal import RadioJournal


class JournalTests(unittest.TestCase):
    def test_pending_survives_reopen_and_ack(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "events.db"
            journal = RadioJournal(path)
            event_id = journal.record("preset", {"code": "10-4"})
            journal.close()
            journal = RadioJournal(path)
            self.assertEqual(journal.pending()[0]["payload"]["code"], "10-4")
            journal.mark_delivered(event_id)
            self.assertEqual(journal.pending(), [])
            journal.close()

    def test_rejects_invalid_kind(self):
        with tempfile.TemporaryDirectory() as tmp:
            journal = RadioJournal(Path(tmp) / "events.db")
            with self.assertRaises(ValueError):
                journal.record("", {})
            journal.close()


if __name__ == "__main__":
    unittest.main()
