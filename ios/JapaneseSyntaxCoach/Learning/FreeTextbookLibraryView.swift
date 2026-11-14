import SwiftUI

/// The user-visible state for each free textbook card.
enum FreeTextbookCardState: Equatable {
    case available
    case downloading
    case downloaded
    case failed(String)

    var actionTitle: String {
        switch self {
        case .available: return "免费下载"
        case .downloading: return "下载中…"
        case .downloaded: return "继续学习"
        case .failed: return "重试"
        }
    }

    var isActionDisabled: Bool {
        if case .downloading = self { return true }
        return false
    }
}

struct FreeTextbookCardPresentation: Equatable {
    let id: String
    let title: String
    let lessonCount: Int
    let questionCount: Int
    let freeLabel: String
    let actionTitle: String
    let isActionDisabled: Bool

    /// Text values fed into the card's visible labels and action. Keeping this derived
    /// from the rendered fields makes policy checks exercise the actual UI copy.
    var renderedTexts: [String] {
        [
            title,
            freeLabel,
            "\(lessonCount) 课",
            "\(questionCount) 题",
            actionTitle
        ]
    }

    static func make(descriptor: FreeTextbookDescriptor, state: FreeTextbookCardState) -> Self {
        Self(
            id: descriptor.id,
            title: descriptor.title,
            lessonCount: descriptor.lessonCount,
            questionCount: descriptor.questionCount,
            freeLabel: "免费教材",
            actionTitle: state.actionTitle,
            isActionDisabled: state.isActionDisabled
        )
    }
}

struct FreeTextbookLibraryView: View {
    @ObservedObject var store: LearningStore
    let downloadStore: DownloadedTextbookStore
    @State private var cardStates: [String: FreeTextbookCardState]

    init(store: LearningStore, downloadStore: DownloadedTextbookStore = DownloadedTextbookStore()) {
        self.store = store
        self.downloadStore = downloadStore
        _cardStates = State(initialValue: Dictionary(
            uniqueKeysWithValues: FreeTextbookCatalog.items.map { descriptor in
                (descriptor.id, downloadStore.contains(id: descriptor.id) ? .downloaded : .available)
            }
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HomeVisualStyle.sectionSpacing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("免费教材库")
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("下载后即可离线学习，所有教材内容免费开放。")
                        .font(.subheadline)
                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                }

                LazyVStack(spacing: 14) {
                    ForEach(FreeTextbookCatalog.items) { descriptor in
                        freeTextbookCard(descriptor)
                    }
                }
            }
            .padding(HomeVisualStyle.screenPadding)
        }
        .homeScreenChrome()
        .navigationTitle("教材库")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func freeTextbookCard(_ descriptor: FreeTextbookDescriptor) -> some View {
        let state = cardStates[descriptor.id] ?? .available
        let presentation = FreeTextbookCardPresentation.make(descriptor: descriptor, state: state)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                textbookBadge(descriptor)

                VStack(alignment: .leading, spacing: 6) {
                    Text(presentation.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(HomeVisualStyle.ink)
                        .multilineTextAlignment(.leading)
                    Text(presentation.freeLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeVisualStyle.accentInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(HomeVisualStyle.mint, in: Capsule())
                        .accessibilityIdentifier("freeTextbookLabel-\(descriptor.id)")
                }

                Spacer(minLength: 4)
            }

            HStack(spacing: 12) {
                Label("\(presentation.lessonCount) 课", systemImage: "book.closed")
                Label("\(presentation.questionCount) 题", systemImage: "checkmark.circle")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(HomeVisualStyle.secondaryInk)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(presentation.lessonCount) 课，\(presentation.questionCount) 题")

            if case .failed(let message) = state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("freeTextbookError-\(descriptor.id)")
            }

            HStack(spacing: 10) {
                Button {
                    handleAction(for: descriptor)
                } label: {
                    HStack(spacing: 6) {
                        if case .downloading = state {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(presentation.actionTitle)
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(HomeVisualStyle.accent)
                .disabled(presentation.isActionDisabled)
                .accessibilityIdentifier("freeTextbookAction-\(descriptor.id)")
                .accessibilityLabel(state.actionTitle + "：" + descriptor.title)

                if case .downloading = state {
                    Text("正在准备教材")
                        .font(.caption)
                        .foregroundStyle(HomeVisualStyle.secondaryInk)
                        .accessibilityIdentifier("freeTextbookDownloading-\(descriptor.id)")
                }
            }
        }
        .homeCardStyle(borderColor: HomeVisualStyle.accent.opacity(0.2))
        .accessibilityIdentifier("freeTextbookCard-\(descriptor.id)")
    }

    private func textbookBadge(_ descriptor: FreeTextbookDescriptor) -> some View {
        VStack(spacing: 2) {
            Text("日语")
                .font(.caption2.weight(.bold))
            Text(descriptor.shortTitle.replacingOccurrences(of: "新标日 ", with: ""))
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(HomeVisualStyle.accentInk)
        .frame(width: 62, height: 72)
        .background(HomeVisualStyle.mint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(HomeVisualStyle.accent.opacity(0.18), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private func handleAction(for descriptor: FreeTextbookDescriptor) {
        let state = cardStates[descriptor.id] ?? .available
        guard !state.isActionDisabled else { return }

        if case .downloaded = state {
            store.activateTextbook(id: descriptor.id)
            return
        }

        cardStates[descriptor.id] = .downloading
        Task { @MainActor in
            do {
                let package = try TextbookRepository.loadBundled(id: descriptor.id)
                try downloadStore.save(package)
                store.activateTextbook(id: descriptor.id)
                cardStates[descriptor.id] = .downloaded
            } catch {
                cardStates[descriptor.id] = .failed("下载失败，请重试。")
            }
        }
    }
}
