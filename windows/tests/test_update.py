# El contrato de docs/reference/versioning.md, caso por caso. Los mismos casos
# viven en Tests/MascoTuscanKitTests/UpdateTests.swift: si se agrega uno aqui, va alla.

import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from mascotuscan_win import update  # noqa: E402


class SemverTests(unittest.TestCase):
    def test_parsea_con_y_sin_prefijo(self):
        self.assertEqual(update.parse("v0.2.0"), (0, 2, 0))
        self.assertEqual(update.parse("0.2.0"), (0, 2, 0))
        self.assertEqual(update.parse(" 1.0.0\n"), (1, 0, 0))

    def test_rechaza_lo_que_no_es_xyz(self):
        # Un prerelease no es una version publicada: no se compara ni se anuncia.
        for raw in ("0.3.0-beta.1", "0.3", "main", "", None):
            self.assertIsNone(update.parse(raw), raw)

    def test_compara_numericamente(self):
        # Comparar como texto diria que 0.9.0 > 0.10.0.
        self.assertLess(update.parse("0.9.0"), update.parse("0.10.0"))
        self.assertLess(update.parse("0.2.0"), update.parse("1.0.0"))
        self.assertLess(update.parse("1.0.0"), update.parse("1.0.1"))
        self.assertEqual(update.parse("v1.2.3"), update.parse("1.2.3"))


class ResponseTests(unittest.TestCase):
    def test_saca_la_version_del_tag_name(self):
        data = b'{"tag_name":"v0.3.0","name":"mascotuscan 0.3.0"}'
        self.assertEqual(update.parse_latest(data), (0, 3, 0))

    def test_respuesta_sin_tag_no_es_version(self):
        self.assertIsNone(update.parse_latest(b'{"message":"Not Found"}'))
        self.assertIsNone(update.parse_latest(b"no es json"))


class CadenceTests(unittest.TestCase):
    def test_consulta_si_nunca_consulto(self):
        self.assertTrue(update.should_query(update.UpdateState()))

    def test_no_consulta_dos_veces_en_un_dia(self):
        now = datetime.now(timezone.utc)
        hace1h = update.UpdateState(checked_at=now - timedelta(hours=1))
        self.assertFalse(update.should_query(hace1h, now))
        hace25h = update.UpdateState(checked_at=now - timedelta(hours=25))
        self.assertTrue(update.should_query(hace25h, now))


class DecideTests(unittest.TestCase):
    def test_anuncia_una_version_mas_nueva(self):
        announce, state = update.decide((0, 2, 0), (0, 3, 0), update.UpdateState())
        self.assertEqual(announce, (0, 3, 0))
        self.assertEqual(state.announced, "0.3.0")
        self.assertEqual(state.latest, "0.3.0")
        self.assertIsNotNone(state.checked_at)

    def test_no_repite_la_misma_version(self):
        # Reiniciar la mascota no puede repetir el aviso.
        ya = update.UpdateState(latest="0.3.0", announced="0.3.0")
        announce, _ = update.decide((0, 2, 0), (0, 3, 0), ya)
        self.assertIsNone(announce)

    def test_si_vuelve_a_haber_otra_mas_nueva_la_anuncia(self):
        ya = update.UpdateState(latest="0.3.0", announced="0.3.0")
        announce, state = update.decide((0, 2, 0), (0, 4, 0), ya)
        self.assertEqual(announce, (0, 4, 0))
        self.assertEqual(state.announced, "0.4.0")

    def test_calla_si_esta_al_dia_o_adelantado(self):
        self.assertIsNone(update.decide((0, 3, 0), (0, 3, 0), update.UpdateState())[0])
        self.assertIsNone(update.decide((0, 4, 0), (0, 3, 0), update.UpdateState())[0])

    def test_sin_release_registra_la_consulta_y_calla(self):
        announce, state = update.decide((0, 2, 0), None, update.UpdateState())
        self.assertIsNone(announce)
        self.assertIsNotNone(state.checked_at)
        self.assertIsNone(state.latest)


class StateFileTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.path = self.dir / "update.json"

    def test_estado_corrupto_es_estado_vacio(self):
        self.path.write_text("{{ no es json", encoding="utf-8")
        self.assertEqual(update.UpdateState.load(self.path), update.UpdateState())

    def test_ausente_es_estado_vacio(self):
        self.assertEqual(update.UpdateState.load(self.path), update.UpdateState())

    def test_el_estado_sobrevive_el_viaje(self):
        when = datetime(2027, 1, 15, 8, 0, 0, tzinfo=timezone.utc)
        update.UpdateState(when, "0.3.0", "0.3.0").save(self.path)
        back = update.UpdateState.load(self.path)
        self.assertEqual(back.latest, "0.3.0")
        self.assertEqual(back.announced, "0.3.0")
        self.assertEqual(back.checked_at, when)
        # La forma del archivo es la que escribe macOS: claves planas e ISO 8601.
        self.assertIn('"checkedAt": "2027-01-15T08:00:00Z"', self.path.read_text(encoding="utf-8"))

    def test_lee_lo_que_escribio_macos(self):
        self.path.write_text(
            '{\n  "announced" : "0.3.0",\n  "checkedAt" : "2027-01-15T08:00:00Z",\n'
            '  "latest" : "0.3.0"\n}\n', encoding="utf-8")
        back = update.UpdateState.load(self.path)
        self.assertEqual(back.announced, "0.3.0")
        self.assertEqual(back.checked_at, datetime(2027, 1, 15, 8, 0, 0, tzinfo=timezone.utc))


class CheckerTests(unittest.TestCase):
    def test_lee_de_un_archivo_local_y_entrega_una_sola_vez(self):
        latest = Path(tempfile.mkdtemp()) / "latest.json"
        latest.write_text('{"tag_name": "v9.9.9"}', encoding="utf-8")
        os.environ["MASCOTUSCAN_UPDATE_URL"] = latest.as_uri()
        try:
            c = update.Checker()
            c.start()
            c._thread.join(5)
            self.assertEqual(c.take(), ((9, 9, 9), None))
            self.assertIsNone(c.take())
        finally:
            del os.environ["MASCOTUSCAN_UPDATE_URL"]


if __name__ == "__main__":
    unittest.main()
