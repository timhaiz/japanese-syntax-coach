import SwiftUI

struct ContentView: View {
    @ObservedObject var auth: AuthSessionStore
    @ObservedObject var learning: LearningStore
    @ObservedObject var storeKit: StoreKitManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    init(auth: AuthSessionStore, learning: LearningStore, storeKit: StoreKitManager) {
        self.auth = auth
        self.learning = learning
        self.storeKit = storeKit
    }

    var body: some View {
        Group {
            if !hasSeenOnboarding {
                OnboardingView { hasSeenOnboarding = true }
            } else if auth.phase == .signedIn {
                TabView {
                    NavigationStack { HomeView(store: learning) }
                        .tabItem { Label("首页", systemImage: "house") }
                    NavigationStack { TextbookView(store: learning) }
                        .tabItem { Label("教材", systemImage: "book") }
                    NavigationStack { LearningProgressView(store: learning) }
                        .tabItem { Label("进度", systemImage: "chart.bar") }
                    NavigationStack {
                        AccountView(auth: auth, learning: learning, storeKit: storeKit)
                    }
                    .tabItem { Label("账户", systemImage: "person.circle") }
                }
            } else {
                AuthView(store: auth)
                    .overlay {
                        if auth.phase == .loading {
                            SwiftUI.ProgressView("正在恢复登录状态…")
                                .padding().background(.regularMaterial).cornerRadius(12)
                        }
                    }
            }
        }
        .task(id: auth.userEmail) {
            if auth.phase == .signedIn {
                storeKit.activateAccount(auth.userID)
                await learning.loadStudyState()
                await learning.retryPending()
                await storeKit.retryPendingTransactions()
            } else { learning.clearUserScopedData() }
        }
        .onChange(of: auth.phase) { phase in
            if phase == .signedOut || phase == .misconfigured {
                learning.clearUserScopedData()
                storeKit.activateAccount(nil)
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active, auth.phase == .signedIn {
                Task {
                    await learning.loadStudyState()
                    await learning.retryPending()
                    await storeKit.retryPendingTransactions()
                }
            }
        }
        .preferredColorScheme(.light)
    }
}
