import SwiftUI

struct QuestionView: View {
    let question: TextbookQuestion
    let isSubmitted: Bool
    let onSubmit: (String) -> Void
    @State private var selectedOption = ""
    @State private var typedAnswer = ""

    private var isTextInput: Bool { question.type == "翻译" || question.type == "问答" }
    private var answer: String { isTextInput ? typedAnswer : Self.submittedOptionText(selectedOption) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(question.type).font(.subheadline.bold()).foregroundStyle(.secondary)
            Text(question.prompt).font(.title3.bold()).textSelection(.enabled)
            if isTextInput {
                TextField("请输入日语答案", text: $typedAnswer, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...8)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("日语答案")
                    .disabled(isSubmitted)
            } else if let options = question.options, !options.isEmpty {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button { selectedOption = option } label: {
                        HStack(alignment: .top) {
                            Image(systemName: selectedOption == option ? "checkmark.circle.fill" : "circle")
                            Text(option).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(selectedOption == option ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedOption == option ? [.isSelected] : [])
                    .disabled(isSubmitted)
                }
            } else {
                Text("本题缺少选项，暂时无法作答。请返回教材重试。").foregroundStyle(.red)
            }
            if !question.hint.isEmpty {
                DisclosureGroup("查看提示") {
                    Text(question.hint).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Button("提交答案") { onSubmit(answer) }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitted || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    static func submittedOptionText(_ option: String) -> String {
        // app/page.tsx submits slice(2).trim() for both choice and particle options.
        String(option.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
