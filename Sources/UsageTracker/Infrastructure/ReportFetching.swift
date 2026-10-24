import Foundation

@MainActor
protocol ReportFetching: AnyObject {
    /// credentials keyed by CredentialField.id for this half.
    func fetchReport(credentials: [String: String], today: Date) async throws -> ProviderReport
}
