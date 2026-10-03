"""Guard against publishing altered evidence or stale expected-answer scores."""
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

import build


class EvidenceTests(unittest.TestCase):
    def test_current_evidence_loads_all_tasks_and_policies(self):
        data = build.load_evidence()
        self.assertEqual(len(data["tasks"]), 4)
        self.assertEqual(len(data["summary"]["runs"]), 48)
        for task in data["tasks"]:
            for entry in task["policies"].values():
                self.assertEqual({case["mode"] for case in entry["report"]["cases"]}, {"compact", "whitespace", "unmasked"})

    def copy_fixture(self, root):
        shutil.copytree(build.ROOT / "examples/logits/evidence", root / "examples/logits/evidence")
        shutil.copyfile(build.ROOT / "examples/logits/corpus.json", root / "examples/logits/corpus.json")

    def test_changed_raw_report_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.copy_fixture(root)
            report = root / "examples/logits/evidence/suite/tool-route/pure-0.json"
            data = json.loads(report.read_text(encoding="utf-8"))
            data["cases"][0]["text"] = '{}'
            report.write_text(json.dumps(data), encoding="utf-8")
            with patch.object(build, "ROOT", root), self.assertRaisesRegex(ValueError, "checksum"):
                build.load_evidence()

    def test_changed_expected_answer_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.copy_fixture(root)
            corpus = root / "examples/logits/corpus.json"
            data = json.loads(corpus.read_text(encoding="utf-8"))
            data[1]["expected"]["arguments"]["city"] = "Paris"
            corpus.write_text(json.dumps(data), encoding="utf-8")
            with patch.object(build, "ROOT", root), self.assertRaisesRegex(ValueError, "Expected-answer"):
                build.load_evidence()


if __name__ == "__main__":
    unittest.main()
