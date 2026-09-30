import unittest

from suite import fingerprint, score, strict_equal, summarize


class SuiteTests(unittest.TestCase):
    def test_semantics_are_separate_from_eos(self):
        result = score({"text": '{"ok":true}', "independent_valid": True, "complete_valid": False}, {"ok": True})
        self.assertTrue(result["expected_match"])
        self.assertFalse(result["complete_expected_match"])
        self.assertFalse(strict_equal({"ok": True}, {"ok": 1}))

    def test_no_extraction_or_repair(self):
        for text in ('answer: {}', '{} {}', 'NaN', '{'):
            self.assertFalse(score({"text": text, "independent_valid": False, "complete_valid": False}, {})["expected_match"])
        self.assertFalse(score({"text": '{}', "independent_valid": False, "complete_valid": False}, {})["expected_match"])

    def test_fingerprint_ignores_only_time(self):
        a = {"trace": [{"token": 7, "chosen_logit": 0.5}], "elapsed_seconds": 1}
        b = {**a, "elapsed_seconds": 2}
        self.assertEqual(fingerprint(a), fingerprint(b))
        b["trace"] = [{"token": 7, "chosen_logit": 0.6}]
        self.assertNotEqual(fingerprint(a), fingerprint(b))

    def test_repeats_do_not_inflate_denominator(self):
        row = {"id": "a", "policy": "pure", "mode": "compact", "schema_valid": True,
               "complete_valid": True, "expected_match": False, "complete_expected_match": False,
               "fingerprint": "first"}
        group = summarize([{**row, "repeat": 0}, {**row, "repeat": 1, "fingerprint": "changed"}])[0]
        self.assertEqual(group["cases"], 1)
        self.assertEqual(group["complete_valid"], 1)
        self.assertEqual(group["expected_match"], 0)
        self.assertFalse(group["repeat_consistent"])


if __name__ == "__main__":
    unittest.main()
