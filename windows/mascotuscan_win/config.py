# Configuracion en disco. Analogo de Model/Config.swift. Sin ventana de
# preferencias: un JSON, el menu contextual y (a futuro) la CLI.

import json
from . import paths

DEFAULTS = {
    "activePet": "astro",
    "quiet": False,
    "narrateEverySeconds": 150,
    "position": None,          # [x, y] recordado tras arrastrar; None = auto
    "animSlowdown": 1,         # velocidad del sprite: 1 nativa, mayor mas lento, 0 quieto
    "spriteHeight": 220,       # altura del sprite en px (para packs con GIF/PNG)
    "spotify": True,           # anunciar la cancion que suena (necesita winrt)
    "workspaceAliases": {},    # carpeta -> nombre corto para roster y burbujas
    "checkUpdates": True,      # consultar una vez al dia si hay version nueva
}


class Config:
    def __init__(self, data=None):
        self._d = dict(DEFAULTS)
        if data:
            self._d.update({k: v for k, v in data.items() if k in DEFAULTS})

    def __getitem__(self, k):
        return self._d[k]

    def __setitem__(self, k, v):
        self._d[k] = v

    def get(self, k, default=None):
        return self._d.get(k, default)

    @classmethod
    def load(cls):
        try:
            return cls(json.loads(paths.CONFIG.read_text(encoding="utf-8")))
        except (OSError, ValueError):
            return cls()

    def save(self):
        try:
            paths.ensure_home()
            paths.CONFIG.write_text(
                json.dumps(self._d, indent=2, ensure_ascii=False), encoding="utf-8")
        except OSError:
            pass
