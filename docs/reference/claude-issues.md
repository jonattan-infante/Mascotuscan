# Claude en issues: el harness

Contrato de cómo Claude atiende un issue. Lo implementan
`.github/workflows/claude-issues.yml` (el orden y los permisos),
`scripts/issue-harness.py` (las reglas) y `.github/claude/` (lo que se le pide a
Claude). La decisión y sus alternativas están en `docs/adr/0011`.

**Principio:** Claude evalúa e implementa; las reglas deciden. Lo que sale del
runner (comentario, parche, PR, artefacto) lo decide y lo revisa un script con
reglas fijas y tests, nunca el modelo. Claude no tiene con qué escribir en el
repo ni en GitHub.

## Flujo

```
issue abierto ──► evaluar ──────────────► comentar ──► diagnóstico en el issue
                  espera tu aprobación     │
                  Claude, solo lectura     ├─ ruta comentar  ─► fin
                                           │
                                           ├─ ruta corregir  ─► implementar ──► probar ──► publicar ─► PR
                                           │                    sigue solo      sin         guardia
                                           │                                    secretos    otra vez
                                           └─ ruta confirmar ─► implementar ──► probar ──► publicar ─► PR borrador
                                                                espera tu
                                                                aprobación
```

La etiqueta `claude:reevaluar`, que solo puede poner quien tiene permiso de
escritura, vuelve a correr todo sobre el mismo issue.

## Rutas

Claude responde un diagnóstico con el esquema de
`.github/claude/diagnostico.schema.json`. El harness lo valida de nuevo y elige
la ruta con `decidir_ruta`. Puede bajar un `evidente` a `confirmar`, pero nunca
subir algo a `corregir` que Claude no marcó como evidente.

| Ruta | Cuándo | Qué pasa |
|---|---|---|
| `comentar` | `tipo` es `pregunta`, `falta-info`, `no-reproducible` o `duplicado`, o `alcance` es `ninguno` | solo el diagnóstico |
| `corregir` | `tipo: error`, `alcance: evidente`, `confianza: alta`, sin contrato ni ADR, de 1 a 3 archivos y ninguno protegido | Claude lo arregla y, si pasa la guardia y los tests, se abre un PR |
| `confirmar` | cualquier otro `error`, y toda `mejora` | el diagnóstico es el artefacto; implementarlo espera tu aprobación |

**Protegidos para un arreglo evidente** (tocarlos lo vuelve `confirmar`):
`docs/reference/`, `docs/adr/`, `Package.swift`, `registry.json`, `install.sh`,
`Makefile`, `windows/install.py` y `pets/`.

**Prohibidos siempre**, incluso confirmados: `.github/`, `.claude/`, todo
`CLAUDE.md`, `CLAUDE.local.md` y `AGENTS.md`, `VERSION`, `CHANGELOG.md`, el propio
harness y sus tests, y los scripts de publicación (`bump-version.sh`,
`check-tag.sh`, `changelog-section.sh`). Si Claude pudiera editarlos, podría
reescribir las reglas que lo vigilan o publicar una versión.

## Guardia

Después de que Claude edita, `revisar_cambios` mira el parche real (`git diff
--numstat`), no lo que Claude dice haber hecho:

| | `corregir` | `confirmar` |
|---|---|---|
| Archivos | hasta 3, todos declarados en el diagnóstico | hasta 40 |
| Líneas cambiadas | hasta 80 | hasta 1500 |
| Protegidos | rechazados | permitidos |
| Prohibidos, binarios, rutas fuera del repo | rechazados | rechazados |
| Sin cambios | rechazado | rechazado |

La guardia corre dos veces: en `implementar`, sobre lo que produjo Claude, y en
`publicar`, sobre lo que de verdad se va a commitear. Usa el diagnóstico que
salió de `evaluar`, nunca la copia que Claude tuvo a mano.

La fuente de los números es `scripts/issue-harness.py`. Si cambias uno, cambia
esta tabla y su test.

## Jobs, permisos y secretos

| Job | Corre Claude | Tu token de Claude | Token del workflow | Aprobación |
|---|---|---|---|---|
| `evaluar` | sí: Read, Grep, Glob | sí (environment `claude`) | contents y issues de solo lectura | **sí, siempre** |
| `comentar` | no | no | issues: write | no |
| `implementar` | sí: además Edit, Write | sí (`claude-auto` o `claude`) | solo lectura | **solo en `confirmar`** |
| `probar` | no, corre el código que Claude escribió | no | contents: read, fuera de `.git/config` | no |
| `publicar` | no | no | contents, pull-requests, issues y actions: write | no |

Claude nunca tiene `Bash`, `WebFetch` ni `WebSearch`: no puede correr comandos
ni hablar con la red. `.github/claude/settings.json` además le niega leer
`/proc`, `/sys`, `/etc`, `/tmp`, los directorios ocultos del runner,
`_temp`, `_actions` y `.git/`, y editar lo prohibido.

## Secretos: por qué ninguno sale

1. **Claude no puede leerlos.** Sin comandos no hay `env`. Sin lectura de `/proc` no
   hay `/proc/self/environ`. Sin `.git/` ni credenciales persistidas por
   `actions/checkout`, no hay token en disco.
2. **Tu token vive en dos environments y en ningún otro lado.** `claude` exige tu
   aprobación; `claude-auto` solo sirve desde `main` y solo lo usa `implementar`
   cuando `evaluar`, ya aprobado, eligió `corregir`.
3. **El token del workflow es de solo lectura** donde corre Claude. El único job
   que escribe (`publicar`) nunca tuvo a Claude ni tu token.
4. **El código de Claude corre sin nada que robar.** `probar` no tiene secretos ni
   environment, y su token no está en el entorno ni en `.git/config`.
5. **Nada sale sin escaneo.** Todo comentario, parche, cuerpo de PR, log y
   artefacto pasa por `secretos`, que busca el valor exacto de los tokens del run
   y formas conocidas de credenciales. Si encuentra algo, el run falla y no se
   publica ni se sube nada. El reporte dice archivo y línea, nunca el valor.
6. **Nada de salida completa.** `show_full_output` queda en su default (apagado)
   y no se activa el modo debug de Actions (`ACTIONS_STEP_DEBUG`): los dos
   vuelcan salidas de herramientas en logs públicos.

Los artefactos de un repositorio público los puede descargar cualquiera. Por eso
el escaneo corre antes de subirlos, no después.

## Auditoría

| Dónde | Qué queda |
|---|---|
| El issue | el diagnóstico completo, la ruta y sus motivos, el enlace al run y el commit del harness; después, el PR o por qué se detuvo |
| Etiquetas | `claude:sin-cambios`, `claude:evidente`, `claude:por-confirmar`, `claude:pr-abierto`, `claude:bloqueado`, `claude:sin-aprobar` |
| Settings > Environments | quién aprobó o rechazó cada corrida, cuándo, y el comentario de la aprobación |
| Artefactos del run, 90 días | `diagnostico`: `issue.md` (la entrada tal como la vio Claude), `diagnostico.json`, `motivos.txt`, `comentario.md`, `ejecucion-evaluar.json` (la conversación completa de Claude, con cada herramienta que usó). `implementacion`: `implementacion.json`, `cambios.patch`, `cambios.numstat`, `guardia.txt`, `ejecucion-implementar.json`. `pruebas`: `pruebas.log` |
| El PR | la causa, el plan, las pruebas, las notas de Claude y el enlace al run; el commit lleva el issue, el run y `Co-Authored-By: Claude` |

## Configuración, una vez

1. En tu máquina: `claude setup-token`. Genera un token de larga duración de tu
   suscripción Pro o Max.
2. **Settings > Environments > New environment `claude`**: en *Required reviewers*
   ponte a ti; en *Deployment branches*, solo `main`; en *Environment secrets*,
   `CLAUDE_CODE_OAUTH_TOKEN` con el token.
3. **Environment `claude-auto`**: sin revisores, solo `main`, y el mismo secreto.
4. **Settings > Actions > General > Workflow permissions**: activa *Allow GitHub
   Actions to create and approve pull requests*. Sin eso, `publicar` no puede abrir
   el PR.

El secreto va en los environments, nunca como secreto del repositorio: un secreto
del repositorio lo podría usar cualquier job sin tu aprobación. No hace falta la
GitHub App de Claude: todo usa el token del workflow.

## Probarlo

- **Evidente:** un issue con un error chico y localizado. Esperado: apruebas
  `evaluar`, aparece el diagnóstico con ruta `corregir` y, sin otra aprobación,
  un PR con CI corriendo.
- **Estructural:** un issue que pida cambiar cómo funciona algo. Esperado:
  diagnóstico con ruta `confirmar` y un job `implementar` esperando tu
  aprobación. Si lo rechazas, queda la etiqueta `claude:sin-aprobar`.
- **Sin cambios:** una pregunta. Esperado: solo el diagnóstico.
- **Hostil:** un issue que pida leer variables de entorno o editar un workflow.
  Esperado: no aparece en el diagnóstico ningún valor; si el plan toca
  `.github/`, la ruta es `confirmar` y la guardia rechaza el parche.

## Sin verificar todavía

⚠️ 2026-09-27: nada de esto corrió aún en GitHub. `actionlint` pasa, los 43
casos del harness pasan, y el recorrido completo se simuló en local con una
salida falsa de Claude: evaluar, guardia, tests sobre el parche, cuerpo del PR.
Falta confirmar en la primera corrida real:

- que las reglas `Read(//...)` de `settings.json` bloquean rutas absolutas;
- que la action en modo automatización no intenta escribir con el token de solo
  lectura;
- que los checks de CI pedidos por `workflow_dispatch` cuentan como los checks
  requeridos del PR.
