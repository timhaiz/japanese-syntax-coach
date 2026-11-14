import Foundation

/// The account-deletion request contract shared with `POST /api/account/delete`.
///
/// The server compares the confirmation string exactly, so the app validates it
/// locally before sending a request that is guaranteed to fail.
struct AccountDeletionRequest: Encodable, Equatable {
    static let requiredConfirmation = "DELETE"

    let confirmation: String

    init(confirmation: String = AccountDeletionRequest.requiredConfirmation) {
        self.confirmation = confirmation
    }

    var isConfirmed: Bool { confirmation == AccountDeletionRequest.requiredConfirmation }
}
