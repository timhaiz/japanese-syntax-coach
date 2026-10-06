import SwiftUI

struct OnboardingView: View {
    let onFinished: () -> Void
    @State private var page = 0

    private let pages = [
        "02-structure",
        "03-listen",
        "04-output",
        "05-feedback"
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    TabView(selection: $page) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, name in
                            OnboardingImage(name: name)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if page == pages.count - 1 {
                            onFinished()
                        } else {
                            withAnimation(.easeInOut) { page += 1 }
                        }
                    }

                    HStack(spacing: 7) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Capsule()
                                .fill(index == page ? Color.primary : Color.secondary.opacity(0.25))
                                .frame(width: index == page ? 20 : 7, height: 7)
                        }
                    }
                    .padding(.bottom, max(12, proxy.safeAreaInsets.bottom))
                }

                VStack {
                    HStack {
                        Text("\(page + 1) / 4")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button("跳过") { onFinished() }
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, max(12, proxy.safeAreaInsets.top + 4))
                    Spacer()
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

private struct OnboardingImage: View {
    let name: String

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .accessibilityLabel("日句首次使用介绍")
    }
}
