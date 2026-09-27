// Los seis estados que toda mascota tiene que poder expresar, y su paleta.
//
// El vocabulario es del sistema, no de la mascota: un pack puede cambiar los
// colores y las imagenes, pero no inventar un estado nuevo. Eso mantiene el
// contrato entre el orquestador y cualquier mascota del marketplace.

import AppKit

public enum Mood: String, CaseIterable {
    case idle, working, done, error, attention, info

    /// Paleta por defecto, la que se usa cuando el pack no declara colores.
    var defaultAccent: NSColor {
        switch self {
        case .idle:      return NSColor(srgbRed: 0.42, green: 0.62, blue: 0.98, alpha: 1)
        case .working:   return NSColor(srgbRed: 0.98, green: 0.72, blue: 0.24, alpha: 1)
        case .done:      return NSColor(srgbRed: 0.30, green: 0.80, blue: 0.50, alpha: 1)
        case .error:     return NSColor(srgbRed: 0.94, green: 0.36, blue: 0.36, alpha: 1)
        case .attention: return NSColor(srgbRed: 0.98, green: 0.55, blue: 0.20, alpha: 1)
        case .info:      return NSColor(srgbRed: 0.55, green: 0.60, blue: 0.98, alpha: 1)
        }
    }

    /// Color del estado, con lo que declare la mascota activa por delante.
    var accent: NSColor {
        PetTheme.shared.accent(for: self) ?? defaultAccent
    }

    /// Cuerpo del renderer vectorial: se deriva del acento para que un pack que
    /// cambia los colores no tenga que declarar tambien los del cuerpo.
    var body: (NSColor, NSColor) {
        switch self {
        case .error, .done, .attention:
            // Un cuerpo tenido del color del estado, oscuro para que el texto
            // blanco siga legible encima.
            let a = accent
            return (a.blended(withFraction: 0.72, of: .black) ?? a,
                    a.blended(withFraction: 0.84, of: .black) ?? a)
        default:
            return (NSColor(srgbRed: 0.20, green: 0.24, blue: 0.34, alpha: 1),
                    NSColor(srgbRed: 0.12, green: 0.15, blue: 0.23, alpha: 1))
        }
    }
}

/// La mascota activa vista desde el dibujo: colores y sprites. Es un punto
/// unico para que las vistas no tengan que cargar el pack cada vez.
public final class PetTheme {
    public static let shared = PetTheme()

    private(set) var pack: PetPack?

    public func activate(_ pack: PetPack?) {
        self.pack = pack
    }

    /// Nombre de la mascota activa, para el menu y los mensajes.
    public var name: String { pack?.name ?? "Mascota" }

    func accent(for mood: Mood) -> NSColor? {
        pack?.accents[mood.rawValue] ?? pack?.accents["default"]
    }

    /// Ruta del sprite del estado, con caida a `default`. nil significa que hay
    /// que dibujar el renderer vectorial.
    func spriteURL(for mood: Mood) -> URL? {
        guard let pack = pack, pack.renderer == .sprites else { return nil }
        return pack.spritePaths[mood.rawValue] ?? pack.spritePaths["default"]
    }
}
