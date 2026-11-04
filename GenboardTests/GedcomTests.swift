import Foundation
import Testing
@testable import Genboard

@MainActor
struct GedcomExportTests {
    @Test func formatsNamesAndDates() {
        #expect(GedcomExporter.gedcomName("Olivine Girard") == "Olivine /Girard/")
        #expect(GedcomExporter.gedcomName("Marie-Louise de la Brodeur") == "Marie-Louise de la /Brodeur/")
        #expect(GedcomExporter.gedcomName("Olivine") == "/Olivine/")
        #expect(GedcomExporter.gedcomDate("14 janvier 1817") == "14 JAN 1817")
        #expect(GedcomExporter.gedcomDate("20 novembre 1855") == "20 NOV 1855")
        #expect(GedcomExporter.gedcomDate("Nov 1855") == "NOV 1855")
        #expect(GedcomExporter.gedcomDate("~1862") == "ABT 1862")
        #expect(GedcomExporter.gedcomDate("unknown") == nil)
    }

    @Test func writesPeopleFamiliesAndSources() {
        let board = Board()
        let antoine = board.person("Antoine Tremblay", "b. 1826", sex: .male)
        let marguerite = board.person("Marguerite Gagnon", "b. ~1832", sex: .female)
        let emilie = board.person("Émilie Tremblay", "1861–1934", sex: .female, place: "St-Hugues")
        board.link(antoine, marguerite, .spouse)
        board.link(antoine, emilie, .parent)
        board.link(marguerite, emilie, .parent)
        let marriage = board.card(.event, "Marriage", date: "20 novembre 1855")
        board.link(antoine, marriage, label: "époux")
        board.link(marguerite, marriage, label: "épouse")
        let baptism = board.card(.evidence, "Drouin: baptism 1861")
        baptism.citation = "St-Hugues parish register, 1861, f. 12"
        baptism.repository = "Drouin Collection"
        baptism.sourceType = .original
        baptism.information = .primary
        board.link(baptism, emilie, .supports)

        let result = GedcomExporter.export(board.project, now: Date(timeIntervalSince1970: 0))
        let lines = result.text.split(separator: "\n").map(String.init)
        #expect(result.people == 3)
        #expect(result.families == 1)
        #expect(lines.first == "0 HEAD")
        #expect(lines.last == "0 TRLR")
        #expect(lines.contains("1 NAME Émilie /Tremblay/"))
        #expect(lines.contains("2 DATE ABT 1832"))
        #expect(lines.contains("2 DATE 20 NOV 1855"))
        #expect(lines.filter { $0.hasPrefix("1 CHIL") }.count == 1)
        #expect(lines.contains("2 PAGE St-Hugues parish register, 1861, f. 12"))
        #expect(lines.contains("2 QUAY 3"))
        #expect(lines.contains("1 PUBL Drouin Collection"))
    }

    @Test func splitsLongNotesIntoContinuationLines() {
        let board = Board()
        let person = board.person("Long Notes")
        person.details = String(repeating: "x", count: 450) + "\nSecond paragraph"
        let lines = GedcomExporter.export(board.project).text.split(separator: "\n")
        #expect(lines.filter { $0.hasPrefix("2 CONC") }.count == 2)
        #expect(lines.contains("2 CONT Second paragraph"))
        #expect(lines.allSatisfy { $0.count < 260 })
    }

    @Test func qualityFollowsSourceAndInformation() {
        let board = Board()
        let card = board.card(.evidence, "Record")
        #expect(GedcomExporter.quality(of: card) == nil)
        card.sourceType = .authored
        #expect(GedcomExporter.quality(of: card) == 0)
        card.sourceType = .derivative
        card.information = .secondary
        #expect(GedcomExporter.quality(of: card) == 1)
        card.information = .primary
        #expect(GedcomExporter.quality(of: card) == 2)
    }
}

@MainActor
struct GedcomImportTests {
    static let sample = """
    0 HEAD
    1 CHAR UTF-8
    0 @I1@ INDI
    1 NAME Antoine /Tremblay/
    1 SEX M
    1 BIRT
    2 DATE ABT 1826
    2 PLAC St-Hugues, Québec
    1 DEAT
    2 DATE 3 MAR 1890
    1 SOUR @S1@
    0 @I2@ INDI
    1 NAME Marguerite /Gagnon/
    1 SEX F
    1 CHR
    2 DATE 1832
    0 @I3@ INDI
    1 NAME Émilie /Tremblay/
    1 SEX F
    1 BIRT
    2 DATE 3 FEB 1861
    1 BURI
    2 DATE 1934
    1 NOTE Baptized at St-Hugues;
    2 CONC  godfather Joseph Tremblay.
    2 CONT Second line.
    0 @F1@ FAM
    1 HUSB @I1@
    1 WIFE @I2@
    1 CHIL @I3@
    1 MARR
    2 DATE 20 NOV 1855
    2 PLAC St-Hugues
    0 @S1@ SOUR
    1 TITL Drouin Collection
    0 TRLR
    """

    @Test func parsesPeopleFamiliesAndSources() throws {
        let result = try GedcomImporter.parse(Fixtures.data(Self.sample))
        #expect(result.people.map(\.name) == ["Antoine Tremblay", "Marguerite Gagnon", "Émilie Tremblay"])
        #expect(result.people[0].sex == .male)
        #expect(result.people[0].birth == .init(date: "ABT 1826", place: "St-Hugues, Québec"))
        #expect(result.people[1].baptism?.date == "1832")
        #expect(result.people[2].notes == ["Baptized at St-Hugues; godfather Joseph Tremblay.\nSecond line."])
        #expect(result.families == [.init(id: "@F1@", husband: "@I1@", wife: "@I2@", children: ["@I3@"],
                                          marriage: .init(date: "20 NOV 1855", place: "St-Hugues"))])
        #expect(result.sources == ["@S1@": "Drouin Collection"])
    }

    @Test func formatsLifeDatesForTheBoard() throws {
        let people = try GedcomImporter.parse(Fixtures.data(Self.sample)).people
        #expect(GedcomImporter.lifeDates(people[0]) == "~1826–1890")
        #expect(GedcomImporter.lifeDates(people[1]) == "b. 1832")
        #expect(GedcomImporter.lifeDates(people[2]) == "1861–1934")
        let details = GedcomImporter.details(people[0], sources: ["@S1@": "Drouin Collection"])
        #expect(details.contains("Born ABT 1826, St-Hugues, Québec"))
        #expect(details.contains("Sources: Drouin Collection"))
    }

    @Test func placesParentsAboveChildren() throws {
        let rows = GedcomImporter.generations(try GedcomImporter.parse(Fixtures.data(Self.sample)))
        #expect(rows["@I1@"] == 0)
        #expect(rows["@I2@"] == 0)
        #expect(rows["@I3@"] == 1)
    }

    @Test func rejectsFilesWithoutPeople() {
        #expect(throws: GedcomImporter.ImportError.self) { try GedcomImporter.parse(Fixtures.data("0 HEAD\n0 TRLR\n")) }
        #expect(throws: GedcomImporter.ImportError.self) { try GedcomImporter.parse(Fixtures.data("not a gedcom")) }
    }

    @Test func readsTheExportBackIn() throws {
        let board = Board()
        let father = board.person("Antoine Tremblay", "1826–1890", sex: .male)
        let mother = board.person("Marguerite Gagnon", "b. 1832", sex: .female)
        let child = board.person("Émilie Tremblay", "1861–1934", sex: .female)
        board.link(father, mother, .spouse)
        board.link(father, child, .parent)
        board.link(mother, child, .parent)

        let result = try GedcomImporter.parse(Fixtures.data(GedcomExporter.export(board.project).text))
        #expect(Set(result.people.map(\.name)) == ["Antoine Tremblay", "Marguerite Gagnon", "Émilie Tremblay"])
        #expect(result.families.count == 1)
        #expect(result.families[0].children.count == 1)
        let emilie = try #require(result.people.first { $0.name == "Émilie Tremblay" })
        #expect(GedcomImporter.lifeDates(emilie) == "1861–1934")
    }

    @Test func importBuildsATreeOnTheBoard() throws {
        let app = AppState()
        let project = ResearchProject(name: "Import")
        app.context.insert(project)
        let url = FileManager.default.temporaryDirectory.appending(path: "genboard-test-\(UUID()).ged")
        try Self.sample.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let counts = try app.importGedcom(from: url, into: project)
        #expect(counts.people == 3)
        #expect(counts.families == 1)
        let graph = FamilyGraph(project: project, includeRefuted: true)
        let emilie = try #require(project.cards.first { $0.title == "Émilie Tremblay" })
        #expect(Set(graph.parents(of: emilie).map(\.title)) == ["Antoine Tremblay", "Marguerite Gagnon"])
        #expect(graph.parents(of: emilie).allSatisfy { $0.y < emilie.y })
        let spouseLink = try #require(project.links.first { $0.role == .spouse })
        #expect(spouseLink.label == "m. 1855")
        #expect(BoardChecks.run(project).isEmpty)
    }
}
