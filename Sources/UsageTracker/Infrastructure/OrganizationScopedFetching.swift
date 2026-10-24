import Foundation

/// A fetcher whose reports belong to one account organization, chosen by
/// the user when the credential can see several. It throws
/// `FetchError.needsOrganizationChoice` until a listed one is chosen.
@MainActor
protocol OrganizationScopedFetching: AnyObject {
    /// What the last listing found for the current credential; empty before one.
    var organizations: [AccountOrganization] { get }
    /// The stored choice, which may no longer be listed.
    var selectedOrganizationID: String? { get }
    func selectOrganization(_ id: String)
    /// The credential was removed or replaced: forgets the choice and the list.
    func resetOrganizations()
}
