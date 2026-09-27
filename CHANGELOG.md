# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
Versionado semántico.

## [0.4.0] — 2026-09-27

El producto se llamaba LucyGlow. Ver `docs/adr/0010`.

### Incompatible

- Renombrado a **MascoTuscan**, comando `mascotuscan`. Repositorio de GitHub:
  `Mascotuscan`; la URL vieja redirige.
- Librería Swift `LucyGlowKit` → `MascoTuscanKit`; paquete de Windows
  `lucy_win` → `mascotuscan_win`; hook de Windows `lucy-hook.ps1` →
  `mascotuscan-hook.ps1`.
- Variables de entorno `LUCY_*` → `MASCOTUSCAN_*`. Si pusiste `~/.lucy/bin` en
  tu `PATH`, cámbialo a mano.
- Directorio de estado `~/.lucy` → `~/.mascotuscan`, con migración automática al
  arrancar y al instalar, en macOS y en Windows. También migra un `~/.cmux-pet`
  que haya quedado de antes.
- La primera línea del mensaje de cada tag pasa a ser `mascotuscan X.Y.Z`.
- En Windows, después de `python install.py --update` desde una versión
  anterior, hay que correr `python install.py` una vez más: el actualizador
  viejo no conoce el nombre nuevo del hook.

### Agregado

- En macOS, responder desde la burbuja un permiso o una pregunta de Claude, con
  clics: sí o no para un permiso, una línea por opción para una pregunta. La
  burbuja muestra el contenido real (el comando que pide permiso, las opciones
  de la pregunta), que se le pide a cmux por el id de la solicitud. Ver
  `docs/adr/0009`. Probado contra el RPC de cmux, sin un permiso real todavía
  ⚠️ 2026-09-27.

### Cambiado

- Las fuentes de eventos cumplen un contrato común (`EventSource` y
  `NormalizedEvent`, `docs/reference/event-source.md`), en macOS y en Windows,
  para que agregar una nueva no toque el orquestador. Sin cambio de
  comportamiento.

### Corregido

- Actualizar desde un nombre anterior ya no deja el `source` viejo en
  `~/.zshrc`, que daba un error al abrir cada terminal, ni hooks de Claude Code
  en Windows apuntando a un archivo que ya no existe.
- Si el directorio de estado no se puede migrar, se dice; antes se creaba el
  nuevo vacío y el viejo quedaba huérfano.

## [0.3.0] — 2026-09-17

El producto se llamaba `cmux-pet`, un nombre que prometía una integración con
cmux que ya no es la única: en Windows observa Claude Code directamente. Ver
`docs/adr/0007`.

### Incompatible

- Renombrado a **LucyGlow**, comando `lucy`. Repositorio de GitHub: `lucyglow`.
- Librería Swift `CmuxPetKit` → `LucyGlowKit`; paquete de Windows
  `cmux_pet_win` → `lucy_win`.
- Variables de entorno `CMUX_PET_*` → `LUCY_*`.
- Directorio de estado `~/.cmux-pet` → `~/.lucy`, con migración automática en
  el primer arranque: nada se pierde de una instalación anterior.

## [0.2.2] — 2026-09-17

### Corregido

- `release.yml` fallaba en `check-tag.sh` con "es un tag ligero" para todo tag
  real: GitHub Actions entrega el ref del tag apuntando al commit que señala,
  no al objeto tag anotado, así que `git cat-file -t` lo veía como ligero. Se
  agrega `git fetch --tags --force origin` tras el checkout, antes de
  verificar. Encontrado publicando `v0.2.1`.

## [0.2.1] — 2026-09-17

**No se publicó.** El tag existe en GitHub, anotado y firmado, pero
`release.yml` falló antes de crear el release por el bug de arriba. La versión
efectiva es `0.2.2`; este tag se queda como está, sin borrarse
(`docs/reference/tags.md`).

### Agregado

- Reglas de los tags en `docs/reference/tags.md`, verificadas por
  `scripts/check-tag.sh` antes de empujar y por CI antes de publicar: anotado,
  firmado, con las notas del CHANGELOG en el mensaje, desde `main`, inmutable.
- `make next-version` y `make release-notes`: proponen la versión y el borrador
  de notas a partir de los commits (Conventional Commits).
- Ruleset en GitHub que impide crear, mover o borrar tags `v*` sin el rol de
  administrador.

### Cambiado

- `make tag` firma el tag con SSH y pone las notas del CHANGELOG en el mensaje.

### Documentación

- Las reglas de tags son obligatorias para cualquier agente de IA que trabaje
  en el repositorio, con sección propia en `CLAUDE.md`, no solo una mención.

## [0.2.0] — 2026-09-17

### Agregado

- **La versión es del producto.** `VERSION` en la raíz es la fuente única; el
  binario de macOS y el paquete de Python llevan una copia que
  `scripts/bump-version.sh` mantiene y que el gate de integridad compara.
- **Publicación por tag.** Empujar `vX.Y.Z` crea el GitHub Release con las notas
  de este archivo, tras verificar que tag, `VERSION` y CHANGELOG coinciden.
  `make tag` hace el paso humano desde `main`.
- **La mascota avisa cuando hay una versión nueva**, en macOS y en Windows: una
  consulta al día como máximo, fuera del hilo principal, y un solo aviso por
  versión. Se apaga con `checkUpdates: false`. Estado en `~/.lucy/update.json`.
- Clase de frase `updateAvailable` con marcador `{version}`, en el contrato de
  voz y en las cuatro mascotas incluidas.
- `lucy update` (macOS) reinstala la última versión publicada;
  `lucy update --check` solo compara. En Windows, `python install.py --update`
  mueve el checkout al tag publicado y `python pet.py --version` dice cuál corre.
- El instalador de macOS clona la última versión publicada en vez de `main`;
  `LUCY_VERSION` fija una versión o la rama.
- Comandos `sprite` para ponerle imagen a una mascota (`--dir`, `--clear`) y
  `fork` para sacar una copia editable de una incluida.
- Renderers integrados `vector:ball` y `vector:sage`, además de `vector:droid`;
  `lucy renderers` los lista.
- Mascotas incluidas `cangrejo` y `llama`, con sprites propios.
- Port para Windows en `windows/`: observa Claude Code por sus hooks, reusa los
  mismos packs y el mismo contrato de voz. Sus tests entran a `make verify` y a CI.

### Cambiado

- La sección "Actualizar" del README explica el aviso y cómo actualizar en cada
  plataforma.

## [0.1.0] — 2026-07-31

Primera versión.

### Agregado

- Droide astromecánico vectorial con seis estados distinguibles, dibujado con
  Core Graphics. Sin imágenes ni dependencias.
- Sprites propios del usuario desde `~/.lucy/sprites/`, con GIF animado.
- Avisos estilo terminal: monoespaciados, un párrafo, escritos letra por letra
  con cursor de bloque.
- Voz generada por Claude Code local sin API key, como plantillas validadas, con
  respaldo estático.
- Seguimiento en vivo de agentes: panel al pasar el mouse, narración periódica y
  línea de estado en el menú.
- Cuatro fuentes de eventos: stream de cmux, RPC de cmux, hooks de zsh y reloj.
- Avisos de comandos largos y fallidos, con denylist de comandos interactivos.
- Avisos de puertos que empiezan y dejan de escuchar.
- Click para saltar al workspace del aviso.
- Modo `--render`: escribe un PNG por estado sin abrir ventana, para revisar el
  dibujo desde CI o desde un agente.
- Instalador de un comando y desinstalador que conserva las preferencias.
