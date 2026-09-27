<!--
Si tu PR agrega una mascota al marketplace, usa la primera sección y borra el resto.
Para cualquier otro cambio, usa la segunda y borra la primera.
-->

## Una mascota nueva en el marketplace

- **id:**
- **Repositorio donde vive:**
- **Licencia del arte:**

Antes de abrir el PR:

- [ ] `mascotuscan validate ./mi-mascota` pasa sin fallas
- [ ] La instalé y la usé un rato: `mascotuscan install ./mi-mascota --use`
- [ ] El `source` del índice es público y se clona sin credenciales
- [ ] La `version` del índice coincide con la del `pet.json`
- [ ] El arte es mío o tengo permiso, y la licencia declarada lo refleja
- [ ] **No es un personaje con dueño** (R2-D2, Pikachu, Clippy y compañía tienen marca registrada)
- [ ] Solo toqué `registry.json`

El job `mascotas y marketplace` clona tu repositorio y valida el paquete. Si
falla, el mensaje dice qué arreglar.

---

## Otro cambio

**Qué cambia y por qué:**

**Cómo lo verificaste:**

```
$ make verify
<pega la salida>
```

- [ ] `make verify` en verde
- [ ] Si toqué algo visual: `make render` y **miré** los PNG
- [ ] Si toqué el formato de paquete: actualicé `docs/reference/pet-pack.md`
- [ ] Si es una decisión durable: hay un ADR nuevo en `docs/adr/`
- [ ] Sin emojis
