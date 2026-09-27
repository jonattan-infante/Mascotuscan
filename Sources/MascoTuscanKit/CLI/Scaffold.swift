// Las plantillas que produce `mascotuscan new`.
//
// Lo que se genera tiene que ser un paquete VALIDO desde el primer segundo: se
// puede instalar y activar sin editar nada. Editar es para darle personalidad, no
// para arreglarlo.

import Foundation

enum Scaffold {
    static func manifest(id: String, name: String, sprites: Bool) -> String {
        let renderer = sprites ? "sprites" : "vector:droid"
        let spritesBlock = sprites
            ? """
              "sprites": {
                "idle": "sprites/idle.png",
                "working": "sprites/working.png",
                "done": "sprites/done.png",
                "error": "sprites/error.png",
                "attention": "sprites/attention.png",
                "info": "sprites/info.png"
              },
            """
            : """
              "sprites": {},
            """

        return """
        {
          "schemaVersion": 1,
          "id": "\(id)",
          "name": "\(name)",
          "version": "0.1.0",
          "author": "tu-usuario",
          "description": "Describe tu mascota en una línea.",
          "license": "MIT",
          "language": "es",
          "renderer": "\(renderer)",
        \(spritesBlock)
          "accent": {
            "idle": "#6B9EFA",
            "working": "#FAB83D",
            "done": "#4CCC80",
            "error": "#F05C5C",
            "attention": "#FA8C33",
            "info": "#8C99FA"
          }
        }
        """
    }

    static func persona(name: String) -> String {
        """
        Eres \(name), una mascota que vive flotando sobre la pantalla de un
        programador y le avisa qué hacen sus agentes de IA y sus comandos.

        <!-- Describe CÓMO habla, no qué dice. Esto se le pasa a Claude Code para
             que escriba las frases, así que sé concreto con el tono. -->

        Hablas en español neutro, en frases cortas.

        Tono: <!-- servicial, sarcástico, entusiasta, seco, formal, cariñoso... -->

        Muletillas o sonidos característicos: <!-- por ejemplo, un maullido, un
        pitido, una interjección que repitas -->

        Lo que nunca haces: <!-- por ejemplo, nunca regañar al usuario, nunca
        sonar como un log de sistema -->
        """
    }

    /// Frases de respaldo genéricas pero válidas: la mascota habla desde el
    /// primer arranque, antes de que Claude Code le escriba las suyas.
    static func phrases(name: String) -> String {
        """
        {
          "greeting": [
            "Aquí estoy, vigilando tu terminal.",
            "\(name) en línea."
          ],
          "agentDone": [
            "{agent} terminó su turno{where}.",
            "Listo: {agent} acabó{where}."
          ],
          "commandDone": [
            "{cmd} terminó en {time}{where}.",
            "{cmd} salió bien, {time}{where}."
          ],
          "commandError": [
            "{cmd} falló con código {code}{where}.",
            "Algo se rompió: {cmd}, código {code}{where}."
          ],
          "attention": [
            "{agent} necesita {what}{where}.",
            "{agent} está esperando: {what}{where}."
          ],
          "working": [
            "{agent} lleva {time}{where} {doing}.",
            "{agent} sigue {doing}, {time}{where}."
          ],
          "portUp": [
            "El puerto {port} está escuchando{where}."
          ],
          "portDown": [
            "El puerto {port} se cerró{where}."
          ],
          "updateAvailable": [
            "Hay una versión nueva de MascoTuscan: {version}. Actualízame cuando puedas."
          ]
        }
        """
    }

    static func spritesReadme() -> String {
        """
        Imágenes de tu mascota, una por estado.

          idle.png        en reposo, nada en curso
          working.png     hay agentes trabajando
          done.png        algo terminó bien
          error.png       algo falló
          attention.png   un agente te necesita
          info.png        novedad sin urgencia
          default.png     comodín para los estados que no tengan archivo propio

        Formatos: gif (se anima solo), png, webp, heic, jpg, tiff, pdf.
        Tamaño sugerido: 150 x 150 px o más, con fondo transparente.

        Declara cada archivo en pet.json, en el objeto "sprites".
        Un estado sin sprite ni default cae al droide vectorial integrado.
        """
    }
}
