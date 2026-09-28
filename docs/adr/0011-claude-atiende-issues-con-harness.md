# ADR 0011 — Claude atiende issues dentro de un harness con reglas fijas

- **Estado:** aceptada
- **Fecha:** 2026-09-27
- **Decide:** cómo Claude evalúa y arregla issues del repositorio sin escribir en
  él y sin exponer secretos

## Contexto

Pedido del autor, con cuatro condiciones:

1. Que Claude **primero evalúe** el problema.
2. Si es un error que requiere cambiar estructuralmente una funcionalidad, que
   el artefacto sea **el diagnóstico** y que pida confirmación.
3. Si es un error evidente, que **abra el PR**.
4. Que se pueda **auditar** lo que hizo y que **en ningún caso exponga variables
   de entorno**.

Además, cada corrida tiene que **esperar aprobación** antes de empezar, y usar la
suscripción de Claude del autor (`claude setup-token`), no una API key.

Hechos verificados en la documentación de `anthropics/claude-code-action@v1`
(`action.yml` y `docs/security.md`, leídos el 2026-09-27):

- la action solo corre si quien dispara el evento tiene escritura en el repo,
  salvo con `allowed_non_write_users`, que exige pasar el token del workflow;
- `--json-schema` en `claude_args` devuelve la respuesta validada en
  `structured_output`, y `execution_file` guarda la conversación completa;
- el token de la app de Claude se revoca al terminar la action, así que un paso
  posterior no puede usarlo para publicar;
- los artefactos y logs de un repo público los puede leer cualquiera.

## Decisión

Un workflow de cinco jobs (`docs/reference/claude-issues.md`) en el que Claude
solo produce **datos**: un diagnóstico JSON y ediciones en el workspace. Todo lo
demás lo hace un script con reglas fijas y tests (`scripts/issue-harness.py`):

- **Evaluar primero:** el job `evaluar` corre con solo lectura, y la ruta la
  decide `decidir_ruta` a partir de lo que Claude declaró. Solo puede bajar un
  `evidente` a `confirmar`.
- **Estructural → diagnóstico y confirmación:** la ruta `confirmar` publica el
  diagnóstico y deja el job `implementar` esperando la aprobación del
  environment `claude`. Aprobarlo es la confirmación.
- **Evidente → PR:** la ruta `corregir` corre `implementar` en el environment
  `claude-auto`, sin revisores, y el PR se abre si pasan la guardia y los tests.
- **Auditable:** el diagnóstico, el parche, la guardia, los logs de Claude y de
  los tests quedan como artefactos del run por 90 días; las aprobaciones quedan
  en el historial del environment.
- **Sin exponer secretos:** Claude no tiene `Bash` ni red y tiene negada la
  lectura de `/proc`, `/etc`, `/tmp` y `.git/`. Su token solo existe en dos
  environments. El código que escribe corre en un job sin secretos. Todo lo que
  sale se escanea antes (valor exacto de los tokens y formas conocidas de
  credenciales), y si algo aparece no se publica nada.

## Alternativas descartadas

- **`@claude` en modo tag con la GitHub App.** Es la configuración por defecto de
  la action: Claude comenta y hace commits él mismo. Contradice la condición 4:
  la decisión de publicar quedaría en manos del modelo, y dejaría de ser un
  código que se puede auditar.
- **Que Claude haga el commit y el push.** Obligaría a darle `Bash` o las
  herramientas de GitHub con escritura. El parche se publicaría antes de que
  una regla fija lo revise.
- **Un token personal (PAT) para que el PR dispare CI.** Es un secreto estático
  más que proteger, y la documentación de la action lo desaconseja junto con
  `allowed_non_write_users`. En su lugar, `publicar` pide CI con
  `workflow_dispatch`, que el token del workflow sí puede disparar.
- **Un solo environment con aprobación para todo.** El error evidente pediría una
  segunda aprobación, en contra de la condición 3. `claude-auto` solo se alcanza
  desde un `evaluar` ya aprobado que eligió `corregir`.

## Consecuencias

- **A favor:** que se abra o no un PR lo decide código con 43 tests, no el
  comportamiento del modelo. Un issue hostil puede engañar a Claude, pero no
  saltarse la guardia ni el escaneo.
- **A favor:** todo corre en `ubuntu-latest`, barato. `make verify` completo, con
  Swift en macOS, corre en CI sobre el PR como en cualquier otro.
- **En contra:** Claude no puede correr tests mientras trabaja. Un arreglo que no
  compila se descubre en `probar` o en CI, no antes.
- **En contra:** hay que crear dos environments con el mismo secreto y activar
  que Actions pueda abrir PRs (`docs/reference/claude-issues.md`, Configuración).
- **Regla derivada:** el harness nunca se modifica desde un issue. Sus archivos
  están en la lista de prohibidos de la guardia y de `settings.json`, y un test
  comprueba que las dos listas coinciden.
