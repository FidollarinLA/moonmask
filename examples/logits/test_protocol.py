"""Model-free integration checks against the real compiled MoonBit process."""
import json
import unittest

from client import Decoder, ROOT


class ProtocolTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tokenizer = (ROOT / "assets/gpt2/tokenizer.json").read_text(encoding="utf-8")
        cls.vocab = json.loads(cls.tokenizer)["model"]["vocab"]

    def setUp(self):
        self.decoder = Decoder()
        self.addCleanup(self.decoder.close)

    def init(self, whitespace=False):
        return self.decoder.request("init", tokenizer=self.tokenizer, schema={"const": True}, whitespace=whitespace)

    def scores(self, **tokens):
        scores = [None] * len(self.vocab)
        for name, score in tokens.items():
            scores[self.vocab[name]] = score
        return scores

    def test_initialization_and_finished_sessions_are_checked(self):
        with self.assertRaisesRegex(ValueError, "initialize first"):
            self.decoder.request("result")
        info = self.init()
        scores = self.scores(true=1.0)
        scores[info["eos"]] = 100.0
        step = self.decoder.request("greedy", logits=scores, raw_token=info["eos"])
        self.assertEqual(step["token"], self.vocab["true"])
        self.assertFalse(step["raw_allowed"])
        self.assertFalse(step["ended"])
        step = self.decoder.request("greedy", logits=scores)
        self.assertEqual(step["token"], info["eos"])
        result = self.decoder.request("result")
        self.assertTrue(result["ended"] and result["accepting"] and result["valid"])
        self.assertEqual(bytes(result["bytes"]), b"true")
        with self.assertRaisesRegex(ValueError, "already ended"):
            self.decoder.request("advance", token=self.vocab["true"])
        self.decoder.request("reset")
        self.assertEqual(self.decoder.request("result")["bytes"], [])

    def test_validation_failure_does_not_change_the_session(self):
        self.init()
        for fields in ({"logits": []}, {"logits": ["bad"]}, {"logits": [], "raw_token": -1}):
            with self.assertRaises(ValueError):
                self.decoder.request("greedy", **fields)
        with self.assertRaises(ValueError):
            self.decoder.request("advance", token=0.5)
        with self.assertRaises(ValueError):
            self.decoder.request("init", tokenizer="invalid", schema={"const": False})
        self.assertEqual(self.decoder.request("result")["bytes"], [])
        self.decoder.request("greedy", logits=self.scores(true=1.0))
        self.assertTrue(self.decoder.request("result")["valid"])

    def test_all_suppressed_is_explicit_and_does_not_advance(self):
        self.init()
        result = self.decoder.request("greedy", logits=self.scores())
        self.assertIsNone(result["token"])
        self.assertFalse(result["ended"])
        self.assertEqual(result["state_before"], result["state"])

    def test_unmasked_eos_does_not_claim_an_incomplete_document_is_valid(self):
        info = self.init()
        self.decoder.request("advance", token=info["eos"])
        result = self.decoder.request("result")
        self.assertTrue(result["ended"])
        self.assertFalse(result["accepting"] or result["valid"])

    def test_raw_invalid_prefix_remains_dead(self):
        info = self.init()
        result = self.decoder.request("advance", token=self.vocab["x"])
        self.assertEqual(result["state"], -1)
        self.decoder.request("advance", token=self.vocab["true"])
        self.decoder.request("advance", token=info["eos"])
        result = self.decoder.request("result")
        self.assertEqual(result["text"], "xtrue")
        self.assertFalse(result["valid"] or result["accepting"])

    def test_finishing_stops_a_whitespace_loop_but_respects_suppression(self):
        info = self.init(whitespace=True)
        self.decoder.request("greedy", logits=self.scores(true=1.0))
        # GPT-2 byte-level alphabet represents a space as U+0120.
        scores = self.scores(**{"Ġ": 100.0, "<|endoftext|>": 1.0})
        self.assertEqual(self.decoder.request("greedy", logits=scores)["token"], self.vocab["Ġ"])
        scores[info["eos"]] = None
        self.assertIsNone(self.decoder.request("greedy", logits=scores, finish=True)["token"])
        scores[info["eos"]] = 1.0
        self.assertTrue(self.decoder.request("greedy", logits=scores, finish=True)["ended"])
        self.assertEqual(self.decoder.request("result")["text"], "true ")


if __name__ == "__main__":
    unittest.main()
