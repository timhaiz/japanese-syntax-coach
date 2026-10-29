import SwiftUI

@main
struct JapaneseSyntaxCoachApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentView(auth: environment.auth, learning: environment.learning, storeKit: environment.storeKit)
                .onOpenURL { url in Task { await environment.auth.handle(url: url) } }
        }
    }
}
