import Foundation

struct WordToken: Identifiable, Equatable {
    let id: String
    let text: String
}

enum WordTokenizer {
    private static let patterns = ["なければなりません", "なくてもいいです", "ないでください", "ではありません", "ませんでした", "かもしれません", "ことができます", "たことがあります", "たほうがいい", "と思います", "ましょうか", "ています", "ください", "ましょう", "でしょう", "ですか", "ました", "ません", "です"].map { Array($0.utf16) }
    private static let particles = ["から", "まで", "は", "が", "を", "に", "で", "と", "の", "も", "へ", "か"].map { Array($0.utf16) }
    private static let words = ["かばん", "かぎ", "もう", "もちろん", "もらいます", "もらいました", "できます", "います", "とき", "とても", "にぎやか", "もの", "はい", "売り場", "銀行", "郵便局", "デパート", "会社", "学校", "駅"].map { Array($0.utf16) }
    private static let punctuation = Set("。！？!?、，．.".utf16)

    static func tokenize(_ answer: String) -> [String] {
        let units = Array(answer.utf16)
        func match(_ list: [[UInt16]], at index: Int) -> [UInt16]? {
            list.first { units[index...].starts(with: $0) }
        }
        var result: [String] = []
        var index = 0
        while index < units.count {
            if punctuation.contains(units[index]) {
                index += 1
            } else if let token = match(words, at: index) ?? match(patterns, at: index) ?? match(particles, at: index) {
                result.append(String(decoding: token, as: UTF16.self))
                index += token.count
            } else {
                var end = index + 1
                while end < units.count && match(particles, at: end) == nil && !punctuation.contains(units[end]) && match(patterns, at: end) == nil {
                    end += 1
                }
                result.append(String(decoding: units[index..<end], as: UTF16.self))
                index = end
            }
        }
        return result
    }

    static func order(_ id: String) -> UInt32 {
        id.utf16.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
    }

    static func create(questionID: String, answer: String) -> [WordToken] {
        tokenize(answer).enumerated().map { index, text in
            WordToken(id: "\(questionID)-T\(String(format: "%02d", index + 1))", text: text)
        }.enumerated().sorted {
            let left = order($0.element.id), right = order($1.element.id)
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
    }
}

struct WordTokenSelection {
    private(set) var selected: [WordToken] = []
    var answer: String { selected.map(\.text).joined() }
    func contains(id: String) -> Bool { selected.contains { $0.id == id } }
    mutating func add(_ token: WordToken) {
        guard !contains(id: token.id) else { return }
        selected.append(token)
    }
    mutating func remove(id: String) { selected.removeAll { $0.id == id } }
    mutating func clear() { selected.removeAll() }
}
