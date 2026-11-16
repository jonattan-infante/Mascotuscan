# Política de seguridad

## Versiones con soporte

Solo la última versión publicada recibe correcciones. Mientras el proyecto esté en
`0.x` no hay ramas de mantenimiento: la corrección sale en la versión siguiente, y
la mascota avisa que hay una nueva.

## Cómo reportar una vulnerabilidad

**No abras un issue público.** Usa el reporte privado de GitHub: pestaña
**Security** > **Report a vulnerability**, o directo en
<https://github.com/jonattan-infante/mascotuscan/security/advisories/new>.

Incluye, si puedes:

- la versión (`mascotuscan --version`) y la plataforma (macOS o Windows, y cuál);
- los pasos para reproducirlo, o el paquete o el issue que lo dispara;
- qué consigue quien lo aprovecha.

Lo mantiene una persona, así que la respuesta es con el mejor esfuerzo: cuenta con
días, no con horas. Recibirás acuse, después la evaluación y, si se confirma, la
versión que lo corrige. Si quieres, el aviso de seguridad te nombra.

## Qué entra

- **Un paquete de mascota** que lea archivos fuera de su carpeta, rompa la app o
  la deje muda. `PetPack.load` es la frontera: un paquete solo aporta texto e
  imágenes y no ejecuta código.
- **El marketplace**: una entrada de `registry.json` que lleve a instalar algo
  distinto de lo que declara.
- **El instalador y los enganches**: `install.sh`, `windows/install.py`, el hook de
  zsh y los hooks de Claude Code.
- **Responder desde la burbuja**: cualquier forma de que un clic apruebe un
  permiso o una respuesta distinta de la que muestra la burbuja.
- **Los workflows de GitHub y el harness de Claude** (issues y revisión de PRs):
  inyección de instrucciones que logre escribir en el repositorio, filtrar un
  secreto o pasar un PR sin revisión.

## Qué no entra

- Fallos de cmux, Claude Code, macOS o Windows: repórtalos a quien los mantiene.
- Lo que un paquete de un tercero dice o muestra, si no aprovecha un fallo del
  programa. Eso lo revisa la curaduría del marketplace (`docs/marketplace.md`).
