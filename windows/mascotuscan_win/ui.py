# La mascota flotante en tkinter. Analogo de Views/ (PetView, BubbleView,
# RosterView) del proyecto macOS, pero con Canvas en vez de AppKit.
#
# Truco de transparencia en Windows: -transparentcolor hace que un color magico
# se vuelva invisible Y click-through, asi la ventana no se come los clicks fuera
# del cuerpo de la mascota. Es el equivalente al hitTest que devuelve nil en las
# zonas transparentes (limite duro 13 del proyecto).

import math
import tkinter as tk
from tkinter import font as tkfont

from .state import Mood, DEFAULT_ACCENT, rgb_to_hex, blend

TRANSPARENT = "#ff00ff"     # magenta: color que desaparece y deja pasar el click
STEEL = "#B2BAC6"
STEEL_DARK = "#586273"
INK = "#1E222C"
BUBBLE_BG = "#241830"       # morado muy oscuro, a juego con la llama
BUBBLE_FG = "#F3EEF9"

# Caja del cuerpo dentro del canvas y margenes al borde de pantalla.
BODY_W, BODY_H = 104, 120
CANVAS_W, CANVAS_H = 480, 380
MARGIN = 24


def accent_hex(mood, pack) -> str:
    rgb = None
    if pack and mood in getattr(pack, "accents", {}):
        rgb = pack.accents[mood]
    if rgb is None:
        rgb = DEFAULT_ACCENT.get(mood, DEFAULT_ACCENT[Mood.IDLE])
    return rgb_to_hex(rgb)


try:                                              # Pillow es opcional
    from PIL import Image, ImageSequence, ImageTk
    _HAS_PIL = True
except ImportError:                               # respaldo: solo tkinter
    _HAS_PIL = False


class Sprite:
    """ Un sprite (PNG o GIF animado) escalado a cualquier altura.

    Con Pillow se redimensiona a la altura exacta pedida (LANCZOS). El
    tkinter puro solo ofrece subsample entero, asi que a 150px de origen solo
    podia mostrar 150/75/50..., saltando de golpe entre tamanos. Para no dejar
    el aura rosada que el antialias mezcla contra el magenta de fondo, el borde
    se hace duro (umbral de alfa) y lo transparente se pinta del color magico.
    Sin Pillow cae al metodo viejo por subsample.
    """

    def __init__(self, path, target_h=150):
        self.frames = []
        try:
            if _HAS_PIL:
                self._load_pil(path, target_h)
            else:
                self._load_tk(path, target_h)
        except (tk.TclError, OSError):
            self.frames = []

    def _load_pil(self, path, target_h):
        magenta = (255, 0, 255)
        im = Image.open(path)
        for frame in ImageSequence.Iterator(im):
            rgba = frame.convert("RGBA")          # convertir DENTRO del loop
            w = max(1, round(rgba.width * target_h / rgba.height))
            rgba = rgba.resize((w, target_h), Image.LANCZOS)
            r, g, b, a = rgba.split()
            a = a.point(lambda v: 255 if v >= 128 else 0)   # borde duro
            bg = Image.new("RGB", rgba.size, magenta)
            bg.paste(Image.merge("RGB", (r, g, b)), (0, 0), a)
            self.frames.append(ImageTk.PhotoImage(bg))

    def _load_tk(self, path, target_h):
        n = 0
        while True:
            try:
                img = tk.PhotoImage(file=path, format="gif -index %d" % n)
            except tk.TclError:
                break
            self.frames.append(self._fit(img, target_h))
            n += 1
        if not self.frames:                       # no era GIF: intentar PNG suelto
            self.frames.append(self._fit(tk.PhotoImage(file=path), target_h))

    @staticmethod
    def _fit(img, target_h):
        factor = max(1, round(img.height() / target_h))
        return img.subsample(factor, factor) if factor > 1 else img

    def __bool__(self):
        return bool(self.frames)

    def frame(self, i):
        return self.frames[i % len(self.frames)]


class PetWindow:
    """ La ventana. No sabe de eventos de Claude Code: recibe mood, texto de
    burbuja y roster ya resueltos, y los dibuja. """

    def __init__(self, root: tk.Tk, pack, on_click=None, on_menu=None):
        self.root = root
        self.pack = pack
        self.on_click = on_click
        self.on_menu = on_menu or {}

        self.mood = Mood.IDLE
        self.phase = 0.0
        self._anim = 0                 # contador de frame del sprite
        self.anim_divisor = 1          # 1 nativa, mayor mas lento, 0 quieto
        self.sprite_h = 220            # altura objetivo del sprite en px
        self._prop = None              # accesorio (botella) al lado de la mascota
        self._prop_key = None
        self._sprite_cache = {}        # ruta -> Sprite (evita recargar el GIF)
        self._bubble_text = ""
        self._bubble_until = 0.0
        self._roster = []
        self._hovering = False
        self._drag = None

        root.overrideredirect(True)
        root.attributes("-topmost", True)
        try:
            root.attributes("-transparentcolor", TRANSPARENT)
        except tk.TclError:
            pass
        root.config(bg=TRANSPARENT)

        self.canvas = tk.Canvas(root, width=CANVAS_W, height=CANVAS_H,
                                bg=TRANSPARENT, highlightthickness=0, bd=0)
        self.canvas.pack()

        # Fuente divertida para las burbujas. Comic Sans MS existe en todo
        # Windows; si faltara, tkinter cae a la de sistema.
        self._font = tkfont.Font(family="Comic Sans MS", size=8)
        self._font_bold = tkfont.Font(family="Comic Sans MS", size=8, weight="bold")
        # Fuente mas pequena para el roster de agentes.
        self._font_roster = tkfont.Font(family="Comic Sans MS", size=8)
        self._font_roster_bold = tkfont.Font(family="Comic Sans MS", size=8, weight="bold")
        # Fuente grande solo para la nota musical de atencion.
        self._font_excl = tkfont.Font(family="Comic Sans MS", size=26, weight="bold")

        # El cuerpo vive en la esquina inferior derecha del canvas.
        self.body_cx = CANVAS_W - MARGIN - BODY_W / 2
        self.body_bottom = CANVAS_H - MARGIN
        # Esquina inferior derecha de la burbuja: se ancla al tope del cuerpo, y
        # el dibujo del sprite la reajusta a su tamano real para no encimarse.
        self._bubble_anchor = (self.body_cx - BODY_W / 2 - 8,
                               self.body_bottom - BODY_H - 6)

        self._bind()

    # --- API que usa la app -------------------------------------------------

    def set_pack(self, pack):
        self.pack = pack
        self._sprite_cache = {}   # otra mascota: descartar sus sprites
        self._prop = None
        self._prop_key = None

    def set_mood(self, mood):
        self.mood = mood

    def show_bubble(self, text, now, seconds=8.0):
        if text:
            self._bubble_text = text
            self._bubble_until = now + seconds

    def set_roster(self, rows):
        self._roster = rows

    def _work_area(self):
        # Area de trabajo real de Windows (sin la barra de tareas). Tk a veces
        # reporta mal el tamano de pantalla al arrancar y mandaba la mascota
        # fuera de vista; ctypes lo da bien y de forma estable.
        try:
            import ctypes

            class R(ctypes.Structure):
                _fields_ = [("l", ctypes.c_long), ("t", ctypes.c_long),
                            ("r", ctypes.c_long), ("b", ctypes.c_long)]
            wa = R()
            if ctypes.windll.user32.SystemParametersInfoW(0x0030, 0,
                                                          ctypes.byref(wa), 0) \
               and wa.r > 100 and wa.b > 100:
                return wa.l, wa.t, wa.r, wa.b
        except Exception:
            pass
        self.root.update_idletasks()
        return 0, 0, self.root.winfo_screenwidth(), self.root.winfo_screenheight()

    def place_bottom_right(self, position=None):
        l, t, r, b = self._work_area()
        if position:
            x, y = position
        else:
            x = r - CANVAS_W - 6
            y = b - CANVAS_H - 6     # b ya excluye la barra de tareas
        # Clamp de seguridad: nunca dejar la ventana fuera de la pantalla.
        x = max(l, min(int(x), r - CANVAS_W))
        y = max(t, min(int(y), b - CANVAS_H))
        self.root.geometry(f"{CANVAS_W}x{CANVAS_H}+{x}+{y}")

    def render(self, now):
        self.phase += 0.05
        self.canvas.delete("all")
        blink = (int(self.phase * 2) % 37) == 0
        self._anim += 1
        self._bubble_anchor = (self.body_cx - BODY_W / 2 - 8,
                               self.body_bottom - BODY_H - 6)
        renderer = getattr(self.pack, "renderer", "vector:droid")
        sprite = self._sprite_for(self.mood) if renderer == "sprites" else None
        if sprite:
            self._draw_sprite(sprite)
        else:
            self._draw_droid(blink)
        if self._hovering and self._roster:
            self._draw_roster()
        elif self._bubble_text and now < self._bubble_until:
            self._draw_bubble(self._bubble_text)

    # --- dibujo del droide --------------------------------------------------

    def _draw_droid(self, blink):
        c = self.canvas
        accent = accent_hex(self.mood, self.pack)
        bx = self.body_cx - BODY_W / 2
        by_top = self.body_bottom - BODY_H
        dome_h = BODY_W * 0.42
        torso_top = by_top + dome_h
        torso = (bx + 7, torso_top, bx + BODY_W - 7, self.body_bottom - 12)
        tx0, ty0, tx1, ty1 = torso
        tmid_x = (tx0 + tx1) / 2
        tmid_y = (ty0 + ty1) / 2

        sway = self._dome_sway()

        # Sombra en el piso: ancla la mascota.
        c.create_oval(bx + 10, self.body_bottom - 4, bx + BODY_W - 10,
                      self.body_bottom + 6, fill="#0A0C10", outline="")

        # Patas (dos traseras + una central), antes del torso.
        self._leg(tx0 + 5, bx + 4, ty1 - 6)
        self._leg(tx1 - 5, bx + BODY_W - 4, ty1 - 6)
        c.create_rectangle(tmid_x - 3, ty1 - 4, tmid_x + 3, self.body_bottom - 2,
                           fill=STEEL_DARK, outline="")
        c.create_rectangle(tmid_x - 8, self.body_bottom - 6, tmid_x + 8,
                           self.body_bottom, fill=INK, outline="")

        # Torso.
        c.create_rectangle(tx0, ty0, tx1, ty1, fill=STEEL, outline=INK, width=1)
        c.create_rectangle(tx0, ty0, tx0 + (tx1 - tx0) * 0.28, ty1,
                           fill=self._shade(STEEL, 0.10), outline="")   # sombra lateral
        # Banda central.
        c.create_rectangle(tx0, tmid_y, tx1, tmid_y + 4, fill=STEEL_DARK, outline="")
        # Rejilla inferior.
        for i in range(4):
            gx = tx0 + 5 + i * 7.5
            c.create_rectangle(gx, ty1 - 9, gx + 4, ty1 - 4, fill=STEEL_DARK, outline="")

        # Panel de color: el unico elemento del torso que cambia con el estado.
        c.create_rectangle(tx0 + 4, tmid_y - 12, tx0 + 16, tmid_y - 1,
                           fill=accent, outline=INK, width=1)
        c.create_rectangle(tx1 - 16, tmid_y - 11, tx1 - 4, tmid_y - 2,
                           fill=STEEL_DARK, outline="")

        # Luces de estado: parpadean en secuencia solo mientras trabaja.
        lights = ["#F25A5A", "#FAC84D", "#66CCF2"]
        for i, col in enumerate(lights):
            if self.mood == Mood.WORKING:
                on = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(self.phase * 6 - i * 1.1))
            else:
                on = 0.5
            lx = tx0 + 6 + i * 6
            c.create_oval(lx, ty0 + 4, lx + 3.6, ty0 + 7.6,
                          fill=self._dim(col, on), outline="")

        # Cupula (semicirculo).
        dome_cx = tmid_x + sway * 0.35
        dome_r = (tx1 - tx0) / 2 + 1
        c.create_arc(dome_cx - dome_r, torso_top - dome_r, dome_cx + dome_r,
                     torso_top + dome_r, start=0, extent=180,
                     fill=STEEL, outline=INK, width=1, style=tk.PIESLICE)
        # Franja de la cupula, tenida por el estado.
        c.create_arc(dome_cx - dome_r + 5, torso_top - dome_r + 5,
                     dome_cx + dome_r - 5, torso_top + dome_r - 5,
                     start=118 - sway, extent=34, style=tk.ARC,
                     outline=accent, width=3)

        # Lente: aro oscuro + ojo tenido que late cuando hay algo que atender.
        lens_x = dome_cx + sway
        lens_y = torso_top - dome_r * 0.42
        c.create_oval(lens_x - 8.5, lens_y - 8.5, lens_x + 8.5, lens_y + 8.5,
                      fill=INK, outline=STEEL_DARK, width=1)
        glow = 0.25 if blink else 1.0
        if self.mood == Mood.ATTENTION:
            glow *= 0.65 + 0.35 * (0.5 + 0.5 * math.sin(self.phase * 6))
        elif self.mood == Mood.ERROR:
            glow *= 0.4 + 0.6 * (1.0 if math.sin(self.phase * 14) > 0 else 0.35)
        # Halo (dos ovalos tenues) + nucleo.
        c.create_oval(lens_x - 7, lens_y - 7, lens_x + 7, lens_y + 7,
                      fill=self._dim(accent, 0.30 * glow), outline="")
        c.create_oval(lens_x - 5, lens_y - 5, lens_x + 5, lens_y + 5,
                      fill=self._dim(accent, glow), outline="")
        c.create_oval(lens_x - 3.2, lens_y - 3.2, lens_x - 0.8, lens_y - 0.8,
                      fill=self._dim("#FFFFFF", 0.85 * glow), outline="")

        # Nota musical cuando te necesita. Contorno claro para que el negro
        # tenga bordes nitidos contra la ventana transparente (si no, el
        # antialias mezcla negro con el magenta de fondo y sale rosado).
        if self.mood == Mood.ATTENTION:
            ex = tx1 + 6
            ey = ty0 - 6
            self._note(ex, ey, 18)

    def _note(self, x, y, size):
        # Nota negra dibujada con figuras, NO con texto. El texto de Tk usa
        # ClearType (subpixeles de color) y sobre la ventana transparente sus
        # bordes quedan con aura rosada/cian. Las figuras del canvas no se
        # antialiasan en Windows: borde duro y limpio contra el color-key.
        c = self.canvas
        ink = "#101317"
        s = float(size)
        hrx, hry = s * 0.28, s * 0.22
        hcx, hcy = x - s * 0.06, y + s * 0.26
        sx = hcx + hrx * 0.9                 # plica pegada al lado derecho
        top = y - s * 0.46
        sw = max(2, int(round(s * 0.13)))
        c.create_line(sx, hcy, sx, top, fill=ink, width=sw, capstyle=tk.PROJECTING)
        c.create_polygon(
            sx, top,
            sx + s * 0.32, top + s * 0.16,
            sx + s * 0.28, top + s * 0.42,
            sx, top + s * 0.22,
            fill=ink, outline="")
        c.create_oval(hcx - hrx, hcy - hry, hcx + hrx, hcy + hry,
                      fill=ink, outline="")

    def _coin(self, x, y, size):
        # Moneda dorada con signo de pesos, tambien solo con figuras (ver _note).
        c = self.canvas
        ink = "#101317"
        gold, gold_dark = "#F5C518", "#C9930A"
        r = float(size) * 0.5
        ow = max(2, int(round(r * 0.14)))
        c.create_oval(x - r, y - r, x + r, y + r, fill=gold, outline=ink, width=ow)
        ri = r * 0.74
        c.create_oval(x - ri, y - ri, x + ri, y + ri, fill=gold, outline=gold_dark,
                      width=max(1, int(round(r * 0.1))))
        # "$": una S suave (spline) y la barra vertical
        sw = max(2, int(round(r * 0.16)))
        a, b = r * 0.30, r * 0.42
        c.create_line(x + a, y - b * 0.7,
                      x, y - b, x - a, y - b * 0.55,
                      x, y, x + a, y + b * 0.55,
                      x, y + b, x - a, y + b * 0.7,
                      fill=ink, width=sw, smooth=True, capstyle=tk.ROUND)
        c.create_line(x, y - b * 1.25, x, y + b * 1.25, fill=ink, width=sw, capstyle=tk.ROUND)

    def _leg(self, top_x, bot_x, top_y):
        c = self.canvas
        c.create_line(top_x, top_y, bot_x, self.body_bottom - 6,
                      fill=STEEL_DARK, width=6, capstyle=tk.ROUND)
        c.create_rectangle(bot_x - 6, self.body_bottom - 6, bot_x + 6,
                           self.body_bottom, fill=INK, outline="")

    def _dome_sway(self):
        p = self.phase
        if self.mood == Mood.WORKING:
            return math.sin(p * 2.6) * 6
        if self.mood == Mood.ATTENTION:
            return math.sin(p * 5.0) * 3
        if self.mood == Mood.ERROR:
            return math.sin(p * 1.2) * 2
        return math.sin(p * 0.7) * 5

    # --- dibujo por sprite --------------------------------------------------

    def _sprite_for(self, mood):
        sprites = getattr(self.pack, "sprites", {})
        path = sprites.get(mood) or sprites.get("default")
        if not path:
            return None
        if path not in self._sprite_cache:
            self._sprite_cache[path] = Sprite(path, target_h=self.sprite_h)
        sp = self._sprite_cache[path]
        return sp if sp else None

    def _draw_sprite(self, sprite):
        c = self.canvas
        div = self.anim_divisor
        frame = sprite.frame(0 if div <= 0 else self._anim // div)
        w, h = frame.width(), frame.height()
        # El sprite se centra por SU tamano, no por la caja del vector: asi nunca
        # se corta contra el borde de la ventana. Se ancla abajo-derecha con margen.
        cx = CANVAS_W - MARGIN - w / 2
        base = CANVAS_H - MARGIN
        self._bubble_anchor = (cx - w / 2 - 8, base - h - 6)   # burbuja sobre el sprite
        c.create_oval(cx - w * 0.28, base - 4, cx + w * 0.28, base + 6,
                      fill="#0A0C10", outline="")
        c.create_image(cx, base + 4, anchor="s", image=frame)
        self._draw_prop(cx - w / 2, base)
        if self.mood == Mood.ATTENTION:
            # Icono proporcional al sprite. Por defecto la nota de la llama (a
            # 150px daba size 30 y offset +6, posicion aprobada por Catalina);
            # cada pack puede cambiar icono y posicion en pet.json ("attention").
            att = getattr(self.pack, "attention", {}) or {}
            ex = cx + w * att.get("x", 0.08)
            ey = base - h + h * att.get("y", 0.04)
            size = h * att.get("size", 0.2)
            if att.get("icon") == "coin":
                self._coin(ex, ey, size)
            else:
                self._note(ex, ey, size)

    def _draw_prop(self, pet_left, base):
        # Accesorio (la botella) parado en el piso, a la izquierda de la mascota.
        path = getattr(self.pack, "prop", None)
        if not path:
            return
        if self._prop_key != path:
            self._prop = Sprite(path, target_h=126)
            self._prop_key = path
        if not self._prop:
            return
        img = self._prop.frame(0)
        pw = img.width()
        px = pet_left + 18 - pw / 2   # pegada a la llama (solapa un poco su lana)
        self.canvas.create_oval(px - pw * 0.4, base - 3, px + pw * 0.4, base + 5,
                                fill="#0A0C10", outline="")
        self.canvas.create_image(px, base + 4, anchor="s", image=img)

    # --- burbuja y roster ---------------------------------------------------

    def _draw_bubble(self, text):
        c = self.canvas
        accent = accent_hex(self.mood, self.pack)
        anchor_x, anchor_y = self._bubble_anchor
        pad = 12
        maxw = 320        # mas ancho: burbuja rectangular en vez de cuadrada
        # Crear el texto primero para medirlo, luego el globo detras.
        t = c.create_text(0, 0, text=text, anchor="nw", width=maxw,
                          fill=BUBBLE_FG, font=self._font)
        x0, y0, x1, y1 = c.bbox(t)
        w = (x1 - x0) + pad * 2
        h = (y1 - y0) + pad * 2
        bx1 = anchor_x
        by1 = anchor_y
        bx0 = bx1 - w
        by0 = by1 - h
        # Clamp: el globo nunca se sale del canvas (por eso a veces se cortaba).
        margin = 6
        if bx0 < margin:
            d = margin - bx0
            bx0 += d
            bx1 += d
        if by0 < margin:
            d = margin - by0
            by0 += d
            by1 += d
        c.delete(t)
        # Sombra suave detras del globo para despegarlo del fondo.
        self._round_rect(bx0 + 3, by0 + 4, bx1 + 3, by1 + 4, 12, fill="#120C18",
                         outline="")
        # Colita hacia la mascota (debajo, para que el borde la tape limpio).
        c.create_polygon(bx1 - 26, by1 - 2, bx1 - 8, by1 - 2, bx1 - 6, by1 + 14,
                         fill=BUBBLE_BG, outline="")
        self._round_rect(bx0, by0, bx1, by1, 12, fill=BUBBLE_BG,
                         outline=accent, width=2)
        c.create_text(bx0 + pad, by0 + pad, text=text, anchor="nw", width=maxw,
                      fill=BUBBLE_FG, font=self._font)

    def _draw_roster(self):
        c = self.canvas
        rows = self._roster[:6]
        pad = 10
        line_h = 13
        icon_w = 16   # ancho del punto de color + su hueco antes del nombre
        gap = 10      # hueco fijo entre el nombre y el estado
        # Ancho de la caja segun el contenido real (medido, no fijo): la fila
        # mas larga (nombre + estado) manda, para que el texto nunca se salga.
        max_row_w = self._font_roster_bold.measure("Agentes")
        row_texts = []
        for r in rows:
            status = f"{r['doing']}  ({r['steps']})"
            name_w = self._font_roster_bold.measure(r["workspace"])
            status_w = self._font_roster.measure(status)
            max_row_w = max(max_row_w, icon_w + name_w + gap + status_w)
            row_texts.append((r, status, name_w))
        w = min(pad * 2 + max_row_w, 420)
        h = pad * 2 + line_h * (len(rows) + 1)
        bx1, by1 = self._bubble_anchor
        bx0 = bx1 - w
        by0 = by1 - h
        self._round_rect(bx0, by0, bx1, by1, 10, fill=BUBBLE_BG, outline=STEEL_DARK)
        c.create_text(bx0 + pad, by0 + pad, anchor="nw", fill=STEEL,
                      font=self._font_roster_bold, text="Agentes")
        y = by0 + pad + line_h
        for r, status, name_w in row_texts:
            dot = "#FA8C33" if r["attention"] else accent_hex(
                Mood.WORKING if r["doing"] not in ("en reposo",) else Mood.IDLE, self.pack)
            c.create_oval(bx0 + pad, y + 4, bx0 + pad + 8, y + 12, fill=dot, outline="")
            name_x = bx0 + pad + icon_w
            c.create_text(name_x, y, anchor="nw", fill=STEEL,
                          font=self._font_roster_bold, text=r["workspace"])
            c.create_text(name_x + name_w + gap, y, anchor="nw", fill=BUBBLE_FG,
                          font=self._font_roster, text=status)
            y += line_h

    def _round_rect(self, x0, y0, x1, y1, r, **kw):
        pts = [x0 + r, y0, x1 - r, y0, x1, y0, x1, y0 + r, x1, y1 - r, x1, y1,
               x1 - r, y1, x0 + r, y1, x0, y1, x0, y1 - r, x0, y0 + r, x0, y0]
        return self.canvas.create_polygon(pts, smooth=True, **kw)

    # --- color helpers ------------------------------------------------------

    def _dim(self, hexcol, alpha):
        # tkinter no tiene alpha por item: se simula mezclando contra el fondo.
        alpha = max(0.0, min(1.0, alpha))
        h = hexcol.lstrip("#")
        r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
        bg = 0x1B, 0x1E, 0x27
        r = int(r * alpha + bg[0] * (1 - alpha))
        g = int(g * alpha + bg[1] * (1 - alpha))
        b = int(b * alpha + bg[2] * (1 - alpha))
        return "#%02X%02X%02X" % (r, g, b)

    def _shade(self, hexcol, frac):
        rgb = tuple(int(hexcol.lstrip("#")[i:i + 2], 16) / 255 for i in (0, 2, 4))
        return rgb_to_hex(blend(rgb, frac))

    # --- interaccion --------------------------------------------------------

    def _bind(self):
        c = self.canvas
        c.bind("<Enter>", self._on_enter)
        c.bind("<Leave>", self._on_leave)
        c.bind("<ButtonPress-1>", self._on_press)
        c.bind("<B1-Motion>", self._on_move)
        c.bind("<ButtonRelease-1>", self._on_release)
        c.bind("<Button-3>", self._on_right)

    def _in_body(self, x, y):
        return (abs(x - self.body_cx) < BODY_W / 2 + 10 and
                self.body_bottom - BODY_H - 10 < y < self.body_bottom + 10)

    def _on_enter(self, _):
        self._hovering = True

    def _on_leave(self, _):
        self._hovering = False

    def _on_press(self, e):
        if self._in_body(e.x, e.y):
            self._drag = (e.x_root, e.y_root, self.root.winfo_x(),
                          self.root.winfo_y(), False)

    def _on_move(self, e):
        if not self._drag:
            return
        dx = e.x_root - self._drag[0]
        dy = e.y_root - self._drag[1]
        moved = self._drag[4] or abs(dx) > 3 or abs(dy) > 3
        self._drag = (self._drag[0], self._drag[1], self._drag[2], self._drag[3], moved)
        self.root.geometry(f"+{self._drag[2] + dx}+{self._drag[3] + dy}")

    def _on_release(self, e):
        if self._drag:
            _, _, _, _, moved = self._drag
            self._drag = None
            if moved and callable(self.on_menu.get("moved")):
                self.on_menu["moved"](self.root.winfo_x(), self.root.winfo_y())
            elif not moved and callable(self.on_click):
                self.on_click()

    def _on_right(self, e):
        menu = tk.Menu(self.root, tearoff=0)
        for label, cb in (self.on_menu.get("items") or []):
            if label == "-":
                menu.add_separator()
            else:
                # Sin callback es una linea informativa (la version), no un boton.
                menu.add_command(label=label, command=cb,
                                 state="normal" if cb else "disabled")
        try:
            menu.tk_popup(e.x_root, e.y_root)
        finally:
            menu.grab_release()
