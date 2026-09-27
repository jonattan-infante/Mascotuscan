// Formateo de texto y duraciones para los avisos.

import Foundation

func truncate(_ s: String, _ n: Int) -> String {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.count <= n { return t }
    return String(t.prefix(n - 1)) + "\u{2026}"
}

func humanDuration(_ seconds: Double) -> String {
    if seconds < 1 { return String(format: "%.0f ms", seconds * 1000) }
    if seconds < 60 { return String(format: "%.1f s", seconds) }
    let total = Int(seconds.rounded())
    let m = total / 60, s = total % 60
    if m < 60 { return s == 0 ? "\(m) min" : "\(m) min \(s) s" }
    return "\(m / 60) h \(m % 60) min"
}

func compactDuration(_ seconds: Double) -> String {
    if seconds < 60 { return "\(Int(seconds.rounded())) s" }
    let m = Int(seconds / 60)
    if m < 60 { return "\(m) min" }
    return "\(m / 60) h \(m % 60) min"
}
