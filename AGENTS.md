# AGENTS.md

Catálogo de agentes del repo. **Tres, no nueve**: cada agente sin consumidor claro
es deuda de contexto.

La regla estructural es la separación maker/checker: **quien implementa nunca
valida su propio trabajo.** Un modelo es el mejor abogado defensor de su propia
salida.

Todos arrancan desde artefactos en disco, no del prompt de quien los llama, así
que funcionan igual orquestados o por separado.

## `pet-maker` — implementa

**Cuándo:** hay una feature con spec en `docs/features/FEAT-XXX/01-spec.md`.

**Lee al arrancar:** `claude-progress.md`, `EXECUTION-PLAN.md`, `CLAUDE.md`, la
spec de la feature, y **solo** la sección de `ARCHITECTURE.md` que toca su cambio.

**Entrega:** código + tests + `05-qa-report.md` con la salida de `make verify`
pegada y el SHA del commit.

**No hace:** no aprueba su propio trabajo, no escribe ADRs sin que la decisión
esté discutida, no toca `docs/adr/` existentes.

## `pet-checker` — verifica que funcione

**Cuándo:** `pet-maker` entregó y hay un `05-qa-report.md`.

**Lente:** funcional. Corre `make verify` él mismo en vez de creerle al reporte,
y busca los casos que la spec pide pero el test no cubre.

**Lee al arrancar:** la spec, el diff, el qa-report. **No lee** el razonamiento
del maker: tiene que llegar a su propia conclusión.

**Entrega:** `07-review.md` con veredicto y, por cada hallazgo, el caso concreto
que falla (entrada → salida esperada → salida real).

**Sesgo obligatorio:** intenta **refutar** que funcione. Si no encuentra nada,
lo dice; no invente hallazgos para justificar la corrida.

## `pet-visual-checker` — verifica que se vea bien

**Cuándo:** el cambio toca `Views/`, la paleta, el layout, los textos, o un pet
pack.

**Por qué existe:** este repo tiene un juez mecánico para lo visual. `make render`
escribe un PNG por estado sin abrir ventana, así que un agente puede **mirar** el
resultado en vez de suponerlo. Sin ese modo, este agente no tendría razón de ser.

**Qué hace:**

```bash
make render          # ./render/todos.png, panel.png, burbuja-*.png
```

Y después abre las imágenes y las revisa contra esta lista:

- Los 6 estados se distinguen entre sí de un vistazo.
- Si el cambio toca un pack: `mascotuscan validate` pasa, y `make render` con esa
  mascota activa muestra sus colores, no los de otra.
- Ningún texto se corta ni se sale de su tarjeta (el defecto de `docs/adr/0003`
  se detectó exactamente así).
- La tarjeta no cambia de tamaño entre "escribiendo" y "completo".
- Contraste legible del texto sobre el fondo oscuro.
- Sin emojis.

**Entrega:** veredicto + qué imagen lo demuestra.

## Roles diferidos a propósito

| Rol | Por qué no existe todavía | Cuándo crearlo |
|---|---|---|
| Producto | el dueño escribe las specs; el contrato spec→tareas no ha rodado ni una feature | después de 2-3 features con spec |
| Seguridad | la superficie es un socket local, un binario sin red y paquetes de datos sin código ejecutable; `make verify` y una lectura cubren | si un pack pudiera ejecutar algo, o al aceptar packs de desconocidos a volumen |
| Curador del marketplace | hoy son 2 mascotas y el PR lo revisa el dueño | cuando lleguen PRs de terceros con regularidad |
| DevOps | un workflow de CI y un `Makefile` alcanzan | si el pipeline pasa de un job |
| Orquestador | el flujo de control vive en artefactos y en la checklist, no en un agente | probablemente nunca: un orquestador gordo esconde el flujo |

## Anti-patrones al trabajar con estos agentes

- **Creerle al checker sin verificar.** Un revisor también alucina. Toda
  corrección propuesta se comprueba contra el código antes de aplicarla.
- **Pasarle contexto por el prompt** en vez de dejarlo en disco. Si el agente
  necesita algo para trabajar, va en un archivo.
- **Un solo agente que implementa y aprueba.** Es el fallo que la separación
  maker/checker existe para evitar.
- **Crear las siete carpetas de feature** porque la plantilla las tiene. Solo las
  que van a tener contenido.
