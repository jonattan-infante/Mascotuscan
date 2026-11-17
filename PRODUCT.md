# PRODUCT.md

## Por qué existe

Cuando trabajas con varios agentes de IA en paralelo, pierdes el hilo de quién
está haciendo qué. Los agentes terminan en ventanas que no estás mirando, piden
permiso y se quedan esperando, los builds terminan sin que te enteres. La
información existe, y cada cliente la publica a su manera (cmux en su sidebar y
su Feed, Claude Code en sus hooks), pero ninguna de esas cosas está mirándote a
la cara.

MascoTuscan pone una mascota sobre la pantalla que te lo dice, venga de donde
venga el agente. **Cuál mascota, lo eliges tú.**

## Qué es, en una frase

Una plataforma de mascotas de escritorio para tus agentes de IA: el programa sabe
**cuándo** hablar, y un paquete instalable decide **cómo se ve y cómo habla**.
**cmux es un cliente, no el producto**: cualquier herramienta que emita eventos
de agente puede alimentar a la mascota con un adapter sobre el contrato
`EventSource` (`docs/reference/event-source.md`).

```
   cmux ──────────┐
   Claude Code ───┤                ┌──────────────────────────────────┐
   shell ─────────┼─ EventSource ─►│  mascotuscan                     │
   OpenCode, ... ─┘                │    decide cuándo y de qué avisar │
                                   └───────────────┬──────────────────┘
                                                   │  los seis estados
                                   ┌───────────────▼──────────────────┐
                                   │  pet pack                        │
                                   │    arte, colores, personalidad   │
                                   └──────────────────────────────────┘
                                      astro   gatito   el tuyo   ...
```

## Clientes

Qué cliente llega hoy a la mascota, en cada sistema. Verificado contra el código
el 2026-11-16.

| Cliente | macOS | Windows | Evidencia |
|---|---|---|---|
| cmux | sí: agentes, permisos, notificaciones, saltar al workspace | no | `makeEventSources()` devuelve `[ShellHookEventSource(), cmux]` (`Sources/MascoTuscanKit/Controller/PetController+EventSources.swift:16`) |
| shell (zsh) | sí: comandos largos, fallos, puertos | no | la misma línea; `ShellHookEventSource` lee lo que escribe `shell/pet.zsh` |
| Claude Code nativo | **no** (hipótesis) | sí | macOS: `grep -n -i -E 'claude\|settings\.json\|hooks' install.sh shell/pet.zsh` solo encuentra `claude` en la lista de comandos que `pet.zsh` ignora; ningún instalador registra hooks. Windows: `python install.py` los registra en `~\.claude\settings.json` (`windows/README.md`) |
| OpenCode | no | no | en espera (`EXECUTION-PLAN.md` F8) |
| wmux | no | esqueleto, sin registrar | `docs/reference/event-source.md` |

El hueco de Claude Code nativo en macOS es la feature piloto del equipo de agentes
(`EXECUTION-PLAN.md` F9, `docs/adr/0015`).

## Para quién

Dos públicos con necesidades distintas, y el producto tiene que servir a ambos:

**Quien la usa.** Desarrolladores que trabajan con uno o más agentes de IA, desde
el cliente que sea (ver §Clientes para lo que hoy funciona). El caso que lo
justifica: 3 o más agentes en paralelo. Quiere
instalar en un comando y elegir una mascota que le caiga bien.

**Quien la crea.** Cualquiera con ganas de inventarle carácter a algo. **No hace
falta saber programar**: crear una mascota es escribir un archivo de texto que
describe cómo habla. Si además tiene arte, lo suelta en una carpeta.

Ese segundo público es la razón de ser del marketplace. Si crear una mascota
requiriera Swift, no habría más de una.

## Qué hace

| Necesidad | Cómo la cubre |
|---|---|
| "¿ya terminó?" | avisa en cuanto un agente cierra su turno, con el workspace |
| "¿está esperándome?" | estado de alerta persistente cuando pide permiso o pregunta |
| "¿en qué van?" | panel al pasar el mouse, más narración periódica |
| "¿pasó el build?" | avisa comandos de más de 20 s y cualquier fallo |
| "¿levantó el server?" | avisa puertos que empiezan y dejan de escuchar |
| "llévame ahí" | con cmux, un click salta al workspace del aviso y trae cmux al frente |
| "quiero otra mascota" | `mascotuscan search` y `mascotuscan install <id> --use` |
| "quiero hacer la mía" | `mascotuscan new mi-mascota`, editar un archivo, listo |
| "¿salió una versión nueva?" | la mascota avisa una vez, con su voz; `mascotuscan update` la trae. Igual en Windows |

## Qué NO es

- **No es un panel de control de ningún cliente.** No crea workspaces, sesiones ni
  paneles.
- **No es un monitor del sistema.** No mira CPU, memoria ni red.
- **No es un cliente de IA.** No habla con agentes ni les manda prompts. Solo
  reporta. La única llamada a un modelo es para que una mascota escriba sus frases.
- **No es un juego ni un tamagotchi.** La mascota no tiene hambre, no hay que
  cuidarla y no se muere. Reporta trabajo; el carácter es la envoltura.
- **No es una tienda.** El marketplace es un índice gratuito. No hay pagos, ni
  cuentas, ni ranking, ni destacados.
- **No es una sola app multiplataforma.** Son dos runtimes con el mismo contrato:
  macOS (Swift y AppKit) y Windows (Python y tkinter), cada uno con sus fuentes de
  eventos. Lo que existe en uno solo no es del producto.

## Criterios de éxito

1. **No se apaga.** Si a la semana el usuario lo silencia, el producto falló. Se
   mide en avisos por hora: más de ~6 es ruido.
2. **Cero fallos silenciosos.** Si no puede escuchar a ningún cliente, o no hay mascota
   instalada, lo dice en pantalla. Un asistente mudo que parece funcionar es peor
   que uno ausente.
3. **Crear una mascota toma menos de diez minutos** y no requiere leer código.
   `mascotuscan new` deja un paquete que ya funciona; el usuario solo le da voz.
4. **Un paquete de un tercero no puede romper la app.** Se valida en la frontera:
   rutas que no se escapan, colores bien escritos, sprites que existen.
5. **Se instala en un comando** y no pide cambiar la configuración de seguridad
   de ningún cliente.
6. **No estorba.** No roba el foco del teclado, deja pasar los clicks en sus zonas
   transparentes, y no dispara redibujados cuando no pasa nada.

## Vocabulario

Estos términos se pisan entre cmux, Claude Code y este repo. Aquí valen estas
definiciones:

| Término | Aquí significa | Ojo con |
|---|---|---|
| **mascota** | el personaje que el usuario ve: arte más personalidad | no es el proceso; el proceso es el asistente |
| **cliente** | la herramienta donde corren los agentes y que emite sus eventos: cmux, Claude Code, OpenCode | la mascota no depende de ninguno en particular |
| **fuente** | el adapter que traduce un cliente a `NormalizedEvent` (`EventSource`) | no decide mood ni texto: eso es del orquestador |
| **pet pack / paquete** | la carpeta instalable que define una mascota | ver `docs/reference/pet-pack.md` |
| **marketplace / registro** | el índice JSON de mascotas publicadas | no hay servidor ni tienda |
| **renderer** | cómo se dibuja: `vector:droid` o `sprites` | no es el motor de la app |
| **persona** | `persona.md`: cómo habla la mascota, en prosa | no es un personaje de ficción con dueño |
| **voz** | las plantillas de frases de una mascota | no es audio; no hay sonido |
| **estado / mood** | idle, working, done, error, attention, info | no es el `workspace status` de cmux (todo/working/done) |
| **workspace** | un workspace de cmux: un grupo de paneles con nombre | no es un workspace de VS Code ni un directorio |
| **surface** | una pestaña dentro de un panel de cmux | cmux también dice "tab" |
| **sesión** | una sesión de agente (`session_id` de los hooks) | varias pueden vivir en un workspace |
| **actividad** | lo que el agente hace ahora, derivado de `tool_name` | no es el contenido: `tool_input` viene redactado |
| **tarea** | el texto del prompt que el humano escribió | es por workspace, no por sesión |

## Decisiones de producto ya tomadas

- **El vocabulario de estados es del programa, no de la mascota.** Un pack no
  puede inventar un estado nuevo, porque el orquestador no sabría cuándo usarlo.
  Seis estados son suficientes y mantienen el contrato simple. Ver `docs/adr/0005`.
- **Sin arte de personajes con dueño.** Ni en los packs incluidos ni en el
  marketplace. R2-D2, Pikachu, Clippy y compañía tienen dueño. El renderer
  `vector:droid` existe para que se pueda tener una mascota decente sin arte y sin
  pisar marcas ajenas.
- **La personalidad se describe, no se programa.** `persona.md` es prosa porque el
  público objetivo de la creación no escribe código.
- **Cada mascota trae frases de respaldo.** Así habla desde el primer arranque,
  sin conexión y sin Claude Code. Lo generado es una mejora, no un requisito.
- **El texto es de terminal, no de UI.** Monoespaciado, fondo oscuro, se escribe
  letra por letra. Encaja con lo que el usuario está mirando todo el día.
- **Las mascotas incluidas son dos, no una.** `astro` y `gatito` comparten
  renderer y difieren solo en personalidad y colores: son la demostración de que
  la plataforma es genérica, y el ejemplo a copiar para hacer la propia.
