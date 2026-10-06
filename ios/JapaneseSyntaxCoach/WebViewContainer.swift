import SwiftUI
import UIKit
import WebKit

struct WebViewContainer: UIViewRepresentable {
    let storeKit: StoreKitManager
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    @Binding var reloadToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(storeKit: storeKit, isLoading: $isLoading, errorMessage: $errorMessage)
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        let marker = WKUserScript(
            source: "window.__SYNTAX_COACH_IOS__ = true;",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        controller.addUserScript(marker)
        controller.add(context.coordinator, name: "syntaxCoach")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        context.coordinator.webView = webView
        webView.load(URLRequest(url: AppConfiguration.webURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.reloadToken != reloadToken {
            context.coordinator.reloadToken = reloadToken
            webView.reload()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let storeKit: StoreKitManager
        let isLoading: Binding<Bool>
        let errorMessage: Binding<String?>
        weak var webView: WKWebView?
        var reloadToken = 0

        init(storeKit: StoreKitManager, isLoading: Binding<Bool>, errorMessage: Binding<String?>) {
            self.storeKit = storeKit
            self.isLoading = isLoading
            self.errorMessage = errorMessage
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "syntaxCoach", webView?.url?.host == AppConfiguration.webURL.host,
                  let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String else { return }

            switch type {
            case "purchase":
                guard let productID = payload["productID"] as? String,
                      AppConfiguration.productIDs.contains(productID),
                      let userID = payload["userID"] as? String else { return }
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    let result = await storeKit.purchase(productID: productID, userID: userID)
                    send(result, callback: "__syntaxCoachApplePurchaseResult")
                }
            case "restore":
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    let results = await storeKit.restorePurchases()
                    results.forEach { send($0, callback: "__syntaxCoachAppleRestoreResult") }
                }
            case "manageSubscriptions":
                guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
                UIApplication.shared.open(url)
            default:
                break
            }
        }

        private func send(_ result: StoreKitResult, callback: String) {
            guard let data = try? JSONEncoder().encode(result),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView?.evaluateJavaScript("window.\(callback) && window.\(callback)(\(json));")
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading.wrappedValue = true
            errorMessage.wrappedValue = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading.wrappedValue = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading.wrappedValue = false
            errorMessage.wrappedValue = "网络连接失败，请检查网络后重试。"
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isLoading.wrappedValue = false
            errorMessage.wrappedValue = "无法打开学习页面，请稍后重试。"
        }
    }
}
