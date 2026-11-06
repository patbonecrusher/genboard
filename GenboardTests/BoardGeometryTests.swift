import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import Genboard

@MainActor
struct BoardGeometryTests {
    private func segment(label: String = "") -> BoardLinksLayer.Segment {
        let board = Board()
        let link = board.link(board.person("A"), board.person("B"))
        board.save()
        return .init(id: link.persistentModelID, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0),
                     color: .blue, dashed: false, arrow: false, label: label)
    }

    @Test func distanceToALineSegment() {
        let line = segment()
        #expect(line.distance(to: CGPoint(x: 50, y: 4)) == 4)
        #expect(line.distance(to: CGPoint(x: -3, y: 4)) == 5)   // past the start: distance to the end point
        #expect(line.distance(to: CGPoint(x: 103, y: -4)) == 5)
    }

    @Test func clickingTheLabelHitsTheLine() {
        let labelled = segment(label: "parent of")
        #expect(labelled.distance(to: CGPoint(x: 62, y: 6)) == 0)
        #expect(segment().distance(to: CGPoint(x: 62, y: 6)) == 6)
    }

    @Test func edgePointLeavesTheCardTowardTheTarget() {
        let card = CGRect(x: 0, y: 0, width: 200, height: 60)
        #expect(BoardView.edgePoint(of: card, toward: CGPoint(x: 1000, y: 30)) == CGPoint(x: 200, y: 30))
        #expect(BoardView.edgePoint(of: card, toward: CGPoint(x: 100, y: -500)) == CGPoint(x: 100, y: 0))
    }
}

@MainActor
struct ScappleTests {
    static let sample = """
    <?xml version="1.0" encoding="UTF-8" standalone="no"?>
    <ScappleDocument Version="1.1">
      <Notes>
        <Note ID="0" Position="10,20" Width="120">
          <Appearance><FillColor>1.0 0.5 0.0</FillColor></Appearance>
          <String>Olivine Girard</String>
          <PointsToNoteIDs>1</PointsToNoteIDs>
        </Note>
        <Note ID="1" Position="200,20" Width="90">
          <String>Pierre Girard</String>
          <ConnectedNoteIDs>2-3</ConnectedNoteIDs>
        </Note>
        <Note ID="2" Position="0,0"><String>Two</String></Note>
        <Note ID="3" Position="0,0"><String>Three</String></Note>
      </Notes>
    </ScappleDocument>
    """

    @Test func parsesNotesPositionsColorsAndConnections() throws {
        let notes = try ScappleImporter.parse(Fixtures.data(Self.sample))
        #expect(notes.count == 4)
        #expect(notes[0].text == "Olivine Girard")
        #expect(notes[0].x == 10 && notes[0].y == 20 && notes[0].width == 120)
        #expect(notes[0].fillHex == "#FF7F00")
        #expect(notes[0].pointsTo == [1])
        #expect(notes[1].connected == [2, 3])
    }

    @Test func importsNotesWithLargeImages() throws {
        // A large pasted image, like a screenshot of a record: random pixels make a ~14 MB base64 block.
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1800, pixelsHigh: 1500, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        var generator = SystemRandomNumberGenerator()
        for offset in 0..<(1800 * 1500 * 4) { rep.bitmapData![offset] = UInt8.random(in: 0...255, using: &generator) }
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let base64 = png.base64EncodedString(options: .lineLength76Characters)
        #expect(base64.count > 10_000_000)
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ScappleDocument Version="1.1"><Notes>
        <Note ID="0" Position="0,0"><String>Baptism record</String><ImageData>\(base64)</ImageData><PointsToNoteIDs>1</PointsToNoteIDs></Note>
        <Note ID="1" Position="300,0"><String>Émilie</String></Note>
        </Notes></ScappleDocument>
        """
        let notes = try ScappleImporter.parse(Data(xml.utf8))
        #expect(notes.map(\.text) == ["Baptism record", "Émilie"])
        #expect(notes[0].pointsTo == [1])
        let image = try #require(notes[0].imagePNG.flatMap(NSBitmapImageRep.init(data:)))
        #expect(image.pixelsWide == 1800)
    }

    @Test func parsesIDLists() {
        #expect(ScappleImporter.ids(from: "1-4, 7, 14") == [1, 2, 3, 4, 7, 14])
        #expect(ScappleImporter.ids(from: "") == [])
    }

    @Test func rejectsOtherXML() {
        #expect(throws: ScappleImporter.ImportError.self) { try ScappleImporter.parse(Fixtures.data("<plist/>")) }
    }

    @Test func importCreatesOneLinkPerPair() throws {
        let app = AppState()
        let project = ResearchProject(name: "Scapple")
        app.context.insert(project)
        let url = FileManager.default.temporaryDirectory.appending(path: "genboard-test-\(UUID()).scap")
        try Self.sample.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try app.importScapple(from: url, into: project) == 4)
        #expect(project.cards.count == 4)
        #expect(project.links.count == 3)
        #expect(project.links.filter(\.directed).count == 1)
    }
}

@MainActor
struct BoardImportTests {
    private func appWithSession() -> (AppState, ResearchProject) {
        let app = AppState()
        let project = ResearchProject(name: "Import")
        app.context.insert(project)
        app.startSession(in: project, goal: "Import")
        return (app, project)
    }

    private func file(_ name: String, _ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID())-\(name)")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func importsScappleAndGedcomByExtension() throws {
        let (app, project) = appWithSession()
        app.mainMode = .browse
        let scap = try file("Board.SCAP", ScappleTests.sample)
        let ged = try file("tree.ged", GedcomImportTests.sample)
        defer { [scap, ged].forEach { try? FileManager.default.removeItem(at: $0) } }

        app.importToBoard(scap)
        #expect(project.cards.count == 4)
        #expect(app.mainMode == .board)
        #expect(app.boardFitRequest == 1)
        app.importToBoard(ged)
        #expect(project.cards.count == 7)
        #expect(app.boardFitRequest == 2)
        #expect(app.boardImportError == nil)
    }

    @Test func reportsUnsupportedAndBrokenFiles() throws {
        let (app, project) = appWithSession()
        let text = try file("notes.txt", "hello")
        let broken = try file("broken.scap", "<plist/>")
        defer { [text, broken].forEach { try? FileManager.default.removeItem(at: $0) } }

        app.importToBoard(text)
        #expect(app.boardImportError?.contains("notes.txt") == true)
        app.boardImportError = nil
        app.importToBoard(broken)
        #expect(app.boardImportError?.contains("Scapple") == true)
        #expect(project.cards.isEmpty)
    }
}

/// Parses a real Scapple file without importing it. Runs only when given one:
///   TEST_RUNNER_GENBOARD_SCAPPLE_FILE=/path/board.scap tools/test.sh RealScappleFileTests
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GENBOARD_SCAPPLE_FILE"] != nil))
struct RealScappleFileTests {
    @Test func parses() throws {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["GENBOARD_SCAPPLE_FILE"]!)
        let notes = try ScappleImporter.parse(Data(contentsOf: url))
        let images = notes.filter { $0.imagePNG != nil }
        print("Parsed \(notes.count) notes, \(images.count) with images, \(notes.map { $0.connected.count + $0.pointsTo.count }.reduce(0, +)) connection ends")
        #expect(!notes.isEmpty)
    }
}
