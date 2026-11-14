import SwiftUI

struct OnboardingView: View {
    let onFinished: () -> Void
    @State private var page = 0

    private let pages = OnboardingArtwork.names

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                OnboardingArtwork.background.ignoresSafeArea()

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, name in
                        OnboardingImage(name: name)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    if page == pages.count - 1 {
                        onFinished()
                    } else {
                        withAnimation(.easeInOut) { page += 1 }
                    }
                }

                // The artwork carries its own page header, so a native band with a matching
                // background covers it and provides the working page counter and skip control.
                VStack(spacing: 0) {
                    Spacer().frame(height: proxy.safeAreaInsets.top)
                    HStack {
                        Text("\(page + 1) / \(pages.count)")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button("跳过") { onFinished() }
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 10)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.bandHeight(for: proxy), alignment: .top)
                .background(OnboardingArtwork.background)
                .offset(y: -proxy.safeAreaInsets.top)
            }
        }
        .preferredColorScheme(.light)
    }

    /// The band has to reach past the header that is baked into the artwork. The artwork
    /// is scaled to fill the screen, so a fixed share of the screen height is enough.
    private static func bandHeight(for proxy: GeometryProxy) -> CGFloat {
        max(proxy.safeAreaInsets.top + 56, proxy.size.height * 0.15)
    }
}

private struct OnboardingImage: View {
    let name: String

    var body: some View {
        Group {
            if let image = OnboardingArtwork.image(named: name) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                OnboardingArtwork.background
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityLabel("日句首次使用介绍")
    }
}

/// The onboarding artwork ships as loose PNG files in the app bundle.
///
/// SwiftUI's `Image(_ name:)` only looks into the asset catalog and silently renders
/// nothing when the name is not part of it, so the artwork is loaded explicitly from
/// the bundle instead.
enum OnboardingArtwork {
    /// The artwork files that have to be present in the app bundle.
    static let names = ["02-structure", "03-listen", "04-output", "05-feedback"]

    /// The paper colour of the artwork, used for the page background and for the band
    /// that covers the header baked into the artwork.
    static let background = Color(red: 0.961, green: 0.969, blue: 0.945)

    /// Loads one artwork image from the app bundle, or `nil` when it is missing.
    static func image(named name: String) -> UIImage? {
        UIImage(named: name)
    }
}
