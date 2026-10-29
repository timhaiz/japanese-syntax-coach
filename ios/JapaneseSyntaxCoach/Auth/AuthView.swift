import AuthenticationServices
import SwiftUI

struct AuthView: View {
    @ObservedObject var store: AuthSessionStore
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var mode: Mode = .login
    @State private var busy = false
    private enum Mode { case login, signup, verify, reset }

    var body: some View {
        NavigationStack {
            Form {
                Section("日句") {
                    Text(mode == .signup ? "创建账号" : mode == .verify ? "验证邮箱" : mode == .reset ? "设置密码" : "登录")
                        .font(.title2.bold())
                    if mode != .verify { TextField("邮箱", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled() }
                    if mode == .login || mode == .signup { SecureField("密码", text: $password) }
                    if mode == .verify { TextField("6 位验证码", text: $code).keyboardType(.numberPad).onChange(of: code) { code = String($0.filter(\.isNumber).prefix(6)) } }
                }
                Section {
                    Button(action: submit) {
                        HStack { Spacer(); Text(buttonTitle); if busy { ProgressView() }; Spacer() }
                    }.disabled(busy)
                    if mode == .login { Button("注册", action: { mode = .signup }); Button("忘记密码", action: { mode = .reset }) }
                    if mode == .signup { Button("返回登录", action: { mode = .login }) }
                    if mode == .verify { Button("返回注册", action: { mode = .signup }) }
                    if mode == .reset { Button("返回登录", action: { mode = .login }) }
                    if mode == .login {
                        SignInWithAppleButton(.signIn, onRequest: { request in
                            request.requestedScopes = [.email, .fullName]
                        }, onCompletion: handleAppleResult)
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 44)
                        .disabled(busy)
                    }
                }
                if let message = store.errorMessage { Section { Text(message).foregroundStyle(.red) } }
            }
            .navigationTitle("账户")
        }
    }

    private var buttonTitle: String { mode == .signup ? "注册" : mode == .verify ? "验证并继续" : mode == .reset ? "发送重置邮件" : "登录" }

    private func submit() {
        guard !busy else { return }
        busy = true
        Task {
            switch mode {
            case .login: await store.signIn(email: email, password: password)
            case .signup: await store.signUp(email: email, password: password); if store.phase == .needsEmailVerification { mode = .verify }
            case .verify: await store.verifySignupCode(email: email, code: code)
            case .reset: await store.requestPasswordReset(email: email)
            }
            busy = false
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = credential.identityToken,
                  let token = String(data: identityToken, encoding: .utf8) else {
                store.errorMessage = "Apple 未返回有效身份凭证。"
                return
            }
            busy = true
            Task { await store.signInWithApple(idToken: token); busy = false }
        case .failure:
            store.errorMessage = "Apple 登录已取消或失败，请稍后重试。"
        }
    }
}
