# Mismos casos que Tests/MascoTuscanKitTests/PathsTests.swift: si se agrega uno
# aca, va alla tambien. La migracion corre sobre el directorio real del usuario,
# asi que un error aqui le borra o le esconde su configuracion.

import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from mascotuscan_win import paths  # noqa: E402


class MigrateLegacyHomeTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def dir(self, name, config=None):
        d = self.root / name
        d.mkdir(parents=True)
        if config is not None:
            (d / "config.json").write_text(config, encoding="utf-8")
        return d

    def test_migra_el_nombre_anterior(self):
        home = self.root / ".mascotuscan"
        lucy = self.dir(".lucy", "lucy")
        self.assertEqual(paths.migrate_legacy_home(home, [lucy]), lucy)
        self.assertEqual((home / "config.json").read_text(encoding="utf-8"), "lucy")
        self.assertFalse(lucy.exists())

    def test_prefiere_el_nombre_mas_reciente(self):
        home = self.root / ".mascotuscan"
        lucy = self.dir(".lucy", "lucy")
        cmux_pet = self.dir(".cmux-pet", "cmux-pet")
        self.assertEqual(paths.migrate_legacy_home(home, [lucy, cmux_pet]), lucy)
        self.assertEqual((home / "config.json").read_text(encoding="utf-8"), "lucy")
        self.assertTrue(cmux_pet.exists(), "el mas viejo se queda donde estaba")

    def test_migra_el_mas_viejo_si_es_el_unico(self):
        home = self.root / ".mascotuscan"
        lucy = self.root / ".lucy"
        cmux_pet = self.dir(".cmux-pet", "cmux-pet")
        self.assertEqual(paths.migrate_legacy_home(home, [lucy, cmux_pet]), cmux_pet)
        self.assertEqual((home / "config.json").read_text(encoding="utf-8"), "cmux-pet")

    def test_no_pisa_un_estado_nuevo(self):
        home = self.dir(".mascotuscan", "nuevo")
        lucy = self.dir(".lucy", "lucy")
        self.assertIsNone(paths.migrate_legacy_home(home, [lucy]))
        self.assertEqual((home / "config.json").read_text(encoding="utf-8"), "nuevo")
        self.assertTrue(lucy.exists())

    def test_sin_nada_que_migrar_no_crea_nada(self):
        home = self.root / ".mascotuscan"
        self.assertIsNone(paths.migrate_legacy_home(home, [self.root / ".lucy"]))
        self.assertFalse(home.exists(), "crear el directorio es trabajo de ensure_home")


if __name__ == "__main__":
    unittest.main()
