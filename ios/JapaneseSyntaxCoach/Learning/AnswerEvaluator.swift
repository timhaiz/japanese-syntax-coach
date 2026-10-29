import Foundation

enum AnswerEvaluator {
    static func normalizeAnswer(_ value: String) -> String {
        String(value.filter { !isIgnored($0) })
    }

    private static func isIgnored(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar) || "。！？!?，,、．.".unicodeScalars.contains(scalar)
        }
    }

    static func evaluate(question: TextbookQuestion, answer: String) -> LocalEvaluation {
        let normalizedAnswer = normalizeAnswer(answer)
        var variants = [question.answer] + (question.acceptedAnswers ?? [])
        if question.answer.contains("ではありません") {
            variants.append(question.answer.replacingOccurrences(of: "ではありません", with: "じゃありません"))
        }
        if question.answer.contains("ではありませんでした") {
            variants.append(question.answer.replacingOccurrences(of: "ではありませんでした", with: "じゃありませんでした"))
        }
        if question.answer.contains("くないです") {
            variants.append(question.answer.replacingOccurrences(of: "くないです", with: "くありません"))
        }
        // lib/question-bank.ts:523 replaces the full seven-character polite negative past.
        // Keep each variant independent, including the overlapping ではありません checks.
        if question.answer.contains("くなかったです") {
            variants.append(question.answer.replacingOccurrences(of: "くなかったです", with: "くありませんでした"))
        }

        let accepted = variants.contains { normalizeAnswer($0) == normalizedAnswer }
        let expected = expectedAnswer(for: question)
        let verdict: String
        if accepted {
            verdict = "correct"
        } else {
            let expectedNormalized = normalizeAnswer(question.answer)
            // Website spreads expected code points but indexes actual UTF-16 units.
            let actualUnits = Array(normalizedAnswer.utf16)
            let expectedCharacters = Array(expectedNormalized.unicodeScalars)
            let shared = expectedCharacters.isEmpty || actualUnits.isEmpty
                ? 0.0
                : Double(expectedCharacters.enumerated().filter { index, character in
                    index < actualUnits.count && character.value == UInt32(actualUnits[index])
                }.count) / Double(max(expectedNormalized.utf16.count, actualUnits.count))
            verdict = shared >= 0.55 ? "needs_fix" : "incorrect"
        }

        let errors = accepted ? [] : errorTags(question: question, actual: answer)
        let feedback: String
        if accepted {
            feedback = "句型结构正确，继续保持主动输出。"
        } else if question.options != nil {
            feedback = "你选择了「\(answer)」，正确选项是「\(expected)」。"
        } else {
            feedback = explainDifference(expected: expected, actual: answer)
        }

        return LocalEvaluation(
            verdict: verdict,
            isCorrect: accepted,
            expectedAnswer: expected,
            feedback: feedback,
            errorTags: errors,
            knowledgeTags: knowledgeTags(question: question)
        )
    }

    static func expectedAnswer(for question: TextbookQuestion) -> String {
        guard let option = question.options?.first(where: { $0.hasPrefix("\(question.answer)：") }) else {
            return question.answer
        }
        return String(option.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func errorTags(question: TextbookQuestion, actual: String) -> [String] {
        if question.type == "助词" { return ["助词"] }
        let expected = question.answer
        if expected.contains("ですか") && actual.contains("でか") { return ["假名"] }
        if expected.contains("ではありません") && actual.contains("でわありません") { return ["假名"] }
        if ["なければ", "なくても", "ないで", "ています", "ました", "ません"].contains(where: expected.contains) {
            return ["活用"]
        }
        if actual.utf16.count != expected.utf16.count { return ["词汇"] }
        return ["句型顺序"]
    }

    static func knowledgeTags(question: TextbookQuestion) -> [String] {
        var tags: [String] = []
        if question.type == "助词" || question.hint.contains("助词") { tags.append("助词") }
        if ["活用", "否定", "过去", "变化", "ます形", "て形"].contains(where: question.hint.contains) { tags.append("活用") }
        if ["假名", "拼写", "词汇"].contains(where: question.hint.contains) { tags.append("词汇") }
        return tags.isEmpty ? ["句型"] : tags
    }

    private static func explainDifference(expected: String, actual: String) -> String {
        let expectedClean = normalizeAnswer(expected)
        let actualClean = normalizeAnswer(actual)
        if expectedClean == actualClean { return "句型和词语正确。" }
        if expected.contains("ですか") && actual.contains("でか") {
            return "句尾疑问形式错误：你写成了「でか」，应为完整的「ですか」（缺少「す」）。"
        }
        if expected.contains("ではありません") && actual.contains("でわありません") {
            return "否定形式的假名错误：「でわ」应写作「では」。"
        }
        let expectedChars = Array(expectedClean)
        let actualChars = Array(actualClean)
        let limit = min(expectedChars.count, actualChars.count)
        var index = 0
        while index < limit && expectedChars[index] == actualChars[index] { index += 1 }
        if index < limit {
            return "第 \(index + 1) 个字有误：你写的是「\(actualChars[index])」，应为「\(expectedChars[index])」。"
        }
        if actualChars.count < expectedChars.count {
            return "答案少了内容：第 \(actualChars.count + 1) 个字应为「\(expectedChars[actualChars.count])」，请检查是否漏写。"
        }
        if actualChars.count > expectedChars.count {
            return "答案多了内容：请检查第 \(expectedChars.count + 1) 个字「\(actualChars[expectedChars.count])」附近。"
        }
        return "请逐字对照参考答案，检查助词、活用和句尾形式。"
    }
}
