import Testing
@testable import Genboard

@MainActor
struct BoardChecksTests {
    @Test func readsYearsInFrenchAndEnglishDates() {
        #expect(BoardChecks.years(in: "14 janvier 1817") == [1817])
        #expect(BoardChecks.years(in: "1861–1934") == [1861, 1934])
        #expect(BoardChecks.years(in: "~1862") == [1862])
        #expect(BoardChecks.years(in: "f. 12, no 345") == [])
    }

    @Test func statedLifeUsesMarkers() {
        let board = Board()
        #expect(BoardChecks.statedLife(board.person("A", "1861–1934")).death == 1934)
        #expect(BoardChecks.statedLife(board.person("B", "d. 1888")).birth == nil)
        #expect(BoardChecks.statedLife(board.person("C", "d. 1888")).death == 1888)
        #expect(BoardChecks.statedLife(board.person("D", "b. 1826")).birth == 1826)
    }

    @Test func burialBeforeStatedDeathIsFlagged() {
        let board = Board()
        let olivine = board.person("Olivine Girard", "1861–1934")
        let burial = board.card(.event, "Burial", date: "1888")
        board.link(olivine, burial)
        let messages = BoardChecks.run(board.project).map(\.message)
        #expect(messages.contains { $0.contains("dates say died 1934") })
    }

    @Test func marriageAgeOnlyChecksSpouses() {
        let board = Board()
        let bride = board.person("Olivine Girard", "b. 1861")
        let child = board.person("Child", "b. 1862")
        let marriage = board.card(.event, "Mariage", date: "1871")
        board.link(bride, marriage, label: "épouse")
        board.link(child, marriage)
        let issues = BoardChecks.run(board.project)
        #expect(issues.contains { $0.message.contains("Olivine Girard would be 10") })
        #expect(!issues.contains { $0.cards.contains { $0 === child } })
    }

    @Test func implausibleParentAgeIsFlagged() {
        let board = Board()
        let parent = board.person("Parent", "b. 1850")
        let child = board.person("Child", "b. 1858")
        board.link(parent, child, .parent)
        #expect(BoardChecks.run(board.project).contains { $0.message.contains("would be 8") })
    }

    @Test func childBornAfterParentDiedIsFlagged() {
        let board = Board()
        let parent = board.person("Parent", "1820–1850")
        let child = board.person("Child", "b. 1855")
        board.link(child, parent, .child)
        #expect(BoardChecks.run(board.project).contains { $0.message.contains("after parent Parent died") })
    }

    @Test func sameNameIsAPossibleDuplicateUntilConnected() {
        let board = Board()
        let first = board.person("Olivine Girard", "b. 1861")
        let second = board.person("olivine  GIRARD", "b. ~1862")
        #expect(BoardChecks.run(board.project).contains { $0.kind == .possibleDuplicate })
        board.link(first, second)
        #expect(!BoardChecks.run(board.project).contains { $0.kind == .possibleDuplicate })
    }

    @Test func consistentBoardHasNoIssues() {
        let board = Board()
        let father = board.person("Antoine Tremblay", "1826–1890")
        let daughter = board.person("Émilie Tremblay", "1861–1934")
        let baptism = board.card(.event, "Baptism", date: "1861")
        board.link(father, daughter, .parent)
        board.link(daughter, baptism)
        #expect(BoardChecks.run(board.project).isEmpty)
    }
}
