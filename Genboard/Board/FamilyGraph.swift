import Foundation

/// Parent, child and spouse relationships between the board's person cards, read from its
/// connections. Shared by the tree view and the GEDCOM export.
struct FamilyGraph {
    let people: [BoardCard]
    private var parentsByChild: [ObjectIdentifier: [BoardCard]] = [:]
    private var childrenByParent: [ObjectIdentifier: [BoardCard]] = [:]
    private var spousesByPerson: [ObjectIdentifier: [BoardCard]] = [:]

    /// Uses what the board shows (hidden theories excluded). With `includeRefuted` false, cards and
    /// connections that only belong to refuted theories are left out too.
    init(project: ResearchProject, includeRefuted: Bool) {
        func included(_ card: BoardCard) -> Bool {
            card.kind == .person && !card.isHiddenByTheories && (includeRefuted || !card.isRefuted)
        }
        people = project.cards.filter(included).sorted { $0.displayName < $1.displayName }

        for link in project.links where !link.isHiddenByTheories && (includeRefuted || !link.isRefuted) {
            guard let from = link.from, let to = link.to, included(from), included(to) else { continue }
            switch link.role {
            case .parent: add(parent: from, child: to)
            case .child: add(parent: to, child: from)
            case .spouse:
                Self.append(to, to: &spousesByPerson[ObjectIdentifier(from), default: []])
                Self.append(from, to: &spousesByPerson[ObjectIdentifier(to), default: []])
            default: break
            }
        }
    }

    func parents(of person: BoardCard) -> [BoardCard] { parentsByChild[ObjectIdentifier(person)] ?? [] }
    func children(of person: BoardCard) -> [BoardCard] { childrenByParent[ObjectIdentifier(person)] ?? [] }
    func spouses(of person: BoardCard) -> [BoardCard] { spousesByPerson[ObjectIdentifier(person)] ?? [] }

    /// A sensible starting person: the selected one, else whoever has the most known ancestors.
    func defaultRoot(selected: BoardCard?) -> BoardCard? {
        if let selected, people.contains(where: { $0 === selected }) { return selected }
        return people.max { ancestorCount($0) < ancestorCount($1) }
    }

    func ancestorCount(_ person: BoardCard) -> Int {
        var seen = Set<ObjectIdentifier>()
        var queue = parents(of: person)
        while let next = queue.popLast() {
            guard seen.insert(ObjectIdentifier(next)).inserted else { continue }
            queue += parents(of: next)
        }
        return seen.count
    }

    private mutating func add(parent: BoardCard, child: BoardCard) {
        Self.append(parent, to: &parentsByChild[ObjectIdentifier(child), default: []])
        Self.append(child, to: &childrenByParent[ObjectIdentifier(parent), default: []])
    }

    private static func append(_ card: BoardCard, to list: inout [BoardCard]) {
        if !list.contains(where: { $0 === card }) { list.append(card) }
    }
}
