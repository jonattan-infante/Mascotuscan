# El marketplace de mascotas

Un índice de mascotas que cualquiera puede instalar con un comando, sin servidor
y sin cuenta.

```bash
mascotuscan search              # ver qué hay
mascotuscan install gatito --use
```

## Cómo funciona

El marketplace es **un archivo JSON en este repositorio**, servido por
`raw.githubusercontent.com`. No hay backend, no hay base de datos, no hay nada
que se caiga ni que cueste dinero mantener.

```
registry.json  ──raw.github──►  mascotuscan search
                                mascotuscan install <id>
                                               │
                                               └─► git clone del repo del autor
                                                   └─► copia a ~/.mascotuscan/pets/<id>/
```

Cada entrada del índice **apunta** al paquete; no lo contiene:

```json
{
  "id": "gatito",
  "name": "Gatito",
  "description": "Un gato de terminal: le da igual tu build, pero te avisa.",
  "author": "jonattan-infante",
  "version": "1.0.0",
  "language": "es",
  "renderer": "vector:droid",
  "source": "https://github.com/jonattan-infante/mascotuscan.git",
  "path": "pets/gatito",
  "tags": ["gato", "vector", "espanol"]
}
```

`source` es cualquier repositorio git y `path` la subcarpeta donde vive el
paquete. Consecuencia importante: **el arte y las frases se quedan en el
repositorio de su autor**. Este repo solo guarda un puntero, así que nadie cede
el control de su trabajo ni tiene que pedir permiso para actualizarlo.

## Publicar una mascota

1. Crea el paquete y valídalo:

   ```bash
   mascotuscan new mi-mascota
   # edita persona.md, y las imágenes si usas sprites
   mascotuscan validate ./mi-mascota
   mascotuscan install ./mi-mascota --use
   mascotuscan voice mi-mascota
   ```

2. Súbelo a un repositorio público tuyo. Puede ser un repo dedicado, con el
   `pet.json` en la raíz, o una carpeta dentro de un repo que ya tengas.

3. Abre un PR a este repositorio que agregue **una entrada** a `registry.json`.
   Nada más: no toques ningún otro archivo.

4. Al mergearse, tu mascota está disponible para todos con
   `mascotuscan install <tu-id>`.

## Qué se revisa en el PR

No es una curaduría de gusto. Se revisa que funcione y que no haga daño:

| Se revisa | Por qué |
|---|---|
| `mascotuscan validate` pasa sobre el paquete | una mascota que no carga es una mala primera experiencia |
| El `id` no está tomado | los ids son únicos en el índice |
| `source` es público y clonable sin credenciales | si no, el install falla para todos |
| El `license` declarado es coherente con el arte | ver abajo |
| Cero emojis, y el texto no es ofensivo | el mismo estándar que el resto del repo |
| La `description` describe la mascota | no es un espacio publicitario |

Lo que **no** se revisa: si la personalidad nos gusta, si el arte es bonito, o si
el idioma es español. Una mascota en portugués con estética de los noventa es
perfectamente bienvenida.

## Derechos del arte

Esto es lo único que puede meter en problemas al proyecto y a ti.

- **No subas arte de personajes con dueño.** R2-D2, Pikachu, Clippy, Hello Kitty
  y compañía son marcas registradas. Un pack con ese arte se rechaza, y si se
  cuela, se quita del índice cuando se detecte.
- **Declara la licencia real** en `license`. Si el arte es tuyo, lo más simple es
  `MIT` o `CC-BY-4.0`. Si es de un tercero con permiso, ponlo y enlaza la fuente
  en el `description` o en un `LICENSE` dentro del paquete.
- El renderer `vector:droid` no tiene este problema: es el dibujo integrado del
  proyecto, y personalizarlo con tus colores no involucra arte de nadie.

## Actualizar tu mascota

Sube el cambio a tu repositorio, y en el PR al índice sube `version`. El usuario
reinstala con:

```bash
mascotuscan install mi-mascota --force
```

Sus frases generadas **no se pierden**: viven en `~/.mascotuscan/voices/<id>.json`,
fuera del paquete, precisamente para que una actualización no las borre.

## Un índice propio

Para una empresa o para probar, se puede apuntar a otro índice:

```bash
export MASCOTUSCAN_REGISTRY=https://ejemplo.interno/mascotas.json
mascotuscan search
```

El formato es el mismo. También se puede saltar el índice por completo:

```bash
mascotuscan install https://github.com/alguien/su-mascota.git
mascotuscan install ./una/carpeta/local
```

## Sin red

`search` guarda una copia del índice en `~/.mascotuscan/registry-cache.json` y la usa
cuando no hay conexión, avisando en el log. `list`, `use` e `install` desde ruta
local nunca necesitan red.
