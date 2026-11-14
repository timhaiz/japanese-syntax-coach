import SwiftUI

struct ContentView: View {
    @ObservedObject var auth: AuthSessionStore
    @ObservedObject var learning: LearningStore
    @ObservedObject var storeKit: StoreKitManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var selectedTab = 0

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
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        HomeView(
                            store: learning,
                            membership: storeKit.membership?.status ?? .free,
                            onSelectTab: { selectedTab = $0 }
                        )
                    }
                    .tabItem { Label("首页", systemImage: "house") }
                    .tag(0)
                    NavigationStack { TextbookView(store: learning) }
                        .tabItem { Label("课程", systemImage: "book") }
                        .tag(1)
                    NavigationStack { MistakesView(store: learning) }
                        .tabItem { Label("错题本", systemImage: "exclamationmark.bubble") }
                        .tag(2)
                    NavigationStack {
                        AccountView(auth: auth, learning: learning, storeKit: storeKit)
                    }
                    .tabItem { Label("我的", systemImage: "person.circle") }
                    .tag(3)
                }
                .tint(HomeVisualStyle.accent)
                .toolbarBackground(HomeVisualStyle.card, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .environment(\.adEligibility, AdEligibility.resolve(membership: storeKit.membership))
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
        .task(id: auth.studyLoadGeneration) {
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
