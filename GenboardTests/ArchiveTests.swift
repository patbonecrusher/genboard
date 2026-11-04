import Foundation
import SwiftData
import Testing
@testable import Genboard

@MainActor
struct ArchiveTests {
    /// A project that touches every model and relationship.
    private func fullBoard(screenshot: String? = nil) -> Board {
        let board = Board("Tremblay family")
        let session = ResearchSession(goal: "Find Émilie's father", project: board.project)
        session.summary = "Baptism found."
        session.endedAt = session.startedAt.addingTimeInterval(3600)
        session.savedTabURLs = ["https://www.familysearch.org/"]
        session.aiCostUSD = 0.12
        board.context.insert(session)
        let visit = Visit(url: URL(string: "https://www.genealogiequebec.com/acte/1")!, title: "Baptême 1861", session: session)
        visit.mark = .pinned
        visit.note = "Names Antoine."
        visit.transcription = "Le trois février…"
        visit.screenshotFile = screenshot
        board.context.insert(visit)

        let antoine = board.person("Antoine Tremblay", "b. 1826", sex: .male)
        let emilie = board.person("Émilie Tremblay", "1861–1934", sex: .female)
        let record = board.card(.evidence, "Drouin: baptism 1861")
        record.visit = visit
        record.citation = "St-Hugues register, f. 12"
        record.sourceType = .original
        record.information = .primary
        record.x = 120
        record.y = -40
        let theory = board.theory("Antoine is the father", cards: [antoine, emilie], status: .supported)
        theory.statement = "The baptism names him."
        let parent = board.link(antoine, emilie, .parent)
        parent.note = "From the baptism."
        parent.hypotheses.append(theory)
        board.link(record, antoine, .supports)
        let todo = TodoItem(text: "Check the 1861 census", project: board.project, fromSessionGoal: session.goal)
        todo.hypothesis = theory
        board.context.insert(todo)
        board.save()
        return board
    }

    @Test func roundTripKeepsEverything() throws {
        let source = fullBoard()
        let data = try ProjectArchive.encode(ProjectArchive.snapshot([source.project]))
        let target = Board("Other")
        let restored = try ProjectArchive.restore(try ProjectArchive.decode(data), into: target.context)
        let project = try #require(restored.first)

        #expect(project.name == "Tremblay family")
        #expect(project.sessions.count == 1)
        let session = try #require(project.sessions.first)
        #expect(session.summary == "Baptism found.")
        #expect(session.savedTabURLs == ["https://www.familysearch.org/"])
        #expect(session.aiCostUSD == 0.12)
        let visit = try #require(session.visits.first)
        #expect(visit.mark == .pinned)
        #expect(visit.transcription == "Le trois février…")

        #expect(project.cards.count == 3)
        let record = try #require(project.cards.first { $0.kind == .evidence })
        #expect(record.visit === visit)
        #expect(record.citation == "St-Hugues register, f. 12")
        #expect(record.evidenceRating == "Original · Primary")
        #expect(record.x == 120 && record.y == -40)

        let theory = try #require(project.hypotheses.first)
        #expect(theory.status == .supported)
        #expect(theory.cards.count == 2)
        #expect(theory.links.count == 1)
        #expect(theory.todos.map(\.text) == ["Check the 1861 census"])
        #expect(theory.strength.level == .fair)

        let parent = try #require(project.links.first { $0.role == .parent })
        #expect(parent.from?.title == "Antoine Tremblay")
        #expect(parent.to?.title == "Émilie Tremblay")
        #expect(parent.note == "From the baptism.")
        #expect(BoardChecks.run(project).isEmpty)
    }

    @Test func restoringNextToTheOriginalRenamesIt() throws {
        let board = fullBoard()
        let archive = ProjectArchive.snapshot([board.project])
        let copy = try #require(try ProjectArchive.restore(archive, into: board.context).first)
        #expect(copy.name == "Tremblay family (restored)")
        #expect(copy !== board.project)
    }

    @Test func rejectsNewerFormatsAndOtherFiles() throws {
        var archive = ProjectArchive.snapshot([])
        archive.version = 99
        let data = try ProjectArchive.encode(archive)
        #expect(throws: ProjectArchive.ArchiveError.self) { try ProjectArchive.decode(data) }
        #expect(throws: ProjectArchive.ArchiveError.self) { try ProjectArchive.decode(Data("{}".utf8)) }
    }

    @Test func fileIncludesScreenshots() throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory.appending(path: "genboard-archive-test-\(UUID())", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: base) }
        let shotsBefore = base.appending(path: "before", directoryHint: .isDirectory)
        let shotsAfter = base.appending(path: "after", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: shotsBefore, withIntermediateDirectories: true)
        try Data("png bytes".utf8).write(to: shotsBefore.appending(path: "shot.png"))

        let board = fullBoard(screenshot: "shot.png")
        let file = base.appending(path: "backup.genboard")
        try ProjectArchive.write([board.project], to: file, screenshots: shotsBefore)
        #expect(fileManager.fileExists(atPath: file.path))

        let target = Board("Other")
        let project = try #require(try ProjectArchive.read(from: file, into: target.context, screenshots: shotsAfter).first)
        let restoredFile = try #require(project.sessions.first?.visits.first?.screenshotFile)
        #expect(restoredFile != "shot.png")
        #expect(try Data(contentsOf: shotsAfter.appending(path: restoredFile)) == Data("png bytes".utf8))
    }
}
