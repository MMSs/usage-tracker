import Foundation

/// An account organization a credential can see. Its name is user data:
/// never log it.
struct AccountOrganization: Equatable, Sendable, Identifiable {
    let id: String
    let name: String?
    /// What sets it apart from a same-named one, such as its plan or "API".
    var detail: String? = nil

    /// The name, or the id's first eight characters when it has none.
    var title: String {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return String(id.prefix(8))
        }

        return name
    }

    /// Each organization's picker label keyed by id: the title and detail,
    /// plus the id's first eight characters while labels still collide.
    /// claude.ai names every new organization "<email>'s Organization".
    static func labels(for organizations: [AccountOrganization]) -> [String: String] {
        let labels = organizations.map { organization in
            ([organization.title] + [organization.detail].compactMap { $0 }).joined(separator: " · ")
        }
        var counts: [String: Int] = [:]
        labels.forEach { counts[$0, default: 0] += 1 }

        return Dictionary(zip(organizations, labels).map { organization, label in
            (organization.id, counts[label, default: 0] > 1 ? "\(label) · \(organization.id.prefix(8))" : label)
        }, uniquingKeysWith: { first, _ in first })
    }
}
