import SwiftUI

@main
struct JapaneseSyntaxCoachApp: App {
    @StateObject private var storeKit = StoreKitManager()

    var body: some Scene {
        WindowGroup {
            ContentView(storeKit: storeKit)
        }
    }
}
