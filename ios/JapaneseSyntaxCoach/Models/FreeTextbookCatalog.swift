import Foundation

struct FreeTextbookDescriptor: Identifiable {
    let id: String
    let title: String
    let shortTitle: String
    let lessonCount: Int
    let questionCount: Int
    let resourceName: String
}

enum FreeTextbookCatalog {
    static let items: [FreeTextbookDescriptor] = [
        FreeTextbookDescriptor(id: "shin-standard-japanese-beginner-lower", title: "新版标准日本语 初级下册", shortTitle: "新标日 初级下", lessonCount: 24, questionCount: 480, resourceName: "shin-standard-japanese-beginner-lower"),
        FreeTextbookDescriptor(id: "shin-standard-japanese-intermediate-upper", title: "新版标准日本语 中级上册", shortTitle: "新标日 中级上", lessonCount: 16, questionCount: 320, resourceName: "shin-standard-japanese-intermediate-upper"),
        FreeTextbookDescriptor(id: "shin-standard-japanese-intermediate-lower", title: "新版标准日本语 中级下册", shortTitle: "新标日 中级下", lessonCount: 16, questionCount: 320, resourceName: "shin-standard-japanese-intermediate-lower")
    ]
}
