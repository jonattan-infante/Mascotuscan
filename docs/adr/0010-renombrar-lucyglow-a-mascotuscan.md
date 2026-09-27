# ADR 0010 — El producto se renombra de LucyGlow a MascoTuscan

- **Estado:** aceptada
- **Fecha:** 2026-09-27
- **Decide:** cómo se llama el producto, el comando, el paquete de Windows, las
  variables de entorno y el directorio de estado en disco. Reemplaza al nombre
  que fijó `docs/adr/0007`; el resto de ese ADR sigue en pie.

## Contexto

Pedido explícito del autor: cambiarle el nombre al proyecto a `mascotuscan`.
`docs/adr/0007` dejó la regla para esto: renombrar temprano, con migración, cuesta
un PR; hacerlo tarde, con usuarios y un marketplace externo dependiendo de la URL,
no. Hoy hay un solo usuario activo y el marketplace solo lista mascotas de este
mismo repositorio.

## Decisión

Marca `MascoTuscan`, con mayúscula interna como tenía `LucyGlow`. Comando
`mascotuscan`, igual al nombre: el autor lo prefirió a un comando corto aun
costando 11 letras en vez de 4 en cada uso.

Búsqueda de colisiones, 2026-09-27, en la web: `"mascotuscan"` y
`mascotuscan github desktop pet AI agents` no devuelven nada con ese nombre; solo
marcas de "Mascot" sin relación (una empresa de nueces, ropa de trabajo) y
mascotas para agentes con otros nombres (`agentpet`, `openpets`). No se revisaron
registros de marca.

| Qué | Antes | Ahora |
|---|---|---|
| Repositorio de GitHub | `lucyglow` | `mascotuscan` (GitHub redirige la URL vieja) |
| Binario y target ejecutable | `lucy` | `mascotuscan` |
| Librería Swift y sus tests | `LucyGlowKit` | `MascoTuscanKit` |
| Paquete de Windows | `lucy_win` | `mascotuscan_win` |
| Hook de Windows | `lucy-hook.ps1` | `mascotuscan-hook.ps1` |
| Variables de entorno | `LUCY_*` | `MASCOTUSCAN_*` |
| Directorio de estado | `~/.lucy` | `~/.mascotuscan` |
| Primera línea del tag | `lucy X.Y.Z` | `mascotuscan X.Y.Z` |

La migración encadena los dos nombres anteriores: si `~/.mascotuscan` no existe,
se mueve ahí el primero que exista de `~/.lucy` y `~/.cmux-pet`. Si ya existe, no
se toca nada: mezclar dos estados podría pisar el nuevo con el viejo. La hacen los
dos runtimes al arrancar (`PetPaths.migrateLegacyHome`,
`paths.migrate_legacy_home`, con los mismos casos de prueba) y los dos
instaladores.

Lo que `docs/adr/0007` no cubrió y este cambio sí:

- **El enganche del zshrc.** `install.sh` quita el de un nombre anterior
  (`source ~/.lucy/shell/pet.zsh`) y pone el nuevo. Antes quedaba apuntando a un
  directorio ya migrado, y zsh daba un error al abrir cada terminal.
- **Los hooks de Claude Code en Windows.** `install.py` reconoce como propios
  `lucy-hook.ps1` y `cmux-pet-hook.ps1` y los reemplaza. Antes quedaban
  registrados apuntando a un archivo que ya no existe.
- **La mascota vieja se detiene antes de mover su directorio**, en los dos
  instaladores. En Windows no se puede mover con archivos abiertos, y en macOS
  podía volver a crearlo.
- **Una migración fallida se dice.** Antes se ignoraba en silencio y el
  directorio nuevo se creaba vacío, dejando el viejo huérfano para siempre.

## Qué no se renombró

Los ADR 0001 a 0009 y las secciones publicadas del `CHANGELOG.md` son registro de
lo que pasó con el nombre de entonces, y los ADR son insert-once. Tampoco la
evidencia pegada en `claude-progress.md` y `EXECUTION-PLAN.md`: son salidas
reales de comandos, y cambiarles el nombre las volvería falsas. Los releases ya
publicados conservan sus assets `lucy-X.Y.Z-macos-arm64.tar.gz`.

## Consecuencias

- **A favor:** la migración y el reemplazo de enganches hacen que actualizar
  desde LucyGlow no pierda configuración, mascotas ni frases, en macOS ni en
  Windows, y no deje nada apuntando a rutas viejas.
- **En contra:** rompe todo script, alias o `PATH` que apunte a `lucy`,
  `~/.lucy/bin` o las variables `LUCY_*`. No se deja compatibilidad hacia atrás,
  igual que en `docs/adr/0007`.
- **En contra:** en Windows, `python install.py --update` desde una versión
  anterior corre con el código viejo, que vuelve a registrar `lucy-hook.ps1`.
  Hace falta un `python install.py` después para que queden los hooks nuevos.
- **Orden obligatorio:** el repositorio se renombra en GitHub antes de mergear,
  porque el código nuevo apunta a `jonattan-infante/mascotuscan`. Después del
  merge hay que publicar una versión pronto: el instalador de `main` instala el
  último release, y mientras ese release sea anterior al cambio compila un
  binario `lucy` que el instalador nuevo no encuentra.
