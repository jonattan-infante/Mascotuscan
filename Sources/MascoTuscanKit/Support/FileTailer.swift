// Sigue un archivo de texto y entrega solo las lineas nuevas en cada poll.

import Foundation

/// Arranca al final (no reproduce historial al abrir). Tolera truncado o
/// rotacion comparando tamaño. Sin hilo propio: el caller la llama desde su
/// propio Timer. Puerto de `windows/mascotuscan_win/events.py::Tailer`, mismo
/// contrato en los dos runtimes (docs/reference/event-source.md).
final class FileTailer {
    let url: URL
    private var offset: UInt64 = 0

    init(url: URL) {
        self.url = url
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        offset = (attrs?[.size] as? UInt64) ?? 0
    }

    /// Lineas nuevas desde la ultima lectura, ya separadas por salto de linea.
    func readNewLines() -> [Data] {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64 else { return [] }
        if size == offset { return [] }
        if size < offset { offset = 0 }   // el archivo roto

        guard let fh = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? fh.close() }
        try? fh.seek(toOffset: offset)
        let data = fh.readDataToEndOfFile()
        offset = size

        return data.split(separator: 0x0A).map { Data($0) }
    }
}
