import AppKit

/// Reads Scapple (.scap) boards: an XML list of notes with positions, text, colors, and connections.
nonisolated enum ScappleImporter {
    struct Note {
        var id: Int
        var x: Double = 0
        var y: Double = 0
        var width: Double = 150
        var text = ""
        var fillHex: String?
        /// Plain lines (stored on both notes).
        var connected: [Int] = []
        /// Arrows from this note.
        var pointsTo: [Int] = []
        var imagePNG: Data?
    }

    enum ImportError: LocalizedError {
        case unreadable(String)
        var errorDescription: String? {
            switch self {
            case .unreadable(let reason): "This doesn't look like a Scapple file: \(reason)"
            }
        }
    }

    static func parse(_ data: Data) throws -> [Note] {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw ImportError.unreadable(parser.parserError?.localizedDescription ?? "unknown XML error")
        }
        guard delegate.sawScappleRoot else { throw ImportError.unreadable("no ScappleDocument element") }
        return delegate.notes
    }

    /// Parses Scapple ID lists such as "1-4, 7, 14".
    static func ids(from list: String) -> [Int] {
        list.split(separator: ",").flatMap { part -> [Int] in
            let bounds = part.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if bounds.count == 2, bounds[0] <= bounds[1] { return Array(bounds[0]...bounds[1]) }
            return bounds.count == 1 ? bounds : []
        }
    }

    /// "0.94 0.52 0.52" (RGB components 0–1) → "#F08585".
    static func hex(fromComponents text: String) -> String? {
        let parts = text.split(separator: " ").compactMap { Double($0) }
        guard parts.count >= 3 else { return nil }
        return String(format: "#%02X%02X%02X", Int(parts[0] * 255), Int(parts[1] * 255), Int(parts[2] * 255))
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var notes: [Note] = []
        var sawScappleRoot = false
        private var current: Note?
        private var path: [String] = []
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            path.append(name)
            text = ""
            if name == "ScappleDocument" { sawScappleRoot = true }
            if name == "Note", let id = attributes["ID"].flatMap(Int.init) {
                var note = Note(id: id)
                let position = (attributes["Position"] ?? "").split(separator: ",").compactMap { Double($0) }
                if position.count == 2 { note.x = position[0]; note.y = position[1] }
                if let width = attributes["Width"].flatMap(Double.init) { note.width = width }
                current = note
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            defer { path.removeLast(); text = "" }
            guard current != nil else { return }
            switch name {
            case "Note":
                if let note = current { notes.append(note) }
                current = nil
            case "String":
                current?.text = text
            case "ConnectedNoteIDs":
                current?.connected = ScappleImporter.ids(from: text)
            case "PointsToNoteIDs":
                current?.pointsTo = ScappleImporter.ids(from: text)
            case "FillColor" where path.contains("Appearance"):
                current?.fillHex = ScappleImporter.hex(fromComponents: text)
            case let element where element.contains("Image"):
                // Best effort: image notes carry base64 image data. Normalize whatever format to PNG.
                let base64 = text.components(separatedBy: .whitespacesAndNewlines).joined()
                if let data = Data(base64Encoded: base64), let image = NSImage(data: data) {
                    current?.imagePNG = ImageUtil.pngData(image)
                }
            default:
                break
            }
        }
    }
}
