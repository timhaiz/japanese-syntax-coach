import XCTest
@testable import JapaneseSyntaxCoach

/// The onboarding artwork ships as loose PNG files in the app bundle.
///
/// SwiftUI's `Image(_ name:)` only searches the asset catalog and silently renders
/// nothing when the name is not part of it, so the first-launch onboarding used to be a
/// blank screen. These tests keep the artwork loadable from the bundle.
final class OnboardingArtworkTests: XCTestCase {
    func testEveryOnboardingArtworkIsPresentInTheAppBundle() {
        for name in OnboardingArtwork.names {
            XCTAssertNotNil(
                Bundle.main.url(forResource: name, withExtension: "png"),
                "\(name).png is missing from the app bundle"
            )
        }
    }

    func testEveryOnboardingArtworkCanBeLoaded() {
        for name in OnboardingArtwork.names {
            let image = OnboardingArtwork.image(named: name)
            XCTAssertNotNil(image, "\(name) cannot be loaded from the app bundle")
            XCTAssertGreaterThan(image?.size.width ?? 0, 0, "\(name) has no usable size")
            XCTAssertGreaterThan(image?.size.height ?? 0, 0, "\(name) has no usable size")
        }
    }

    func testOnboardingHasFourDistinctPages() {
        XCTAssertEqual(OnboardingArtwork.names.count, 4)
        XCTAssertEqual(Set(OnboardingArtwork.names).count, OnboardingArtwork.names.count)
    }
}
