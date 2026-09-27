# Sonido del recordatorio. Se sintetiza una campanita suave (dos notas seno con
# decaimiento, volumen bajo) y se cachea como .wav en ~/.mascotuscan; asi no hay
# binarios en el repo y se puede afinar cambiando numeros.
#
# Antes eran dos winsound.Beep(): onda cuadrada a todo volumen, muy estridente.

import math
import struct
import wave

from . import paths

RATE = 22050
# (frecuencia Hz, inicio s, duracion s). Mi4 y Si4: una quinta grave, calmado.
NOTES = [(329.63, 0.0, 1.0), (493.88, 0.35, 1.1)]
PEAK = 0.10                       # 1.0 seria a tope; esto es MUY bajito (Catalina: 0.28 era fuerte)
HARMONICS = [(1, 1.0), (2, 0.22), (3, 0.06)]   # timbre tipo campana, no pito
ATTACK_S = 0.008                  # evita el "click" al arrancar la nota
DECAY = 4.5                       # mayor = se apaga mas rapido


def _samples():
    total = max(start + dur for _, start, dur in NOTES)
    n = int(total * RATE)
    out = [0.0] * n
    for freq, start, dur in NOTES:
        s0 = int(start * RATE)
        for i in range(int(dur * RATE)):
            t = i / RATE
            env = math.exp(-DECAY * t / dur)
            if t < ATTACK_S:
                env *= t / ATTACK_S
            v = sum(a * math.sin(2 * math.pi * freq * k * t) for k, a in HARMONICS)
            out[s0 + i] += v * env
    peak = max(abs(x) for x in out) or 1.0
    return [x / peak * PEAK for x in out]


def write_reminder_wav(path=None):
    path = path or paths.REMINDER_WAV
    data = _samples()
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(x * 32767)) for x in data))
    return path


def ensure_reminder_wav():
    path = paths.REMINDER_WAV
    if not path.exists():
        paths.ensure_home()
        write_reminder_wav(path)
    return path


def play_reminder():
    # Asincrono: PlaySound con SND_ASYNC no bloquea la UI. Si algo falla con el
    # .wav, cae a un beep corto y bajo (mejor eso que silencio).
    try:
        import winsound
        path = ensure_reminder_wav()
        winsound.PlaySound(str(path), winsound.SND_FILENAME | winsound.SND_ASYNC | winsound.SND_NODEFAULT)
    except Exception:
        try:
            import winsound
            winsound.Beep(523, 150)
        except Exception:
            pass
