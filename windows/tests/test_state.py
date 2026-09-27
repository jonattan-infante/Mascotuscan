import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from mascotuscan_win.state import ACTIVE_WINDOW, PROMPT_WINDOW, StateMachine, Mood  # noqa: E402


def ev(event, session="s1", cwd="C:/code/Fineract", **kw):
    d = {"event": event, "session": session, "cwd": cwd}
    d.update(kw)
    return d


class StateMachineTests(unittest.TestCase):
    def test_idle_when_empty(self):
        sm = StateMachine()
        self.assertEqual(sm.mood(now=100.0), Mood.IDLE)

    def test_pretooluse_is_working(self):
        sm = StateMachine()
        sm.ingest(ev("PreToolUse", tool="Bash"), now=10.0)
        self.assertEqual(sm.mood(now=11.0), Mood.WORKING)

    def test_working_decays_to_idle(self):
        sm = StateMachine()
        sm.ingest(ev("PreToolUse", tool="Read"), now=10.0)
        # Pasada la ventana activa y sin done reciente: vuelve a reposo.
        self.assertEqual(sm.mood(now=10.0 + ACTIVE_WINDOW + 1), Mood.IDLE)

    def test_stop_is_done_then_idle(self):
        sm = StateMachine()
        a = sm.ingest(ev("Stop"), now=20.0)
        self.assertIsNotNone(a)
        self.assertEqual(a.kind, "agentDone")
        self.assertEqual(sm.mood(now=21.0), Mood.DONE)
        self.assertEqual(sm.mood(now=40.0), Mood.IDLE)

    def test_agent_por_defecto_es_claude(self):
        sm = StateMachine()
        a = sm.ingest(ev("Stop"), now=1.0)
        self.assertEqual(a.vars["agent"], "Claude")

    def test_agent_lo_pone_la_fuente_y_se_mantiene_en_la_sesion(self):
        # Una fuente distinta (p.ej. OpenCode) lo dice en el primer evento;
        # los siguientes de la misma sesion no necesitan repetirlo.
        sm = StateMachine()
        sm.ingest(ev("PreToolUse", tool="Bash", agent="OpenCode"), now=1.0)
        a = sm.ingest(ev("Stop"), now=2.0)
        self.assertEqual(a.vars["agent"], "OpenCode")

    def test_notification_is_attention_and_persists(self):
        sm = StateMachine()
        a = sm.ingest(ev("Notification", message="Claude needs permission to run Bash"),
                      now=5.0)
        self.assertEqual(a.kind, "attention")
        self.assertEqual(a.vars["what"], "un permiso")
        # La atencion no decae sola: sigue mucho despues.
        self.assertEqual(sm.mood(now=500.0), Mood.ATTENTION)

    def test_userprompt_clears_attention(self):
        sm = StateMachine()
        sm.ingest(ev("Notification", message="needs permission"), now=5.0)
        sm.ingest(ev("UserPromptSubmit"), now=6.0)
        self.assertNotEqual(sm.mood(now=7.0), Mood.ATTENTION)

    def test_failed_tool_is_error(self):
        sm = StateMachine()
        a = sm.ingest(ev("PostToolUse", tool="Bash", ok=False, exit=1,
                          cmd="pytest -q"), now=30.0)
        self.assertEqual(a.kind, "commandError")
        self.assertEqual(a.vars["code"], "1")
        self.assertEqual(a.vars["cmd"], "pytest -q")
        self.assertEqual(a.vars["where"], " en Fineract")
        self.assertEqual(sm.mood(now=31.0), Mood.ERROR)

    def test_attention_wins_over_working(self):
        sm = StateMachine()
        sm.ingest(ev("PreToolUse", session="a", tool="Bash"), now=10.0)
        sm.ingest(ev("Notification", session="b", cwd="C:/code/Backend",
                     message="permission"), now=10.5)
        self.assertEqual(sm.mood(now=11.0), Mood.ATTENTION)

    def test_roster_lists_sessions_recent_first(self):
        sm = StateMachine()
        sm.ingest(ev("PreToolUse", session="a", cwd="C:/x/Alpha", tool="Read"), now=1.0)
        sm.ingest(ev("PreToolUse", session="b", cwd="C:/x/Beta", tool="Bash"), now=2.0)
        rows = sm.roster(now=2.5)
        self.assertEqual(rows[0]["workspace"], "Beta")
        self.assertEqual(rows[1]["workspace"], "Alpha")

    def test_ghost_sweep(self):
        sm = StateMachine()
        sm.ingest(ev("PreToolUse", tool="Bash"), now=0.0)
        self.assertEqual(len(sm.roster(now=10000.0)), 0)

    def test_workspace_from_windows_path(self):
        sm = StateMachine()
        a = sm.ingest(ev("Stop", cwd=r"C:\Users\me\repos\Fineract"), now=1.0)
        self.assertEqual(a.vars["where"], " en Fineract")


if __name__ == "__main__":
    unittest.main()


class IdleNoticeTests(unittest.TestCase):
    def test_waiting_for_input_no_es_atencion(self):
        sm = StateMachine()
        sm.ingest(ev("PreToolUse", tool="Bash"), now=1.0)
        sm.ingest(ev("Stop"), now=2.0)
        a = sm.ingest(ev("Notification", message="Claude is waiting for your input"), now=62.0)
        self.assertIsNone(a)
        self.assertEqual(sm.mood(now=70.0), Mood.IDLE)

    def test_permission_si_es_atencion(self):
        sm = StateMachine()
        sm.ingest(ev("Notification", message="Claude needs your permission"), now=1.0)
        self.assertEqual(sm.mood(now=2.0), Mood.ATTENTION)


class PromptWithoutToolsTests(unittest.TestCase):
    def test_prompt_solo_trabaja_un_rato_corto(self):
        # Respuesta solo de texto y Stop que no llega: no puede quedarse en plata.
        sm = StateMachine()
        sm.ingest(ev("UserPromptSubmit"), now=10.0)
        self.assertEqual(sm.mood(now=11.0), Mood.WORKING)
        self.assertEqual(sm.mood(now=10.0 + PROMPT_WINDOW + 1), Mood.IDLE)

    def test_herramienta_sostiene_la_ventana_larga(self):
        sm = StateMachine()
        sm.ingest(ev("UserPromptSubmit"), now=10.0)
        sm.ingest(ev("PreToolUse", tool="Bash"), now=12.0)
        self.assertEqual(sm.mood(now=12.0 + PROMPT_WINDOW + 5), Mood.WORKING)
        self.assertEqual(sm.mood(now=12.0 + ACTIVE_WINDOW + 1), Mood.IDLE)

