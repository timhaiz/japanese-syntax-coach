import SwiftUI

@main
struct JapaneseSyntaxCoachApp: App {
    @StateObject private var auth = AuthSessionStore()
    @StateObject private var storeKit = StoreKitManager()

    var body: some Scene {
        WindowGroup {
            ContentView(auth: auth)
                .onOpenURL { url in Task { await auth.handle(url: url) } }
        }
    }
}
