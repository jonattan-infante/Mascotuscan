// Sprites del usuario, incluidos GIF animados.

import AppKit

final class Sprite {
    let image: NSImage
    let rep: NSBitmapImageRep?
    let frameCount: Int
    let durations: [Double]
    let total: Double

    init?(url: URL) {
        guard let img = NSImage(contentsOf: url) else { return nil }
        image = img

        var animated: NSBitmapImageRep? = nil
        for r in img.representations {
            if let b = r as? NSBitmapImageRep,
               let n = b.value(forProperty: .frameCount) as? Int, n > 1 {
                animated = b
                break
            }
        }
        guard let b = animated,
              let n = b.value(forProperty: .frameCount) as? Int else {
            rep = nil
            frameCount = 1
            durations = []
            total = 0
            return
        }

        var d: [Double] = []
        for i in 0..<n {
            b.setProperty(.currentFrame, withValue: i)
            let raw = (b.value(forProperty: .currentFrameDuration) as? Double) ?? 0.1
            d.append(raw < 0.02 ? 0.1 : raw)   // los GIF con 0 ms se reproducen a 10 fps
        }
        b.setProperty(.currentFrame, withValue: 0)
        rep = b
        frameCount = n
        durations = d
        total = d.reduce(0, +)
    }

    /// Dibuja el cuadro correspondiente al tiempo dado.
    func draw(in rect: CGRect, at time: Double) {
        guard let b = rep, frameCount > 1, total > 0 else {
            image.draw(in: rect)
            return
        }
        var t = time.truncatingRemainder(dividingBy: total)
        var idx = 0
        for (i, d) in durations.enumerated() {
            if t < d { idx = i; break }
            t -= d
            idx = i
        }
        b.setProperty(.currentFrame, withValue: idx)
        b.draw(in: rect)
    }

    var size: CGSize { image.size }
}
