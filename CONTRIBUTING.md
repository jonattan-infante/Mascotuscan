# Contribuir

## Empezar

```bash
git clone https://github.com/jonattan-infante/mascotuscan.git
cd mascotuscan
make verify      # debe pasar antes de que toques nada
make run         # arranca en primer plano, Ctrl-C para salir
```

## Issues

Un issue nuevo lo diagnostica Claude, pero solo cuando el dueño del repo aprueba
la corrida. Si es un error evidente, el diagnóstico llega con un PR; si cambia
cómo funciona algo, llega el diagnóstico y el PR espera confirmación. Cómo
funciona y qué no puede hacer Claude: `docs/reference/claude-issues.md`.

Para reportar un error, usa la plantilla: pide la versión, los pasos y el log,
que es lo que Claude necesita para diagnosticarlo sin volver a preguntarte.

## Revisión de Claude

Cada PR hacia `main` lo revisa Claude: seguridad, calidad y los contratos de
este repo. Deja un comentario con los hallazgos y el status `claude/revision`,
que **bloquea el merge si encuentra algo crítico o alto**. Un commit nuevo se
revisa de nuevo. Un PR de un fork, o uno que toca `.github/`, las instrucciones
de los agentes o la publicación, espera a que el dueño apruebe la revisión.
Detalle: `docs/reference/claude-revision.md`.

## El gate

`make verify` es el juez: compila, corre los tests de Swift, los de los hooks de
zsh, los del instalador, la integridad del repo y la validación de las mascotas.
Es exactamente lo que corre CI. Si pasa, tu cambio es candidato; si no pasa, no
existe.

En GitHub son cinco jobs, para que se lea de un vistazo qué falló:

| Job | Qué cubre |
|---|---|
| `build y tests` | compila y tests de lógica, en macOS 14 y 15 |
| `shell e instalador` | hooks de zsh, instalación y desinstalación, integridad del repo (incluida la versión) |
| `mascotas y marketplace` | valida cada pet pack y el índice, clonando incluso los de terceros |
| `port de Windows` | tests de lógica pura del port, en un runner de Windows |
| `vista previa` | dibuja los estados y los sube como artefacto; no bloquea |

```bash
make verify
```

Si tocaste algo visual, además:

```bash
make render && open render/todos.png
```

Y **míralo**. La última línea cortada de una burbuja no la detecta ningún test;
se detectó mirando un PNG.

## Qué se espera de un cambio

- **Tests para la lógica pura.** Parseo, validación, formateo: todo eso es
  testeable y va con test. Lo que depende de pantalla se verifica con `make render`.
- **Comentarios que expliquen por qué**, nunca qué. Si el comentario parafrasea la
  línea de abajo, bórralo.
- **Una decisión durable va a un ADR** en `docs/adr/`. Son insert-once: se agregan,
  no se editan.
- **Cero emojis**, en código, mensajes, commits y documentación.
- Español en documentación y comentarios; inglés en identificadores.

## Límites del diseño

Están en [`CLAUDE.md`](CLAUDE.md) como una lista de doce. Los tres que más se
violan por accidente:

1. Nunca `boundingRect` para medir y `draw(with:)` para dibujar en la misma vista.
   Divergen y cortan texto. Usa `layoutText(...)`.
2. Nunca suprimas avisos por workspace, solo por pane exacto.
3. Nunca llames a un modelo en el camino de un aviso.

Cada uno tiene su ADR con la evidencia de por qué.

## El flujo: todo pasa por un PR

`main` está protegido. No se puede empujar directo, ni siquiera el dueño: los
cuatro checks tienen que estar en verde y el cambio tiene que venir de un PR.

```bash
git checkout -b fix/mi-arreglo
# trabajar
git push -u origin fix/mi-arreglo
make pr                          # corre el gate y abre el PR
make merge                       # se mergea solo cuando CI pase
```

No hace falta que nadie apruebe: el PR existe para que CI opine antes de que el
cambio entre, no para pedir permiso. Los merges son squash y la rama se borra
sola.

Si CI falla y necesitas hacer un hotfix urgente, la protección se puede levantar
un momento desde Settings > Branches. Es la salida de emergencia; volver a
activarla después.

## Commits y ramas

Conventional Commits, imperativo y minúsculas:

```
feat(voice): validar marcadores de plantillas
fix(bubble): medir y dibujar con el mismo layout manager
docs(adr): registrar el rechazo del socket bajo launchd
```

Ramas: `<tipo>/<descripcion-corta-en-kebab>`.

## Publicar una versión

La versión es del producto, no de un binario: `VERSION` en la raíz es la fuente
única y macOS y Windows llevan una copia que el gate compara
([`docs/reference/versioning.md`](docs/reference/versioning.md)). Publicar es un
tag, y el tag tiene reglas que CI exige
([`docs/reference/tags.md`](docs/reference/tags.md)): anotado, firmado, con las
notas del CHANGELOG en el mensaje, desde `main`, e inmutable.

```bash
make next-version                # propone X.Y.Z desde los commits (Conventional Commits)
make release-notes               # borrador de la seccion del CHANGELOG; pegar y reescribir
./scripts/bump-version.sh X.Y.Z  # VERSION, Swift y Python
make pr && make merge            # la version entra a main por PR, como todo
git checkout main && git pull
make tag                         # tag anotado y firmado, verificado, empujado; CI crea el release
```

Si el tag no coincide con `VERSION`, no trae notas, no está firmado o no viene de
`main`, `make tag` lo borra en local sin empujar y explica qué falta. Si un tag ya
empujado salió mal, no se borra: se sube la versión y se etiqueta de nuevo.

Para firmar hace falta configurar la llave una vez; está en
[`docs/reference/tags.md`](docs/reference/tags.md#firmar-configuración-de-una-vez).

## Reportar un problema

Incluye siempre:

- salida de `~/.mascotuscan/pet.log` (registra cada aviso, cada supresión y cada
  caída del stream)
- versión de macOS y de cmux
- `cmux capabilities | grep access_mode`

Ese último dato resuelve la mitad de los reportes de "no me llegan avisos": si no
dice `cmuxOnly`, alguien cambió la configuración del socket.
