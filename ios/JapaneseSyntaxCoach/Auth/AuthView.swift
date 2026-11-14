import AuthenticationServices
import SwiftUI

struct AuthView: View {
    @ObservedObject var store: AuthSessionStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var mode: Mode = .login
    @State private var busy = false
    @State private var sendingCode = false
    @State private var codeSent = false
    @State private var resendCountdown = 0
    @State private var countdownTask: Task<Void, Never>?
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case email, password, code }
    private enum Mode { case login, signup, reset }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HomeVisualStyle.sectionSpacing) {
                    brandHeader
                    formCard
                    if let message = store.errorMessage {
                        messageBanner(message)
                    }
                    if mode == .login {
                        appleSignInSection
                    }
                }
                .padding(.horizontal, HomeVisualStyle.screenPadding)
                .padding(.vertical, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(canvasColor.ignoresSafeArea())
            .foregroundStyle(inkColor)
            .tint(accentColor)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .navigationTitle("账户")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                countdownTask?.cancel()
            }
        }
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("日句")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(accentColor)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("authBrandTitle")
            Text("拆解核心句型，循序渐进练习日语造句与到期复习。")
                .font(.subheadline)
                .foregroundStyle(secondaryInkColor)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("authLearningGuide")
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(modeTitle)
                    .font(.title2.bold())
                    .foregroundStyle(inkColor)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("authModeTitle")
                Text(modeSubtitle)
                    .font(.footnote)
                    .foregroundStyle(secondaryInkColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                inputContainer(label: "邮箱") {
                    TextField("邮箱", text: $email)
                        .focused($focusedField, equals: .email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .foregroundStyle(inkColor)
                        .accessibilityLabel("邮箱")
                        .accessibilityIdentifier("authEmailField")
                }
                if mode == .login || mode == .signup {
                    inputContainer(label: mode == .signup ? "密码（至少 6 位）" : "密码") {
                        SecureField(mode == .signup ? "设置至少 6 位密码" : "密码", text: $password)
                            .focused($focusedField, equals: .password)
                            .textContentType(mode == .signup ? .newPassword : .password)
                            .foregroundStyle(inkColor)
                            .accessibilityLabel("密码")
                            .accessibilityIdentifier("authPasswordField")
                    }
                }
                if mode == .signup {
                    verificationCodeSection
                }
            }

            primaryActionButton
            secondaryActions
        }
        .padding(HomeVisualStyle.cardPadding + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: HomeVisualStyle.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HomeVisualStyle.cornerRadius, style: .continuous)
                .stroke(accentColor.opacity(colorScheme == .dark ? 0.28 : 0.18), lineWidth: 1)
        )
    }

    private var verificationCodeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("6 位验证码")
                .font(.caption.weight(.medium))
                .foregroundStyle(secondaryInkColor)
                .accessibilityHidden(true)
            HStack(spacing: 10) {
                TextField("输入 6 位验证码", text: $code)
                    .focused($focusedField, equals: .code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .foregroundStyle(inkColor)
                    .onChange(of: code) {
                        code = String($0.filter(\.isNumber).prefix(6))
                    }
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .background(fieldBackgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(accentColor.opacity(colorScheme == .dark ? 0.32 : 0.22), lineWidth: 1)
                    )
                    .accessibilityLabel("6 位验证码")
                    .accessibilityHint("输入发送到邮箱的 6 位数字验证码")
                    .accessibilityIdentifier("authCodeField")

                Button(action: sendVerificationCode) {
                    HStack(spacing: 6) {
                        Text(sendCodeButtonTitle)
                            .font(.subheadline.weight(.semibold))
                        if sendingCode {
                            ProgressView()
                                .controlSize(.small)
                                .tint(accentInkColor)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(accentColor.opacity(colorScheme == .dark ? 0.18 : 0.10))
                    .foregroundStyle(accentInkColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(accentColor.opacity(colorScheme == .dark ? 0.42 : 0.30), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(busy || sendingCode || resendCountdown > 0)
                .opacity((busy || sendingCode || resendCountdown > 0) ? 0.6 : 1)
                .accessibilityLabel(sendCodeButtonTitle)
                .accessibilityIdentifier("authSendCodeButton")
            }
        }
    }

    private func inputContainer<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(secondaryInkColor)
                .accessibilityHidden(true)
            content()
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 48)
                .background(fieldBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(accentColor.opacity(colorScheme == .dark ? 0.32 : 0.22), lineWidth: 1)
                )
        }
    }

    private var primaryActionButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                Spacer()
                Text(buttonTitle)
                    .font(.headline)
                if busy {
                    ProgressView()
                        .tint(.white)
                }
                Spacer()
            }
            .padding(.vertical, 6)
            .frame(minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .tint(accentColor)
        .foregroundStyle(Color.white)
        .disabled(busy || sendingCode)
        .accessibilityLabel(busy ? "\(buttonTitle)，正在处理" : buttonTitle)
        .accessibilityIdentifier("authPrimaryButton")
    }

    @ViewBuilder
    private var secondaryActions: some View {
        if mode == .login {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    signupSwitchButton
                    resetSwitchButton
                }
            } else {
                HStack(spacing: 16) {
                    signupSwitchButton
                    Spacer(minLength: 12)
                    resetSwitchButton
                }
            }
        }
        if mode == .signup {
            Button("返回登录", action: { switchMode(.login) })
                .font(.subheadline.weight(.medium))
                .foregroundStyle(accentInkColor)
                .frame(minHeight: 36)
                .accessibilityIdentifier("authBackToLogin")
        }
        if mode == .reset {
            Button("返回登录", action: { switchMode(.login) })
                .font(.subheadline.weight(.medium))
                .foregroundStyle(accentInkColor)
                .frame(minHeight: 36)
                .accessibilityIdentifier("authResetBackToLogin")
        }
    }

    private var signupSwitchButton: some View {
        Button("注册", action: { switchMode(.signup) })
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(accentInkColor)
            .frame(minHeight: 36)
            .accessibilityHint("切换到创建新账号")
            .accessibilityIdentifier("authSwitchToSignup")
    }

    private var resetSwitchButton: some View {
        Button("忘记密码", action: { switchMode(.reset) })
            .font(.subheadline)
            .foregroundStyle(secondaryInkColor)
            .frame(minHeight: 36)
            .accessibilityHint("切换到发送重置密码邮件")
            .accessibilityIdentifier("authSwitchToReset")
    }

    private var appleSignInSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(secondaryInkColor.opacity(0.22))
                    .frame(height: 1)
                Text("或使用其他方式")
                    .font(.caption)
                    .foregroundStyle(secondaryInkColor)
                Rectangle()
                    .fill(secondaryInkColor.opacity(0.22))
                    .frame(height: 1)
            }
            .accessibilityHidden(true)

            SignInWithAppleButton(.signIn, onRequest: { request in
                request.requestedScopes = [.email, .fullName]
            }, onCompletion: handleAppleResult)
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(busy || sendingCode)
            .accessibilityIdentifier("authAppleSignIn")
        }
    }

    private func isInfoMessage(_ message: String) -> Bool {
        store.phase == .needsEmailVerification || message.contains("已发送")
    }

    private func messageBanner(_ message: String) -> some View {
        let info = isInfoMessage(message)
        let tint: Color = info ? accentInkColor : .red
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: info ? "checkmark.circle.fill" : "info.circle.fill")
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(HomeVisualStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: HomeVisualStyle.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HomeVisualStyle.cornerRadius, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("提示：\(message)")
        .accessibilityIdentifier("authErrorMessage")
    }

    private var modeTitle: String {
        mode == .signup ? "创建账号" : mode == .reset ? "设置密码" : "登录"
    }

    private var modeSubtitle: String {
        switch mode {
        case .login:
            return "登录以同步你的课程进度与到期复习计划。"
        case .signup:
            return "填写邮箱与密码，先获取 6 位验证码，再提交注册。"
        case .reset:
            return "输入注册邮箱，我们将向你发送密码重置链接。"
        }
    }

    private var sendCodeButtonTitle: String {
        if sendingCode { return "发送中…" }
        if resendCountdown > 0 { return "\(resendCountdown)s 后重发" }
        return codeSent ? "重新获取" : "获取验证码"
    }

    private var buttonTitle: String {
        mode == .signup ? "提交注册" : mode == .reset ? "发送重置邮件" : "登录"
    }

    private var canvasColor: Color {
        colorScheme == .dark
            ? Color(red: 22.0 / 255, green: 25.0 / 255, blue: 24.0 / 255)
            : HomeVisualStyle.canvas
    }

    private var cardColor: Color {
        colorScheme == .dark
            ? Color(red: 32.0 / 255, green: 36.0 / 255, blue: 34.0 / 255)
            : HomeVisualStyle.card
    }

    private var fieldBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 26.0 / 255, green: 30.0 / 255, blue: 28.0 / 255)
            : HomeVisualStyle.canvas
    }

    private var inkColor: Color {
        colorScheme == .dark
            ? Color(red: 238.0 / 255, green: 240.0 / 255, blue: 237.0 / 255)
            : HomeVisualStyle.ink
    }

    private var secondaryInkColor: Color {
        colorScheme == .dark
            ? Color(red: 168.0 / 255, green: 176.0 / 255, blue: 171.0 / 255)
            : HomeVisualStyle.secondaryInk
    }

    private var accentColor: Color {
        colorScheme == .dark
            ? Color(red: 66.0 / 255, green: 158.0 / 255, blue: 143.0 / 255)
            : HomeVisualStyle.accent
    }

    private var accentInkColor: Color {
        colorScheme == .dark
            ? Color(red: 98.0 / 255, green: 192.0 / 255, blue: 176.0 / 255)
            : HomeVisualStyle.accentInk
    }

    private func switchMode(_ next: Mode) {
        focusedField = nil
        mode = next
        code = ""
        codeSent = false
        resendCountdown = 0
        countdownTask?.cancel()
        store.errorMessage = nil
    }

    private func startResendCountdown() {
        countdownTask?.cancel()
        resendCountdown = 60
        countdownTask = Task {
            while !Task.isCancelled && resendCountdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                await MainActor.run {
                    if resendCountdown > 0 {
                        resendCountdown -= 1
                    }
                }
            }
        }
    }

    private func sendVerificationCode() {
        guard !busy && !sendingCode && resendCountdown == 0 else { return }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty else {
            store.errorMessage = "请输入邮箱地址。"
            focusedField = .email
            return
        }
        guard password.count >= 6 else {
            store.errorMessage = "请先设置至少 6 位密码，再获取验证码。"
            focusedField = .password
            return
        }
        store.errorMessage = nil
        sendingCode = true
        Task {
            await store.signUp(email: normalizedEmail, password: password)
            sendingCode = false
            if store.phase == .needsEmailVerification {
                codeSent = true
                startResendCountdown()
                focusedField = .code
            }
        }
    }

    private func submit() {
        guard !busy && !sendingCode else { return }
        focusedField = nil
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if mode == .signup {
            guard !normalizedEmail.isEmpty else {
                store.errorMessage = "请输入邮箱地址。"
                focusedField = .email
                return
            }
            guard password.count >= 6 else {
                store.errorMessage = "密码至少需要 6 位。"
                focusedField = .password
                return
            }
            guard code.count == 6 else {
                store.errorMessage = "请先获取并输入 6 位数字验证码。"
                focusedField = .code
                return
            }
        }
        busy = true
        Task {
            switch mode {
            case .login:
                await store.signIn(email: normalizedEmail, password: password)
            case .signup:
                await store.verifySignupCode(email: normalizedEmail, code: code)
            case .reset:
                await store.requestPasswordReset(email: normalizedEmail)
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
