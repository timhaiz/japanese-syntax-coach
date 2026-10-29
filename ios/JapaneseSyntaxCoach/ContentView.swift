import SwiftUI

struct ContentView: View {
    @ObservedObject var auth: AuthSessionStore

    var body: some View {
        Group {
            switch auth.phase {
            case .loading:
                ProgressView("正在恢复登录状态…")
            case .misconfigured:
                VStack(spacing: 14) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 34))
                        .foregroundStyle(.orange)
                    Text("服务尚未配置").font(.title3.bold())
                    Text(auth.errorMessage ?? "请在构建设置中填入 Supabase 配置。")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            case .signedOut, .needsEmailVerification, .error:
                AuthView(store: auth)
            case .signedIn:
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle").font(.system(size: 42)).foregroundStyle(.green)
                    Text("登录成功").font(.title2.bold())
                    Text(auth.userEmail ?? "").foregroundStyle(.secondary)
                    Button("退出登录") { Task { await auth.signOut() } }.buttonStyle(.bordered)
                    Text("原生学习界面将在后续任务接入。").font(.footnote).foregroundStyle(.secondary)
                }.padding()
            }
        }
        .preferredColorScheme(.light)
    }
}
