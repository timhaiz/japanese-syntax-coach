import SwiftUI

struct QuestionView: View {
    let question: TextbookQuestion
    let isSubmitted: Bool
    let onSubmit: (String) -> Void
    @AppStorage("nihongo.kana.enabled") private var showKana = true
    @State private var selectedOption = ""
    @State private var tokenSelection = WordTokenSelection()

    private var isTokenQuestion: Bool { question.type == "翻译" || question.type == "问答" }
    private var answer: String { isTokenQuestion ? tokenSelection.answer : Self.submittedOptionText(selectedOption) }
    private var candidates: [WordToken] { WordTokenizer.create(questionID: question.id, answer: question.answer) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(question.type)
                .font(.caption.weight(.semibold))
                .foregroundStyle(HomeVisualStyle.accentInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(HomeVisualStyle.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(WordTokenReadings.annotate(question.prompt, enabled: showKana))
                .font(.title3.bold())
                .foregroundStyle(HomeVisualStyle.ink)
                .textSelection(.enabled)

            if isTokenQuestion {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("已选答案").font(.subheadline.weight(.medium))
                        Spacer()
                        Button("清空") { tokenSelection.clear() }
                            .disabled(isSubmitted || tokenSelection.selected.isEmpty)
                    }
                    .foregroundStyle(HomeVisualStyle.secondaryInk)
                    if tokenSelection.selected.isEmpty {
                        Text("点击下方词块组成答案")
                            .font(.subheadline)
                            .foregroundStyle(HomeVisualStyle.secondaryInk)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    } else {
                        WordTokenFlowLayout {
                            ForEach(tokenSelection.selected) { token in
                                tokenButton(token, selected: true) { tokenSelection.remove(id: token.id) }
                                    .disabled(isSubmitted)
                                    .accessibilityLabel("移除词块 \(token.text)")
                            }
                        }
                    }
                    WordTokenFlowLayout {
                        ForEach(candidates) { token in
                            let selected = tokenSelection.contains(id: token.id)
                            tokenButton(token, selected: false) { tokenSelection.add(token) }
                                .opacity(selected ? 0 : 1)
                                .disabled(isSubmitted || selected)
                                .accessibilityLabel(token.text)
                                .accessibilityHidden(selected)
                        }
                    }
                    .accessibilityLabel("候选词块")
                }
            } else if let options = question.options, !options.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                        let isSelected = selectedOption == option
                        Button {
                            selectedOption = option
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? HomeVisualStyle.accent : HomeVisualStyle.secondaryInk)
                                Text(WordTokenReadings.annotate(option, enabled: showKana))
                                    .font(.body)
                                    .foregroundStyle(HomeVisualStyle.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(isSelected ? HomeVisualStyle.accent.opacity(0.12) : HomeVisualStyle.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        isSelected ? HomeVisualStyle.accent : HomeVisualStyle.accent.opacity(0.14),
                                        lineWidth: isSelected ? 1.5 : 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                        .disabled(isSubmitted)
                    }
                }
            } else {
                Text("本题缺少选项，暂时无法作答。请返回教材重试。")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            if !question.hint.isEmpty {
                DisclosureGroup("查看提示") {
                    Text(question.hint)
                        .font(.subheadline)
                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                        .padding(.top, 4)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(HomeVisualStyle.accentInk)
                .tint(HomeVisualStyle.accent)
            }

            Button {
                onSubmit(answer)
            } label: {
                Text("提交答案")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeVisualStyle.card)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(HomeVisualStyle.accent)
            .disabled(isSubmitted || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .homeCardStyle()
    }

    private func tokenButton(_ token: WordToken, selected: Bool, action: @escaping () -> Void) -> some View {
        let kanaSuffix = WordTokenReadings.kana(for: token.text, enabled: showKana)
        return Button(action: action) {
            (Text(token.text).font(.body) + Text(kanaSuffix).font(.caption))
                .foregroundStyle(HomeVisualStyle.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(selected ? HomeVisualStyle.accent.opacity(0.12) : HomeVisualStyle.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(HomeVisualStyle.accent.opacity(0.3)))
        }
        .buttonStyle(.plain)
    }

    static func submittedOptionText(_ option: String) -> String {
        // app/page.tsx submits slice(2).trim() for both choice and particle options.
        String(option.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
