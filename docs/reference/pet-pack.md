# Formato de paquete de mascota (pet pack)

Un **pet pack** es una carpeta que define una mascota: cómo se ve, cómo habla y
cómo se llama. Es la unidad que se instala, se comparte y se publica en el
marketplace.

Este documento es el **contrato**. El código, el CLI y el registro dependen de él.
Un cambio incompatible sube `schemaVersion`.

## Estructura

```
mi-mascota/
├── pet.json          manifiesto (obligatorio)
├── persona.md        la personalidad, en prosa (obligatorio)
├── phrases.json      frases de respaldo (opcional pero recomendado)
└── sprites/          imágenes por estado (obligatorio si renderer = "sprites")
    ├── idle.gif
    ├── working.png
    ├── done.png
    ├── error.png
    ├── attention.png
    └── info.png
```

Nada más es necesario. Un pack mínimo válido son dos archivos: `pet.json` y
`persona.md`.

## `pet.json`

```json
{
  "schemaVersion": 1,
  "id": "astro",
  "name": "Astro",
  "version": "1.0.0",
  "author": "jonattan-infante",
  "description": "Un droide astromecánico que reporta como una unidad de servicio.",
  "license": "MIT",
  "language": "es",
  "renderer": "vector:droid",
  "sprites": {},
  "accent": {
    "idle": "#6B9EFA",
    "working": "#FAB83D",
    "done": "#4CCC80",
    "error": "#F05C5C",
    "attention": "#FA8C33",
    "info": "#8C99FA"
  }
}
```

| Campo | Obligatorio | Qué es |
|---|---|---|
| `schemaVersion` | sí | `1`. Si no coincide, el pack se rechaza con un mensaje claro |
| `id` | sí | identificador único, `[a-z0-9-]{2,32}`. Es el nombre de la carpeta instalada y el que se usa en los comandos |
| `name` | sí | nombre para mostrar |
| `version` | sí | semver. El marketplace lo usa para saber si hay actualización |
| `author` | sí | quien la hizo. Texto libre; por convención el usuario de GitHub |
| `description` | sí | una línea. Es lo que se ve al buscar en el marketplace |
| `license` | no | por defecto `"unlicensed"`. **Importante**: si usas arte de terceros, decláralo |
| `language` | no | código ISO, por defecto `"es"`. Define el idioma de las frases generadas |
| `renderer` | sí | `"vector:droid"` o `"sprites"`. Ver abajo |
| `sprites` | si `renderer = "sprites"` | mapa estado → ruta relativa dentro del pack |
| `accent` | no | color por estado. Si falta, se usa la paleta por defecto |
| `roam` | no | cómo recorre la pantalla mientras hay trabajo. Si falta, se queda en su lugar. Ver abajo |

### Renderers

| Valor | Qué dibuja | Cuándo usarlo |
|---|---|---|
| `vector:droid` | droide astromecánico: cúpula con lente, torso con paneles, tres patas | voz de máquina de servicio |
| `vector:ball` | droide esférico apoyado en el piso: quieto, la cabeza mira alrededor con pausas; trabajando, rueda hacia quien mira con los paneles barridos | voz ágil o juguetona |
| `vector:sage` | figura encapuchada: túnica, ojos en la sombra, bastón | voz tranquila o sentenciosa |
| `sprites` | tus propias imágenes | tienes arte propio |

Los tres vectoriales se dibujan con Core Graphics y se tiñen con tus `accent`:
no pesan nada y no involucran arte de nadie. Para verlos:

```bash
mascotuscan renderers
```

Con `sprites`, los formatos aceptados son `gif` (se anima solo), `png`, `webp`,
`heic`, `jpg`, `tiff` y `pdf`. Fondo transparente, 150 px o más de lado.

No hace falta declarar los seis estados. El que falte cae a `default` si existe,
y si tampoco existe, al renderer vectorial. Así un pack con una sola imagen es
válido.

Cada imagen animada empieza en su primer cuadro cuando aparece (al entrar al
estado, o al dejar de moverse) y después se repite. Así un estado puede tener un
gesto de una sola vez: `done` dura 3 s, y una imagen de 3 s para `done` se ve
entera, de principio a fin.

### Recorrer la pantalla (`roam`)

Opcional, y cada mascota decide si lo quiere. Con `roam`, mientras hay al menos
un agente trabajando la mascota rueda (o camina) hasta el borde de la pantalla,
da la vuelta en espejo y sigue de borde a borde; cuando ya no hay trabajo,
vuelve a su lugar y se queda ahí. Ver `docs/adr/0013`.

```json
"roam": {
  "start": "sprites/arranque.png",
  "loop": "sprites/rodando.png",
  "speed": 73
}
```

| Campo | Obligatorio | Qué es |
|---|---|---|
| `loop` | sí | se reproduce en bucle mientras avanza |
| `start` | no | se reproduce una vez, sin moverse, antes de avanzar (por ejemplo, girar la cabeza hacia donde va). Al revés es la frenada. Sin él, arranca y frena en seco |
| `speed` | sí | puntos por segundo, de 10 a 400 |

Reglas del dibujo:

- **Las dos imágenes miran a la derecha.** Hacia la izquierda el programa las
  espeja; no hay que dibujar las dos direcciones.
- **Mismo lienzo que los sprites de estado.** Se dibujan en la misma caja, así
  que si miden distinto la mascota cambia de tamaño al arrancar.
- **`start` termina en el primer cuadro de `loop`**, y empieza en la pose de
  reposo: al frenar se reproduce al revés y tiene que quedar como estaba.
- **Cada cuadro dura lo que declara**, en GIF, PNG animado, WebP o HEICS; menos
  de 20 ms cuenta como 100 ms, como en los navegadores. Una pausa conviene
  escribirla como un solo cuadro largo y no como muchos iguales: cada cuadro
  distinto ocupa memoria. Hasta la 0.4.0, en macOS un PNG animado tomaba la
  duración del primer cuadro para todos; si el pack tiene que verse bien ahí,
  todos los cuadros con la misma duración.
- **`speed` sin patinar**: si el cuerpo rueda, la velocidad es el perímetro de la
  rueda en pantalla dividido por lo que dura una vuelta de `loop`. Con otra
  velocidad se ve como si patinara.
- Para bordes suaves sobre cualquier escritorio conviene PNG animado (APNG): el
  GIF solo tiene transparencia de un bit.

Cuándo se detiene: mientras tienes el mouse encima, mientras hay un permiso o una
pregunta esperando respuesta en la burbuja, mientras un agente la necesita
(`attention`) y mientras celebra que algo terminó (`done`). No se le puede hacer
clic a una burbuja que se va, y un gesto de celebración no se ve rodando. Si el
estado tiene imagen propia (no solo `default`), se ve en cuanto empieza a frenar,
sin esperar la frenada. Al reanudar sigue hacia donde iba. Si la arrastras, ese
pasa a ser su lugar.

Quieta, se dibuja el sprite del estado como siempre. En movimiento no flota: va
apoyada en el piso.

## Los seis estados

Toda mascota tiene que poder expresar estos seis. Es el vocabulario del sistema.

| Estado | Significa |
|---|---|
| `idle` | no hay nada en curso |
| `working` | al menos un agente trabajando |
| `done` | algo terminó bien |
| `error` | algo falló |
| `attention` | un agente necesita al humano y no avanza sin él |
| `info` | novedad sin urgencia: una notificación, un puerto |

## `persona.md`

La personalidad en prosa. Se le pasa a Claude Code como parte del prompt que
genera las frases, así que **describe cómo habla tu mascota, no qué dice**.

```markdown
Eres un droide astromecánico que vive flotando sobre la pantalla de un
programador. Hablas en español neutro.

Cada frase empieza con una onomatopeya entre asteriscos, variada y acorde al
tono: alegre al terminar, chirriante al fallar. *bip-bip*, *whirr*, *bzzzt*,
*blip*, *dwoo-weep*.

Tono servicial, seco, con carácter. Humor leve de droide, sin chistes largos.
Nunca sonar como un log de sistema.
```

Lo que **no** va aquí, porque el generador ya lo impone: el formato JSON, los
marcadores obligatorios, el límite de longitud, la prohibición de emojis y saltos
de línea. Solo la voz.

Un `persona.md` de tres líneas funciona. Uno de treinta también, pero cuanto más
largo, menos se respeta el conjunto.

## `phrases.json`

Frases de respaldo, con la misma forma que produce el generador. Se usan cuando no
hay frases generadas todavía o cuando la generación falla, así que **una mascota
con `phrases.json` funciona sin conexión y sin Claude Code**.

```json
{
  "greeting":     ["*bip-bip* aquí estoy, listo para flotar sobre tu código."],
  "agentDone":    ["*bip-bip* {agent} terminó su turno{where}. Todo en orden."],
  "commandDone":  ["*whirr* {cmd} terminó en {time}{where}."],
  "commandError": ["*bzzzt* {cmd} falló con código {code}{where}."],
  "attention":    ["*bip! bip!* {agent} necesita {what}{where}."],
  "working":      ["*whirr* {agent} lleva {time}{where} {doing}."],
  "portUp":       ["*blip* el puerto {port} está escuchando{where}."],
  "portDown":     ["*blip* el puerto {port} se cerró{where}."],
  "updateAvailable": ["*bip* hay una versión nueva de MascoTuscan: {version}."]
}
```

### Marcadores

Cada clase de aviso acepta unos marcadores y **debe usarlos todos**. Una plantilla
que le falte uno se descarta al validar.

| Clase | Marcadores obligatorios | Qué contienen |
|---|---|---|
| `greeting` | ninguno | — |
| `agentDone` | `{agent}` `{where}` | `"Claude"`, `" en Fineract"` |
| `commandDone` | `{cmd}` `{time}` `{where}` | `"./gradlew build"`, `"1 min 34 s"` |
| `commandError` | `{cmd}` `{code}` `{where}` | `"npm test"`, `"1"` |
| `attention` | `{agent}` `{what}` `{where}` | `{what}` es un sustantivo: `"un permiso para usar Bash"` |
| `working` | `{agent}` `{doing}` `{time}` `{where}` | `{doing}` es gerundio: `"corriendo comandos"` |
| `portUp` / `portDown` | `{port}` `{where}` | `"3000"` |
| `updateAvailable` | `{version}` | `"0.3.0"`: hay una versión nueva del programa; la frase invita a actualizar |

Dos reglas que cuestan errores si se olvidan:

1. **`{where}` ya trae la preposición** (`" en Fineract"`) o viene vacío. Se pega
   directo después de una palabra. Nunca escribas `"en {where}"`.
2. **`{what}` es un sustantivo**, no una oración. Las plantillas lo enchufan tras
   "necesita" o "está atascado en".

## Reglas de validación

`mascotuscan validate <ruta>` comprueba todo esto y explica cada fallo:

- `schemaVersion` es 1.
- `id` casa con `[a-z0-9-]{2,32}` y no choca con un pack ya instalado de otro autor.
- `name`, `version`, `author`, `description` presentes y no vacíos.
- `version` es semver.
- `renderer` es un valor conocido.
- Si `renderer = "sprites"`, cada ruta declarada existe dentro del pack y no se
  escapa de la carpeta (`..` prohibido).
- Los colores de `accent` son `#RRGGBB`.
- Si hay `roam`: es un objeto; `loop` (y `start`, si está) existe dentro del
  paquete sin `..`; `speed` es un número entre 10 y 400.
- `persona.md` existe y no está vacío.
- Si hay `phrases.json`: es JSON válido, y **cada clase declarada conserva al
  menos una plantilla** después de validar marcadores. Una clase que se queda en
  cero es un error, no una advertencia: en producción sería una frase que nunca
  sale.
- Cero emojis en `pet.json`, `persona.md` y `phrases.json`.

## Dónde vive lo instalado

```
~/.mascotuscan/
├── pets/
│   ├── astro/            un pack instalado
│   │   ├── pet.json
│   │   ├── persona.md
│   │   ├── phrases.json
│   │   └── sprites/
│   └── mi-gato/
├── voices/
│   ├── astro.json        frases generadas para ese pack
│   └── mi-gato.json
└── config.json           incluye "activePet": "astro"
```

Las frases generadas viven **fuera** del pack, en `voices/`, por dos razones: el
pack se puede reinstalar o actualizar sin perderlas, y un pack de solo lectura
(instalado desde el registro) no se modifica nunca.

## El registro

El marketplace es un archivo JSON en este repositorio, servido por `raw.github`.
No hay servidor.

```json
{
  "schemaVersion": 1,
  "pets": [
    {
      "id": "astro",
      "name": "Astro",
      "description": "Un droide astromecánico.",
      "author": "jonattan-infante",
      "version": "1.0.0",
      "language": "es",
      "renderer": "vector:droid",
      "source": "https://github.com/jonattan-infante/mascotuscan.git",
      "path": "pets/astro",
      "tags": ["droide", "vector", "sin-arte"]
    }
  ]
}
```

`source` + `path` permiten que un pack viva en cualquier repositorio, no solo en
este. Publicar es abrir un PR que agrega una entrada al registro; el arte y el
código se quedan donde su autor quiera.

## Compatibilidad

- `schemaVersion` solo sube con cambios incompatibles. Agregar un campo opcional
  no lo sube.
- Un campo desconocido en `pet.json` se ignora en silencio: así un pack hecho para
  una versión futura sigue funcionando en una vieja mientras lo esencial no cambie.
- Un `renderer` desconocido **no** es silencioso: cae al vectorial y avisa en el
  log, porque mostrar la mascota equivocada sin decir nada es peor.
