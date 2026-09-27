# ARCHITECTURE.md

Cómo está construido MascoTuscan. Router, no enciclopedia: cada sección apunta al
archivo donde vive el detalle.

## Las dos ideas centrales

**1. cmux ya sabe todo lo que pasa.** Qué agente trabaja, qué herramienta usa, qué
puerto se abrió. Lo publica en un stream de eventos y en un socket de control.
MascoTuscan no observa el sistema: traduce lo que cmux ya dice.

**2. La mascota es un dato, no código.** El programa decide **cuándo** hablar y en
qué estado está; un paquete instalable decide **cómo se ve y cómo habla**. Esa
separación es lo que hace posible el marketplace. Ver `docs/adr/0005`.

```
┌─────────────────────────────────────────────────────────────┐
│  cmux                                                       │
│    events (JSON line-delimited)   rpc (socket de control)   │
└───────────┬─────────────────────────────┬───────────────────┘
            │                             │
      ┌─────▼─────────────────────────────▼──────┐
      │  PetController                           │
      │    correlaciona sesiones y workspaces    │
      │    decide si avisar o callar              │
      │    resuelve el estado: uno de seis        │
      └───┬──────────────┬───────────────┬───────┘
          │              │               │
     ┌────▼────┐   ┌─────▼─────┐   ┌─────▼──────┐
     │ PetView │   │ BubbleView│   │ RosterView │
     │ el cuerpo│  │ el aviso  │   │ el estado  │
     └────┬────┘   └─────┬─────┘   └────────────┘
          │              │
     ┌────▼──────────────▼────┐        ┌──────────────────┐
     │ PetTheme  │  Voice     │◄───────│  pet pack        │
     │ colores   │  frases    │        │  pet.json        │
     │ sprites   │            │        │  persona.md      │
     └───────────┴────────────┘        │  phrases.json    │
                                       │  sprites/        │
                                       └──────────────────┘
```

## Dominios y dirección de dependencias

Las flechas solo apuntan hacia abajo. Una violación es un error de diseño.

```
main.swift            (arranque, --render, despacho de subcomandos)
     │
     ├──────────────────────────┐
     ▼                          ▼
Controller/                 CLI/
(orquesta)                  (list, use, install, new, validate, voice, search)
     │                          │
     ├──────────┬───────────────┤
     ▼          ▼               ▼
Views/       Voice/          Model/
             (conoce         (PetPack, PetLibrary, PetTheme,
              Model)          Mood, Config, Bubble, AgentActivity)
     │          │               │
     └──────────┴───────┬───────┘
                        ▼
                    Support/    (rutas, CLI de cmux, formateo)
```

- **`Model/` no importa AppKit** salvo `Mood` y `PetPack`, que manejan color.
  Es deliberado: el color es parte del significado del estado y del manifiesto.
- **`Views/` nunca llama a cmux ni lee el disco del pack.** Pide colores y sprites
  a `PetTheme`; los datos le llegan.
- **`Support/CmuxCLI` es el único lugar que ejecuta `cmux`.**
- **`CLI/` no conoce las vistas.** Es una herramienta de terminal: escribe a
  stdout y devuelve un código de salida. Por eso se puede probar.

## El modelo de mascotas

| Pieza | Archivo | Responsabilidad |
|---|---|---|
| `PetPack` | `Model/PetPack.swift` | carga y **valida** un paquete. Es la frontera: lo escribe un tercero |
| `PetLibrary` | `Model/PetLibrary.swift` | qué está instalado, cuál está activa, instalar y quitar |
| `PetTheme` | `Model/Mood.swift` | la mascota activa vista desde el dibujo: colores y sprites |
| `Voice` | `Voice/Voice.swift` | frases de la mascota activa: generadas, con respaldo del pack |
| `Registry` | `CLI/Registry.swift` | el índice del marketplace, con cache para funcionar sin red |
| `Scaffold` | `CLI/Scaffold.swift` | lo que produce `mascotuscan new`: un paquete **válido** desde el inicio |

Contrato con los packs, en dos direcciones:

| Lo pone el programa | Lo pone el pack |
|---|---|
| los seis estados | qué color y qué imagen tiene cada uno |
| los marcadores (`{agent}`, `{cmd}`, `{where}`…) | las frases que los usan |
| el contrato del prompt: formato, longitud, sin emojis | la personalidad en prosa |
| cuándo avisar y cuándo callar | nada |

Consecuencia práctica: una regla nueva del contrato aplica a **todas** las
mascotas existentes sin tocarlas.

## Las fuentes de eventos

Dos de las cuatro fuentes originales son `EventSource` (protocolo en
`Controller/EventSource.swift`, contrato en `docs/reference/event-source.md`,
decisión en `docs/adr/0008`): traducen su transporte a `NormalizedEvent` y el
orquestador (`PetController.ingest`) es el único que decide mood y texto. Las
otras dos no encajan en ese contrato (no producen eventos discretos de
agente/comando) y siguen cableadas al controller.

| Fuente | Mecanismo | Qué aporta | Archivo |
|---|---|---|---|
| Eventos de cmux (`EventSource`) | subproceso `cmux events --reconnect`, lectura por líneas | agentes que arrancan, terminan, piden permiso; foco de pane; notificaciones | `Controller/Sources/CmuxEventSource.swift` |
| Shell del usuario (`EventSource`) | hooks zsh que hacen append a `shell.jsonl`; tail cada 0.4 s | comandos largos y exit codes | `Controller/Sources/ShellHookEventSource.swift` |
| RPC de cmux | `cmux rpc <método>` sincrónico en cola de fondo, cada 10 s | títulos de workspace, puertos escuchando | `PetController+Sources.swift` |
| Reloj | timers | narración periódica, barrida de sesiones fantasma | `PetController+Bubbles.swift` |

Por qué un archivo plano para el shell y no un socket o un FIFO: un append nunca
bloquea el prompt del usuario. Un FIFO sin lector bloquea al abrir, y un socket
implica un servidor. El precio de la simplicidad es un poll de 400 ms, que es
gratis.

Agregar una fuente nueva (OpenCode, wmux) es escribir una clase que implemente
`EventSource`, sin tocar `ingest` salvo que traiga un evento que el vocabulario
de `docs/reference/event-source.md` todavía no cubra.

## El marketplace

Un JSON en el repositorio, servido por `raw.github`. Sin servidor, sin cuentas.
Cada entrada **apunta** al paquete con `source` + `path`, así que el arte se queda
en el repositorio de su autor. Ver `docs/marketplace.md`.

`install` acepta tres orígenes y los resuelve en este orden: ruta local con
`pet.json`, URL de git, id del registro. La instalación **valida antes de escribir
y revalida después de copiar**: nunca queda instalado algo que no carga.

## Límites duros del diseño

1. Un pack **no puede inventar un estado**. El vocabulario es del programa.
2. `PetPack.load` es código defensivo: rutas con `..` prohibidas, colores
   validados, sprites que tienen que existir. Es la frontera del sistema.
3. Las frases generadas viven **fuera** del pack (`~/.mascotuscan/voices/<id>.json`):
   actualizar un pack no las borra, y un pack del registro es de solo lectura.
4. El prompt se **compone**: personalidad del pack + contrato del programa.
5. Un renderer desconocido cae al vectorial y **avisa en el log**. Un campo
   obligatorio que falta, en cambio, es fatal: adivinar es peor que rechazar.
6. Un solo camino de layout de texto: `layoutText(...)`. Ver `docs/adr/0003`.
7. Un solo lugar decide tamaño y posición del panel: `PetController.layout()`.
   Burbuja y panel de estado comparten el hueco; el hover manda.
8. La supresión de avisos es por pane exacto, nunca por workspace. Ver `docs/adr/0004`.
9. Ninguna llamada a un modelo en el camino de un aviso. Ver `docs/adr/0002`.
10. `Voice` valida todo lo que entra; un lote incompleto se descarta entero.
11. El respaldo del pack siempre existe: la mascota no puede quedar muda.
12. El estado de agentes se barre a los 10 minutos sin señal.
13. `PetView.hitTest` devuelve nil fuera del cuerpo, y `ContainerView.hitTest`
    devuelve nil en las zonas transparentes, o la ventana se comería los clicks.
14. El panel es `NSPanel` con `canBecomeKey = false`: nunca le roba el teclado a
    la terminal.
15. Todo el estado en disco vive en `~/.mascotuscan`. El repo no escribe ahí.

## Preocupaciones transversales

| Tema | Punto de entrada |
|---|---|
| Trazas y diagnóstico | `plog(...)` en `Support/Paths.swift`; sale a `~/.mascotuscan/pet.log` |
| Ejecutar cmux | `cmuxJSON(...)` (espera respuesta) y `cmuxFire(...)` (dispara y olvida) |
| Rutas en disco | `PetPaths` y `PetLibrary` |
| Textos de cara al usuario | `Voice.phrase(...)` con respaldo del pack |
| Colores y arte | `PetTheme.shared` |
| Verificación visual | `renderShowcase(to:)`, expuesto como `--render` |

## Lo que NO hay, a propósito

- **Sin dependencias externas.** Solo AppKit y Foundation.
- **Sin servidor de marketplace.** Un JSON y `git clone`.
- **Sin bundle .app.** Es un ejecutable que se registra como `.accessory`.
- **Sin ventana de preferencias.** `config.json`, el menú contextual y el CLI.
- **Sin base de datos.** El estado vivo es memoria; lo que persiste son JSON.
- **Sin telemetría.** Nada sale de la máquina salvo la llamada a Claude Code que
  el propio usuario dispara y la descarga del índice del marketplace.
