import Testing
@testable import Genboard

@MainActor
struct FamilyGraphTests {
    @Test func readsParentChildAndSpouseLinksInBothDirections() {
        let board = Board()
        let father = board.person("Father")
        let mother = board.person("Mother")
        let child = board.person("Child")
        board.link(father, child, .parent)
        board.link(child, mother, .child)
        board.link(father, mother, .spouse)
        let graph = FamilyGraph(project: board.project, includeRefuted: true)
        #expect(Set(graph.parents(of: child).map(\.title)) == ["Father", "Mother"])
        #expect(graph.children(of: mother).map(\.title) == ["Child"])
        #expect(graph.spouses(of: mother).map(\.title) == ["Father"])
        #expect(graph.ancestorCount(child) == 2)
        #expect(graph.defaultRoot(selected: nil) === child)
    }

    @Test func leavesOutHiddenAndRefutedTheories() {
        let board = Board()
        let child = board.person("Child")
        let antoine = board.person("Antoine")
        let joseph = board.person("Joseph")
        board.link(antoine, child, .parent)
        board.link(joseph, child, .parent)
        board.theory("Joseph is the father", cards: [joseph], status: .refuted)
        let hidden = board.theory("Antoine is the father", cards: [antoine])

        #expect(FamilyGraph(project: board.project, includeRefuted: true).parents(of: child).count == 2)
        #expect(FamilyGraph(project: board.project, includeRefuted: false).parents(of: child).map(\.title) == ["Antoine"])
        hidden.isVisible = false
        #expect(FamilyGraph(project: board.project, includeRefuted: false).parents(of: child).isEmpty)
    }

    @Test func ignoresNonPersonCards() {
        let board = Board()
        let person = board.person("Person")
        let note = board.card(.note, "Note")
        board.link(note, person, .parent)
        #expect(FamilyGraph(project: board.project, includeRefuted: true).parents(of: person).isEmpty)
    }
}
