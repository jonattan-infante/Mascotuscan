import os
import sys
import json
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from mascotuscan_win.events import parse_line, normalize, Tailer  # noqa: E402


class ParseTests(unittest.TestCase):
    def test_compact_line(self):
        ev = parse_line('{"event":"Stop","session":"abc","cwd":"C:/x/Repo"}')
        self.assertEqual(ev["event"], "Stop")
        self.assertEqual(ev["session"], "abc")

    def test_raw_hook_shape(self):
        # Forma cruda de Claude Code: hook_event_name + tool_name + tool_input.
        raw = {
            "hook_event_name": "PostToolUse",
            "session_id": "xyz",
            "cwd": "C:/x/Repo",
            "tool_name": "Bash",
            "tool_input": {"command": "npm test"},
            "tool_response": {"is_error": True},
        }
        ev = normalize(raw)
        self.assertEqual(ev["event"], "PostToolUse")
        self.assertEqual(ev["tool"], "Bash")
        self.assertEqual(ev["cmd"], "npm test")
        self.assertFalse(ev["ok"])

    def test_unknown_event_ignored(self):
        self.assertIsNone(parse_line('{"event":"PreCompact"}'))

    def test_garbage_ignored(self):
        self.assertIsNone(parse_line("not json"))
        self.assertIsNone(parse_line(""))
        self.assertIsNone(parse_line("[1,2,3]"))


class TailerTests(unittest.TestCase):
    def test_reads_only_new_lines(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "shell.jsonl"
            p.write_text(json.dumps({"event": "SessionStart", "session": "a"}) + "\n",
                         encoding="utf-8")
            t = Tailer(p)               # arranca al final: no ve la linea previa
            self.assertEqual(t.read_new(), [])

            with p.open("a", encoding="utf-8") as f:
                f.write(json.dumps({"event": "Stop", "session": "a"}) + "\n")
                f.write(json.dumps({"event": "Notification", "session": "a",
                                    "message": "permiso"}) + "\n")
            got = t.read_new()
            self.assertEqual([e["event"] for e in got], ["Stop", "Notification"])
            self.assertEqual(t.read_new(), [])   # ya consumidas

    def test_missing_file_is_ok(self):
        with tempfile.TemporaryDirectory() as d:
            t = Tailer(Path(d) / "nope.jsonl")
            self.assertEqual(t.read_new(), [])

    def test_truncation_resets(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "shell.jsonl"
            p.write_text("x\n" * 50, encoding="utf-8")
            t = Tailer(p)
            t.read_new()
            p.write_text(json.dumps({"event": "Stop", "session": "z"}) + "\n",
                         encoding="utf-8")
            got = t.read_new()
            self.assertEqual([e["event"] for e in got], ["Stop"])

    def test_parse_is_injectable(self):
        # Otra fuente (p.ej. el plugin-puente de OpenCode) reusa Tailer con su
        # propio formato de linea, sin duplicar la logica de seguimiento.
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "opencode.jsonl"
            p.write_text("", encoding="utf-8")
            t = Tailer(p, parse=lambda line: {"event": "Stop", "session": "oc",
                                              "agent": "OpenCode", "raw": line.strip()})
            with p.open("a", encoding="utf-8") as f:
                f.write("cualquier-formato\n")
            got = t.read_new()
            self.assertEqual(got, [{"event": "Stop", "session": "oc",
                                    "agent": "OpenCode", "raw": "cualquier-formato"}])


if __name__ == "__main__":
    unittest.main()
