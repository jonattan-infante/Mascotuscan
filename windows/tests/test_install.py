import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import install  # noqa: E402

HOOK = Path("C:/fake/mascotuscan-hook.ps1")


class MergeTests(unittest.TestCase):
    def test_adds_all_events(self):
        out = install.merge({}, HOOK)
        for ev in install.ALL_EVENTS:
            self.assertIn(ev, out["hooks"])
        self.assertTrue(install._has_our_hook(out["hooks"]["Stop"]))

    def test_tool_events_have_matcher(self):
        out = install.merge({}, HOOK)
        self.assertEqual(out["hooks"]["PreToolUse"][0]["matcher"], "")
        self.assertNotIn("matcher", out["hooks"]["Stop"][0])

    def test_idempotent(self):
        once = install.merge({}, HOOK)
        twice = install.merge(once, HOOK)
        # No duplica: sigue habiendo una sola entrada nuestra por evento.
        self.assertEqual(len(twice["hooks"]["Stop"]), 1)
        self.assertEqual(once, twice)

    def test_preserves_foreign_hooks(self):
        existing = {"hooks": {"Stop": [{"hooks": [
            {"type": "command", "command": "echo ajeno"}]}]}}
        out = install.merge(existing, HOOK)
        cmds = [h["command"] for e in out["hooks"]["Stop"] for h in e["hooks"]]
        self.assertIn("echo ajeno", cmds)
        self.assertTrue(any(install.MARK in c for c in cmds))

    def test_uninstall_removes_only_ours(self):
        existing = {"hooks": {"Stop": [{"hooks": [
            {"type": "command", "command": "echo ajeno"}]}]}}
        installed = install.merge(existing, HOOK)
        removed = install.merge(installed, HOOK, uninstall=True)
        cmds = [h["command"] for e in removed["hooks"]["Stop"] for h in e["hooks"]]
        self.assertIn("echo ajeno", cmds)
        self.assertFalse(any(install.MARK in c for c in cmds))

    def test_replaces_hooks_from_previous_names(self):
        # Una instalacion vieja registro el hook con el nombre anterior del
        # producto; ese archivo ya no existe y Claude Code fallaria en cada evento.
        existing = {"hooks": {"Stop": [{"hooks": [
            {"type": "command", "command": 'powershell -File "C:/viejo/lucy-hook.ps1"'},
            {"type": "command", "command": 'powershell -File "C:/viejo/cmux-pet-hook.ps1"'},
            {"type": "command", "command": "echo ajeno"}]}]}}
        out = install.merge(existing, HOOK)
        cmds = [h["command"] for e in out["hooks"]["Stop"] for h in e["hooks"]]
        self.assertEqual(sum(install.MARK in c for c in cmds), 1)
        self.assertFalse(any(m in c for c in cmds for m in install.LEGACY_MARKS))
        self.assertIn("echo ajeno", cmds)

    def test_uninstall_removes_hooks_from_previous_names(self):
        existing = {"hooks": {"Stop": [{"hooks": [
            {"type": "command", "command": 'powershell -File "C:/viejo/lucy-hook.ps1"'}]}]}}
        removed = install.merge(existing, HOOK, uninstall=True)
        self.assertNotIn("hooks", removed)

    def test_uninstall_from_empty_is_clean(self):
        installed = install.merge({}, HOOK)
        removed = install.merge(installed, HOOK, uninstall=True)
        self.assertNotIn("hooks", removed)


if __name__ == "__main__":
    unittest.main()
