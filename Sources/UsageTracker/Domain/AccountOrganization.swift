import Foundation

/// An account organization a credential can see. Its name is user data:
/// never log it.
struct AccountOrganization: Equatable, Sendable, Identifiable {
    let id: String
    let name: String?

    /// The name, or the id's first eight characters when it has none.
    var title: String {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return String(id.prefix(8))
        }

        return name
    }
}
