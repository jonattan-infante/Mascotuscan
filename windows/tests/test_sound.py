import wave
from pathlib import Path

from mascotuscan_win import sound


def test_reminder_wav_es_valido_y_bajito(tmp_path):
    path = sound.write_reminder_wav(tmp_path / "r.wav")
    with wave.open(str(path), "rb") as w:
        assert w.getnchannels() == 1
        assert w.getsampwidth() == 2
        assert w.getframerate() == sound.RATE
        seconds = w.getnframes() / w.getframerate()
    assert 0.8 <= seconds <= 2.0
    # volumen acotado: el pico normalizado nunca pasa de PEAK
    assert max(abs(x) for x in sound._samples()) <= sound.PEAK + 1e-6
