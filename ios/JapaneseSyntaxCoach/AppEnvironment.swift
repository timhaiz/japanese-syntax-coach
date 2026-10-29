import SwiftUI

/// Holds the long-lived app services so the authentication session, the StoreKit
/// manager and the learning store all share the same signed-in account.
@MainActor
final class AppEnvironment: ObservableObject {
    let auth: AuthSessionStore
    let storeKit: StoreKitManager
    let learning: LearningStore

    init() {
        let auth = AuthSessionStore()
        self.auth = auth
        self.storeKit = StoreKitManager(
            entitlements: EntitlementSync(api: APIClient(tokenProvider: auth)),
            userIDProvider: { auth.userID }
        )
        self.learning = LearningStore(auth: auth)
    }
}
