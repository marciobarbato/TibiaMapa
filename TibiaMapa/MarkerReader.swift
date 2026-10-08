import Foundation

struct MapMarker: Identifiable {
    let id: Int
    let x: UInt64
    let y: UInt64
    let z: UInt64
    let icon: UInt64
    let text: String
    let source: String
}

/// Read-only protobuf wire decoder. Unknown fields are skipped, never rewritten.
enum MarkerReader {
    struct Field {
        let number: UInt64
        let integer: UInt64?
        let bytes: Data?
    }
    static func fields(_ data: Data) throws -> [Field] {
        let bytes = Array(data)
        var cursor = 0
        func varint() throws -> UInt64 {
            var result: UInt64 = 0
            for i in 0..<10 {
                guard cursor < bytes.count else { throw MapFailure("Arquivo de marcações truncado.") }
                let byte = bytes[cursor]; cursor += 1
                guard i < 9 || byte <= 1 else { throw MapFailure("Número inválido no arquivo de marcações.") }
                result |= UInt64(byte & 127) << (i * 7)
                if byte & 128 == 0 { return result }
            }
            throw MapFailure("Número inválido no arquivo de marcações.")
        }
        var output: [Field] = []
        while cursor < bytes.count {
            let key = try varint()
            let number = key >> 3
            guard number > 0 else { throw MapFailure("Formato de marcações não reconhecido.") }
            switch key & 7 {
            case 0: output.append(Field(number: number, integer: try varint(), bytes: nil))
            case 1, 5:
                let length = key & 7 == 1 ? 8 : 4
                guard length <= bytes.count - cursor else { throw MapFailure("Arquivo de marcações truncado.") }
                cursor += length
            case 2:
                let length = try varint()
                guard length <= UInt64(bytes.count - cursor) else { throw MapFailure("Arquivo de marcações truncado.") }
                output.append(Field(number: number, integer: nil, bytes: Data(bytes[cursor..<(cursor + Int(length))])))
                cursor += Int(length)
            default: throw MapFailure("Versão do arquivo de marcações não suportada.")
            }
        }
        return output
    }
    static func read(_ data: Data, source: String) throws -> [MapMarker] {
        guard data.count <= 20 * 1024 * 1024 else { throw MapFailure("Arquivo de marcações muito grande.") }
        var markers: [MapMarker] = []
        for field in try fields(data) where field.number == 1 {
            guard let bytes = field.bytes else { throw MapFailure("Registro de marcação inválido.") }
            let record = try fields(bytes)
            guard let position = record.last(where: { $0.number == 1 })?.bytes else { throw MapFailure("Marcação sem coordenadas.") }
            let coordinate = try fields(position)
            func value(_ n: UInt64) -> UInt64 { coordinate.last(where: { $0.number == n })?.integer ?? 0 }
            let textData = record.last(where: { $0.number == 3 })?.bytes ?? Data()
            guard let text = String(data: textData, encoding: .utf8), value(3) <= 15 else {
                throw MapFailure("Descrição ou andar inválido no arquivo de marcações.")
            }
            markers.append(MapMarker(id: markers.count, x: value(1), y: value(2), z: value(3),
                                     icon: record.last(where: { $0.number == 2 })?.integer ?? 0, text: text, source: source))
        }
        return markers
    }
    static func load(folder: URL) -> (markers: [MapMarker], error: String?) {
        var all: [MapMarker] = []
        var errors: [String] = []
        for (name, label) in [("minimapmarkers.bin", "Normal"), ("privateminimapmarkers.bin", "Privada")] {
            let file = folder.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            do {
                let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? 0) <= 20 * 1024 * 1024 else { throw MapFailure("Arquivo inválido ou muito grande.") }
                for marker in try read(Data(contentsOf: file), source: label) {
                    all.append(MapMarker(id: all.count, x: marker.x, y: marker.y, z: marker.z, icon: marker.icon, text: marker.text, source: marker.source))
                }
            } catch { errors.append("\(name): \(error.localizedDescription)") }
        }
        return (all, errors.isEmpty ? nil : errors.joined(separator: "\n"))
    }

}
