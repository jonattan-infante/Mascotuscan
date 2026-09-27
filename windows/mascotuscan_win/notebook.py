# La libreta de la mascota: una agenda tipo cuaderno de verdad. Espiral +
# pestañas de colores a la izquierda (una por pagina), UNA pagina abierta a
# la vez que ocupa toda la hoja; click en una pestaña para "pasar la hoja".
# Cada pagina es de un tipo (nota, lista, post-it) con su propio estilo.
# Ventana aparte (Toplevel) porque es una feature de UI independiente del
# ciclo de vida de la mascota: se abre con un click y se guarda sola, sin
# pasar por el tick de animacion de app.py.

import json
import tkinter as tk
from tkinter import messagebox, simpledialog

from . import paths

WIN_W, WIN_H = 660, 640   # con espacio real para checkbox+texto+recordatorio+quitar
SPINE_W = 18
TAB_W = 104
TAB_H = 30

# Negros y grises: nada de cuero cafe ni anillos dorados.
COVER = "#1E1E1E"
RING = "#8A8A8A"          # anillos color plata
TAB_INACTIVE = "#333333"
TAB_ACTIVE = "#ECECEC"
# Los post-its de la pagina "Post-its" SI son de colores vivos: son literal
# notas adhesivas, a diferencia del resto de la agenda (en gris/negro).
POSTIT_COLORS = ["#FFF59D", "#F8BBD0", "#B3E5FC", "#C8E6C9", "#FFE0B2", "#D1C4E9"]
BLANK_TODO_ROWS = 10
DEFAULT_REMIND_MINUTES = 60   # cada item de lista trae su propio reloj

INK = "#1A1A1A"
INK_DIM = "#767676"
BORDER = "#D6D6D6"

FONT = ("Segoe UI", 11)
FONT_TITLE = ("Segoe UI Semibold", 10)
FONT_HEADER = ("Segoe UI Semibold", 16)
FONT_SMALL = ("Segoe UI", 8)


def _blank_items(n):
    return [{"text": "", "done": False, "remind_minutes": DEFAULT_REMIND_MINUTES,
             "last_reminded": 0} for _ in range(n)]


def _format_reminder(minutes):
    if minutes <= 0:
        return "sin aviso"
    if minutes % 60 == 0:
        return f"{minutes // 60}h"
    return f"{minutes}m"


REMIND_UNITS = [("min", 1), ("h", 60), ("d", 1440)]


def _minutes_to_value_unit(minutes):
    for label, factor in reversed(REMIND_UNITS):
        if minutes and minutes % factor == 0:
            return minutes // factor, label
    return minutes, "min"


def _default_pages():
    return [
        {"title": "To Do List", "type": "todo", "content": "",
         "items": _blank_items(BLANK_TODO_ROWS)},
        {"title": "Post-its", "type": "postits", "content": "", "items": [],
         "notes": []},
    ]


def _load():
    try:
        data = json.loads(paths.NOTEBOOK.read_text(encoding="utf-8"))
        pages = data.get("pages") or []
        if pages:
            for i, p in enumerate(pages):
                p.setdefault("type", "notes")
                p.setdefault("content", "")
                p.setdefault("items", [])
                p.setdefault("notes", [])
                for item in p["items"]:
                    item.setdefault("remind_minutes", DEFAULT_REMIND_MINUTES)
                    item.setdefault("last_reminded", 0)
            active = max(0, min(data.get("active", 0), len(pages) - 1))
            return pages, active
    except (OSError, ValueError):
        pass
    return _default_pages(), 0


def scan_due_items(pages, now):
    """ Recorre pages EN SITIO marcando last_reminded en los items cuyo
    intervalo ya se cumplio; devuelve (textos_pendientes, si_cambio_algo).

    Separado de due_todo_reminders para que app.py pueda operar sobre el
    self.pages de un NotebookWindow ya abierto (mismo objeto en memoria) en
    vez de leer el archivo aparte: si la libreta esta abierta y esta funcion
    escribiera a disco por su cuenta, el siguiente guardado de la ventana
    (con su copia vieja en memoria) pisaria el cambio y el aviso saldria de
    nuevo cada rato en vez de respetar el intervalo. """
    due = []
    changed = False
    for page in pages:
        if page.get("type") != "todo":
            continue
        for item in page.get("items", []):
            text = item.get("text", "").strip()
            if not text or item.get("done"):
                continue
            minutes = item.get("remind_minutes", DEFAULT_REMIND_MINUTES)
            if minutes <= 0:
                continue
            if now - item.get("last_reminded", 0) >= minutes * 60:
                due.append(text)
                item["last_reminded"] = now
                changed = True
    return due, changed


def due_todo_reminders(now):
    """ Para cuando la libreta esta CERRADA: lee y escribe el archivo directo,
    no hay ningun NotebookWindow con una copia en memoria que pueda pisarlo. """
    pages, active = _load()
    due, changed = scan_due_items(pages, now)
    if changed:
        _save(pages, active)
    return due


def _save(pages, active):
    paths.ensure_home()
    paths.NOTEBOOK.write_text(
        json.dumps({"pages": pages, "active": active}, ensure_ascii=False, indent=2),
        encoding="utf-8")


def _blend(hexcol, bg, alpha):
    h = hexcol.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    hb = bg.lstrip("#")
    br, bgc, bb = int(hb[0:2], 16), int(hb[2:4], 16), int(hb[4:6], 16)
    r = int(r * alpha + br * (1 - alpha))
    g = int(g * alpha + bgc * (1 - alpha))
    b = int(b * alpha + bb * (1 - alpha))
    return "#%02X%02X%02X" % (r, g, b)


class NotebookWindow:
    """ app.py guarda la instancia y la reusa mientras siga viva (winfo_exists),
    en vez de abrir una ventana nueva en cada click. """

    def __init__(self, root):
        self.pages, self.active = _load()
        self.text = None   # widget Text de la pagina de notas/post-it actual

        self.win = tk.Toplevel(root)
        self.win.title("Agenda")
        self.win.geometry(f"{WIN_W}x{WIN_H}")
        self.win.minsize(480, 380)
        self.win.configure(bg=COVER)
        self.win.protocol("WM_DELETE_WINDOW", self._on_close)

        left = tk.Frame(self.win, bg=COVER, width=SPINE_W + TAB_W)
        left.pack(side="left", fill="y")
        left.pack_propagate(False)

        self.spine = tk.Canvas(left, width=SPINE_W, bg=COVER, highlightthickness=0)
        self.spine.pack(side="left", fill="y")
        self.spine.bind("<Configure>", self._draw_spine)

        self.tabs_area = tk.Frame(left, bg=COVER)
        self.tabs_area.pack(side="left", fill="both", expand=True)

        self.page_area = tk.Frame(self.win, bg="#FFFFFF")
        self.page_area.pack(side="left", fill="both", expand=True)

        self._render_tabs()
        self._render_page()

    # --- lomo -----------------------------------------------------------------

    def _draw_spine(self, e):
        c = self.spine
        c.delete("ring")
        y = 16
        while y < e.height - 8:
            c.create_oval(e.width / 2 - 5, y - 5, e.width / 2 + 5, y + 5,
                          outline=RING, width=2, tags="ring")
            y += 28

    # --- pestañas ----------------------------------------------------------------

    def _render_tabs(self):
        for w in self.tabs_area.winfo_children():
            w.destroy()
        for idx, page in enumerate(self.pages):
            self._build_tab(idx, page)
        add = tk.Canvas(self.tabs_area, width=TAB_W - 10, height=TAB_H - 6, bg=COVER,
                        highlightthickness=0, cursor="hand2")
        add.pack(pady=(6, 0), anchor="w")
        add.create_text((TAB_W - 10) / 2, (TAB_H - 6) / 2, text="+", fill=RING,
                        font=("Segoe UI Semibold", 12))
        add.bind("<Button-1>", self._open_add_menu)
        # Eliminar/renombrar viven en el click derecho de cada pestaña, no
        # como texto suelto en la franja oscura (no hace falta verlo siempre).

    def _build_tab(self, idx, page):
        selected = idx == self.active
        bg = TAB_ACTIVE if selected else TAB_INACTIVE
        fg = INK if selected else "#AAAAAA"
        tab = tk.Frame(self.tabs_area, bg=bg, height=TAB_H)
        tab.pack(fill="x", pady=1)
        tab.pack_propagate(False)
        accent = tk.Frame(tab, bg=RING if selected else bg, width=3)
        accent.pack(side="left", fill="y")
        label = page["title"] if len(page["title"]) <= 14 else page["title"][:13] + "…"
        # Mismo tamaño de letra siempre: que se note cual esta abierta por el
        # color y el filete, no porque el texto se agrande.
        lbl = tk.Label(tab, text=label, bg=bg, fg=fg, font=FONT_SMALL, anchor="w")
        lbl.pack(side="left", fill="both", expand=True, padx=(6, 4))
        for w_ in (tab, accent, lbl):
            w_.bind("<Button-1>", lambda _e, i=idx: self.select_page(i))
            w_.bind("<Double-Button-1>", lambda _e, i=idx: self.rename_page(i))
            w_.bind("<Button-3>", lambda e, i=idx: self._open_tab_menu(e, i))
            w_.configure(cursor="hand2")

    def _open_tab_menu(self, e, idx):
        menu = tk.Menu(self.win, tearoff=0)
        menu.add_command(label="Renombrar", command=lambda: self.rename_page(idx))
        menu.add_command(label="Eliminar", command=lambda: self.delete_page(idx))
        try:
            menu.tk_popup(e.x_root, e.y_root)
        finally:
            menu.grab_release()

    def _open_add_menu(self, e):
        menu = tk.Menu(self.win, tearoff=0)
        menu.add_command(label="Lista", command=lambda: self.add_page("todo"))
        menu.add_command(label="Nota", command=lambda: self.add_page("notes"))
        menu.add_command(label="Post-its", command=lambda: self.add_page("postits"))
        try:
            menu.tk_popup(e.x_root, e.y_root)
        finally:
            menu.grab_release()

    # --- la hoja abierta -----------------------------------------------------------

    def _render_page(self):
        for w in self.page_area.winfo_children():
            w.destroy()
        self.text = None
        page = self.pages[self.active]
        bg = "#FFFFFF" if page["type"] in ("todo", "postits") else "#F5F5F5"
        self.page_area.configure(bg=bg)

        header = tk.Frame(self.page_area, bg=bg)
        header.pack(fill="x", padx=28, pady=(20, 0))
        is_todo = page["type"] == "todo"
        title = tk.Label(header, text=page["title"].upper() if is_todo else page["title"],
                         bg=bg, fg=INK,
                         font=FONT_HEADER if is_todo else ("Segoe UI Semibold", 15),
                         anchor="center" if is_todo else "w", cursor="hand2")
        title.pack(fill="x")
        title.bind("<Double-Button-1>", lambda _e: self.rename_page(self.active))
        if is_todo:
            tk.Frame(self.page_area, bg=INK, height=1).pack(fill="x", padx=28, pady=(6, 0))

        if page["type"] == "todo":
            self._build_todo(bg, page)
        elif page["type"] == "postits":
            self._build_postits(page)
        else:
            self._build_notes(bg, page)

    def _build_notes(self, bg, page):
        wrap = tk.Frame(self.page_area, bg=bg)
        wrap.pack(fill="both", expand=True, padx=28, pady=16)
        if page["type"] == "notes":
            margin = tk.Frame(wrap, bg=INK_DIM, width=2)
            margin.pack(side="left", fill="y", padx=(0, 16))
        self.text = tk.Text(wrap, bg=bg, fg=INK, insertbackground=INK, bd=0,
                            wrap="word", font=FONT, padx=0, pady=0, undo=True,
                            highlightthickness=0)
        self.text.pack(side="left", fill="both", expand=True)
        self.text.insert("1.0", page["content"])
        self.text.edit_modified(False)
        self.text.bind("<<Modified>>", self._on_text_modified)
        self.text.focus_set()

    def _build_todo(self, bg, page):
        wrap = tk.Frame(self.page_area, bg=bg)
        wrap.pack(fill="both", expand=True, padx=28, pady=(14, 20))

        self.item_entries = {}
        rows = tk.Frame(wrap, bg=bg)
        rows.pack(fill="both", expand=True)
        for item_idx, item in enumerate(page["items"]):
            row = tk.Frame(rows, bg=bg)
            row.pack(fill="x", pady=(6, 0))
            top = tk.Frame(row, bg=bg)
            top.pack(fill="x")
            self._checkbox(top, bg, item_idx, item.get("done", False)).pack(
                side="left", padx=(0, 8))
            fg = INK_DIM if item.get("done") else INK
            # Renglon en blanco listo para escribir, no un texto fijo: se
            # escribe directo encima de la linea punteada, como la plantilla.
            entry_wrap = tk.Frame(top, bg=bg)
            entry_wrap.pack(side="left", fill="x", expand=True)
            entry = tk.Entry(entry_wrap, bg=bg, fg=fg, font=FONT, bd=0,
                             insertbackground=INK, highlightthickness=0)
            entry.insert(0, item["text"])
            entry.pack(fill="x", expand=True)
            entry.bind("<FocusOut>", lambda _e, i=item_idx, en=entry: self._on_item_text(i, en))
            entry.bind("<Return>", lambda _e, i=item_idx, en=entry: self._on_item_text(i, en))
            self.item_entries[item_idx] = entry
            if item.get("done"):
                # Linea de tachado dibujada encima del Entry, en vez de fiarse
                # del overstrike de la fuente (poco confiable en Entry/Windows).
                tk.Frame(entry_wrap, bg=INK_DIM, height=2).place(
                    relx=0, rely=0.5, relwidth=1, anchor="w")
            xbtn = tk.Label(top, text="quitar", bg=bg, fg=INK_DIM,
                            font=FONT_SMALL, cursor="hand2")
            xbtn.pack(side="right", padx=4)
            xbtn.bind("<Button-1>", lambda _e, i=item_idx: self.delete_item(i))
            remind_min = item.get("remind_minutes", DEFAULT_REMIND_MINUTES)
            remind_lbl = tk.Label(top, text=_format_reminder(remind_min), bg=bg,
                                  fg=INK_DIM, font=FONT_SMALL, cursor="hand2")
            remind_lbl.pack(side="right", padx=4)
            remind_lbl.bind("<Button-1>", lambda _e, i=item_idx: self._edit_reminder(i))
            dots = tk.Canvas(row, bg=bg, height=8, highlightthickness=0)
            dots.pack(fill="x", padx=(28, 4))
            dots.bind("<Configure>", lambda e, d=dots: self._draw_dots(d, e.width))

        tk.Label(wrap, text="+ agregar renglon", bg=bg, fg=INK_DIM, font=FONT_SMALL,
                 cursor="hand2").pack(anchor="w", pady=(10, 0))
        wrap.winfo_children()[-1].bind("<Button-1>", lambda _e: self.add_blank_row())

    CHECKBOX_SIZE = 20

    def _checkbox(self, parent, bg, item_idx, done):
        # Dibujado a mano (no Checkbutton nativo): asi controlamos el tamano
        # de verdad y el visto queda siempre visible, sin depender de que el
        # selectcolor del tema de Windows contraste con el fondo.
        s = self.CHECKBOX_SIZE
        c = tk.Canvas(parent, width=s, height=s, bg=bg, highlightthickness=0,
                     cursor="hand2")
        c.create_rectangle(2, 2, s - 2, s - 2, outline=INK, width=2)
        if done:
            c.create_line(4, s * 0.55, s * 0.42, s - 4, fill=INK, width=2)
            c.create_line(s * 0.42, s - 4, s - 4, 4, fill=INK, width=2)
        c.bind("<Button-1>", lambda _e, i=item_idx: self.toggle_item(i))
        return c

    def _on_item_text(self, item_idx, entry):
        self.pages[self.active]["items"][item_idx]["text"] = entry.get()
        self.save()

    def _draw_dots(self, canvas, width):
        canvas.delete("dots")
        canvas.create_line(0, 4, width, 4, fill=INK_DIM, dash=(2, 3), tags="dots")

    def _edit_reminder(self, item_idx):
        self._flush_text()
        item = self.pages[self.active]["items"][item_idx]
        current = item.get("remind_minutes", DEFAULT_REMIND_MINUTES)
        val = self._ask_minutes(current)
        if val is None:
            return
        item["remind_minutes"] = val
        item["last_reminded"] = 0  # que cuente de nuevo con el intervalo recien puesto
        self._render_page()
        self.save()

    def _ask_minutes(self, current):
        # Dialogo propio, minimo: sin texto explicativo, solo el numero y la
        # unidad (min/h/d). El de Tk por defecto (simpledialog) se veia fuera
        # de lugar al lado del resto de la agenda, y con mucho texto de mas.
        result = {"value": None}
        number, unit = _minutes_to_value_unit(current)
        state = {"unit": unit}

        dlg = tk.Toplevel(self.win)
        dlg.title("")
        dlg.configure(bg="#FFFFFF")
        dlg.resizable(False, False)
        dlg.transient(self.win)
        dlg.grab_set()

        row = tk.Frame(dlg, bg="#FFFFFF")
        row.pack(padx=14, pady=14)

        entry = tk.Entry(row, font=FONT, width=4, justify="center", bd=1,
                         relief="solid")
        entry.insert(0, str(number))
        entry.pack(side="left", ipady=4)
        entry.select_range(0, tk.END)
        entry.focus_set()

        unit_buttons = {}

        def pick_unit(u):
            state["unit"] = u
            for label, btn in unit_buttons.items():
                on = label == u
                btn.configure(bg=INK if on else "#EFEFEF", fg="#FFFFFF" if on else INK)

        units_row = tk.Frame(row, bg="#FFFFFF")
        units_row.pack(side="left", padx=(8, 0))
        for label, _factor in REMIND_UNITS:
            btn = tk.Label(units_row, text=label, font=FONT_SMALL, padx=8, pady=5,
                          cursor="hand2")
            btn.pack(side="left", padx=2)
            btn.bind("<Button-1>", lambda _e, l=label: pick_unit(l))
            unit_buttons[label] = btn
        pick_unit(unit)

        def confirm(_e=None):
            try:
                n = max(0, int(entry.get()))
            except ValueError:
                return
            result["value"] = n * dict(REMIND_UNITS)[state["unit"]]
            dlg.destroy()

        btns = tk.Frame(dlg, bg="#FFFFFF")
        btns.pack(pady=(0, 12), padx=14, fill="x")
        tk.Button(btns, text="Cancelar", command=dlg.destroy, bg="#EFEFEF", fg=INK,
                 relief="flat", bd=0, font=FONT_SMALL, padx=8, pady=4, cursor="hand2"
                 ).pack(side="right")
        tk.Button(btns, text="Guardar", command=confirm, bg=INK, fg="#FFFFFF",
                 relief="flat", bd=0, font=FONT_SMALL, padx=10, pady=4, cursor="hand2"
                 ).pack(side="right", padx=(0, 6))
        entry.bind("<Return>", confirm)

        dlg.update_idletasks()
        x = self.win.winfo_rootx() + (self.win.winfo_width() - dlg.winfo_width()) // 2
        y = self.win.winfo_rooty() + (self.win.winfo_height() - dlg.winfo_height()) // 2
        dlg.geometry(f"+{x}+{y}")

        dlg.wait_window()
        return result["value"]

    # --- pagina de post-its (tablero suelto dentro de la hoja) --------------------

    def _build_postits(self, page):
        board = tk.Frame(self.page_area, bg="#FFFFFF")
        board.pack(fill="both", expand=True, padx=14, pady=(6, 14))
        self.postit_board = board
        for idx in range(len(page["notes"])):
            self._place_postit(idx)

        add = tk.Canvas(self.page_area, width=44, height=44, bg="#FFFFFF",
                        highlightthickness=0, cursor="hand2")
        add.place(relx=1.0, rely=1.0, x=-24, y=-24, anchor="se")
        add.create_oval(2, 2, 42, 42, fill=INK, outline="")
        add.create_text(22, 22, text="+", fill="#FFFFFF", font=("Segoe UI", 18, "bold"))
        add.bind("<Button-1>", lambda _e: self.add_postit())

    def _place_postit(self, idx):
        page = self.pages[self.active]
        note = page["notes"][idx]
        frame = tk.Frame(self.postit_board, bg=note["color"],
                         highlightthickness=1, highlightbackground=BORDER)
        frame.place(x=note["x"], y=note["y"], width=note.get("w", 160),
                   height=note.get("h", 130))

        header = tk.Frame(frame, bg=note["color"], cursor="fleur", height=14)
        header.pack(fill="x")
        close = tk.Label(header, text="x", bg=note["color"], fg=INK_DIM,
                         font=FONT_SMALL, cursor="hand2")
        close.pack(side="right")
        close.bind("<Button-1>", lambda _e, i=idx: self.delete_postit(i))
        header.bind("<ButtonPress-1>", lambda e, i=idx: self._postit_drag_start(e, i))
        header.bind("<B1-Motion>", lambda e, i=idx: self._postit_drag_move(e, i, frame))
        header.bind("<ButtonRelease-1>", lambda e, i=idx: self._postit_drag_end(e, i, frame))

        text = tk.Text(frame, bg=note["color"], fg=INK, bd=0, wrap="word",
                       font=("Segoe UI", 10), highlightthickness=0, padx=6, pady=2)
        text.pack(fill="both", expand=True)
        text.insert("1.0", note["text"])
        text.edit_modified(False)
        text.bind("<<Modified>>", lambda _e, i=idx, t=text: self._on_postit_text(i, t))

    def _postit_drag_start(self, e, idx):
        note = self.pages[self.active]["notes"][idx]
        self._postit_drag = (e.x_root, e.y_root, note["x"], note["y"])

    def _postit_drag_move(self, e, idx, frame):
        x0, y0, px, py = self._postit_drag
        nx = max(0, px + (e.x_root - x0))
        ny = max(0, py + (e.y_root - y0))
        frame.place(x=nx, y=ny)

    def _postit_drag_end(self, e, idx, frame):
        pos = frame.place_info()
        note = self.pages[self.active]["notes"][idx]
        note["x"] = int(float(pos["x"]))
        note["y"] = int(float(pos["y"]))
        self.save()

    def _on_postit_text(self, idx, text_widget):
        if not text_widget.edit_modified():
            return
        self.pages[self.active]["notes"][idx]["text"] = text_widget.get("1.0", "end-1c")
        self.save()
        text_widget.edit_modified(False)

    def add_postit(self):
        page = self.pages[self.active]
        n = len(page["notes"])
        offset = 24 * (n % 6)
        page["notes"].append({
            "text": "", "x": 20 + offset, "y": 20 + offset,
            "color": POSTIT_COLORS[n % len(POSTIT_COLORS)],
        })
        self._render_page()
        self.save()

    def delete_postit(self, idx):
        del self.pages[self.active]["notes"][idx]
        self._render_page()
        self.save()

    # --- acciones de pagina --------------------------------------------------------

    def _flush_text(self):
        page = self.pages[self.active]
        if self.text is not None and self.text.winfo_exists():
            page["content"] = self.text.get("1.0", "end-1c")
        # Los renglones de lista solo se guardaban en FocusOut/Enter: si se
        # escribia y de una se le daba click al check, se perdia lo escrito
        # porque nunca habia llegado a guardarse. Aqui se vuelca todo antes
        # de cualquier accion que vaya a redibujar (y por tanto destruir los
        # Entry con lo que la usuaria acaba de teclear).
        for idx, entry in getattr(self, "item_entries", {}).items():
            if entry.winfo_exists():
                page["items"][idx]["text"] = entry.get()

    def select_page(self, idx):
        if idx == self.active:
            return
        self._flush_text()
        self.active = idx
        self._render_tabs()
        self._render_page()
        self.save()

    def add_page(self, kind):
        self._flush_text()
        n = len(self.pages) + 1
        titles = {"todo": f"Lista {n}", "postits": "Post-its", "notes": f"Pagina {n}"}
        items = _blank_items(BLANK_TODO_ROWS) if kind == "todo" else []
        self.pages.append({"title": titles[kind], "type": kind, "content": "",
                           "items": items, "notes": []})
        self.active = len(self.pages) - 1
        self._render_tabs()
        self._render_page()
        self.save()

    def delete_page(self, idx):
        if len(self.pages) <= 1:
            return
        title = self.pages[idx]["title"]
        if not messagebox.askyesno("Eliminar pagina", f"Borrar '{title}'?",
                                    parent=self.win):
            return
        self._flush_text()
        del self.pages[idx]
        self.active = max(0, min(self.active, len(self.pages) - 1))
        self._render_tabs()
        self._render_page()
        self.save()

    def rename_page(self, idx):
        self._flush_text()
        new = simpledialog.askstring("Renombrar pagina", "Nuevo nombre:",
                                     initialvalue=self.pages[idx]["title"],
                                     parent=self.win)
        if new:
            self.pages[idx]["title"] = new
            self._render_tabs()
            self._render_page()
            self.save()

    def _on_text_modified(self, _e):
        if not self.text.edit_modified():
            return
        self.pages[self.active]["content"] = self.text.get("1.0", "end-1c")
        self.save()
        self.text.edit_modified(False)

    def add_blank_row(self):
        self._flush_text()
        self.pages[self.active]["items"].append(
            {"text": "", "done": False, "remind_minutes": DEFAULT_REMIND_MINUTES,
             "last_reminded": 0})
        self._render_page()
        self.save()

    def toggle_item(self, item_idx):
        self._flush_text()
        items = self.pages[self.active]["items"]
        items[item_idx]["done"] = not items[item_idx]["done"]
        self.save()
        self._render_page()

    def delete_item(self, item_idx):
        self._flush_text()
        del self.pages[self.active]["items"][item_idx]
        self._render_page()
        self.save()

    def save(self):
        _save(self.pages, self.active)

    # --- ventana ---------------------------------------------------------------------

    def _on_close(self):
        self._flush_text()
        self.save()
        self.win.destroy()

    def show(self):
        self.win.deiconify()
        self.win.lift()
        self.win.focus_force()
