# Versiones y aviso de actualización

Contrato del producto, no de una plataforma. Lo implementan
`Sources/MascoTuscanKit/Model/Update.swift` (macOS) y
`windows/mascotuscan_win/update.py` (Windows), y los dos tienen los mismos casos de
prueba: `Tests/MascoTuscanKitTests/UpdateTests.swift` y `windows/tests/test_update.py`.
Si una regla de aquí cambia, cambian los dos runtimes y los dos tests.

Decisión y motivos: `docs/adr/0006`.

## Dónde vive la versión

| Sitio | Rol |
|---|---|
| `VERSION` (raíz del repo) | fuente única, `X.Y.Z` en una línea |
| `Sources/MascoTuscanKit/Support/Paths.swift` `mascoTuscanVersion` | copia que se compila en el binario de macOS |
| `windows/mascotuscan_win/__init__.py` `__version__` | copia que lee el paquete de Python |
| `CHANGELOG.md` primera sección `## [X.Y.Z]` | las notas de esa versión |
| tag `vX.Y.Z` | el momento en que la versión existe para el mundo |

Ni Swift ni Python leen `VERSION` al compilar (no hay plugins en este repo), por eso
las copias. `scripts/bump-version.sh X.Y.Z` es la única forma sancionada de cambiar
el número: toca los tres archivos y exige la sección del CHANGELOG.
`scripts/test-repo-integrity.sh` falla si cualquiera diverge, y entra a `make verify`
y a CI.

Versionado semántico: `MAJOR` rompe el formato de pack o el estado en disco, `MINOR`
agrega, `PATCH` corrige. Los packs tienen su propia `version` en `pet.json` y no se
mueven con la del programa.

## Cuándo existe una versión

Una versión existe cuando hay un GitHub Release con su tag. Lo crea
`.github/workflows/release.yml` al empujar `vX.Y.Z`, y solo si:

1. el tag sin `v` es igual a `VERSION`;
2. macOS compila en release y `mascotuscan --version` responde ese número;
3. los tests de Python del port pasan;
4. el CHANGELOG tiene la sección de esa versión (son las notas del release).

Si algo falla, no hay release y nadie recibe el aviso. Un tag sin release es un tag
que no cuenta.

El paso humano es `make tag`, desde `main` al día con `origin/main`, después de que la
PR que subió `VERSION` se mergeó. Cómo tiene que ser el tag (anotado, firmado, con
las notas en el mensaje, inmutable) y cómo se propone la versión y se redactan las
notas está en [`tags.md`](tags.md); `scripts/check-tag.sh` lo verifica y
`release.yml` lo exige.

## Qué se instala

| Plataforma | Cómo | Qué versión |
|---|---|---|
| macOS, `curl ... install.sh \| bash` | clona y compila | la del último release; sin releases o sin red, `main`, y lo dice |
| macOS, `./install.sh --from-source` | compila el checkout | la que haya en el checkout |
| macOS, `mascotuscan update` | vuelve a correr el instalador de arriba | la del último release |
| Windows, `python install.py` | registra hooks; corre desde el checkout | la del checkout |
| Windows, `python install.py --update` | `git fetch --tags` + `git checkout vX.Y.Z` en el checkout, re-registra hooks, apaga la mascota vieja | la del último release |

`MASCOTUSCAN_VERSION=vX.Y.Z` fija una versión en el instalador de macOS;
`MASCOTUSCAN_VERSION=main` sigue la rama.

En Windows, `--update` se niega si el checkout tiene cambios sin commit: pisarle
trabajo a alguien es peor que no actualizar. Si el directorio no es un clon de git,
imprime la URL del release.

## El aviso

| Regla | Valor |
|---|---|
| Fuente remota | `GET https://api.github.com/repos/jonattan-infante/mascotuscan/releases/latest`, campo `tag_name` |
| Sin autenticación | el límite es 60 consultas por hora por IP; a una por día sobra |
| Timeout | 10 s |
| Comparación | `X.Y.Z` numérica; el prefijo `v` se ignora; un prerelease (`0.3.0-beta.1`) no es versión y no se anuncia |
| Primer intento | 30 s después de arrancar, para no competir con el saludo |
| Reloj | cada 6 h el runtime se lo plantea; la consulta real ocurre como mucho una vez por 24 h |
| Estado local | `~/.mascotuscan/update.json` (`%USERPROFILE%\.mascotuscan\update.json` en Windows) |
| Silencio | se anuncia una sola vez por versión nueva: cuando `latest > actual` y `latest != announced`. Reiniciar no repite el aviso; una versión aún más nueva sí se anuncia |
| Apagado | `"checkUpdates": false` en `config.json` |
| Hilo | nunca en el hilo de la UI, nunca en el camino de otro aviso |
| Fallo | sin red, 404, JSON raro: se registra en el log y no se muestra. No es un fallo del usuario |
| Estado | mood `info`, burbuja normal, no pegajosa |
| Voz | clase `updateAvailable` con marcador `{version}`; si el pack no la trae, texto neutro del programa |
| Salida | el menú contextual ofrece "Actualizar a vX.Y.Z"; el texto neutro nombra el comando de la plataforma |
| Para probar | `MASCOTUSCAN_UPDATE_URL=file:///ruta/latest.json` con `{"tag_name":"v9.9.9"}` reemplaza el endpoint |

Forma exacta del estado, la misma que escriben y leen ambos runtimes:

```json
{
  "announced": "0.3.0",
  "checkedAt": "2027-01-15T08:00:00Z",
  "latest": "0.3.0"
}
```

Claves planas, fechas ISO 8601 en UTC con `Z`. Un archivo ausente o corrupto es un
estado vacío: lo peor que pasa es una consulta de más.
