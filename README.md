# MascoTuscan

[![verify](https://github.com/jonattan-infante/mascotuscan/actions/workflows/ci.yml/badge.svg)](https://github.com/jonattan-infante/mascotuscan/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/jonattan-infante/mascotuscan?label=release)](https://github.com/jonattan-infante/mascotuscan/releases)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS · Windows](https://img.shields.io/badge/platform-macOS%20%7C%20Windows-lightgrey)

Una mascota de escritorio que te cuenta qué están haciendo tus agentes de IA.
En macOS observa [cmux](https://cmux.com); en Windows observa
[Claude Code](https://claude.com/claude-code). **Elige la tuya, o hazla.**

```
                                    ┌──────────────────────────────────────┐
      ___                           │ › *bip-bip* ./gradlew build terminó  │
     /o o\                          │ en 1 min 34 s en Fineract. Todo en   │
    | ___ |                         │ orden.█                              │
    |[###]|  ◄───────────────────── └──────────────────────────────────────┘
    /|   |\
   ▄▄▀   ▀▄▄
```

Cuando trabajas con varios agentes en paralelo pierdes el hilo: terminan en
workspaces que no estás mirando, se quedan esperando permiso, los builds pasan sin
que te enteres. La mascota flota sobre todo lo demás y te lo dice, con su propia
personalidad.

## Contenido

- [Características](#características)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Uso](#uso)
- [Mascotas](#mascotas)
- [Configuración](#configuración)
- [Actualizar](#actualizar)
- [Cómo funciona](#cómo-funciona)
- [Solución de problemas](#solución-de-problemas)
- [Contribuir](#contribuir)
- [Estado del proyecto](#estado-del-proyecto)
- [Licencia](#licencia)

## Características

- **Avisa cuando un agente termina** su turno, y en qué workspace.
- **Se pone en alerta** cuando un agente pide permiso o hace una pregunta, y se
  queda así hasta que le hagas caso.
- **Te dice en qué van**: pasa el mouse por encima y ves cada agente, qué
  herramienta usa, cuántos pasos lleva y con qué prompt arrancó.
- **Avisa de comandos largos** (más de 20 s) y de cualquier comando que falle.
- **Avisa de puertos** que empiezan y dejan de escuchar.
- **Un click te lleva** al workspace del aviso y trae cmux al frente.
- **Mascotas intercambiables**: cuatro incluidas, un marketplace sin servidor, y
  un formato de paquete para hacer la tuya sin programar.
- **Voz con personalidad**: Claude Code local escribe las frases de cada mascota
  a partir de una descripción en prosa. Sin API key. Sin Claude Code, habla igual
  con las frases de respaldo del paquete.
- **No molesta**: se calla si estás mirando ese pane, ignora comandos
  interactivos y no cuenta Ctrl-C como fallo.
- **Sin dependencias**: un binario de Swift de menos de 1 MB en macOS; solo la
  biblioteca estándar de Python en Windows.

## Requisitos

| Plataforma | Necesita | Observa |
|---|---|---|
| macOS 13 o más | [cmux](https://cmux.com) y Swift (viene con Xcode o con `xcode-select --install`) | eventos de cmux, hooks de zsh, puertos |
| Windows 10/11 | Python 3 con tkinter (el instalador oficial lo incluye) y Claude Code | hooks de Claude Code |

Las dos plataformas comparten los paquetes de mascotas, el contrato de voz y el
formato del estado en disco.

## Instalación

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/jonattan-infante/mascotuscan/main/install.sh | bash
```

Instala la última versión publicada en `~/.mascotuscan`, engancha `~/.zshrc` y la
mascota aparece en la esquina inferior derecha al abrir una terminal de cmux.
Desde un clon del repositorio: `./install.sh --from-source`.

### Windows

```powershell
git clone https://github.com/jonattan-infante/mascotuscan.git
cd mascotuscan\windows
python install.py
```

Registra los hooks en `~\.claude\settings.json` respetando los que ya tengas. La
mascota arranca sola en tu próxima sesión de Claude Code. Los detalles del port
están en [`windows/README.md`](windows/README.md).

### Desinstalar

```bash
curl -fsSL https://raw.githubusercontent.com/jonattan-infante/mascotuscan/main/install.sh | bash -s -- --uninstall
```

Quita el binario y el enganche del shell. Tus preferencias, mascotas y arte se
conservan en `~/.mascotuscan`; bórralo tú si quieres empezar de cero. En Windows:
`python install.py --uninstall`.

## Uso

Una vez instalada no hay nada que hacer: la mascota escucha y habla sola.

| Acción | Qué pasa |
|---|---|
| Click | salta al workspace del último aviso |
| Arrastrar | la mueves; recuerda la posición |
| Mouse encima | panel con el estado de cada agente |
| Click derecho | cambiar de mascota, silenciar, reescribir frases, actualizar, salir |

Los comandos de terminal (macOS):

| Comando | Qué hace |
|---|---|
| `mascotuscan list` | mascotas instaladas, con la activa marcada |
| `mascotuscan use <id>` | cambiar de mascota, en caliente |
| `mascotuscan search [texto]` | buscar en el marketplace |
| `mascotuscan install <id\|url\|ruta> [--use]` | instalar del marketplace, de un repositorio git o de una carpeta |
| `mascotuscan new <id> [--sprites]` | crear un paquete nuevo, ya válido |
| `mascotuscan fork <origen> <nuevo>` | copia editable de una mascota existente |
| `mascotuscan sprite <id> <estado> <archivo>` | ponerle una imagen a un estado; `--dir`, `--clear` |
| `mascotuscan validate <ruta>` | revisar un paquete y explicar cada fallo |
| `mascotuscan voice [<id>]` | que Claude Code le escriba las frases |
| `mascotuscan update [--check]` | actualizar a la última versión publicada |
| `mascotuscan --version`, `mascotuscan help` | |

## Mascotas

El programa es uno; las mascotas son muchas. Vienen cuatro:

| id | Mascota | Dibujo | Cómo habla |
|---|---|---|---|
| `astro` | Astro | vectorial | droide de servicio: *bip-bip*, seco, con carácter |
| `gatito` | Gatito | vectorial | indiferencia felina: te avisa, pero tenía otros planes |
| `cangrejo` | Don Cangrejo | sprites | tacaño y marinero: cada minuto de agente cuesta |
| `llama` | Llama | sprites | audífonos puestos, beat sonando, te cuida los agentes |

La misma alerta, dos personalidades:

```
astro   › *bzzzt* npm run build falló con código 1 en Backend. Algo no cuadra.
gatito  › npm run build se rompió, código 1 en Backend. No fui yo.
```

### Hacer la tuya

No hace falta programar. Una mascota es una carpeta con un archivo que describe
cómo habla:

```bash
mascotuscan new mi-mascota        # crea un paquete que ya funciona
# edita mi-mascota/persona.md  <- lo único imprescindible
mascotuscan validate ./mi-mascota
mascotuscan install ./mi-mascota --use
mascotuscan voice mi-mascota      # Claude Code le escribe sus frases
```

`persona.md` es prosa, no configuración:

```markdown
Eres Gatito, un gato que vive flotando sobre la pantalla de un programador.

Tu tono es de indiferencia felina cortés: informas lo que pasó, pero dejas claro
que tú tenías otros planes. Nunca eres grosero.

Usas sonidos de gato con moderación: "mrrp", "miau", "prrr". No en todas las
frases, y nunca más de uno por frase.
```

Con eso, `mascotuscan voice` produjo 64 frases como estas:

```
{cmd} explotó{where}, código {code}, fffs. Vuelvo a mi caja.
{agent} lleva {time} {doing}{where}. Yo llevo el mismo tiempo sin moverme del sol.
```

Usa tu sesión local de Claude Code, sin API key. Las frases generadas se guardan
fuera del paquete, así que actualizar la mascota no las borra.

### Con tu propio arte

```bash
mascotuscan sprite mi-mascota idle gato.png       # una imagen a un estado
mascotuscan sprite mi-mascota --dir ./mis-dibujos # varias, por nombre de archivo
mascotuscan sprite mi-mascota --clear             # volver al dibujo vectorial
```

Con `--dir` toma los archivos que se llamen como un estado (`idle.png`,
`working.gif`, `done.png`, `error.png`, `attention.png`, `info.png`) o
`default.png` como comodín. Los GIF se animan solos. La imagen reemplaza el cuerpo
entero; el programa sigue dibujando la sombra, los puntos de "trabajando", el
signo de admiración cuando te necesita y el salto al terminar.

Para partir de una mascota incluida, saca tu copia primero: las de fábrica se
reemplazan al actualizar.

```bash
mascotuscan fork gatito mi-gato --name "Mi Gato"
mascotuscan sprite mi-gato --dir ./mis-dibujos
mascotuscan use mi-gato
```

### Sin arte propio

Tres dibujos integrados que se tiñen con los colores del paquete. No pesan nada y
son originales:

| `renderer` | Qué dibuja |
|---|---|
| `vector:droid` | droide astromecánico: cúpula con lente, torso, tres patas |
| `vector:ball` | droide esférico: cuerpo bola que rueda, cúpula y antena |
| `vector:sage` | figura encapuchada: túnica, ojos en la sombra, bastón |

`mascotuscan renderers` los lista. El formato completo del paquete está en
[`docs/reference/pet-pack.md`](docs/reference/pet-pack.md).

### Publicar en el marketplace

El marketplace es un JSON en este repositorio: sin servidor, sin cuentas, sin
pagos. Cada entrada apunta al repositorio del autor, así que tu arte se queda donde
tú quieras.

1. Sube tu paquete a un repositorio público tuyo.
2. Abre un PR que agregue una entrada a [`registry.json`](registry.json).
3. Al mergearse, `mascotuscan install tu-id` funciona para todo el mundo.

Qué se revisa y qué se rechaza: [`docs/marketplace.md`](docs/marketplace.md). Una
regla que no se negocia: **nada de arte de personajes con dueño**.

## Configuración

`~/.mascotuscan/config.json` (en Windows, `%USERPROFILE%\.mascotuscan\config.json`):

| Clave | Por defecto | Qué controla |
|---|---|---|
| `activePet` | la primera instalada | mascota activa, por id |
| `quiet` | `false` | silenciar todos los avisos |
| `watchPorts` | `true` | avisar de puertos que abren y cierran (macOS) |
| `notifyWhileWatching` | `false` | avisar aunque estés mirando ese pane (macOS) |
| `narrateEverySeconds` | `150` | cada cuánto cuenta en qué van los agentes; `0` lo apaga |
| `checkUpdates` | `true` | consultar una vez al día si hay una versión nueva |

Variables de entorno para los hooks de zsh, en `~/.zshrc` antes del `source`:

```zsh
export MASCOTUSCAN_MIN_SECONDS=20        # umbral de "comando largo"
export MASCOTUSCAN_IGNORE="vim ssh ..."  # comandos que nunca se reportan
export MASCOTUSCAN_NO_AUTOSTART=1        # no arrancar solo
export MASCOTUSCAN_REGISTRY=<url>        # usar otro marketplace
```

## Actualizar

La mascota avisa una vez cuando sale una versión nueva, con su propia voz. Después
de eso, actualizar es un comando:

```bash
mascotuscan update            # macOS: reinstala la última publicada
mascotuscan update --check    # solo dice si hay una más nueva
```

En Windows, desde `windows/`: `python install.py --update`.

**Si venías de LucyGlow** (comando `lucy`): `lucy update` instala MascoTuscan y
mueve `~/.lucy` a `~/.mascotuscan` sin perder configuración, mascotas ni frases;
también cambia el enganche de tu `~/.zshrc`. Desde ahí el comando es
`mascotuscan` y las variables son `MASCOTUSCAN_*`: si pusiste `~/.lucy/bin` en tu
`PATH` o usabas alguna `LUCY_*`, cámbialas a mano. En Windows, después de
`python install.py --update`, corre `python install.py` una vez más para
registrar los hooks con su nombre nuevo. Por qué y qué cambió:
[`docs/adr/0010`](docs/adr/0010-renombrar-lucyglow-a-mascotuscan.md).

La comprobación es una consulta al día a GitHub, en segundo plano, y se apaga con
`checkUpdates: false`. Las versiones siguen [SemVer](https://semver.org/lang/es/) y
cada una tiene sus notas en [`CHANGELOG.md`](CHANGELOG.md). Cómo se publica una:
[`docs/reference/versioning.md`](docs/reference/versioning.md).

## Cómo funciona

```
cmux events ──┐
cmux rpc    ──┼──► orquestador ──► estado (uno de seis) ──► pet pack
zsh hooks   ──┤                                              arte + voz
reloj       ──┘
```

El programa decide **cuándo** hablar y en qué estado está; el paquete decide
**cómo se ve y cómo habla**. Toda mascota expresa los mismos seis estados, que son
el vocabulario del sistema:

| Estado | Cuándo |
|---|---|
| `idle` | nada en curso |
| `working` | hay agentes activos |
| `done` | terminó bien |
| `error` | exit code distinto de cero |
| `attention` | pide permiso o pregunta |
| `info` | notificación, puerto o versión nueva |

Para verlos sin instalar nada: `make render && open render/todos.png`.

Tres reglas para que no moleste: no avisa de lo que ya estás viendo (pane enfocado
y cmux al frente), ignora los comandos interactivos (`vim`, `ssh`, `btop`,
`claude`, `psql`, `tail`...) y no cuenta Ctrl-C como fallo.

La arquitectura está en [`ARCHITECTURE.md`](ARCHITECTURE.md) y cada decisión con
su evidencia en [`docs/adr/`](docs/adr/). Una que sorprende: cmux solo acepta
control de procesos que descienden de cmux, así que la mascota no puede arrancar
desde launchd. Por eso arranca desde tu shell
([`docs/adr/0001`](docs/adr/0001-arranque-por-shell-no-launchd.md)).

## Solución de problemas

**No llegan avisos.** Mira `~/.mascotuscan/pet.log`: registra cada aviso, cada
supresión y cada caída de la conexión con cmux. Si dice que el socket rechazó el
proceso, la mascota se arrancó fuera de cmux; ciérrala y abre una terminal de cmux
nueva. `cmux capabilities | grep access_mode` dice cómo está configurado el socket.

**Habla con frases genéricas.** Todavía no tiene frases generadas: click derecho,
"Reescribir sus frases", o `mascotuscan voice`. Necesita Claude Code instalado.

**No hay mascota.** `mascotuscan install astro --use`. Sin mascota instalada lo dice
en pantalla en vez de quedarse muda.

**Molesta.** Click derecho, "Silenciar avisos". O ajusta `config.json`.

Para reportar un problema, incluye la salida de `pet.log`, la versión de macOS o
Windows, y `mascotuscan --version`.

## Contribuir

```bash
git clone https://github.com/jonattan-infante/mascotuscan.git
cd mascotuscan
make verify        # el gate completo: lo mismo que corre CI
make render        # revisar el dibujo a ojo
make run           # arrancar en primer plano
```

`main` está protegido: todo entra por PR con CI en verde. Convenciones, flujo y
qué se espera de un cambio: [`CONTRIBUTING.md`](CONTRIBUTING.md). Si vas a trabajar
con un agente de IA, [`CLAUDE.md`](CLAUDE.md) es el router del repositorio.

## Estado del proyecto

Versión `0.2.0`, en uso diario por su autor. Lo entregado, lo que está en vuelo y
el backlog viven en [`EXECUTION-PLAN.md`](EXECUTION-PLAN.md), con la evidencia de
cada estado. Los cambios por versión, en [`CHANGELOG.md`](CHANGELOG.md).

## Licencia

[MIT](LICENSE). Cada mascota del marketplace declara la suya.

MascoTuscan no está afiliado a cmux ni a Anthropic. Los dibujos integrados son
originales.
