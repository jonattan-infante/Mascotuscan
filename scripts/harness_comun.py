# Lo que comparten los harness de Claude: el de issues (issue-harness.py) y el
# de revision de PRs (revision-harness.py). Aqui vive lo que decide si algo
# puede salir del runner: el escaneo de secretos y la limpieza de texto. Un
# arreglo en una de estas reglas tiene que valer para los dos.

import json
import re
import sys
from pathlib import PurePosixPath

# Formas conocidas de credenciales. El escaneo tambien busca el valor exacto de
# los secretos del run (--env), que es lo que de verdad importa: estos patrones
# atrapan credenciales que no son las nuestras.
PATRONES_SECRETOS = (
    ("clave de Anthropic", re.compile(r"sk-ant-[A-Za-z0-9_-]{10,}")),
    ("token de GitHub", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}")),
    ("token fino de GitHub", re.compile(r"github_pat_[A-Za-z0-9_]{20,}")),
    ("llave privada", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("clave de AWS", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("token de Slack", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}")),
)

# Un secreto de menos de 8 caracteres daria falsos positivos en cualquier texto.
MIN_LARGO_SECRETO = 8

# Caracteres que no se ven y sirven para esconder instrucciones: espacios de ancho
# cero, marcas de direccion y el BOM. Escritos como escapes para que se lean.
INVISIBLES = re.compile("[\u200b-\u200f\u202a-\u202e\u2060-\u2064\u2066-\u2069\ufeff]")
COMENTARIO_HTML = re.compile(r"<!--.*?-->", re.S)
MENCION = re.compile(r"(?<![\w`/.])@([A-Za-z0-9][A-Za-z0-9-]*)")

# GitHub rechaza comentarios de mas de 65536 caracteres.
MAX_COMENTARIO = 60000


class Invalido(Exception):
    pass


def _texto(d, campo, largo_max, errores, vacio=False):
    v = d.get(campo)
    if not isinstance(v, str) or (not vacio and not v.strip()):
        errores.append(f"{campo}: tiene que ser texto{'' if vacio else ' no vacio'}")
    elif len(v) > largo_max:
        errores.append(f"{campo}: mas de {largo_max} caracteres")


def _lista_de_textos(d, campo, max_items, errores, largo_item=500):
    v = d.get(campo)
    if not isinstance(v, list):
        errores.append(f"{campo}: tiene que ser una lista")
        return
    if len(v) > max_items:
        errores.append(f"{campo}: mas de {max_items} elementos")
    for i, x in enumerate(v):
        if not isinstance(x, str) or not x.strip():
            errores.append(f"{campo}[{i}]: tiene que ser texto no vacio")
        elif len(x) > largo_item:
            errores.append(f"{campo}[{i}]: mas de {largo_item} caracteres")


def ruta_valida(p):
    """ Una ruta relativa dentro del repo: nada absoluto ni con '..'. El parche
    y el diagnostico hablan del repo, nunca del resto de la maquina. """
    if not isinstance(p, str) or not p or p.startswith("/") or "\\" in p:
        return False
    return ".." not in PurePosixPath(p).parts


def buscar_secretos(textos, valores, patrones=True):
    """ textos: [(nombre, contenido)]; valores: {nombre_env: valor}. Devuelve
    hallazgos como 'archivo:linea: regla', nunca el valor encontrado: un
    reporte que repitiera el secreto seria la fuga que intenta evitar.
    patrones=False busca solo los valores exactos: para textos que traen
    contenido de un tercero, donde una forma de credencial no es nuestra. """
    hallazgos = []
    utiles = {k: v for k, v in valores.items() if v and len(v) >= MIN_LARGO_SECRETO}
    for nombre, contenido in textos:
        for n, linea in enumerate(contenido.splitlines(), 1):
            for env, valor in utiles.items():
                if valor in linea:
                    hallazgos.append(f"{nombre}:{n}: contiene el valor de {env}")
            for regla, patron in PATRONES_SECRETOS if patrones else ():
                if patron.search(linea):
                    hallazgos.append(f"{nombre}:{n}: tiene forma de {regla}")
    return hallazgos


def escanear_archivos(paths, valores, patrones=True):
    """ El subcomando `secretos` de los dos harness. Devuelve el codigo de
    salida: 1 si algo aparece, y entonces no se publica nada. """
    textos = []
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as f:
            textos.append((path, f.read()))
    hallazgos = buscar_secretos(textos, valores, patrones)
    if hallazgos:
        print("FALLA el escaneo de secretos; no se publica nada:", file=sys.stderr)
        for h in hallazgos:
            print(f"  {h}", file=sys.stderr)
        return 1
    print(f"sin secretos en {len(textos)} archivo(s)")
    return 0


def limpiar_entrada(s):
    """ Lo que escribe un tercero (un issue, un PR) se le pasa a Claude como
    datos. Se quitan los escondites conocidos de instrucciones: comentarios HTML
    y caracteres invisibles. """
    return INVISIBLES.sub("", COMENTARIO_HTML.sub("", s or ""))


def neutralizar(s):
    """ Lo que escribe Claude se publica en GitHub. Una mencion notificaria a
    alguien por un texto que ningun humano escribio; en un bloque de codigo no
    notifica. Los comentarios HTML esconderian texto del lector. Las comillas
    escapadas son un resto del JSON que a veces Claude escribe dentro del texto:
    en markdown se verian con la barra. """
    s = limpiar_entrada(s).replace('\\"', '"')
    return MENCION.sub(lambda m: f"`@{m.group(1)}`", s)


def extraer_salida(mensajes):
    """ El archivo de ejecucion de claude-code-action es la lista de mensajes
    del SDK, y el ultimo de tipo 'result' trae structured_output. Se lee de ahi
    y no de la salida del paso de la action porque GitHub imprime en el log el
    entorno de cada paso: la respuesta se veria en un log publico antes de
    pasar por el escaneo de secretos. """
    if not isinstance(mensajes, list):
        raise Invalido("el archivo de ejecucion no es una lista de mensajes")
    for m in reversed(mensajes):
        if isinstance(m, dict) and m.get("type") == "result":
            salida = m.get("structured_output")
            if not isinstance(salida, dict):
                raise Invalido("el resultado de Claude no trae structured_output")
            return salida
    raise Invalido("el archivo de ejecucion no tiene un mensaje de resultado")


def cargar_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        raise Invalido(f"no pude leer {path}: {e}")
