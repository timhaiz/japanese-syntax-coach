import XCTest
@testable import JapaneseSyntaxCoach

final class AdEligibilityTests: XCTestCase {
    func testProMembershipDisablesAds() {
        let membership = MembershipState(
            authenticated: true,
            status: .member,
            isMember: true,
            endsAt: "2099-01-01T00:00:00Z"
        )

        XCTAssertEqual(AdEligibility.resolve(membership: membership), .noAds)
        XCTAssertFalse(AdEligibility.resolve(membership: membership).shouldShowAds)
    }

    func testFreeOrUnknownMembershipAllowsAds() {
        let freeMembership = MembershipState(
            authenticated: true,
            status: .free,
            isMember: false,
            endsAt: nil
        )

        XCTAssertEqual(AdEligibility.resolve(membership: nil), .adsAllowed)
        XCTAssertEqual(AdEligibility.resolve(membership: freeMembership), .adsAllowed)
        XCTAssertTrue(AdEligibility.resolve(membership: nil).shouldShowAds)
    }

    func testUnknownMembershipStatusAllowsAds() {
        XCTAssertEqual(AdEligibility.resolve(membership: .unknown), .adsAllowed)
    }
}
