import Testing
@testable import Genboard

@MainActor
struct EvidenceTests {
    @Test func guessesSourceTypeFromTheSite() {
        #expect(SourceType.guess(from: "https://www.genealogiequebec.com/Membership/LFT/acte/123") == .original)
        #expect(SourceType.guess(from: "https://www.familysearch.org/ark:/61903/3:1:ABCD") == .original)
        #expect(SourceType.guess(from: "https://www.familysearch.org/ark:/61903/1:1:ABCD") == .derivative)
        #expect(SourceType.guess(from: "https://www.familysearch.org/tree/person/details/L1") == .authored)
        #expect(SourceType.guess(from: "https://www.wikitree.com/wiki/Tremblay-1") == .authored)
        #expect(SourceType.guess(from: "https://example.com") == .unknown)
    }

    @Test func weighsEvidenceBySourceAndInformation() {
        let board = Board()
        let record = board.card(.evidence, "Baptism")
        record.sourceType = .original
        record.information = .primary
        #expect(record.evidenceWeight == 1)
        #expect(record.evidenceRating == "Original · Primary")
        let tree = board.card(.evidence, "Online tree")
        tree.sourceType = .authored
        #expect(tree.evidenceWeight < 0.3)
        #expect(board.card(.evidence, "Unrated").evidenceRating == "Not rated")
        #expect(board.card(.note, "Thought").evidenceWeight == 0.2)
    }

    @Test func theoryStrengthComesFromItsEvidence() {
        let board = Board()
        let father = board.person("Antoine")
        let theory = board.theory("Antoine is the father", cards: [father])
        #expect(theory.strength.level == .none)

        let tree = board.card(.evidence, "WikiTree")
        tree.sourceType = .authored
        board.link(tree, father, .supports)
        #expect(theory.strength.level == .weak)

        for title in ["Baptism", "Marriage"] {
            let record = board.card(.evidence, title)
            record.sourceType = .original
            record.information = .primary
            board.link(record, father, .supports)
        }
        #expect(theory.strength.level == .strong)
        #expect(theory.strength.counts == "3 for")

        let doubt = board.card(.evidence, "Census")
        doubt.sourceType = .original
        doubt.information = .primary
        let doubt2 = board.card(.evidence, "Burial")
        doubt2.sourceType = .original
        doubt2.information = .primary
        board.link(doubt, father, .contradicts)
        board.link(doubt2, father, .contradicts)
        #expect(theory.strength.level == .contested)
    }

    @Test func evidenceBackingSeveralCardsCountsOnce() {
        let board = Board()
        let a = board.person("A"), b = board.person("B")
        let theory = board.theory("T", cards: [a, b])
        let record = board.card(.evidence, "Record")
        board.link(record, a, .supports)
        board.link(record, b, .supports)
        #expect(theory.strength.forCount == 1)
    }
}
