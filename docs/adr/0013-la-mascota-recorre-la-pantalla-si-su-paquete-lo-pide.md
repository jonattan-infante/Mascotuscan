# ADR 0013 — La mascota recorre la pantalla si su paquete lo pide

- **Estado:** aceptada
- **Fecha:** 2026-09-27
- **Decide:** si la ventana de la mascota se mueve, cuándo, hasta dónde y quién
  lo decide

## Contexto

Hasta ahora la ventana de la mascota solo se movía si la arrastrabas. El autor
pidió, para una mascota que rueda, que mientras trabaja "se mueva también en la
pantalla de izquierda a derecha", mirando al frente al arrancar y luego girando
la cabeza e inclinándose hacia donde va.

Preguntado explícitamente, decidió cuatro cosas (2026-09-27):

1. Llega **hasta el borde de la pantalla**.
2. De vuelta, **al revés, como un espejo**.
3. Cuando termina el trabajo, **regresa a su lugar**.
4. **Es una implementación de cada mascota**: no todas se mueven.

Lo que ya existía y condiciona el diseño:

- La ventana es un panel con la mascota y la burbuja; todo cuelga de
  `PetController.anchor`, y `layout()` ya coloca la burbuja respecto a él.
- `Sprite.draw(in:at:)` reproduce en bucle con el reloj global: no sabe de
  gestos de una sola vez, como girar la cabeza antes de salir.
- La burbuja puede tener botones para responder un permiso o una pregunta
  (`docs/adr/0009`). A un botón que se mueve no se le puede hacer clic.
- Un pack no puede inventar estados (`docs/adr/0005`): moverse no puede ser un
  séptimo estado.

## Decisión

**Moverse es una capacidad opcional del paquete, no un estado.** `pet.json` gana
un bloque `roam` con `loop` (en bucle mientras avanza), `start` opcional (una
vez, sin moverse, antes de avanzar; al revés es la frenada) y `speed`. El
contrato está en `docs/reference/pet-pack.md`. Sin `roam`, nada cambia.

**El orquestador decide a dónde quiere ir; un modelo puro decide cómo.**
`Model/Roam.swift` (`Roamer`) recibe el tiempo, un objetivo y los bordes, y
devuelve la posición y la fase (`resting`, `starting`, `rolling`, `stopping`).
`PetController+Roam.swift` elige el objetivo y mueve `anchor`; `PetView` dibuja
según la fase. El comportamiento se prueba en `RoamTests` sin abrir pantalla.

Objetivo, en este orden:

| Situación | Objetivo |
|---|---|
| mouse sobre la mascota o sobre su burbuja | `hold`: se detiene donde está |
| algo acaba de terminar (`done`, 3 s) | `hold`: celebra quieta |
| al menos un agente trabajando | `roam`: de borde a borde |
| nada en curso | `home`: vuelve a su lugar |

**Las imágenes miran a la derecha y el programa las espeja.** Es lo que pidió el
autor y le ahorra al autor del pack dibujar dos direcciones.

**Frenar es el arranque al revés**, y entre frenar y volver a arrancar no hay un
cuadro de reposo: en el borde la cabeza vuelve al frente y gira al otro lado sin
parpadeo. Si se interrumpe a medio giro, la frenada empieza desde ese cuadro.

**Al terminar un trabajo celebra quieta.** El autor pidió, en la misma sesión,
que BB-8 saque su flamita cuando un trabajo termina. Eso es la imagen de `done`
de su paquete, y pedía dos cosas del programa: detenerse durante `done` (rodando
no se ve) y que cada imagen empiece en su primer cuadro al aparecer (con el
reloj global, un gesto de una sola vez empezaba a la mitad). Mientras frena, un
estado con imagen propia gana sobre la frenada, para que el gesto empiece
enseguida y dure los 3 s de `done`.

**Su lugar es donde lo dejaste.** Rodar no guarda la posición; arrastrar sí, y
el lugar nuevo es a donde vuelve.

**En movimiento no flota**: va apoyada en el piso (`PetAnimation.hop` en vez de
`lift`). Quieta, se ve como siempre.

## Alternativas descartadas

- **Un estado `moving`.** Viola `docs/adr/0005`: el orquestador tendría que
  saber cuándo usarlo en cada pack, y un pack viejo no lo tendría.
- **Moverse todas las mascotas.** El autor lo quiso por mascota; además una
  mascota vectorial o un sprite que no está pensado para caminar se vería
  deslizándose.
- **Seguir moviéndose con el mouse encima.** Rompe la respuesta desde la
  burbuja de `docs/adr/0009`: con el mouse sobre la mascota o sobre la burbuja
  se detiene al instante (frenar no la desplaza), y ya se le puede hacer clic.
- **Detenerse mientras un agente espera respuesta (`attention`) o mientras hay
  una pregunta con botones.** Fue la primera versión y dejó a la mascota sin
  rodar. Medido el 2026-09-28 en `pet.log`: Claude Code avisa `attention` 60 s
  después de cada turno que queda sin respuesta (`done` 14:40:24, `attention`
  14:41:24; igual en los cinco turnos de esa media hora), y esa sesión sigue en
  `attention` hasta que le vuelves a escribir. Con varias sesiones abiertas,
  siempre había una. Una burbuja con botones tampoco se va sola si respondes
  desde la terminal. El mouse encima cubre lo mismo sin quedarse pegado.
- **Un tramo corto alrededor de su lugar.** Era la recomendación; el autor
  eligió el borde.
- **Una imagen con introducción y bucle en el mismo archivo** (`loopFrom`).
  Dos archivos dicen lo mismo sin un número mágico, y el mismo `start` sirve al
  revés para frenar.

## Consecuencias

- La burbuja se mueve con la mascota, porque `layout()` ya la ancla a `anchor`.
  Cerca del borde izquierdo pasa al lado derecho, igual que antes al arrastrar.
- Mientras hay trabajo, la animación corre a 30 fps aunque el ánimo sea `idle`
  por un instante: el temporizador ya no descansa si la mascota no está quieta.
- Tras dormir la máquina, el primer paso se limita a 0.1 s: sin ese tope,
  aparecería de golpe en el otro extremo.

## Fuera de alcance

- **Windows.** Por `docs/adr/0006` una funcionalidad del producto va en los dos
  runtimes; el port de `windows/` va en un PR aparte, con los mismos casos de
  `RoamTests`. Hasta entonces, en Windows un pack con `roam` se queda en su
  lugar.
- **Renderers vectoriales.** `roam` es de imágenes. Un droide vectorial que
  rueda necesitaría dibujar la dirección, y ninguno lo pide todavía.
## Costo de CPU

Mientras rodaba, la mascota de prueba gastaba mucho más que quieta. `sample`
sobre el proceso: de ~515 muestras activas del hilo principal en 5 s, 226 eran
ImageIO descomprimiendo el cuadro actual (`PNGReadPlugin::DecodeFrameAPNG`):
`NSBitmapImageRep` no guarda cuadros decodificados, y en un PNG animado componer
un cuadro obliga a decodificar los anteriores. Además daba a todos los cuadros
la duración del primero.

`Sprite` pasó a leer con ImageIO: cada cuadro se decodifica una vez, al tamaño
en píxeles en que se dibuja, y conserva su duración. Banco aislado, 300 dibujos
(10 s a 30 fps) al tamaño real en Retina: el bucle de rodar pasa de 4.51 % a
0.23 % de un núcleo. Con la mascota real rodando, el proceso entero gasta 7.2 %
(1.44 s de CPU en 20 s); lo que queda es Core Animation publicando la ventana y
el dibujo, no la imagen. Mover la ventana sin redibujar la burbuja podría bajar
algo más; no se hizo.
