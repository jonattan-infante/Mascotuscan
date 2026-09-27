import os
import sys
import random
import unittest
from pathlib import Path

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from mascotuscan_win import voice, paths  # noqa: E402


class ValidateTests(unittest.TestCase):
    def test_drops_missing_marker(self):
        raw = {"agentDone": ["{agent} termino", "{agent} termino{where}"]}
        out = voice.validate(raw)
        # La primera no usa {where}: se cae. La segunda sobrevive.
        self.assertEqual(out["agentDone"], ["{agent} termino{where}"])

    def test_drops_invented_marker(self):
        raw = {"greeting": ["hola {bogus}", "hola"]}
        out = voice.validate(raw)
        self.assertEqual(out["greeting"], ["hola"])

    def test_bundled_astro_pack_loads(self):
        pack = voice.load_pack(paths.BUNDLED_PETS / "astro")
        self.assertEqual(pack.id, "astro")
        self.assertEqual(pack.renderer, "vector:droid")
        self.assertIn("done", pack.accents)
        self.assertIn("agentDone", pack.fallback)


class PhraseTests(unittest.TestCase):
    def _pack(self):
        return voice.Pack(
            pet_id="t", name="T", accents={},
            fallback={"agentDone": ["{agent} listo{where}", "{agent} cerro{where}"],
                      "greeting": ["hola"]},
            persona=None, language="es", renderer="vector:droid")

    def test_fills_markers(self):
        v = voice.Voice(self._pack(), rng=random.Random(1))
        s = v.phrase("agentDone", {"agent": "Claude", "where": " en Fineract"})
        self.assertIn("Claude", s)
        self.assertIn("Fineract", s)
        self.assertNotIn("{", s)

    def test_none_when_no_phrase(self):
        v = voice.Voice(self._pack(), rng=random.Random(1))
        self.assertIsNone(v.phrase("portUp", {"port": "3000", "where": ""}))

    def test_no_immediate_repeat(self):
        v = voice.Voice(self._pack(), rng=random.Random(0))
        seen = [v.phrase("agentDone", {"agent": "C", "where": ""}) for _ in range(6)]
        # Con dos opciones, nunca la misma dos veces seguidas.
        for a, b in zip(seen, seen[1:]):
            self.assertNotEqual(a, b)


if __name__ == "__main__":
    unittest.main()
