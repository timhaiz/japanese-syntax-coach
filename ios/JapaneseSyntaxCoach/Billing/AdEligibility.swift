import SwiftUI

/// Controls whether a future ad placement may be considered for the current membership.
enum AdEligibility: Equatable {
    case noAds
    case adsAllowed

    static func resolve(membership: MembershipState?) -> AdEligibility {
        guard let membership, membership.status == .member, membership.isMember else {
            return .adsAllowed
        }
        return .noAds
    }

    var shouldShowAds: Bool {
        self == .adsAllowed
    }
}

private struct AdEligibilityKey: EnvironmentKey {
    static let defaultValue: AdEligibility = .adsAllowed
}

extension EnvironmentValues {
    var adEligibility: AdEligibility {
        get { self[AdEligibilityKey.self] }
        set { self[AdEligibilityKey.self] = newValue }
    }
}

/// Non-blocking future ad boundary. There is no ad SDK wired into this target yet.
struct AdPlacementBoundary: View {
    let eligibility: AdEligibility

    var body: some View {
        if eligibility.shouldShowAds {
            Color.clear
                .frame(height: 0)
                .accessibilityHidden(true)
        }
    }
}
