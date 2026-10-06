import SwiftUI

struct ContentView: View {
    @ObservedObject var storeKit: StoreKitManager
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var reloadToken = 0

    var body: some View {
        ZStack {
            WebViewContainer(
                storeKit: storeKit,
                isLoading: $isLoading,
                errorMessage: $errorMessage,
                reloadToken: $reloadToken
            )

            if isLoading {
                ProgressView("正在打开日句…")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }

            if let errorMessage {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 30))
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                    Button("重新加载") {
                        self.errorMessage = nil
                        reloadToken += 1
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .padding(28)
            }
        }
        .preferredColorScheme(.light)
    }
}
