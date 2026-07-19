import AppKit
import SwiftUI

struct CoachConversationMessageView: View {
    @Environment(\.feedbackTextScale) private var textScale
    let message: CoachConversationMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 28)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(message.role == .user ? "You" : "Codex")
                    .font(scaledFeedbackFont(10, scale: textScale, weight: .bold))
                    .foregroundStyle(message.role == .user ? Theme.primary : Theme.accent)

                renderedText
                    .font(scaledFeedbackFont(13, scale: textScale))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(9)
            .frame(maxWidth: message.role == .user ? 300 : .infinity, alignment: .leading)
            .background(message.role == .user ? Theme.primary.opacity(0.10) : Theme.panel.opacity(0.86))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if message.role == .assistant {
                Spacer(minLength: 0)
            }
        }
    }

    private var renderedText: Text {
        if let attributed = try? AttributedString(markdown: message.text) {
            return Text(attributed)
        }
        return Text(message.text)
    }
}
struct CoachFeedbackView: View, Equatable {
    let markdown: String
    let textScale: CGFloat

    static func == (lhs: CoachFeedbackView, rhs: CoachFeedbackView) -> Bool {
        lhs.markdown == rhs.markdown && lhs.textScale == rhs.textScale
    }

    private var sections: [CoachFeedbackSection] {
        CoachFeedbackParser.parse(CoachFeedbackSanitizer.clean(markdown))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: section.icon)
                            .font(scaledFeedbackFont(13, scale: textScale, weight: .bold))
                            .foregroundStyle(section.tint)
                            .frame(width: 24, height: 24)
                            .background(section.tint.opacity(0.13))
                            .clipShape(RoundedRectangle(cornerRadius: 7))

                        Text(section.title)
                            .font(scaledFeedbackFont(15, scale: textScale, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(section.items) { item in
                            CoachFeedbackItemRow(item: item, tint: section.tint, textScale: textScale)
                        }
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.panel.opacity(0.78))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.border.opacity(0.75))
                )
            }
        }
    }
}

struct CoachFeedbackItemRow: View {
    let item: CoachFeedbackItem
    let tint: Color
    let textScale: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch item.kind {
            case .bullet:
                Circle()
                    .fill(tint.opacity(0.78))
                    .frame(width: 5, height: 5)
            case .numbered(let number):
                Text("\(number)")
                    .font(scaledFeedbackFont(10, scale: textScale, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(tint)
                    .clipShape(Circle())
            case .paragraph:
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 5, height: 5)
            }

            markdownText(item.text)
                .font(scaledFeedbackFont(item.isParagraph ? 14 : 13, scale: textScale))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func markdownText(_ text: String) -> Text {
        if let attributed = try? AttributedString(markdown: text) {
            return Text(attributed)
        }
        return Text(text)
    }
}

struct CoachFeedbackSection: Identifiable {
    let id: String
    var title: String
    var items: [CoachFeedbackItem]

    var icon: String {
        switch title {
        case let value where value.contains("核心") || value.contains("判断") || value.contains("结果"):
            return "scalemass"
        case let value where value.contains("参考句"):
            return "text.magnifyingglass"
        case let value where value.contains("原句"):
            return "quote.opening"
        case let value where value.contains("重构") || value.contains("你的表达"):
            return "person.wave.2"
        case let value where value.contains("差异") || value.contains("用词"):
            return "arrow.left.arrow.right"
        case let value where value.contains("读成"):
            return "ear"
        case let value where value.contains("句意") || value.contains("语块"):
            return "text.quote"
        case let value where value.contains("漏记") || value.contains("记成"):
            return "brain.head.profile"
        case let value where value.contains("记忆"):
            return "link"
        case let value where value.contains("重说"):
            return "arrow.clockwise"
        case let value where value.contains("改"):
            return "wrench.and.screwdriver"
        case let value where value.contains("下一"):
            return "figure.walk.motion"
        default:
            return "sparkles"
        }
    }

    var tint: Color {
        switch title {
        case let value where value.contains("核心") || value.contains("判断") || value.contains("结果"):
            return Theme.accent
        case let value where value.contains("参考句"):
            return Theme.warning
        case let value where value.contains("差异") || value.contains("用词") || value.contains("读成"):
            return Color(red: 0.78, green: 0.48, blue: 0.12)
        case let value where value.contains("记成") || value.contains("记忆"):
            return Color(red: 0.45, green: 0.32, blue: 0.76)
        case let value where value.contains("改"):
            return Theme.danger
        case let value where value.contains("下一") || value.contains("重说"):
            return Theme.success
        default:
            return Theme.primary
        }
    }
}

struct CoachFeedbackItem: Identifiable {
    enum Kind: Equatable {
        case paragraph
        case bullet
        case numbered(Int)
    }

    let id: String
    var kind: Kind
    var text: String

    var isParagraph: Bool {
        if case .paragraph = kind {
            return true
        }
        return false
    }
}

enum CoachFeedbackParser {
    static func parse(_ markdown: String) -> [CoachFeedbackSection] {
        var sections: [CoachFeedbackSection] = []
        var currentTitle = "Coach"
        var currentItems: [CoachFeedbackItem] = []

        func flush() {
            guard !currentItems.isEmpty else { return }
            sections.append(
                CoachFeedbackSection(
                    id: "section-\(sections.count)",
                    title: currentTitle,
                    items: currentItems
                )
            )
            currentItems = []
        }

        func appendItem(kind: CoachFeedbackItem.Kind, text: String) {
            currentItems.append(
                CoachFeedbackItem(
                    id: "section-\(sections.count)-item-\(currentItems.count)",
                    kind: kind,
                    text: text
                )
            )
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("##") {
                flush()
                currentTitle = line
                    .replacingOccurrences(of: "#", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                appendItem(kind: .bullet, text: String(line.dropFirst(2)))
                continue
            }

            if let numbered = numberedItem(from: line) {
                appendItem(kind: numbered.kind, text: numbered.text)
                continue
            }

            appendItem(kind: .paragraph, text: line)
        }

        flush()
        if sections.isEmpty {
            return [
                CoachFeedbackSection(
                    id: "section-0",
                    title: "Coach",
                    items: [CoachFeedbackItem(id: "section-0-item-0", kind: .paragraph, text: markdown)]
                )
            ]
        }
        return sections
    }

    private static func numberedItem(from line: String) -> CoachFeedbackItem? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let prefix = String(line[..<dotIndex])
        guard let number = Int(prefix), number > 0 else { return nil }
        let textStart = line.index(after: dotIndex)
        let text = line[textStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return CoachFeedbackItem(id: "temporary", kind: .numbered(number), text: text)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(color.opacity(configuration.isPressed ? 0.82 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct InteractiveSentenceView: View {
    @EnvironmentObject private var coach: SpeechCoach
    let text: String
    let fontSize: CGFloat
    @State private var selectedTokenIDs: Set<Int> = []
    @State private var tokenFrames: [Int: CGRect] = [:]
    @State private var selectionStart: CGPoint?
    @State private var selectionCurrent: CGPoint?

    private var tokens: [SentenceLookupToken] {
        SentenceLookupToken.tokenize(text)
    }

    private var selectedPhrase: String {
        tokens
            .filter { selectedTokenIDs.contains($0.id) && $0.isWordLike }
            .sorted(by: { $0.id < $1.id })
            .map(\.text)
            .joined(separator: " ")
    }

    private var definition: String? {
        guard selectedTokenIDs.count == 1, !selectedPhrase.isEmpty else { return nil }
        return coach.lookupSummary.isEmpty ? nil : coach.lookupSummary
    }

    private var selectionRect: CGRect? {
        guard let selectionStart, let selectionCurrent else { return nil }
        return CGRect(
            x: min(selectionStart.x, selectionCurrent.x),
            y: min(selectionStart.y, selectionCurrent.y),
            width: abs(selectionStart.x - selectionCurrent.x),
            height: abs(selectionStart.y - selectionCurrent.y)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topLeading) {
                TokenFlowLayout(spacing: 8, rowSpacing: 8) {
                    ForEach(tokens) { token in
                        Text(token.text)
                            .font(.system(size: fontSize, weight: token.isWordLike ? .semibold : .regular, design: .rounded))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(token.isWordLike ? .primary : .secondary)
                            .padding(.horizontal, token.isWordLike ? 9 : 2)
                            .padding(.vertical, 6)
                            .background(selectedTokenIDs.contains(token.id) ? Theme.primary.opacity(0.14) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .contentShape(RoundedRectangle(cornerRadius: 7))
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: TokenFramePreferenceKey.self,
                                        value: [token.id: proxy.frame(in: .named("sentenceTokenSelection"))]
                                    )
                                }
                            )
                            .onTapGesture {
                                toggle(token)
                            }
                    }
                }
                .onPreferenceChange(TokenFramePreferenceKey.self) { frames in
                    tokenFrames = frames
                }

                if let selectionRect, selectionRect.width > 3, selectionRect.height > 3 {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.primary.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Theme.primary.opacity(0.55), lineWidth: 1)
                        )
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .offset(x: selectionRect.minX, y: selectionRect.minY)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "sentenceTokenSelection")
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .named("sentenceTokenSelection"))
                    .onChanged { value in
                        if selectionStart == nil {
                            selectionStart = value.startLocation
                        }
                        selectionCurrent = value.location
                        updateBoxSelection()
                    }
                    .onEnded { _ in
                        selectionStart = nil
                        selectionCurrent = nil
                        updateLookupForCurrentSelection()
                    }
            )

            if !selectedPhrase.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(selectedPhrase)
                            .font(.callout.weight(.semibold))
                            .lineLimit(2)
                        Spacer()
                        Button {
                            selectedTokenIDs.removeAll()
                            coach.clearPhraseLookup()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }

                    if let definition, !definition.isEmpty {
                        ScrollView {
                            DictionaryResultView(text: definition)
                        }
                        .frame(maxHeight: 140)
                    } else {
                        Text(selectedTokenIDs.count == 1 ? "Looking up word..." : "Phrase selected.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if selectedTokenIDs.count > 1 {
                        HStack {
                            Button {
                                coach.translatePhrase(selectedPhrase)
                            } label: {
                                Label(coach.isTranslatingPhrase ? "Translating" : "Translate", systemImage: "character.book.closed")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(coach.isTranslatingPhrase)

                            Button {
                                copyToClipboard(selectedPhrase)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }

                    if !coach.phraseTranslation.isEmpty {
                        ScrollView {
                            Text(coach.phraseTranslation)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(.trailing, 4)
                        }
                        .frame(maxHeight: 180)
                        .padding(.top, 2)
                    }
                }
                .padding(12)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.border)
                )
            }
        }
    }

    private func toggle(_ token: SentenceLookupToken) {
        guard token.isWordLike else { return }
        if selectedTokenIDs.contains(token.id) {
            selectedTokenIDs.remove(token.id)
        } else {
            selectedTokenIDs.insert(token.id)
        }
        coach.clearPhraseLookup()
        updateLookupForCurrentSelection()
    }

    private func updateBoxSelection() {
        guard let selectionRect else { return }
        let selected = tokens.compactMap { token -> Int? in
            guard token.isWordLike, let frame = tokenFrames[token.id], frame.intersects(selectionRect) else {
                return nil
            }
            return token.id
        }
        selectedTokenIDs = Set(selected)
        coach.clearPhraseLookup()
    }

    private func updateLookupForCurrentSelection() {
        if selectedTokenIDs.count == 1, let selected = tokens.first(where: { selectedTokenIDs.contains($0.id) }) {
            coach.lookupWord(selected.text)
        }
    }

    private func copyToClipboard(_ phrase: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(phrase, forType: .string)
    }

}

struct DictionaryResultView: View {
    let text: String

    private var lines: [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.lowercased().hasPrefix("pronunciation:") {
                    Label(
                        line.replacingOccurrences(of: "Pronunciation:", with: ""),
                        systemImage: "speaker.wave.2.fill"
                    )
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.primary)
                } else if line.lowercased().hasPrefix("e.g.") {
                    Text(line)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                        .padding(.leading, 13)
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Theme.primary.opacity(0.72))
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                        Text(line.hasPrefix("-") ? String(line.dropFirst()).trimmingCharacters(in: .whitespaces) : line)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TokenFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct TokenFlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 640
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)
        return CGSize(width: maxWidth, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        for row in rows {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [FlowRow] {
        var rows: [FlowRow] = []
        var currentItems: [FlowItem] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let itemWidth = min(size.width, maxWidth)
            if x > 0, x + itemWidth > maxWidth {
                rows.append(FlowRow(y: y, height: rowHeight, items: currentItems))
                y += rowHeight + rowSpacing
                currentItems.removeAll()
                x = 0
                rowHeight = 0
            }

            currentItems.append(FlowItem(index: index, x: x, size: CGSize(width: itemWidth, height: size.height)))
            x += itemWidth + spacing
            rowHeight = max(rowHeight, size.height)
        }

        if !currentItems.isEmpty {
            rows.append(FlowRow(y: y, height: rowHeight, items: currentItems))
        }
        return rows
    }
}

private struct FlowRow {
    let y: CGFloat
    let height: CGFloat
    let items: [FlowItem]
}

private struct FlowItem {
    let index: Int
    let x: CGFloat
    let size: CGSize
}

struct SentenceLookupToken: Identifiable {
    let id: Int
    let text: String
    let isWordLike: Bool

    static func tokenize(_ text: String) -> [SentenceLookupToken] {
        guard let regex = try? NSRegularExpression(pattern: #"[A-Za-z]+(?:['-][A-Za-z]+)?|\d+(?:[.,]\d+)?|[^\s]"#) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).enumerated().compactMap { index, match in
            guard let range = Range(match.range, in: text) else { return nil }
            let token = String(text[range])
            let isWordLike = token.range(of: #"[A-Za-z0-9]"#, options: .regularExpression) != nil
                && token.range(of: #"^[,.;:!?\"()\[\]{}]$"#, options: .regularExpression) == nil
            return SentenceLookupToken(id: index, text: token, isWordLike: isWordLike)
        }
    }
}

enum LocalDictionary {
    static func definition(for phrase: String) -> String? {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let range = CFRange(location: 0, length: trimmed.utf16.count)
        guard let definition = DCSCopyTextDefinition(nil, trimmed as CFString, range) else {
            return nil
        }
        return (definition.takeRetainedValue() as String)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum DictionaryLookupClient {
    static func lookup(_ word: String) async -> String {
        let normalized = word
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9'-]"#, with: "", options: .regularExpression)
        guard !normalized.isEmpty else { return "No lookup text." }

        if let online = try? await onlineDefinition(for: normalized), !online.isEmpty {
            return online
        }
        if let local = LocalDictionary.definition(for: normalized), !local.isEmpty {
            return conciseLocalDefinition(local)
        }
        return "No clear definition found."
    }

    private static func onlineDefinition(for word: String) async throws -> String {
        let escaped = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
        let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(escaped)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("ShadowCoach/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "DictionaryLookupClient", code: http.statusCode)
        }
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let entry = entries.first else {
            throw NSError(domain: "DictionaryLookupClient", code: -1)
        }

        let phonetic = bestPhonetic(from: entry)
        let meaningLines = (entry["meanings"] as? [[String: Any]] ?? [])
            .prefix(3)
            .compactMap { meaning -> String? in
                let part = (meaning["partOfSpeech"] as? String) ?? ""
                guard let definitions = meaning["definitions"] as? [[String: Any]],
                      let definition = definitions.first?["definition"] as? String else { return nil }
                let example = definitions.first?["example"] as? String
                var line = part.isEmpty ? "- \(definition)" : "- \(part): \(definition)"
                if let example, !example.isEmpty {
                    line += "\n  e.g. \(example)"
                }
                return line
            }

        var sections: [String] = []
        if let phonetic, !phonetic.isEmpty {
            sections.append("Pronunciation: \(phonetic)")
        }
        sections.append(contentsOf: meaningLines)
        return sections.joined(separator: "\n")
    }

    private static func bestPhonetic(from entry: [String: Any]) -> String? {
        if let phonetic = entry["phonetic"] as? String, !phonetic.isEmpty {
            return phonetic
        }
        return (entry["phonetics"] as? [[String: Any]] ?? [])
            .compactMap { $0["text"] as? String }
            .first { !$0.isEmpty }
    }

    private static func conciseLocalDefinition(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sentences = cleaned
            .split(separator: ".", maxSplits: 3, omittingEmptySubsequences: true)
            .prefix(3)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if sentences.isEmpty {
            return String(cleaned.prefix(320))
        }
        return sentences.map { "- \($0)." }.joined(separator: "\n")
    }
}

struct WordDiffFlow: View {
    @Environment(\.feedbackTextScale) private var textScale
    let items: [WordDiffItem]
    private let columns = [GridItem(.adaptive(minimum: 54), spacing: 6)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                Text(item.text)
                    .font(scaledFeedbackFont(12, scale: textScale, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(foreground(for: item.status))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(background(for: item.status))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(border(for: item.status))
                    )
                    .help(help(for: item))
            }
        }
    }

    private func foreground(for status: WordDiffStatus) -> Color {
        switch status {
        case .matched:
            return Theme.success
        case .substituted:
            return Theme.warning
        case .missing, .extra:
            return Theme.danger
        }
    }

    private func background(for status: WordDiffStatus) -> Color {
        switch status {
        case .matched:
            return Theme.success.opacity(0.10)
        case .substituted:
            return Theme.warning.opacity(0.12)
        case .missing:
            return Theme.danger.opacity(0.12)
        case .extra:
            return Theme.danger.opacity(0.06)
        }
    }

    private func border(for status: WordDiffStatus) -> Color {
        switch status {
        case .matched:
            return Theme.success.opacity(0.22)
        case .substituted:
            return Theme.warning.opacity(0.45)
        case .missing:
            return Theme.danger.opacity(0.42)
        case .extra:
            return Theme.danger.opacity(0.28)
        }
    }

    private func help(for item: WordDiffItem) -> String {
        switch item.status {
        case .matched:
            return "Matched"
        case .substituted:
            return "Reference: \(item.text) · You said: \(item.counterpartText ?? "another word")"
        case .missing:
            return "Missing from your recording"
        case .extra:
            return "Extra word in your recording"
        }
    }
}

struct WordComparisonView: View {
    @Environment(\.feedbackTextScale) private var textScale
    let referenceText: String
    let userText: String
    let items: [WordDiffItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            comparisonRow(title: "Ref", words: referenceWords)
            comparisonRow(title: "You", words: userWords)
        }
    }

    private var referenceWords: [WordDiffItem] {
        let filtered = items.filter { $0.status != .extra }
        if !filtered.isEmpty { return filtered }
        return WordDiffEngine.tokenize(referenceText).map { WordDiffItem(text: $0.text, status: .missing) }
    }

    private var userWords: [WordDiffItem] {
        let filtered = items.compactMap { item -> WordDiffItem? in
            switch item.status {
            case .missing:
                return nil
            case .matched:
                return WordDiffItem(
                    text: item.counterpartText ?? item.text,
                    status: .matched,
                    counterpartText: item.text
                )
            case .substituted:
                return WordDiffItem(
                    text: item.counterpartText ?? item.text,
                    status: .substituted,
                    counterpartText: item.text
                )
            case .extra:
                return item
            }
        }
        if !filtered.isEmpty { return filtered }
        return WordDiffEngine.tokenize(userText).map { WordDiffItem(text: $0.text, status: .extra) }
    }

    private func comparisonRow(title: String, words: [WordDiffItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(scaledFeedbackFont(11, scale: textScale, weight: .bold))
                .foregroundStyle(.secondary)
            WordDiffFlow(items: words)
        }
    }
}

struct AzurePronunciationPanel: View {
    @Environment(\.feedbackTextScale) private var textScale
    let analysis: AzurePronunciationAnalysis
    let issues: [PronunciationRuleIssue]
    @State private var selectedIndex = 0
    @State private var showWordDetails = false

    private var selectedWord: AzurePronunciationWord? {
        guard analysis.words.indices.contains(selectedIndex) else { return analysis.words.first }
        return analysis.words[selectedIndex]
    }

    private var selectedWordIssues: [PronunciationRuleIssue] {
        issues.filter { $0.wordIndex == selectedIndex }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Azure Pronunciation", systemImage: "waveform.badge.magnifyingglass")
                    .font(scaledFeedbackFont(12, scale: textScale, weight: .semibold))
                Spacer()
                if let error = analysis.error {
                    Text("error")
                        .font(scaledFeedbackFont(10, scale: textScale, weight: .bold))
                        .foregroundStyle(Theme.danger)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.danger.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .help(error)
                } else if analysis.rawStatus?.lowercased() == "success" {
                    Text("cached provider result")
                        .font(scaledFeedbackFont(10, scale: textScale, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text("WhisperX checks what you said. Azure checks how closely you said the reference.")
                .font(scaledFeedbackFont(10, scale: textScale))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = analysis.error {
                Text(error)
                    .font(scaledFeedbackFont(12, scale: textScale))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], spacing: 8) {
                    AzureScoreTile(label: "Pron", value: analysis.pronunciation)
                    AzureScoreTile(label: "Accuracy", value: analysis.accuracy)
                    AzureScoreTile(label: "Fluency", value: analysis.fluency)
                    AzureScoreTile(label: "Complete", value: analysis.completeness)
                    AzureScoreTile(label: "Prosody", value: analysis.prosody)
                }

                if !issues.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Top fixes")
                            .font(scaledFeedbackFont(12, scale: textScale, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(issues.prefix(3).enumerated()), id: \.element.id) { index, issue in
                            HStack(alignment: .top, spacing: 7) {
                                Text("\(index + 1)")
                                    .font(scaledFeedbackFont(10, scale: textScale, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 18, height: 18)
                                    .background(issueColor(issue))
                                    .clipShape(Circle())
                                    .padding(.top, 1)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(issue.title)
                                        .font(scaledFeedbackFont(12, scale: textScale, weight: .semibold))
                                    Text(issue.evidence)
                                        .font(scaledFeedbackFont(10, scale: textScale))
                                        .foregroundStyle(.secondary)
                                    Text(issue.coachNote)
                                        .font(scaledFeedbackFont(12, scale: textScale))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(9)
                    .background(Theme.panel.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if !analysis.words.isEmpty {
                    Button {
                        showWordDetails.toggle()
                    } label: {
                        HStack {
                            Label("Word-level details", systemImage: showWordDetails ? "chevron.down" : "chevron.right")
                            Spacer()
                            Text("\(analysis.words.count) words")
                                .font(scaledFeedbackFont(10, scale: textScale, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .font(scaledFeedbackFont(12, scale: textScale, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)

                    if showWordDetails {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Sentence overview")
                                .font(scaledFeedbackFont(12, scale: textScale, weight: .semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 7)], alignment: .leading, spacing: 7) {
                                ForEach(Array(analysis.words.enumerated()), id: \.element.id) { index, word in
                                    let issue = primaryIssue(for: index)
                                    let color = issue.map(issueColor) ?? scoreColor(word.accuracy)
                                    Button {
                                        selectedIndex = index
                                    } label: {
                                        VStack(spacing: 2) {
                                            HStack(spacing: 3) {
                                                Text(word.text)
                                                    .font(scaledFeedbackFont(12, scale: textScale, weight: .semibold))
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.7)
                                                if issue != nil {
                                                    Circle()
                                                        .fill(color)
                                                        .frame(width: 5, height: 5)
                                                }
                                            }
                                            Text(scoreLabel(word.accuracy))
                                                .font(scaledFeedbackFont(9, scale: textScale, weight: .bold, design: .rounded))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 6)
                                        .background(color.opacity(selectedIndex == index ? 0.24 : 0.11))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7)
                                                .stroke(selectedIndex == index ? color.opacity(0.75) : color.opacity(0.18))
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 7))
                                    }
                                    .buttonStyle(.plain)
                                    .help(wordHelp(word))
                                }
                            }
                        }

                        if let selectedWord {
                            AzureWordDetail(word: selectedWord, issues: selectedWordIssues)
                        }
                    }
                } else {
                    Text("Azure returned sentence-level scores, but no word/phoneme details. Check whether the Speech resource supports phoneme granularity for this request.")
                        .font(scaledFeedbackFont(12, scale: textScale))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .background(Theme.panel.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func scoreLabel(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))" } ?? "--"
    }

    private func wordHelp(_ word: AzurePronunciationWord) -> String {
        var parts = ["Accuracy \(scoreLabel(word.accuracy))"]
        if let errorType = word.errorType, errorType != "None" {
            parts.append(errorType)
        }
        return parts.joined(separator: " · ")
    }

    private func issueIcon(_ issue: PronunciationRuleIssue) -> String {
        switch issue.severity {
        case .strong:
            return "exclamationmark.triangle.fill"
        case .warning:
            return "exclamationmark.circle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    private func issueColor(_ issue: PronunciationRuleIssue) -> Color {
        switch issue.severity {
        case .strong:
            return Theme.danger
        case .warning:
            return Theme.primary
        case .info:
            return .secondary
        }
    }

    private func primaryIssue(for wordIndex: Int) -> PronunciationRuleIssue? {
        issues
            .filter { $0.wordIndex == wordIndex }
            .sorted { lhs, rhs in severityRank(lhs.severity) > severityRank(rhs.severity) }
            .first
    }

    private func severityRank(_ severity: PronunciationRuleSeverity) -> Int {
        switch severity {
        case .strong:
            return 3
        case .warning:
            return 2
        case .info:
            return 1
        }
    }
}

struct AzureScoreTile: View {
    @Environment(\.feedbackTextScale) private var textScale
    let label: String
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(scaledFeedbackFont(10, scale: textScale, weight: .bold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.map { "\(Int($0.rounded()))" } ?? "--")
                    .font(scaledFeedbackFont(18, scale: textScale, weight: .semibold, design: .rounded))
                    .foregroundStyle(scoreColor(value))
                Text("/100")
                    .font(scaledFeedbackFont(10, scale: textScale, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.border.opacity(0.75))
                    Capsule()
                        .fill(scoreColor(value))
                        .frame(width: proxy.size.width * CGFloat(max(0, min(100, value ?? 0)) / 100))
                }
            }
            .frame(height: 5)
        }
        .padding(8)
        .background(scoreColor(value).opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct AzureWordDetail: View {
    @Environment(\.feedbackTextScale) private var textScale
    let word: AzurePronunciationWord
    let issues: [PronunciationRuleIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(word.text)
                    .font(scaledFeedbackFont(15, scale: textScale, weight: .semibold))
                Spacer()
                Text("Accuracy \(scoreText(word.accuracy))")
                    .font(scaledFeedbackFont(12, scale: textScale, weight: .bold))
                    .foregroundStyle(scoreColor(word.accuracy))
            }
            if let errorType = word.errorType, errorType != "None" {
                Label(errorType, systemImage: "exclamationmark.triangle.fill")
                    .font(scaledFeedbackFont(12, scale: textScale, weight: .semibold))
                    .foregroundStyle(Theme.danger)
            }
            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Main issue")
                        .font(scaledFeedbackFont(10, scale: textScale, weight: .bold))
                        .foregroundStyle(.secondary)
                    ForEach(issues.prefix(2)) { issue in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title)
                                .font(scaledFeedbackFont(12, scale: textScale, weight: .semibold))
                            Text(issue.coachNote)
                                .font(scaledFeedbackFont(12, scale: textScale))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(issue.evidence)
                                .font(scaledFeedbackFont(10, scale: textScale))
                                .foregroundStyle(.secondary)
                        }
                        .padding(7)
                        .background(scoreColor(word.accuracy).opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            if !word.phonemes.isEmpty {
                unitSection(title: "Phonemes", units: word.phonemes)
            }
            if !word.syllables.isEmpty {
                unitSection(title: "Syllables", units: word.syllables)
            }
            Text(coachNote(for: word))
                .font(scaledFeedbackFont(12, scale: textScale))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Theme.panel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func unitSection(title: String, units: [AzurePronunciationUnit]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(scaledFeedbackFont(10, scale: textScale, weight: .bold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(units) { unit in
                    HStack(spacing: 4) {
                        Text(unit.text)
                            .font(scaledFeedbackFont(12, scale: textScale, weight: .semibold))
                            .lineLimit(1)
                        Text(scoreText(unit.accuracy))
                            .font(scaledFeedbackFont(9, scale: textScale, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(scoreColor(unit.accuracy).opacity(0.15))
                    .overlay(
                        Capsule()
                            .stroke(scoreColor(unit.accuracy).opacity(0.34))
                    )
                    .clipShape(Capsule())
                }
            }
        }
    }

    private func coachNote(for word: AzurePronunciationWord) -> String {
        if let lowest = word.phonemes.compactMap({ unit -> AzurePronunciationUnit? in
            guard let score = unit.accuracy, score < 70 else { return nil }
            return unit
        }).min(by: { ($0.accuracy ?? 100) < ($1.accuracy ?? 100) }) {
            return "Main issue: the phoneme \(lowest.text) is the weakest signal. Practice the word slowly, then put it back into the full sentence."
        }
        if let errorType = word.errorType, errorType != "None" {
            return "Main issue: Azure marked this word as \(errorType). Compare it with the reference and repeat this word inside the phrase."
        }
        return "This word is mostly stable. Keep it connected to the neighboring words."
    }

    private func scoreText(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))" } ?? "--"
    }
}

private func scoreColor(_ value: Double?) -> Color {
    guard let value else { return .secondary }
    if value >= 85 { return Theme.success }
    if value >= 70 { return Theme.primary }
    return Theme.danger
}

struct RhythmMetricCard: View {
    @Environment(\.feedbackTextScale) private var textScale
    let label: String
    let unit: String
    let referenceValue: Double
    let userValue: Double
    let idealTolerance: Double
    let warningTolerance: Double
    let verdict: String

    private var delta: Double {
        userValue - referenceValue
    }

    private var absoluteDelta: Double {
        abs(delta)
    }

    private var statusColor: Color {
        if absoluteDelta <= idealTolerance { return Theme.success }
        if absoluteDelta <= warningTolerance { return Theme.primary }
        return Theme.danger
    }

    private var statusLabel: String {
        if absoluteDelta <= idealTolerance { return "Close" }
        return delta > 0 ? "Higher" : "Lower"
    }

    private var deltaLabel: String {
        let sign = delta > 0 ? "+" : ""
        if unit.isEmpty {
            return "\(sign)\(Int(delta.rounded()))"
        }
        return String(format: "\(sign)%.1f%@", delta, unit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(scaledFeedbackFont(12, scale: textScale, weight: .semibold))
                Spacer()
                Text(statusLabel)
                    .font(scaledFeedbackFont(10, scale: textScale, weight: .bold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 8) {
                valuePill(title: "Ref", value: referenceValue, color: .secondary)
                rhythmDeltaBar
                valuePill(title: "You", value: userValue, color: statusColor)
            }

            HStack(spacing: 6) {
                Image(systemName: delta == 0 ? "equal" : (delta > 0 ? "arrow.up.right" : "arrow.down.right"))
                    .font(scaledFeedbackFont(10, scale: textScale, weight: .bold))
                    .foregroundStyle(statusColor)
                Text(deltaLabel)
                    .font(scaledFeedbackFont(10, scale: textScale, weight: .bold))
                    .foregroundStyle(statusColor)
                Text(verdict)
                    .font(scaledFeedbackFont(12, scale: textScale))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(statusColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor.opacity(0.22))
        )
    }

    private var rhythmDeltaBar: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let center = width / 2
            let normalized = min(1, absoluteDelta / max(warningTolerance, 0.01))
            let barWidth = max(3, normalized * center)
            ZStack {
                Capsule()
                    .fill(Theme.border.opacity(0.9))
                    .frame(height: 6)
                Rectangle()
                    .fill(Theme.border.opacity(0.8))
                    .frame(width: 1, height: 16)
                Capsule()
                    .fill(statusColor)
                    .frame(width: barWidth, height: 6)
                    .offset(x: delta >= 0 ? barWidth / 2 : -barWidth / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 26)
    }

    private func valuePill(title: String, value: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(scaledFeedbackFont(9, scale: textScale, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(formatted(value))
                .font(scaledFeedbackFont(12, scale: textScale, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 54)
        .padding(.vertical, 5)
        .background(Theme.panel.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func formatted(_ value: Double) -> String {
        if unit.isEmpty {
            return "\(Int(value.rounded()))"
        }
        if unit == "wpm" {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }
}

struct ProsodyCurveView: View {
    @Environment(\.feedbackTextScale) private var textScale
    let title: String
    let userPoints: [ProsodyPoint]
    let referencePoints: [ProsodyPoint]?
    let color: Color

    var body: some View {
        Canvas { context, size in
            let allPoints = userPoints + (referencePoints ?? [])
            let values = allPoints.map(\.value).filter { $0.isFinite }
            guard let minValue = values.min(), let maxValue = values.max(), maxValue > minValue else { return }
            draw(points: referencePoints ?? [], in: size, context: &context, color: .secondary.opacity(0.42), dashed: true, minValue: minValue, maxValue: maxValue)
            draw(points: userPoints, in: size, context: &context, color: color, dashed: false, minValue: minValue, maxValue: maxValue)
        }
        .overlay(alignment: .topLeading) {
            Text(title)
                .font(scaledFeedbackFont(10, scale: textScale, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(6)
        }
        .background(Theme.panel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.border)
        )
    }

    private func draw(points: [ProsodyPoint], in size: CGSize, context: inout GraphicsContext, color: Color, dashed: Bool, minValue: Double, maxValue: Double) {
        guard points.count > 1 else { return }
        let maxTime = max(points.map(\.time).max() ?? 1, 0.01)
        var path = Path()
        for (index, point) in points.enumerated() {
            let x = CGFloat(point.time / maxTime) * size.width
            let y = size.height - CGFloat((point.value - minValue) / (maxValue - minValue)) * (size.height - 12) - 6
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: dashed ? 1.2 : 2.0, lineCap: .round, lineJoin: .round, dash: dashed ? [4, 4] : [])
        )
    }
}
