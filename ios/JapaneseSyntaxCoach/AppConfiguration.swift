import Foundation

enum AppConfiguration {
    static let webURL = URL(string: "https://japanese-syntax-coach.vercel.app/")!
    static let monthlyProductID = "com.juxintong.nihongo.monthly"
    static let yearlyProductID = "com.juxintong.nihongo.yearly"
    static let productIDs: Set<String> = [monthlyProductID, yearlyProductID]
}
