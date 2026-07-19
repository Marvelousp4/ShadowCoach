import AVFoundation
import AppKit
import Foundation
import Security
import SwiftUI
import UniformTypeIdentifiers

@main
struct ShadowCoachApp: App {
    @StateObject private var coach = SpeechCoach()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coach)
                .frame(minWidth: 760, minHeight: 640)
        }
        .windowStyle(.titleBar)
    }
}

enum ShortcutAction {
    case listen
    case toggleRecord
    case playback
    case reveal
    case favorite
    case previous
    case next
}

enum FocusedInput: Hashable {
    case generationTopic
    case sentenceEditor
    case librarySearch
    case coachQuestion
    case realUseWords
}

enum CoachFeedbackProvider: String, CaseIterable, Identifiable, Codable {
    case gemini
    case codex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gemini: return "Gemini"
        case .codex: return "Local Codex"
        }
    }
}

enum CoachFeedbackDepth: String, CaseIterable, Identifiable {
    case focused
    case balanced
    case deep

    var id: String { rawValue }

    var label: String {
        switch self {
        case .focused: return "Focused"
        case .balanced: return "Balanced"
        case .deep: return "Deep"
        }
    }

    var maxOutputTokens: Int {
        switch self {
        case .focused: return 700
        case .balanced: return 1_000
        case .deep: return 1_400
        }
    }
}

enum CoachFeedbackPolicy {
    static func outputGuidance(accuracy: Double, depth: CoachFeedbackDepth) -> String {
        let issueLimit: Int
        switch accuracy {
        case 90...: issueLimit = 2
        case 70..<90: issueLimit = 3
        default: issueLimit = 4
        }

        let characterRange: String
        switch (depth, accuracy) {
        case (.focused, 90...): characterRange = "120-220"
        case (.focused, 70..<90): characterRange = "180-300"
        case (.focused, _): characterRange = "240-360"
        case (.balanced, 90...): characterRange = "180-300"
        case (.balanced, 70..<90): characterRange = "260-420"
        case (.balanced, _): characterRange = "320-480"
        case (.deep, 90...): characterRange = "260-400"
        case (.deep, 70..<90): characterRange = "360-560"
        case (.deep, _): characterRange = "420-650"
        }

        let depthRule: String
        switch depth {
        case .focused:
            depthRule = "Skip speculative memory diagnosis and secondary wording notes."
        case .balanced:
            depthRule = "Add one concise grammar, collocation, or memory explanation only when it changes the learner's next attempt."
        case .deep:
            depthRule = "You may add a short 深入理解 section for useful grammar, collocation, register, or a well-supported memory pattern."
        }

        return "Limit the report to about \(characterRange) Chinese characters and at most \(issueLimit) prioritized differences. \(depthRule)"
    }
}

enum ReferenceOriginPolicy {
    static func guidance(quality: ImportQuality?, hasSourceAudio: Bool?) -> String {
        switch quality {
        case .humanCaptions:
            return "Published source audio with human captions. Treat ordinary spontaneous wording as real speech, while still allowing an obvious caption or grammar problem to be flagged cautiously."
        case .whisperX, .whisperKit, .autoCaptions:
            return "Authentic source recording with machine-generated captions. Preserve natural spoken style, but treat the reference text as fallible because ASR may have misheard or split words incorrectly."
        case .localSubtitle:
            return "A local subtitle is attached to audio. The material may be a prepared script, TTS, or local recording; audio presence alone does not prove native or natural wording. Validate the reference before teaching it."
        case .generated:
            return "AI-generated practice text. Validate grammar, collocation, clarity, and spoken naturalness before asking the learner to memorize it."
        case .transcript, .estimatedTiming:
            return "Text-derived practice material without reliable native-speech provenance. Validate the target sentence and use nearby context before teaching it."
        case .builtIn:
            return "Curated practice text. It is likely intentional, but still flag a genuine ambiguity or unnatural construction instead of defending it automatically."
        case nil:
            if hasSourceAudio == true {
                return "Source audio is attached, but its provenance is unknown. It may be native speech, a prepared script, or TTS; validate the wording cautiously."
            }
            if hasSourceAudio == false {
                return "No source audio is attached. The reference may be a user script, generated line, or TTS text, so verify that it is natural English before teaching it as the target."
            }
            return "The reference origin is unknown. Check its English quality cautiously and do not assume it is flawless."
        }
    }
}

enum AppAppearanceOption: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum FeedbackTextSizeOption: String, CaseIterable, Identifiable {
    case compact
    case standard
    case large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact: return "Small"
        case .standard: return "Medium"
        case .large: return "Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .compact: return 0.92
        case .standard: return 1.0
        case .large: return 1.15
        }
    }
}

struct FeedbackTextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var feedbackTextScale: CGFloat {
        get { self[FeedbackTextScaleKey.self] }
        set { self[FeedbackTextScaleKey.self] = newValue }
    }
}

func scaledFeedbackFont(
    _ baseSize: CGFloat,
    scale: CGFloat,
    weight: Font.Weight = .regular,
    design: Font.Design = .default
) -> Font {
    .system(size: (baseSize * scale).rounded(), weight: weight, design: design)
}

enum PracticeTextSizeOption: String, CaseIterable, Identifiable {
    case compact
    case standard
    case large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact: return "Small"
        case .standard: return "Medium"
        case .large: return "Large"
        }
    }

    var pointSize: CGFloat {
        switch self {
        case .compact: return 21
        case .standard: return 24
        case .large: return 28
        }
    }
}

enum ReviewRetentionOption: Double, CaseIterable, Identifiable {
    case relaxed = 0.85
    case balanced = 0.90
    case strong = 0.95

    var id: Double { rawValue }

    var label: String {
        switch self {
        case .relaxed: return "Light 85%"
        case .balanced: return "Balanced 90%"
        case .strong: return "Strong 95%"
        }
    }
}

enum AppSettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case practice
    case analysis

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appearance: return "Appearance"
        case .practice: return "Practice"
        case .analysis: return "Analysis"
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush"
        case .practice: return "mic"
        case .analysis: return "waveform.badge.magnifyingglass"
        }
    }
}

enum ImportQuality: String, Codable, Hashable {
    case builtIn
    case generated
    case transcript
    case localSubtitle
    case humanCaptions
    case whisperX
    case whisperKit
    case autoCaptions
    case estimatedTiming

    var label: String {
        switch self {
        case .builtIn: return "Core"
        case .generated: return "AI"
        case .transcript: return "Text"
        case .localSubtitle: return "Local Sub"
        case .humanCaptions: return "Human Sub"
        case .whisperX: return "WhisperX"
        case .whisperKit: return "WhisperKit"
        case .autoCaptions: return "Auto Sub"
        case .estimatedTiming: return "Estimated"
        }
    }

    var systemImage: String {
        switch self {
        case .builtIn: return "books.vertical"
        case .generated: return "sparkles"
        case .transcript: return "doc.text"
        case .localSubtitle: return "captions.bubble"
        case .humanCaptions: return "checkmark.seal"
        case .whisperX, .whisperKit: return "waveform.badge.magnifyingglass"
        case .autoCaptions: return "wand.and.rays"
        case .estimatedTiming: return "clock.badge.questionmark"
        }
    }
}

struct PracticeLine: Identifiable, Hashable {
    let id: UUID
    let title: String
    let source: String
    let text: String
    let sourceMediaRelativePath: String?
    let sourceStartTime: Double?
    let sourceEndTime: Double?
    let quality: ImportQuality?

    var hasSourceAudio: Bool {
        sourceMediaRelativePath != nil && sourceStartTime != nil
    }

    init(
        id: UUID = UUID(),
        title: String,
        source: String,
        text: String,
        sourceMediaRelativePath: String? = nil,
        sourceStartTime: Double? = nil,
        sourceEndTime: Double? = nil,
        quality: ImportQuality? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.text = text
        self.sourceMediaRelativePath = sourceMediaRelativePath
        self.sourceStartTime = sourceStartTime
        self.sourceEndTime = sourceEndTime
        self.quality = quality
    }

    func replacingID(with id: UUID) -> PracticeLine {
        PracticeLine(
            id: id,
            title: title,
            source: source,
            text: text,
            sourceMediaRelativePath: sourceMediaRelativePath,
            sourceStartTime: sourceStartTime,
            sourceEndTime: sourceEndTime,
            quality: quality
        )
    }

    static let library: [PracticeLine] = [
        PracticeLine(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, title: "Careful Listening", source: "Core", text: "The fastest way to improve your English is to listen carefully and repeat out loud."),
        PracticeLine(id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!, title: "Project Update", source: "Work", text: "We need a clear timeline, a reliable owner, and a simple way to measure progress."),
        PracticeLine(id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!, title: "Customer Site", source: "Work", text: "Before we change the configuration, let's confirm the root cause with real logs."),
        PracticeLine(id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!, title: "Quiet Confidence", source: "Legal drama style", text: "Facts are patient, but people usually are not."),
        PracticeLine(id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!, title: "The Record", source: "Legal drama style", text: "If it is not in the record, it is only a story."),
        PracticeLine(id: UUID(uuidString: "10000000-0000-0000-0000-000000000006")!, title: "Hard Choice", source: "Legal drama style", text: "You can win the argument and still lose the trust."),
        PracticeLine(id: UUID(uuidString: "10000000-0000-0000-0000-000000000007")!, title: "Clean Deal", source: "Crime drama style", text: "A clean plan fails when one person starts improvising."),
        PracticeLine(id: UUID(uuidString: "10000000-0000-0000-0000-000000000008")!, title: "Pressure", source: "Crime drama style", text: "When the pressure rises, small mistakes become expensive."),
        PracticeLine(id: UUID(uuidString: "10000000-0000-0000-0000-000000000009")!, title: "No Shortcut", source: "Crime drama style", text: "There is no shortcut that stays hidden forever."),
        PracticeLine(id: UUID(uuidString: "10000000-0000-0000-0000-000000000010")!, title: "Hamlet", source: "Shakespeare", text: "To be, or not to be, that is the question."),
        PracticeLine(id: UUID(uuidString: "10000000-0000-0000-0000-000000000011")!, title: "Julius Caesar", source: "Shakespeare", text: "Cowards die many times before their deaths."),
        PracticeLine(id: UUID(uuidString: "10000000-0000-0000-0000-000000000012")!, title: "Romeo and Juliet", source: "Shakespeare", text: "Parting is such sweet sorrow.")
    ]
}

extension PracticeLine: Codable {}

struct PersistedLibrary: Codable {
    let importedLines: [PracticeLine]
    let generatedLines: [PracticeLine]
}

struct SpeechVoice: Identifiable, Hashable {
    let id: String
    let name: String
    let locale: String

    var displayName: String {
        locale.isEmpty ? name : "\(name) · \(locale)"
    }
}

struct TimedSubtitle: Hashable {
    let start: Double
    let end: Double
    let text: String
}

struct URLImportResult {
    let sourceName: String
    let lines: [PracticeLine]
    let usedEstimatedTiming: Bool
    let quality: ImportQuality
}

struct URLImportPreview {
    let sourceURL: URL
    let title: String
    let duration: Double
    let hasManualEnglish: Bool
    let hasAutomaticEnglish: Bool
    let pipeline: ImportQuality
    let warning: String?
}

extension JSONEncoder {
    static var storage: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

struct GeneratedPracticeLine: Decodable {
    let title: String
    let source: String
    let text: String
}

enum TranscriptParser {
    static func parse(_ raw: String, sourceName: String) -> [PracticeLine] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let cleanedLines = normalized
            .components(separatedBy: .newlines)
            .map(cleanLine)
            .filter { !$0.isEmpty }
        return splitSentences(cleanedLines)
            .prefix(300)
            .enumerated()
            .map { index, sentence in
                PracticeLine(
                    title: "Line \(index + 1)",
                    source: sourceName,
                    text: sentence,
                    quality: .transcript
                )
            }
    }

    private static func cleanLine(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }
        if text == "WEBVTT" { return "" }
        if text == "Time Subtitle" { return "" }
        if text.hasPrefix("Cleaned and speaker-relabeled transcript") { return "" }
        if text == "Notes:" { return "" }
        if text.hasPrefix("- The source captions") { return "" }
        if text.hasPrefix("- Technical terms") { return "" }
        if text.hasPrefix("- No substantive content") { return "" }
        if text.range(of: #"^\d+$"#, options: .regularExpression) != nil { return "" }
        if text.range(of: #"^\d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil { return "" }
        if text.range(of: #"\d{1,2}:\d{2}:\d{2}[,.]\d{3}\s*-->\s*\d{1,2}:\d{2}:\d{2}[,.]\d{3}"#, options: .regularExpression) != nil { return "" }
        if text.range(of: #"\d{1,2}:\d{2}[,.]\d{3}\s*-->\s*\d{1,2}:\d{2}[,.]\d{3}"#, options: .regularExpression) != nil { return "" }

        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[[^\]]+\]"#, with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.range(of: #"^\d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil { return "" }
        text = text.replacingOccurrences(of: #"^\s*[A-Z][A-Za-z .'-]{1,32}:\s+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"^\s*\d{1,2}:\d{2}(:\d{2})?\s+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"^\s*\d+\s*s\s+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”")))
    }

    private static func splitSentences(_ lines: [String]) -> [String] {
        var result: [String] = []

        for line in lines {
            var buffer = ""

            for character in line {
                buffer.append(character)
                if character == "." || character == "!" || character == "?" {
                    appendSentence(buffer, to: &result)
                    buffer = ""
                    if result.count >= 300 { return result }
                }
            }

            appendSentence(buffer, to: &result)
            if result.count >= 300 { return result }
        }

        return result
    }

    private static func appendSentence(_ raw: String, to result: inout [String]) {
        let cleaned = raw
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”")))
        let wordCount = cleaned.split { $0 == " " || $0 == "\t" }.count
        let hasLetter = cleaned.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil

        if hasLetter, wordCount >= 4, wordCount <= 28 {
            if result.last != cleaned {
                result.append(cleaned)
            }
        }
    }
}

enum TimedSubtitleParser {
    static func parse(_ raw: String) -> [TimedSubtitle] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var result: [TimedSubtitle] = []

        for block in blocks {
            let lines = block
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0 != "WEBVTT" }
            guard let timingLine = lines.first(where: { $0.contains("-->") }) else { continue }
            let parts = timingLine.components(separatedBy: "-->")
            guard parts.count == 2,
                  var start = parseTime(parts[0]),
                  var end = parseTime(parts[1]) else { continue }
            if let embedded = embeddedTiming(in: lines), end - start < 0.2 {
                start = embedded.start
                end = embedded.end
            }
            let text = lines
                .filter { isSubtitleTextLine($0) }
                .joined(separator: " ")
            let cleanedText = cleanSubtitleText(text)
            if isUsable(cleanedText) {
                result.append(TimedSubtitle(start: start, end: max(end, start + 0.8), text: cleanedText))
            }
        }

        return result
    }

    private static func isSubtitleTextLine(_ line: String) -> Bool {
        if line == "WEBVTT" { return false }
        if line.contains("-->") { return false }
        if line.range(of: #"^\d+$"#, options: .regularExpression) != nil { return false }
        if line.range(of: #"^\d{1,2}:\d{2}:\d{2}[\.,]\d{3}\s*--\s*\d{1,2}:\d{2}:\d{2}[\.,]\d{3}$"#, options: .regularExpression) != nil { return false }
        if line.range(of: #"^\d{1,2}:\d{2}[\.,]\d{3}\s*--\s*\d{1,2}:\d{2}[\.,]\d{3}$"#, options: .regularExpression) != nil { return false }
        return line.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
    }

    static func cleanSubtitleText(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\((Laughter|Applause|Music|Cheers|Audience laughter|Audience applause)[^)]+\)"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\((Laughter|Applause|Music|Cheers)\)"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"(^|\s)\d{1,2}:\d{2}:\d{2}[\.,]\d{3}\s*--\s*\d{1,2}:\d{2}:\d{2}[\.,]\d{3}(\s|$)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(^|\s)\d{1,2}:\d{2}[\.,]\d{3}\s*--\s*\d{1,2}:\d{2}[\.,]\d{3}(\s|$)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapseRepeatedText(cleaned)
    }

    private static func embeddedTiming(in lines: [String]) -> (start: Double, end: Double)? {
        for line in lines {
            let patterns = [
                #"^(\d{1,2}:\d{2}:\d{2}[\.,]\d{3})\s*--\s*(\d{1,2}:\d{2}:\d{2}[\.,]\d{3})$"#,
                #"^(\d{1,2}:\d{2}[\.,]\d{3})\s*--\s*(\d{1,2}:\d{2}[\.,]\d{3})$"#
            ]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                guard let match = regex.firstMatch(in: line, range: range),
                      match.numberOfRanges == 3,
                      let startRange = Range(match.range(at: 1), in: line),
                      let endRange = Range(match.range(at: 2), in: line),
                      let start = parseTime(String(line[startRange])),
                      let end = parseTime(String(line[endRange])) else { continue }
                return (start, end)
            }
        }
        return nil
    }

    private static func collapseRepeatedText(_ text: String) -> String {
        let tokens = text.split(separator: " ").map(String.init)
        guard tokens.count >= 6, tokens.count.isMultiple(of: 2) else { return text }
        let midpoint = tokens.count / 2
        let lhs = tokens[..<midpoint].map { normalizedTextToken($0) }
        let rhs = tokens[midpoint...].map { normalizedTextToken($0) }
        if lhs == rhs {
            return tokens[..<midpoint].joined(separator: " ")
        }
        return text
    }

    private static func normalizedTextToken(_ token: String) -> String {
        token.lowercased().replacingOccurrences(of: #"[^a-z0-9']"#, with: "", options: .regularExpression)
    }

    static func parseTime(_ raw: String) -> Double? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .first?
            .replacingOccurrences(of: ",", with: ".") ?? ""
        if cleaned.hasSuffix("s"), let seconds = Double(cleaned.dropLast()) {
            return seconds
        }

        let parts = cleaned.split(separator: ":").compactMap { Double($0) }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        return Double(cleaned)
    }

    static func isUsable(_ text: String) -> Bool {
        let wordCount = text.split { $0 == " " || $0 == "\t" || $0 == "\n" }.count
        return text.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil && wordCount >= 2 && wordCount <= 40
    }
}

enum SubtitleSegmenter {
    struct TimedWord {
        let raw: String
        let normalized: String
        let start: Double
        let end: Double
    }

    static func segment(_ cues: [TimedSubtitle]) -> [TimedSubtitle] {
        let words = reconstructWords(from: cues)
        guard !words.isEmpty else { return [] }

        var result: [TimedSubtitle] = []
        var buffer: [TimedWord] = []

        for word in words {
            buffer.append(word)
            let duration = (buffer.last?.end ?? word.end) - (buffer.first?.start ?? word.start)
            let shouldBreak = endsSentence(word.raw) || buffer.count >= 30 || duration >= 9.5

            if shouldBreak {
                appendSegment(buffer, to: &result)
                buffer.removeAll()
            }
        }
        appendSegment(buffer, to: &result)

        return result
    }

    static func segmentTED(_ cues: [TimedSubtitle]) -> [TimedSubtitle] {
        let cleanedCues = cues
            .sorted(by: { $0.start < $1.start })
            .map { TimedSubtitle(start: $0.start, end: $0.end, text: TimedSubtitleParser.cleanSubtitleText($0.text)) }
            .filter { TimedSubtitleParser.isUsable($0.text) && !isCreditCue($0.text) }
        guard !cleanedCues.isEmpty else { return [] }

        var result: [TimedSubtitle] = []
        var buffer: [TimedSubtitle] = []

        for index in cleanedCues.indices {
            let cue = cleanedCues[index]
            buffer.append(cue)

            let text = cleanSentence(buffer.map(\.text).joined(separator: " "))
            let duration = (buffer.last?.end ?? cue.end) - (buffer.first?.start ?? cue.start)
            let wordCount = text.split(separator: " ").count
            let nextGap = index < cleanedCues.index(before: cleanedCues.endIndex)
                ? cleanedCues[cleanedCues.index(after: index)].start - cue.end
                : 2.0

            let hasSentenceEnd = endsSentence(cue.text) || endsSentence(text)
            let hasNaturalGap = nextGap > 0.45
            let isTooLong = duration >= 13.5 || wordCount >= 42
            let shouldBreak = hasSentenceEnd || (isTooLong && hasNaturalGap) || duration >= 17.0

            if shouldBreak {
                appendCueSegment(buffer, to: &result)
                buffer.removeAll()
            }
        }

        appendCueSegment(buffer, to: &result)
        return result
    }

    private static func reconstructWords(from cues: [TimedSubtitle]) -> [TimedWord] {
        var transcriptTokens: [String] = []
        var words: [TimedWord] = []

        for cue in cues.sorted(by: { $0.start < $1.start }) {
            let rawTokens = TimedSubtitleParser.cleanSubtitleText(cue.text)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .split(separator: " ")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !isTimestampToken($0) }
            let normalizedTokens = rawTokens.map(normalizeToken)
            let usablePairs = zip(rawTokens, normalizedTokens).filter { !$0.1.isEmpty }
            guard !usablePairs.isEmpty else { continue }

            let cueTokens = usablePairs.map(\.1)
            let overlap = overlapLength(previous: transcriptTokens, current: cueTokens)
            guard overlap < usablePairs.count else { continue }

            let duration = max(0.05, cue.end - cue.start)
            let tokenDuration = duration / Double(usablePairs.count)
            for index in overlap..<usablePairs.count {
                let pair = usablePairs[index]
                let start = cue.start + Double(index) * tokenDuration
                let end = cue.start + Double(index + 1) * tokenDuration
                words.append(TimedWord(raw: cleanRawToken(pair.0), normalized: pair.1, start: start, end: end))
                transcriptTokens.append(pair.1)
                if transcriptTokens.count > 80 {
                    transcriptTokens.removeFirst(transcriptTokens.count - 80)
                }
            }
        }

        return words.filter { !$0.raw.isEmpty }
    }

    private static func overlapLength(previous: [String], current: [String]) -> Int {
        guard !previous.isEmpty, !current.isEmpty else { return 0 }
        let maxOverlap = min(previous.count, current.count)
        for length in stride(from: maxOverlap, through: 1, by: -1) {
            if Array(previous.suffix(length)) == Array(current.prefix(length)) {
                return length
            }
        }
        return 0
    }

    private static func appendSegment(_ buffer: [TimedWord], to result: inout [TimedSubtitle]) {
        guard let first = buffer.first, let last = buffer.last else { return }
        let text = cleanSentence(buffer.map(\.raw).joined(separator: " "))
        let wordCount = text.split(separator: " ").count
        if TimedSubtitleParser.isUsable(text), wordCount >= 4, result.last?.text != text {
            result.append(TimedSubtitle(start: first.start, end: max(last.end, first.start + 0.8), text: text))
        }
    }

    private static func appendCueSegment(_ buffer: [TimedSubtitle], to result: inout [TimedSubtitle]) {
        guard let first = buffer.first, let last = buffer.last else { return }
        let text = cleanSentence(buffer.map(\.text).joined(separator: " "))
        let wordCount = text.split(separator: " ").count
        guard text.count >= 12, wordCount >= 3, wordCount <= 90, result.last?.text != text else { return }
        result.append(TimedSubtitle(start: first.start, end: max(last.end, first.start + 0.8), text: text))
    }

    private static func cleanSentence(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—\"“”")))
    }

    private static func cleanRawToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isTimestampToken(_ raw: String) -> Bool {
        raw.range(of: #"^\d{1,2}:\d{2}(:\d{2})?[\.,]\d{3}$"#, options: .regularExpression) != nil
            || raw == "--"
    }

    private static func normalizeToken(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9']"#, with: "", options: .regularExpression)
    }

    private static func isCreditCue(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.hasPrefix("translator:")
            || lowercased.hasPrefix("reviewer:")
            || lowercased.contains(" translator:")
            || lowercased.contains(" reviewer:")
    }

    private static func endsSentence(_ raw: String) -> Bool {
        raw.range(of: #"[.!?]["”']?$"#, options: .regularExpression) != nil
    }
}

enum URLMediaImporter {
    private struct SubtitleMetadata {
        let hasManualEnglish: Bool
        let hasAutomaticEnglish: Bool
    }

    static func previewURL(_ sourceURL: URL) throws -> URLImportPreview {
        let output = try runYTDLPWithCookieRetry([
            "--dump-single-json",
            "--skip-download",
            "--no-playlist",
            "--",
            sourceURL.absoluteString
        ])
        guard let data = output.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "URLMediaImporter", code: -3, userInfo: [NSLocalizedDescriptionKey: "Could not read URL metadata"])
        }

        let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = json["duration"] as? Double
            ?? (json["duration"] as? NSNumber)?.doubleValue
            ?? 0
        let manual = json["subtitles"] as? [String: Any] ?? [:]
        let automatic = json["automatic_captions"] as? [String: Any] ?? [:]
        let hasManualEnglish = hasEnglishKey(in: manual)
        let hasAutomaticEnglish = hasEnglishKey(in: automatic)
        let pipeline: ImportQuality
        if hasManualEnglish {
            pipeline = .humanCaptions
        } else if hasAutomaticEnglish {
            pipeline = .whisperX
        } else {
            pipeline = .estimatedTiming
        }

        let warning: String?
        if duration > 60 * 30 {
            warning = "Long video. The first 500 practice clips will be imported."
        } else if pipeline == .estimatedTiming {
            warning = "No English captions detected. Timing may be rough."
        } else if pipeline == .whisperX {
            warning = "Only automatic captions detected. The app will rebuild timing with local WhisperX."
        } else {
            warning = nil
        }

        return URLImportPreview(
            sourceURL: sourceURL,
            title: title?.isEmpty == false ? title! : sourceURL.absoluteString,
            duration: duration,
            hasManualEnglish: hasManualEnglish,
            hasAutomaticEnglish: hasAutomaticEnglish,
            pipeline: pipeline,
            warning: warning
        )
    }

    static func importURL(_ sourceURL: URL, importDirectory: URL, mediaDirectory: URL) async throws -> URLImportResult {
        let workDirectory = importDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        ImportLogger.write("urlImport workDir=\(workDirectory.path)")

        try runYTDLP(sourceURL: sourceURL, workDirectory: workDirectory)

        let files = try FileManager.default.contentsOfDirectory(at: workDirectory, includingPropertiesForKeys: nil)
        let mediaURL = try findDownloadedMedia(in: files)
        let sourceName = metadataTitle(in: files) ?? cleanedBaseName(mediaURL)
        let copiedMediaURL = try copyMedia(mediaURL, to: mediaDirectory)
        let relativeMediaPath = "Media/\(copiedMediaURL.lastPathComponent)"

        var timedSubtitles: [TimedSubtitle] = []
        let metadata = subtitleMetadata(in: files)
        let shouldUseLocalTranscriber = metadata.hasAutomaticEnglish && !metadata.hasManualEnglish
        var quality: ImportQuality = metadata.hasManualEnglish ? .humanCaptions : (metadata.hasAutomaticEnglish ? .autoCaptions : .estimatedTiming)
        if shouldUseLocalTranscriber {
            do {
                ImportLogger.write("whisperx start reason=automatic_subtitles media=\(mediaURL.lastPathComponent)")
                timedSubtitles = try await WhisperXTranscriber.transcribe(mediaURL)
                quality = .whisperX
                ImportLogger.write("whisperx success lines=\(timedSubtitles.count)")
            } catch {
                ImportLogger.write("whisperx failed \(error.localizedDescription); trying WhisperKit")
            }
        }

        if shouldUseLocalTranscriber && timedSubtitles.isEmpty {
            do {
                ImportLogger.write("whisperkit start reason=automatic_subtitles media=\(mediaURL.lastPathComponent)")
                timedSubtitles = try await WhisperKitTranscriber.transcribe(mediaURL)
                quality = .whisperKit
                ImportLogger.write("whisperkit success lines=\(timedSubtitles.count)")
            } catch {
                ImportLogger.write("whisperkit failed \(error.localizedDescription); falling back to downloaded subtitles")
            }
        }

        if timedSubtitles.isEmpty {
            let prefersTEDSegmentation = isTEDSource(sourceURL: sourceURL, title: sourceName)
            timedSubtitles = try findSubtitles(in: files).lazy.compactMap { subtitleURL -> [TimedSubtitle]? in
                let raw = try String(contentsOf: subtitleURL, encoding: .utf8)
                let cues = TimedSubtitleParser.parse(raw)
                let parsed = prefersTEDSegmentation ? SubtitleSegmenter.segmentTED(cues) : SubtitleSegmenter.segment(cues)
                ImportLogger.write("subtitle parse file=\(subtitleURL.lastPathComponent) lines=\(parsed.count) mode=\(prefersTEDSegmentation ? "ted" : "default")")
                return parsed.isEmpty ? nil : parsed
            }.first ?? []
            if !timedSubtitles.isEmpty,
               let offset = subtitleTimingOffsetIfNeeded(sourceURL: sourceURL, mediaURL: mediaURL, subtitles: timedSubtitles) {
                ImportLogger.write("subtitle offset calibration source=\(sourceURL.host ?? "") offset=\(offset)")
                timedSubtitles = timedSubtitles.map { subtitle in
                    TimedSubtitle(
                        start: max(0, subtitle.start + offset),
                        end: max(0.8, subtitle.end + offset),
                        text: subtitle.text
                    )
                }
            }
        }
        var usedEstimatedTiming = false

        if timedSubtitles.isEmpty {
            let transcript = try HTMLTranscriptExtractor.extractTranscript(from: sourceURL)
            let duration = audioDuration(mediaURL)
            timedSubtitles = estimateTimings(for: transcript, duration: duration)
            usedEstimatedTiming = true
            quality = .estimatedTiming
        }

        let lines = timedSubtitles
            .prefix(500)
            .enumerated()
            .map { index, subtitle in
                PracticeLine(
                    title: "Clip \(index + 1)",
                    source: sourceName,
                    text: subtitle.text,
                    sourceMediaRelativePath: relativeMediaPath,
                    sourceStartTime: subtitle.start,
                    sourceEndTime: subtitle.end,
                    quality: quality
                )
            }

        guard !lines.isEmpty else {
            throw NSError(domain: "URLMediaImporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "No usable English subtitles or transcript found"])
        }

        return URLImportResult(sourceName: sourceName, lines: lines, usedEstimatedTiming: usedEstimatedTiming, quality: quality)
    }

    private static func isTEDSource(sourceURL: URL, title: String) -> Bool {
        let host = sourceURL.host?.lowercased() ?? ""
        let lowercasedTitle = title.lowercased()
        return host.contains("ted.com")
            || lowercasedTitle.contains("tedx")
            || lowercasedTitle.contains(" | ted")
            || lowercasedTitle.contains("｜ ted")
            || lowercasedTitle.hasSuffix(" ted")
    }

    private static func runYTDLP(sourceURL: URL, workDirectory: URL) throws {
        let outputTemplate = "%(title).120B [%(id)s].%(ext)s"
        let arguments = ytDLPArguments(sourceURL: sourceURL, workDirectory: workDirectory, outputTemplate: outputTemplate)
        let output = try runYTDLPWithCookieRetry(arguments)
        ImportLogger.write("yt-dlp output \(output.suffix(3000))")
    }

    private static func runYTDLPWithCookieRetry(_ arguments: [String]) throws -> String {
        do {
            return try runYTDLP(arguments)
        } catch {
            let message = error.localizedDescription
            guard shouldRetryYTDLPWithBrowserCookies(message) else { throw error }

            let browser = ProcessInfo.processInfo.environment["SHADOW_COACH_YTDLP_COOKIES_BROWSER"] ?? "chrome"
            ImportLogger.write("yt-dlp retry with cookies-from-browser \(browser) after error \(message.prefix(500))")
            let retryArguments = ["--cookies-from-browser", browser] + arguments
            let output = try runYTDLP(retryArguments)
            ImportLogger.write("yt-dlp cookie retry output \(output.suffix(3000))")
            return output
        }
    }

    private static func ytDLPArguments(sourceURL: URL, workDirectory: URL, outputTemplate: String) -> [String] {
        [
            "--no-playlist",
            "--paths", workDirectory.path,
            "--output", outputTemplate,
            "--extract-audio",
            "--audio-format", "m4a",
            "--audio-quality", "0",
            "--write-subs",
            "--write-auto-subs",
            "--sub-langs", "en,en-orig,en-en",
            "--sub-format", "vtt/srt/best",
            "--convert-subs", "srt",
            "--write-info-json",
            "--",
            sourceURL.absoluteString
        ]
    }

    private static func runYTDLP(_ arguments: [String]) throws -> String {
        let command = LocalToolLocator.command(named: "yt-dlp", overrideVariable: "SHADOW_COACH_YTDLP")
        return try CommandRunner.run(
            executable: command.executable,
            arguments: command.argumentsPrefix + arguments,
            environment: [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/opt/homebrew/sbin:/usr/local/sbin"
            ]
        )
    }

    private static func shouldRetryYTDLPWithBrowserCookies(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("sign in to confirm")
            || lowercased.contains("not a bot")
            || lowercased.contains("cookies-from-browser")
            || lowercased.contains("use --cookies")
    }

    private static func findDownloadedMedia(in files: [URL]) throws -> URL {
        let mediaExtensions = ["m4a", "mp3", "mp4", "mov", "aac", "wav"]
        if let media = files
            .filter({ mediaExtensions.contains($0.pathExtension.lowercased()) })
            .sorted(by: { fileSize($0) > fileSize($1) })
            .first {
            return media
        }
        throw NSError(domain: "URLMediaImporter", code: -2, userInfo: [NSLocalizedDescriptionKey: "yt-dlp did not create a playable media file"])
    }

    private static func subtitleTimingOffsetIfNeeded(sourceURL: URL, mediaURL: URL, subtitles: [TimedSubtitle]) -> Double? {
        guard sourceURL.host?.lowercased().contains("ted.com") == true,
              let firstSubtitle = subtitles.first,
              firstSubtitle.start < 4.0 else {
            return nil
        }
        guard let speechStart = firstSpeechStart(in: mediaURL), speechStart.isFinite else {
            return nil
        }
        let offset = speechStart - firstSubtitle.start
        guard offset > 1.0, offset < 8.0 else { return nil }
        return offset
    }

    private static func firstSpeechStart(in mediaURL: URL) -> Double? {
        let ffmpeg = LocalToolLocator.command(named: "ffmpeg", overrideVariable: "SHADOW_COACH_FFMPEG")
        guard let output = try? CommandRunner.run(
            executable: ffmpeg.executable,
            arguments: ffmpeg.argumentsPrefix + [
                "-hide_banner",
                "-nostats",
                "-i", mediaURL.path,
                "-t", "20",
                "-af", "silencedetect=noise=-35dB:d=0.2",
                "-f", "null",
                "-"
            ],
            environment: [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/opt/homebrew/sbin:/usr/local/sbin"
            ]
        ) else {
            return nil
        }
        let pattern = #"silence_end:\s*([0-9]+(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        let candidates = regex.matches(in: output, range: range).compactMap { match -> Double? in
            guard let valueRange = Range(match.range(at: 1), in: output) else { return nil }
            return Double(output[valueRange])
        }
        return candidates.first { $0 > 1.0 && $0 < 12.0 }
    }

    private static func findSubtitles(in files: [URL]) throws -> [URL] {
        files
            .filter { ["srt", "vtt"].contains($0.pathExtension.lowercased()) }
            .filter { !$0.lastPathComponent.lowercased().contains("live_chat") }
            .sorted { lhs, rhs in
                let lhsName = lhs.lastPathComponent.lowercased()
                let rhsName = rhs.lastPathComponent.lowercased()
                let lhsScore = subtitleScore(lhsName, extension: lhs.pathExtension, size: fileSize(lhs))
                let rhsScore = subtitleScore(rhsName, extension: rhs.pathExtension, size: fileSize(rhs))
                return lhsScore > rhsScore
            }
    }

    private static func subtitleScore(_ name: String, extension pathExtension: String, size: Int) -> Int {
        var score = 0
        if name.contains(".en.") || name.contains(".en-") { score += 100 }
        if name.contains("orig") { score -= 80 }
        if pathExtension.lowercased() == "srt" { score += 20 }
        score += min(size / 1024, 50)
        return score
    }

    private static func copyMedia(_ url: URL, to mediaDirectory: URL) throws -> URL {
        let fileName = "\(UUID().uuidString)-\(url.lastPathComponent)"
        let destination = mediaDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    private static func metadataTitle(in files: [URL]) -> String? {
        guard let infoURL = files.first(where: { $0.lastPathComponent.hasSuffix(".info.json") }),
              let data = try? Data(contentsOf: infoURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["title"] as? String else {
            return nil
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func subtitleMetadata(in files: [URL]) -> SubtitleMetadata {
        guard let infoURL = files.first(where: { $0.lastPathComponent.hasSuffix(".info.json") }),
              let data = try? Data(contentsOf: infoURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SubtitleMetadata(hasManualEnglish: false, hasAutomaticEnglish: false)
        }
        let manual = json["subtitles"] as? [String: Any] ?? [:]
        let automatic = json["automatic_captions"] as? [String: Any] ?? [:]
        return SubtitleMetadata(
            hasManualEnglish: hasEnglishKey(in: manual),
            hasAutomaticEnglish: hasEnglishKey(in: automatic)
        )
    }

    private static func hasEnglishKey(in dictionary: [String: Any]) -> Bool {
        dictionary.keys.contains { key in
            let normalized = key.lowercased()
            return normalized == "en" || normalized == "en-us" || normalized == "en-gb" || normalized.hasPrefix("en-")
        }
    }

    private static func cleanedBaseName(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: #"\s+\[[^\]]+\]$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func audioDuration(_ url: URL) -> Double {
        let seconds = (try? AVAudioPlayer(contentsOf: url).duration) ?? 0
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    private static func estimateTimings(for transcript: String, duration: Double) -> [TimedSubtitle] {
        let textLines = TranscriptParser.parse(transcript, sourceName: "URL Transcript").map(\.text)
        guard !textLines.isEmpty else { return [] }

        let wordCounts = textLines.map { max(1, $0.split { $0 == " " || $0 == "\t" || $0 == "\n" }.count) }
        let totalWords = max(1, wordCounts.reduce(0, +))
        let usableDuration = duration > 0 ? duration : Double(textLines.count) * 4.0
        var cursor = 0.0

        return zip(textLines, wordCounts).map { text, wordCount in
            let segmentDuration = max(1.2, usableDuration * Double(wordCount) / Double(totalWords))
            let subtitle = TimedSubtitle(start: cursor, end: min(cursor + segmentDuration, usableDuration), text: text)
            cursor += segmentDuration
            return subtitle
        }
    }

    static func fileSize(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue) ?? 0
    }
}

enum WhisperKitTranscriber {
    static func transcribe(_ mediaURL: URL) async throws -> [TimedSubtitle] {
        let reportDirectory = mediaURL.deletingLastPathComponent()
            .appendingPathComponent("WhisperKit Reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)

        let command = ProcessInfo.processInfo.environment["SHADOW_COACH_WHISPERKIT_COMMAND"] ?? "whisperkit-cli"
        let commandParts = command.split(separator: " ").map(String.init)
        guard let executable = commandParts.first else {
            throw NSError(domain: "WhisperKitTranscriber", code: -1, userInfo: [NSLocalizedDescriptionKey: "WhisperKit command is empty"])
        }

        let arguments = Array(commandParts.dropFirst()) + [
            "transcribe",
            "--audio-path", mediaURL.path,
            "--model", "tiny.en",
            "--language", "en",
            "--skip-special-tokens",
            "--report",
            "--report-path", reportDirectory.path
        ]

        let output = try CommandRunner.run(
            executable: "/usr/bin/env",
            arguments: [executable] + arguments,
            environment: [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/opt/homebrew/sbin:/usr/local/sbin"
            ]
        )
        ImportLogger.write("whisperkit-cli output \(output.suffix(2000))")

        let reports = try FileManager.default.contentsOfDirectory(at: reportDirectory, includingPropertiesForKeys: nil)
        guard let srtURL = reports
            .filter({ $0.pathExtension.lowercased() == "srt" })
            .sorted(by: { URLMediaImporter.fileSize($0) > URLMediaImporter.fileSize($1) })
            .first else {
            throw NSError(domain: "WhisperKitTranscriber", code: -2, userInfo: [NSLocalizedDescriptionKey: "WhisperKit did not create an SRT report"])
        }
        let raw = try String(contentsOf: srtURL, encoding: .utf8)
        return SubtitleSegmenter.segment(TimedSubtitleParser.parse(raw))
    }
}

enum SpeechRecognitionHints {
    private static let knownTerms: [String] = [
        "AGV", "AMR", "LiDAR", "LM174", "MID360", "PAT", "RoboShop", "WhisperX"
    ]

    private static let contextualPhraseHints: [(pattern: String, terms: [String])] = [
        (#"\bon(?:[\s-]+)?site\b"#, ["on-site", "onsite"]),
        (#"\bcheck(?:[\s-]+)?points?\b"#, ["checkpoint", "checkpoints"])
    ]

    static func terms(in referenceText: String) -> [String] {
        let tokens = referenceText
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let knownByLowercase = Dictionary(
            uniqueKeysWithValues: knownTerms.map { ($0.lowercased(), $0) }
        )
        var seen = Set<String>()
        var result: [String] = []

        for token in tokens {
            let lowercase = token.lowercased()
            let containsLetter = token.unicodeScalars.contains { CharacterSet.letters.contains($0) }
            let containsDigit = token.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
            let isAcronym = token.count > 1
                && containsLetter
                && token == token.uppercased()
            let canonical = knownByLowercase[lowercase]
                ?? ((containsLetter && containsDigit) || isAcronym ? token : nil)
            guard let canonical, seen.insert(canonical.lowercased()).inserted else { continue }
            result.append(canonical)
        }

        for hint in contextualPhraseHints {
            guard referenceText.range(of: hint.pattern, options: [.regularExpression, .caseInsensitive]) != nil else {
                continue
            }
            for term in hint.terms where seen.insert(term.lowercased()).inserted {
                result.append(term)
            }
        }
        return result
    }
}

enum FastWhisperTranscriber {
    static let modelName = "small"
    static let cacheIdentifier = "faster-whisper-small-contextual-hints-v2"

    private struct FastTranscriptJSON: Decodable {
        struct Segment: Decodable {
            let text: String
            let start: Double
            let end: Double
        }

        let transcript: String
        let segments: [Segment]
    }

    static func transcribeDetailed(_ mediaURL: URL, referenceText: String = "") async throws -> DetailedTranscript {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowCoach Fast Transcript \(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let python = ProcessInfo.processInfo.environment["SHADOW_COACH_PYTHON"]
            ?? "\(NSHomeDirectory())/.local/share/shadowcoach-whisperx-venv/bin/python"
        let scriptURL = fastTranscriptScriptURL()
        var arguments = [
            python,
            scriptURL.path,
            "--audio", mediaURL.path,
            "--output", outputURL.path,
            "--model", modelName
        ]
        let recognitionHints = SpeechRecognitionHints.terms(in: referenceText)
        if !recognitionHints.isEmpty {
            arguments += ["--hotwords", recognitionHints.joined(separator: ", ")]
        }

        let output = try CommandRunner.run(
            executable: "/usr/bin/env",
            arguments: arguments,
            environment: [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/opt/homebrew/sbin:/usr/local/sbin"
            ]
        )
        if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ImportLogger.write("fast-whisper output \(output.suffix(1000))")
        }

        let data = try Data(contentsOf: outputURL)
        let decoded = try JSONDecoder().decode(FastTranscriptJSON.self, from: data)
        let transcript = decoded.transcript
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            throw NSError(domain: "FastWhisperTranscriber", code: -1, userInfo: [NSLocalizedDescriptionKey: "The fast local recognizer returned an empty transcript"])
        }
        return DetailedTranscript(
            transcript: transcript,
            words: [],
            rawJSON: String(data: data, encoding: .utf8)
        )
    }

    private static func fastTranscriptScriptURL() -> URL {
        if let bundled = Bundle.main.url(forResource: "fast_transcribe", withExtension: "py") {
            return bundled
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/fast_transcribe.py")
    }
}

enum WhisperXTranscriber {
    static let modelName = "small"
    static let alignedCacheIdentifier = "whisperx-small-aligned-contextual-hints-v2"
    static let unalignedCacheIdentifier = "whisperx-small-contextual-hints-v2"

    private struct WhisperXJSON: Decodable {
        struct Segment: Decodable {
            struct Word: Decodable {
                let word: String?
                let start: Double?
                let end: Double?
            }

            let text: String?
            let words: [Word]?
        }

        let segments: [Segment]?
    }

    static func transcribe(_ mediaURL: URL) async throws -> [TimedSubtitle] {
        let reportDirectory = mediaURL.deletingLastPathComponent()
            .appendingPathComponent("WhisperX Reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)

        let defaultCommand = "\(NSHomeDirectory())/.local/share/shadowcoach-whisperx-venv/bin/whisperx"
        let command = ProcessInfo.processInfo.environment["SHADOW_COACH_WHISPERX_COMMAND"] ?? defaultCommand
        let commandParts = command.split(separator: " ").map(String.init)
        guard let executable = commandParts.first else {
            throw NSError(domain: "WhisperXTranscriber", code: -1, userInfo: [NSLocalizedDescriptionKey: "WhisperX command is empty"])
        }

        let arguments = Array(commandParts.dropFirst()) + [
            mediaURL.path,
            "--model", modelName,
            "--language", "en",
            "--device", "cpu",
            "--compute_type", "int8",
            "--output_format", "srt",
            "--output_dir", reportDirectory.path,
            "--verbose", "False",
            "--print_progress", "False"
        ]

        let output = try CommandRunner.run(
            executable: "/usr/bin/env",
            arguments: [executable] + arguments,
            environment: [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/opt/homebrew/sbin:/usr/local/sbin"
            ]
        )
        ImportLogger.write("whisperx output \(output.suffix(2000))")

        let reports = try FileManager.default.contentsOfDirectory(at: reportDirectory, includingPropertiesForKeys: nil)
        guard let srtURL = reports
            .filter({ $0.pathExtension.lowercased() == "srt" })
            .sorted(by: { URLMediaImporter.fileSize($0) > URLMediaImporter.fileSize($1) })
            .first else {
            throw NSError(domain: "WhisperXTranscriber", code: -2, userInfo: [NSLocalizedDescriptionKey: "WhisperX did not create an SRT report"])
        }
        let raw = try String(contentsOf: srtURL, encoding: .utf8)
        return SubtitleSegmenter.segment(TimedSubtitleParser.parse(raw))
    }

    static func transcribeDetailed(
        _ mediaURL: URL,
        alignWords: Bool = true,
        referenceText: String = ""
    ) async throws -> DetailedTranscript {
        let reportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowCoach WhisperX \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)

        let defaultCommand = "\(NSHomeDirectory())/.local/share/shadowcoach-whisperx-venv/bin/whisperx"
        let command = ProcessInfo.processInfo.environment["SHADOW_COACH_WHISPERX_COMMAND"] ?? defaultCommand
        let commandParts = command.split(separator: " ").map(String.init)
        guard let executable = commandParts.first else {
            throw NSError(domain: "WhisperXTranscriber", code: -1, userInfo: [NSLocalizedDescriptionKey: "WhisperX command is empty"])
        }

        var arguments = Array(commandParts.dropFirst()) + [
            mediaURL.path,
            "--model", modelName,
            "--language", "en",
            "--device", "cpu",
            "--compute_type", "int8",
            "--output_format", "json",
            "--output_dir", reportDirectory.path,
            "--verbose", "False",
            "--print_progress", "False"
        ]
        if !alignWords {
            arguments.append("--no_align")
        }
        let recognitionHints = SpeechRecognitionHints.terms(in: referenceText)
        if !recognitionHints.isEmpty {
            arguments += ["--hotwords", recognitionHints.joined(separator: ", ")]
        }

        let output = try CommandRunner.run(
            executable: "/usr/bin/env",
            arguments: [executable] + arguments,
            environment: [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/opt/homebrew/sbin:/usr/local/sbin"
            ]
        )
        ImportLogger.write("whisperx detailed output \(output.suffix(2000))")

        let reports = try FileManager.default.contentsOfDirectory(at: reportDirectory, includingPropertiesForKeys: nil)
        guard let jsonURL = reports
            .filter({ $0.pathExtension.lowercased() == "json" })
            .sorted(by: { URLMediaImporter.fileSize($0) > URLMediaImporter.fileSize($1) })
            .first else {
            throw NSError(domain: "WhisperXTranscriber", code: -3, userInfo: [NSLocalizedDescriptionKey: "WhisperX did not create a JSON transcript"])
        }

        let data = try Data(contentsOf: jsonURL)
        let decoded = try JSONDecoder().decode(WhisperXJSON.self, from: data)
        let segments = decoded.segments ?? []
        let transcript = segments.compactMap(\.text).joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let words = segments.flatMap { segment -> [TimedWord] in
            (segment.words ?? []).compactMap { word in
                guard let raw = word.word?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
                let normalized = WordDiffEngine.normalize(raw)
                guard !normalized.isEmpty else { return nil }
                return TimedWord(text: raw, normalized: normalized, start: word.start, end: word.end)
            }
        }
        guard !transcript.isEmpty || !words.isEmpty else {
            throw NSError(domain: "WhisperXTranscriber", code: -4, userInfo: [NSLocalizedDescriptionKey: "WhisperX returned an empty transcript"])
        }
        return DetailedTranscript(
            transcript: transcript.isEmpty ? words.map(\.text).joined(separator: " ") : transcript,
            words: words,
            rawJSON: String(data: data, encoding: .utf8)
        )
    }
}

struct ProviderConfig: Codable {
    let azure: AzureProviderConfig?
}

struct AzureProviderConfig: Codable {
    let speechKey: String?
    let translatorKey: String?
    let endpoint: String?
    let translatorEndpoint: String?
    let region: String?
    let translatorRegion: String?

    enum CodingKeys: String, CodingKey {
        case speechKey = "speech_key"
        case translatorKey = "translator_key"
        case endpoint
        case translatorEndpoint = "translator_endpoint"
        case region
        case translatorRegion = "translator_region"
    }
}

enum ProviderConfigLoader {
    static func load(shadowCoachAppSupportDirectory: URL) -> ProviderConfig? {
        let url = shadowCoachAppSupportDirectory.appendingPathComponent("provider-config.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProviderConfig.self, from: data)
    }
}

enum PhraseTranslatorClient {
    static func translate(_ text: String, shadowCoachAppSupportDirectory: URL) async throws -> String {
        do {
            return try await AzureTranslatorClient.translate(text, shadowCoachAppSupportDirectory: shadowCoachAppSupportDirectory)
        } catch {
            ImportLogger.write("azure translate failed; falling back to MyMemory: \(error.localizedDescription)")
            do {
                return try await MyMemoryTranslatorClient.translate(text)
            } catch {
                throw NSError(domain: "PhraseTranslatorClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Azure Translator is not available, and the free fallback also failed. Try again later or add translator_key in provider-config.json."])
            }
        }
    }
}

enum AzureTranslatorClient {
    static func translate(_ text: String, shadowCoachAppSupportDirectory: URL) async throws -> String {
        guard let config = ProviderConfigLoader.load(shadowCoachAppSupportDirectory: shadowCoachAppSupportDirectory),
              let azure = config.azure else {
            throw NSError(domain: "AzureTranslatorClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No Azure config found. Add provider-config.json to Shadow Coach's Application Support folder."])
        }
        let key = (azure.translatorKey ?? azure.speechKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw NSError(domain: "AzureTranslatorClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Azure key is missing in provider-config.json."])
        }

        var components = URLComponents(url: translatorEndpoint(for: azure), resolvingAgainstBaseURL: false)!
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/translate"
        if !components.path.hasPrefix("/") {
            components.path = "/" + components.path
        }
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "3.0"),
            URLQueryItem(name: "from", value: "en"),
            URLQueryItem(name: "to", value: "zh-Hans")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        let region = (azure.translatorRegion ?? azure.region ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !region.isEmpty {
            request.setValue(region, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [["Text": text]])

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            let message: String
            if http.statusCode == 401 || http.statusCode == 403 {
                message = "Azure Translator rejected the key/region. Check whether the Speech resource is multi-service or add translator_key/translator_endpoint."
            } else {
                message = detail
            }
            throw NSError(domain: "AzureTranslatorClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let translations = array.first?["translations"] as? [[String: Any]],
              let translated = translations.first?["text"] as? String,
              !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "AzureTranslatorClient", code: -3, userInfo: [NSLocalizedDescriptionKey: "Azure returned no translation text."])
        }
        return translated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func translatorEndpoint(for config: AzureProviderConfig) -> URL {
        if let endpoint = config.translatorEndpoint?.trimmingCharacters(in: .whitespacesAndNewlines), !endpoint.isEmpty,
           let url = URL(string: endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) {
            return url
        }
        return URL(string: "https://api.cognitive.microsofttranslator.com")!
    }
}

enum MyMemoryTranslatorClient {
    static func translate(_ text: String) async throws -> String {
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "en|zh-CN")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("ShadowCoach/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "MyMemoryTranslatorClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: detail])
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseData = object["responseData"] as? [String: Any],
              let translated = responseData["translatedText"] as? String,
              !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "MyMemoryTranslatorClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Free translator returned no text."])
        }
        return translated
            .replacingOccurrences(of: #"&#39;"#, with: "'", options: .regularExpression)
            .replacingOccurrences(of: #"&quot;"#, with: "\"", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AzurePronunciationClient {
    static func assess(audioURL: URL, referenceText: String, shadowCoachAppSupportDirectory: URL) async throws -> AzurePronunciationAnalysis {
        guard let config = ProviderConfigLoader.load(shadowCoachAppSupportDirectory: shadowCoachAppSupportDirectory),
              let azure = config.azure,
              let key = azure.speechKey,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AzurePronunciationAnalysis(
                enabled: false,
                error: nil,
                rawStatus: nil,
                display: "",
                accuracy: nil,
                fluency: nil,
                completeness: nil,
                prosody: nil,
                pronunciation: nil,
                words: [],
                rawJSON: nil
            )
        }

        let wavURL = try normalizedWav(from: audioURL)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        var request = URLRequest(url: try speechURL(for: azure))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("audio/wav; codecs=audio/pcm; samplerate=16000", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        let assessment: [String: Any] = [
            "ReferenceText": referenceText,
            "GradingSystem": "HundredMark",
            "Granularity": "Phoneme",
            "Dimension": "Comprehensive",
            "EnableMiscue": "True",
            "EnableProsodyAssessment": "True"
        ]
        let assessmentData = try JSONSerialization.data(withJSONObject: assessment)
        request.setValue(assessmentData.base64EncodedString(), forHTTPHeaderField: "Pronunciation-Assessment")
        request.httpBody = try Data(contentsOf: wavURL)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "AzurePronunciationClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: detail])
        }
        let rawObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let rawJSON = String(data: try JSONSerialization.data(withJSONObject: rawObject, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)
        return parse(rawObject, rawJSON: rawJSON)
    }

    private static func speechURL(for config: AzureProviderConfig) throws -> URL {
        var region = config.region?.trimmingCharacters(in: .whitespacesAndNewlines)
        if (region == nil || region?.isEmpty == true),
           let endpoint = config.endpoint,
           let host = URL(string: endpoint)?.host {
            let parts = host.split(separator: ".").map(String.init)
            if parts.count >= 5, parts.dropFirst() == ["api", "cognitive", "microsoft", "com"] {
                region = parts[0]
            }
        }
        if let region, !region.isEmpty {
            return URL(string: "https://\(region).stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=en-US&format=detailed")!
        }
        if let endpoint = config.endpoint?.trimmingCharacters(in: .whitespacesAndNewlines), !endpoint.isEmpty {
            return URL(string: endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/stt/speech/recognition/conversation/cognitiveservices/v1?language=en-US&format=detailed")!
        }
        throw NSError(domain: "AzurePronunciationClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Azure Speech endpoint or region is missing."])
    }

    private static func normalizedWav(from audioURL: URL) throws -> URL {
        let wavURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowCoach Azure \(UUID().uuidString).wav")
        let ffmpeg = LocalToolLocator.command(named: "ffmpeg", overrideVariable: "SHADOW_COACH_FFMPEG")
        _ = try CommandRunner.run(
            executable: ffmpeg.executable,
            arguments: ffmpeg.argumentsPrefix + ["-y", "-i", audioURL.path, "-ac", "1", "-ar", "16000", "-vn", "-f", "wav", wavURL.path],
            environment: [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/opt/homebrew/sbin:/usr/local/sbin"
            ]
        )
        return wavURL
    }

    private static func parse(_ json: [String: Any], rawJSON: String?) -> AzurePronunciationAnalysis {
        let best = (json["NBest"] as? [[String: Any]])?.first ?? [:]
        let words = (best["Words"] as? [[String: Any]] ?? []).map(parseWord)
        return AzurePronunciationAnalysis(
            enabled: true,
            error: nil,
            rawStatus: json["RecognitionStatus"] as? String,
            display: (best["Display"] as? String) ?? (json["DisplayText"] as? String) ?? "",
            accuracy: number(best["AccuracyScore"]),
            fluency: number(best["FluencyScore"]),
            completeness: number(best["CompletenessScore"]),
            prosody: number(best["ProsodyScore"]),
            pronunciation: number(best["PronScore"]),
            words: words,
            rawJSON: rawJSON
        )
    }

    private static func parseWord(_ raw: [String: Any]) -> AzurePronunciationWord {
        let assessment = raw["PronunciationAssessment"] as? [String: Any] ?? [:]
        let rawSyllables = raw["Syllables"] as? [[String: Any]] ?? []
        let syllables = rawSyllables.map { unit in
            parseUnit(unit, textKeys: ["Syllable", "Grapheme"])
        }
        let directPhonemes = raw["Phonemes"] as? [[String: Any]] ?? []
        let nestedPhonemes = rawSyllables.flatMap { syllable in
            syllable["Phonemes"] as? [[String: Any]] ?? []
        }
        let phonemes = (directPhonemes + nestedPhonemes).map { unit in
            parseUnit(unit, textKeys: ["Phoneme"])
        }
        return AzurePronunciationWord(
            text: string(raw["Word"]) ?? string(raw["DisplayText"]) ?? "",
            accuracy: number(assessment["AccuracyScore"]) ?? number(raw["AccuracyScore"]),
            errorType: string(assessment["ErrorType"]) ?? string(raw["ErrorType"]),
            offsetSeconds: seconds(fromAzureTicks: raw["Offset"]),
            durationSeconds: seconds(fromAzureTicks: raw["Duration"]),
            syllables: syllables,
            phonemes: phonemes
        )
    }

    private static func parseUnit(_ raw: [String: Any], textKeys: [String]) -> AzurePronunciationUnit {
        let assessment = raw["PronunciationAssessment"] as? [String: Any] ?? [:]
        let text = textKeys.compactMap { string(raw[$0]) }.first ?? ""
        return AzurePronunciationUnit(
            text: text,
            accuracy: number(assessment["AccuracyScore"]) ?? number(raw["AccuracyScore"]),
            offsetSeconds: seconds(fromAzureTicks: raw["Offset"]),
            durationSeconds: seconds(fromAzureTicks: raw["Duration"])
        )
    }

    private static func seconds(fromAzureTicks value: Any?) -> Double? {
        number(value).map { $0 / 10_000_000 }
    }

    private static func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}

enum ProsodyAnalyzer {
    private struct RawProsody: Decodable {
        let user: ProsodyTrack
        let reference: ProsodyTrack?
    }

    static func analyze(
        userAudioURL: URL,
        referenceAudioURL: URL?,
        referenceStart: Double?,
        referenceEnd: Double?,
        userWords: [TimedWord],
        targetWordCount: Int
    ) throws -> ProsodyAnalysis {
        let scriptURL = prosodyScriptURL()
        var arguments = [
            scriptURL.path,
            "--user-audio", userAudioURL.path,
            "--user-word-count", "\(userWords.count)",
            "--target-word-count", "\(targetWordCount)"
        ]
        if let referenceAudioURL, let referenceStart, let referenceEnd {
            arguments += [
                "--reference-audio", referenceAudioURL.path,
                "--reference-start", "\(referenceStart)",
                "--reference-end", "\(referenceEnd)"
            ]
        }

        let python = ProcessInfo.processInfo.environment["SHADOW_COACH_PYTHON"]
            ?? "\(NSHomeDirectory())/.local/share/shadowcoach-whisperx-venv/bin/python"
        let output = try CommandRunner.run(
            executable: "/usr/bin/env",
            arguments: [python] + arguments,
            environment: [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/opt/homebrew/sbin:/usr/local/sbin"
            ]
        )
        guard let data = output.data(using: .utf8) else {
            throw NSError(domain: "ProsodyAnalyzer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Prosody analyzer returned non-UTF8 output"])
        }
        let raw = try JSONDecoder().decode(RawProsody.self, from: data)
        let userStress = stressCandidates(from: userWords, windows: raw.user.emphasisWindows)
        return ProsodyAnalysis(
            user: raw.user,
            reference: raw.reference,
            userStressCandidates: userStress,
            referenceStressCandidates: []
        )
    }

    private static func prosodyScriptURL() -> URL {
        if let bundled = Bundle.main.url(forResource: "prosody_analyzer", withExtension: "py") {
            return bundled
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/prosody_analyzer.py")
    }

    private static func stressCandidates(from words: [TimedWord], windows: [TimeWindow]) -> [String] {
        guard !words.isEmpty, !windows.isEmpty else { return [] }
        var candidates: [String] = []
        for word in words {
            guard let start = word.start, let end = word.end else { continue }
            let midpoint = (start + end) / 2
            if windows.contains(where: { midpoint >= $0.start && midpoint <= $0.end }) {
                candidates.append(word.text)
            }
        }
        return Array(candidates.prefix(8))
    }
}

enum HTMLTranscriptExtractor {
    static func extractTranscript(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw NSError(domain: "HTMLTranscriptExtractor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not read webpage text"])
        }

        let paragraphs = html.matches(pattern: #"<p[^>]*>(.*?)</p>"#)
            .map(stripHTML)
            .map(decodeEntities)
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { text in
                text.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil &&
                text.split(separator: " ").count >= 4
            }

        let transcript = paragraphs.joined(separator: "\n")
        guard !transcript.isEmpty else {
            throw NSError(domain: "HTMLTranscriptExtractor", code: -2, userInfo: [NSLocalizedDescriptionKey: "No transcript-like webpage text found"])
        }
        return transcript
    }

    private static func stripHTML(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }

    private static func decodeEntities(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

enum LocalToolLocator {
    struct Command {
        let executable: String
        let argumentsPrefix: [String]
    }

    static func command(named name: String, overrideVariable: String) -> Command {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment[overrideVariable]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return Command(executable: override, argumentsPrefix: [])
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let candidates = [
            appSupport.appendingPathComponent("ShadowCoach/Tools/\(name)").path,
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        if let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return Command(executable: executable, argumentsPrefix: [])
        }
        return Command(executable: "/usr/bin/env", argumentsPrefix: [name])
    }
}

enum CommandRunner {
    static func run(executable: String, arguments: [String], environment: [String: String] = [:]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        var mergedEnvironment = ProcessInfo.processInfo.environment
        environment.forEach { mergedEnvironment[$0.key] = $0.value }
        process.environment = mergedEnvironment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var outputData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        try process.run()
        process.waitUntilExit()
        group.wait()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw NSError(domain: "CommandRunner", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "Command failed" : output])
        }
        return output
    }
}

extension String {
    func matches(pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: self) else { return nil }
            return String(self[range])
        }
    }
}

enum ImportLogger {
    private static let queue = DispatchQueue(label: "ShadowCoach.importLogger", qos: .utility)
    private static let maximumLogSize = 2 * 1_024 * 1_024

    static var logURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShadowCoach", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("import.log")
    }

    static func write(_ message: String) {
        let timestamp = Date()
        queue.async {
            let formatter = ISO8601DateFormatter()
            let line = "\(formatter.string(from: timestamp)) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            let destination = logURL
            rotateLogIfNeeded(at: destination, incomingBytes: data.count)

            if FileManager.default.fileExists(atPath: destination.path),
               let handle = try? FileHandle(forWritingTo: destination) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: destination, options: .atomic)
            }
        }
    }

    private static func rotateLogIfNeeded(at url: URL, incomingBytes: Int) {
        let existingBytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
            .intValue ?? 0
        guard existingBytes + incomingBytes > maximumLogSize else { return }

        let archivedURL = url.deletingLastPathComponent().appendingPathComponent("import.previous.log")
        try? FileManager.default.removeItem(at: archivedURL)
        try? FileManager.default.moveItem(at: url, to: archivedURL)
    }
}

enum XlsxTextExtractor {
    static func extractText(from url: URL) throws -> String {
        let start = Date()
        let sharedStringsData = try readZipEntry("xl/sharedStrings.xml", from: url)
        ImportLogger.write("xlsx sharedStrings bytes=\(sharedStringsData.count) elapsed=\(Date().timeIntervalSince(start))")
        let sheetData = try readZipEntry("xl/worksheets/sheet1.xml", from: url)
        ImportLogger.write("xlsx sheet bytes=\(sheetData.count) elapsed=\(Date().timeIntervalSince(start))")
        let sharedStrings = try SharedStringsParser.parse(sharedStringsData)
        ImportLogger.write("xlsx sharedStrings parsed count=\(sharedStrings.count) elapsed=\(Date().timeIntervalSince(start))")
        let rows = try SheetTextParser.parse(sheetData, sharedStrings: sharedStrings)
        ImportLogger.write("xlsx sheet parsed rows=\(rows.count) elapsed=\(Date().timeIntervalSince(start))")
        return rows.joined(separator: "\n")
    }

    static func extractTimedSubtitles(from url: URL) throws -> [TimedSubtitle] {
        let sharedStringsData = try readZipEntry("xl/sharedStrings.xml", from: url)
        let sheetData = try readZipEntry("xl/worksheets/sheet1.xml", from: url)
        let sharedStrings = try SharedStringsParser.parse(sharedStringsData)
        let rows = try SheetRowsParser.parse(sheetData, sharedStrings: sharedStrings)
        var startsAndTexts: [(Double, String)] = []

        for row in rows {
            guard row.count >= 2,
                  let start = TimedSubtitleParser.parseTime(row[0]) else { continue }
            let text = row[1...].joined(separator: " ")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”")))
            if TimedSubtitleParser.isUsable(text) {
                startsAndTexts.append((start, text))
            }
        }

        return startsAndTexts.enumerated().map { index, item in
            let nextStart = index + 1 < startsAndTexts.count ? startsAndTexts[index + 1].0 : item.0 + 4.0
            return TimedSubtitle(start: item.0, end: max(nextStart, item.0 + 0.8), text: item.1)
        }
    }

    private static func readZipEntry(_ entry: String, from url: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, entry]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let message = String(data: errorData, encoding: .utf8) ?? "Could not read \(entry)"
            throw NSError(domain: "XlsxTextExtractor", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }
        return data
    }
}

final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var insideText = false

    static func parse(_ data: Data) throws -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? NSError(domain: "SharedStringsParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not parse shared strings"])
        }
        return delegate.strings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "si" { current = "" }
        if elementName == "t" { insideText = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "t" { insideText = false }
        if elementName == "si" { strings.append(current) }
    }
}

final class SheetTextParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var rows: [String] = []
    private var currentRow: [String] = []
    private var currentCellType = ""
    private var currentValue = ""
    private var insideValue = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    static func parse(_ data: Data, sharedStrings: [String]) throws -> [String] {
        let delegate = SheetTextParser(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? NSError(domain: "SheetTextParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not parse worksheet"])
        }
        return delegate.rows
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "row" {
            currentRow = []
        } else if elementName == "c" {
            currentCellType = attributeDict["t"] ?? ""
            currentValue = ""
        } else if elementName == "v" || elementName == "t" {
            insideValue = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideValue { currentValue += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "v" || elementName == "t" {
            insideValue = false
        } else if elementName == "c" {
            let value = resolvedValue()
            if value.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil {
                currentRow.append(value)
            }
            currentCellType = ""
            currentValue = ""
        } else if elementName == "row" {
            let text = currentRow.joined(separator: " ")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { rows.append(text) }
            currentRow = []
        }
    }

    private func resolvedValue() -> String {
        let trimmed = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentCellType == "s", let index = Int(trimmed), sharedStrings.indices.contains(index) {
            return sharedStrings[index]
        }
        return trimmed
    }
}

final class SheetRowsParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var rows: [[String]] = []
    private var currentRow: [String] = []
    private var currentCellType = ""
    private var currentValue = ""
    private var insideValue = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    static func parse(_ data: Data, sharedStrings: [String]) throws -> [[String]] {
        let delegate = SheetRowsParser(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? NSError(domain: "SheetRowsParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not parse worksheet rows"])
        }
        return delegate.rows
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "row" {
            currentRow = []
        } else if elementName == "c" {
            currentCellType = attributeDict["t"] ?? ""
            currentValue = ""
        } else if elementName == "v" || elementName == "t" {
            insideValue = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideValue { currentValue += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "v" || elementName == "t" {
            insideValue = false
        } else if elementName == "c" {
            currentRow.append(resolvedValue())
            currentCellType = ""
            currentValue = ""
        } else if elementName == "row" {
            if !currentRow.isEmpty { rows.append(currentRow) }
            currentRow = []
        }
    }

    private func resolvedValue() -> String {
        let trimmed = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentCellType == "s", let index = Int(trimmed), sharedStrings.indices.contains(index) {
            return sharedStrings[index]
        }
        return trimmed
    }
}

struct GeminiResponse: Decodable {
    let candidates: [Candidate]

    struct Candidate: Decodable {
        let content: Content
    }

    struct Content: Decodable {
        let parts: [Part]
    }

    struct Part: Decodable {
        let text: String?
    }
}

enum CodexWorkload: String, CaseIterable {
    case learningTargetSelection
    case practiceGeneration
    case transformationFeedback
    case freeSpeakingFeedback
    case realUseFeedback
    case exactCoaching
    case exactFollowUp
    case transformationFollowUp
    case freeSpeakingFollowUp

    fileprivate var tier: CodexModelTier {
        switch self {
        case .learningTargetSelection, .practiceGeneration, .transformationFeedback,
             .realUseFeedback, .transformationFollowUp:
            return .fast
        case .freeSpeakingFeedback, .exactCoaching, .exactFollowUp, .freeSpeakingFollowUp:
            return .nuanced
        }
    }

    static func feedback(for activity: PracticeActivity) -> CodexWorkload {
        switch activity {
        case .transformation: return .transformationFeedback
        case .freeExpression: return .freeSpeakingFeedback
        case .shadowing, .correction: return .exactCoaching
        }
    }

    static func followUp(for activity: PracticeActivity) -> CodexWorkload {
        switch activity {
        case .transformation: return .transformationFollowUp
        case .freeExpression: return .freeSpeakingFollowUp
        case .shadowing, .correction: return .exactFollowUp
        }
    }
}

enum CodexModelTier: Equatable {
    case fast
    case nuanced
}

struct CodexModelRoute: Equatable {
    let model: String
    let reasoningEffort: String
    let tier: CodexModelTier
}

enum CodexModelRouter {
    private struct Catalog: Decodable {
        let models: [CatalogModel]
    }

    private struct CatalogModel: Decodable {
        let slug: String
    }

    private static let fastCandidates = [
        "gpt-5.6-luna",
        "gpt-5.4-mini",
        "gpt-5.6-terra",
        "gpt-5.4",
        "gpt-5.5",
        "gpt-5.6-sol"
    ]
    private static let nuancedCandidates = [
        "gpt-5.6-terra",
        "gpt-5.5",
        "gpt-5.4",
        "gpt-5.6-luna",
        "gpt-5.6-sol",
        "gpt-5.4-mini"
    ]

    static func route(
        for workload: CodexWorkload,
        availableModels: Set<String>? = nil
    ) -> CodexModelRoute {
        let available = availableModels ?? discoveredModels()
        let candidates = workload.tier == .fast ? fastCandidates : nuancedCandidates
        let fallback = workload.tier == .fast ? "gpt-5.4-mini" : "gpt-5.4"
        let model: String

        if available.isEmpty {
            model = fallback
        } else if let preferred = candidates.first(where: available.contains) {
            model = preferred
        } else {
            model = available
                .filter { $0 != "codex-auto-review" }
                .sorted()
                .first ?? fallback
        }

        return CodexModelRoute(
            model: model,
            reasoningEffort: "none",
            tier: workload.tier
        )
    }

    static var settingsSummary: String {
        let fast = route(for: .learningTargetSelection).model
        let nuanced = route(for: .exactCoaching).model
        if fast == nuanced {
            return displayName(for: fast)
        }
        return "Fast: \(displayName(for: fast)) · Deep: \(displayName(for: nuanced))"
    }

    static func displayName(for model: String) -> String {
        model
            .replacingOccurrences(of: "gpt-", with: "GPT ")
            .replacingOccurrences(of: "-codex-", with: " Codex ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { token in
                let lower = token.lowercased()
                if lower == "gpt" { return "GPT" }
                if lower == "codex" { return "Codex" }
                return token.prefix(1).uppercased() + token.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func discoveredModels() -> Set<String> {
        let catalogURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/models_cache.json")
        guard let data = try? Data(contentsOf: catalogURL),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else {
            return []
        }
        return Set(catalog.models.map(\.slug))
    }
}

enum CodexFeedbackClient {
    static func route(for workload: CodexWorkload) -> CodexModelRoute {
        CodexModelRouter.route(for: workload)
    }

    static func run(
        prompt: String,
        workload: CodexWorkload,
        onPartial: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let route = route(for: workload)
        ImportLogger.write("codex route workload=\(workload.rawValue) tier=\(route.tier) model=\(route.model)")
        return try await run(
            prompt: prompt,
            model: route.model,
            reasoningEffort: route.reasoningEffort,
            onPartial: onPartial
        )
    }

    static func run(
        prompt: String,
        model: String? = nil,
        reasoningEffort: String? = nil,
        onPartial: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        if let model, !model.isEmpty {
            do {
                let startedAt = Date()
                let result = try await CodexAppServerClient.shared.run(
                    prompt: prompt,
                    model: model,
                    reasoningEffort: reasoningEffort ?? "none",
                    onPartial: onPartial
                )
                ImportLogger.write("codex persistent done model=\(model) seconds=\(String(format: "%.2f", Date().timeIntervalSince(startedAt)))")
                return result
            } catch {
                ImportLogger.write("codex persistent failed; using exec fallback: \(error.localizedDescription)")
            }
        }
        return try await runExec(prompt: prompt, model: model, reasoningEffort: reasoningEffort)
    }

    private static func runExec(
        prompt: String,
        model: String?,
        reasoningEffort: String?
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("shadowcoach-codex-\(UUID().uuidString).txt")
            let stdoutURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("shadowcoach-codex-stdout-\(UUID().uuidString).log")
            let stderrURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("shadowcoach-codex-stderr-\(UUID().uuidString).log")
            defer {
                try? FileManager.default.removeItem(at: outputURL)
                try? FileManager.default.removeItem(at: stdoutURL)
                try? FileManager.default.removeItem(at: stderrURL)
            }

            let process = Process()
            let executable = Self.codexExecutablePath()
            process.executableURL = URL(fileURLWithPath: executable)
            var arguments = [
                "exec",
                "--ignore-user-config",
                "--ignore-rules",
                "--disable", "plugins",
                "--disable", "apps",
                "--disable", "remote_plugin",
                "--disable", "skill_search",
                "--disable", "multi_agent",
                "--cd", FileManager.default.temporaryDirectory.path
            ]
            if let model, !model.isEmpty {
                arguments += ["--model", model]
            }
            if let reasoningEffort, !reasoningEffort.isEmpty {
                arguments += ["--config", "model_reasoning_effort=\"\(reasoningEffort)\""]
            }
            arguments += [
                "--sandbox", "read-only",
                "--skip-git-repo-check",
                "--ephemeral",
                "--output-last-message", outputURL.path,
                "-"
            ]
            if executable == "/usr/bin/env" {
                arguments.insert("codex", at: 0)
            }
            process.arguments = arguments
            process.environment = Self.processEnvironment()

            let stdin = Pipe()
            FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
            let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
            let stderrHandle = try FileHandle(forWritingTo: stderrURL)
            defer {
                try? stdoutHandle.close()
                try? stderrHandle.close()
            }
            process.standardInput = stdin
            process.standardOutput = stdoutHandle
            process.standardError = stderrHandle

            try process.run()
            if let data = prompt.data(using: .utf8) {
                stdin.fileHandleForWriting.write(data)
            }
            stdin.fileHandleForWriting.closeFile()
            let timeout = Date().addingTimeInterval(180)
            while process.isRunning && Date() < timeout {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
                throw NSError(
                    domain: "CodexFeedback",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Local Codex timed out after 3 minutes. Check that the Codex CLI is signed in, then analyze again."]
                )
            }
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = (try? Data(contentsOf: stderrURL)) ?? Data()
                let outputData = (try? Data(contentsOf: stdoutURL)) ?? Data()
                let message = [
                    String(data: errorData, encoding: .utf8),
                    String(data: outputData, encoding: .utf8)
                ]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                let conciseMessage = String(message.suffix(1_800))
                throw NSError(
                    domain: "CodexFeedback",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: conciseMessage.isEmpty ? "Codex CLI failed. Run codex in Terminal once to verify sign-in." : conciseMessage]
                )
            }

            let data = try Data(contentsOf: outputURL)
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else {
                throw NSError(domain: "CodexFeedback", code: -1, userInfo: [NSLocalizedDescriptionKey: "Codex returned no feedback."])
            }
            return text
        }.value
    }

    fileprivate static func codexExecutablePath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/env"
    }

    fileprivate static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        environment["PATH"] = "\(home)/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/opt/homebrew/sbin:/usr/local/sbin"
        return environment
    }
}

final class CodexAppServerClient: @unchecked Sendable {
    static let shared = CodexAppServerClient()

    private let requestQueue = DispatchQueue(label: "com.shadowcoach.codex-app-server", qos: .userInitiated)
    private let messageLock = NSLock()
    private let messageSemaphore = DispatchSemaphore(value: 0)
    private var messages: [[String: Any]] = []
    private var outputBuffer = Data()
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var nextRequestID = 1

    func run(
        prompt: String,
        model: String,
        reasoningEffort: String,
        onPartial: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            requestQueue.async {
                do {
                    continuation.resume(returning: try self.performTurn(
                        prompt: prompt,
                        model: model,
                        reasoningEffort: reasoningEffort,
                        onPartial: onPartial
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func performTurn(
        prompt: String,
        model: String,
        reasoningEffort: String,
        onPartial: (@Sendable (String) -> Void)?
    ) throws -> String {
        do {
            try ensureServerStarted()
            let threadRequestID = requestID()
            try send([
                "jsonrpc": "2.0",
                "id": threadRequestID,
                "method": "thread/start",
                "params": [
                    "model": model,
                    "cwd": FileManager.default.temporaryDirectory.path,
                    "approvalPolicy": "never",
                    "sandbox": "read-only",
                    "ephemeral": true,
                    "baseInstructions": "You are a text-only English shadowing coach. Never use tools or inspect files. Return only the answer requested by the user.",
                    "developerInstructions": "Follow the requested output structure exactly. Be concise, practical, and do not overclaim.",
                    "dynamicTools": [],
                    "environments": [],
                    "allowProviderModelFallback": false
                ]
            ])
            let threadResponse = try waitForResponse(id: threadRequestID, timeout: 15)
            guard let result = threadResponse["result"] as? [String: Any],
                  let thread = result["thread"] as? [String: Any],
                  let threadID = thread["id"] as? String else {
                throw serverError("Codex app-server did not return a thread ID")
            }

            let turnRequestID = requestID()
            try send([
                "jsonrpc": "2.0",
                "id": turnRequestID,
                "method": "turn/start",
                "params": [
                    "threadId": threadID,
                    "input": [["type": "text", "text": prompt]],
                    "effort": reasoningEffort
                ]
            ])
            return try waitForTurn(requestID: turnRequestID, timeout: 90, onPartial: onPartial)
        } catch {
            stopServer()
            throw error
        }
    }

    private func ensureServerStarted() throws {
        if process?.isRunning == true, inputHandle != nil, outputHandle != nil {
            return
        }

        stopServer()
        resetMessages()

        let server = Process()
        let executable = CodexFeedbackClient.codexExecutablePath()
        server.executableURL = URL(fileURLWithPath: executable)
        var arguments = [
            "app-server",
            "--stdio",
            "--disable", "plugins",
            "--disable", "apps",
            "--disable", "remote_plugin",
            "--disable", "skill_search",
            "--disable", "multi_agent"
        ]
        if executable == "/usr/bin/env" {
            arguments.insert("codex", at: 0)
        }
        server.arguments = arguments
        server.environment = CodexFeedbackClient.processEnvironment()

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        server.standardInput = inputPipe
        server.standardOutput = outputPipe
        server.standardError = FileHandle.nullDevice

        process = server
        inputHandle = inputPipe.fileHandleForWriting
        outputHandle = outputPipe.fileHandleForReading
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                self?.enqueue(["_shadowCoachServerClosed": true])
            } else {
                self?.consumeOutput(data)
            }
        }

        do {
            try server.run()
            let initializeRequestID = requestID()
            try send([
                "jsonrpc": "2.0",
                "id": initializeRequestID,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "shadow-coach",
                        "title": "Shadow Coach",
                        "version": "1"
                    ],
                    "capabilities": ["experimentalApi": true]
                ]
            ])
            _ = try waitForResponse(id: initializeRequestID, timeout: 15)
            try send([
                "jsonrpc": "2.0",
                "method": "initialized",
                "params": [:]
            ])
            ImportLogger.write("codex persistent server started pid=\(server.processIdentifier)")
        } catch {
            stopServer()
            throw error
        }
    }

    private func waitForResponse(id: Int, timeout: TimeInterval) throws -> [String: Any] {
        let deadline = DispatchTime.now() + timeout
        while true {
            let message = try nextMessage(deadline: deadline)
            if let responseID = message["id"] as? Int, responseID == id {
                if let error = message["error"] {
                    throw serverError("Codex app-server request failed: \(error)")
                }
                return message
            }
        }
    }

    private func waitForTurn(
        requestID: Int,
        timeout: TimeInterval,
        onPartial: (@Sendable (String) -> Void)?
    ) throws -> String {
        let deadline = DispatchTime.now() + timeout
        var answerParts: [String] = []
        var streamedAnswer = ""
        var lastPartialDelivery = Date.distantPast
        while true {
            let message = try nextMessage(deadline: deadline)
            if let responseID = message["id"] as? Int, responseID == requestID,
               let error = message["error"] {
                throw serverError("Codex turn failed to start: \(error)")
            }

            if message["method"] as? String == "item/agentMessage/delta",
               let params = message["params"] as? [String: Any],
               let delta = params["delta"] as? String,
               !delta.isEmpty {
                streamedAnswer += delta
                if Date().timeIntervalSince(lastPartialDelivery) >= 0.08 {
                    onPartial?(streamedAnswer)
                    lastPartialDelivery = Date()
                }
            }

            if message["method"] as? String == "item/completed",
               let params = message["params"] as? [String: Any],
               let item = params["item"] as? [String: Any],
               item["type"] as? String == "agentMessage",
               let text = item["text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                answerParts = [text]
            }

            guard message["method"] as? String == "turn/completed",
                  let params = message["params"] as? [String: Any],
                  let turn = params["turn"] as? [String: Any] else {
                continue
            }

            if turn["status"] as? String != "completed" {
                throw serverError("Codex turn did not complete: \(turn["error"] ?? "unknown error")")
            }
            if answerParts.isEmpty, let items = turn["items"] as? [[String: Any]] {
                answerParts = items.compactMap { item in
                    guard item["type"] as? String == "agentMessage" else { return nil }
                    return item["text"] as? String
                }
            }
            let answer = (answerParts.isEmpty ? streamedAnswer : answerParts.joined(separator: "\n"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else {
                throw serverError("Codex app-server returned no feedback")
            }
            onPartial?(answer)
            return answer
        }
    }

    private func requestID() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }

    private func send(_ message: [String: Any]) throws {
        guard process?.isRunning == true, let inputHandle else {
            throw serverError("Codex app-server is not running")
        }
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        inputHandle.write(data)
    }

    private func nextMessage(deadline: DispatchTime) throws -> [String: Any] {
        while true {
            if messageSemaphore.wait(timeout: deadline) == .timedOut {
                throw serverError("Codex app-server timed out")
            }
            messageLock.lock()
            let message = messages.isEmpty ? nil : messages.removeFirst()
            messageLock.unlock()
            guard let message else { continue }
            if message["_shadowCoachServerClosed"] as? Bool == true {
                throw serverError("Codex app-server closed unexpectedly")
            }
            return message
        }
    }

    private func consumeOutput(_ data: Data) {
        var parsedMessages: [[String: Any]] = []
        messageLock.lock()
        outputBuffer.append(data)
        while let newlineIndex = outputBuffer.firstIndex(of: 0x0A) {
            let line = Data(outputBuffer[..<newlineIndex])
            outputBuffer.removeSubrange(outputBuffer.startIndex...newlineIndex)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line),
                  let message = object as? [String: Any] else {
                continue
            }
            parsedMessages.append(message)
        }
        messages.append(contentsOf: parsedMessages)
        messageLock.unlock()
        for _ in parsedMessages {
            messageSemaphore.signal()
        }
    }

    private func enqueue(_ message: [String: Any]) {
        messageLock.lock()
        messages.append(message)
        messageLock.unlock()
        messageSemaphore.signal()
    }

    private func resetMessages() {
        messageLock.lock()
        messages.removeAll()
        outputBuffer.removeAll(keepingCapacity: true)
        messageLock.unlock()
        while messageSemaphore.wait(timeout: .now()) == .success {}
    }

    private func stopServer() {
        outputHandle?.readabilityHandler = nil
        try? inputHandle?.close()
        try? outputHandle?.close()
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        inputHandle = nil
        outputHandle = nil
    }

    private func serverError(_ message: String) -> NSError {
        NSError(domain: "CodexAppServer", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

enum KeychainStore {
    static func save(_ value: String, service: String, account: String) {
        let data = Data(value.utf8)
        delete(service: service, account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct ActionTileButtonStyle: ButtonStyle {
    let color: Color

    private var foreground: Color {
        color == .gray ? .primary : .white
    }

    private var background: Color {
        color == .gray ? Theme.control : color
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(foreground)
            .background(background.opacity(configuration.isPressed ? 0.78 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(configuration.isPressed ? Theme.controlPressed : Theme.control)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 34, height: 34)
            .background(configuration.isPressed ? Theme.controlPressed : Theme.control)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

enum Theme {
    static let appBackground = adaptive(
        light: NSColor(srgbRed: 0.94, green: 0.96, blue: 0.97, alpha: 1),
        dark: NSColor(srgbRed: 0.075, green: 0.09, blue: 0.105, alpha: 1)
    )
    static let sidebar = adaptive(
        light: NSColor(srgbRed: 0.90, green: 0.93, blue: 0.95, alpha: 1),
        dark: NSColor(srgbRed: 0.105, green: 0.13, blue: 0.15, alpha: 1)
    )
    static let topBar = adaptive(
        light: NSColor(srgbRed: 0.985, green: 0.987, blue: 0.99, alpha: 1),
        dark: NSColor(srgbRed: 0.095, green: 0.11, blue: 0.125, alpha: 1)
    )
    static let panel = adaptive(
        light: NSColor(srgbRed: 0.995, green: 0.996, blue: 0.998, alpha: 1),
        dark: NSColor(srgbRed: 0.14, green: 0.165, blue: 0.185, alpha: 1)
    )
    static let subtle = adaptive(
        light: NSColor(srgbRed: 0.925, green: 0.945, blue: 0.955, alpha: 1),
        dark: NSColor(srgbRed: 0.12, green: 0.145, blue: 0.165, alpha: 1)
    )
    static let pill = adaptive(
        light: NSColor(srgbRed: 0.94, green: 0.955, blue: 0.965, alpha: 1),
        dark: NSColor(srgbRed: 0.17, green: 0.20, blue: 0.225, alpha: 1)
    )
    static let control = adaptive(
        light: NSColor(white: 0, alpha: 0.055),
        dark: NSColor(white: 1, alpha: 0.08)
    )
    static let controlPressed = adaptive(
        light: NSColor(white: 0, alpha: 0.105),
        dark: NSColor(white: 1, alpha: 0.15)
    )
    static let border = adaptive(
        light: NSColor(white: 0, alpha: 0.075),
        dark: NSColor(white: 1, alpha: 0.105)
    )
    static let selected = adaptive(
        light: NSColor(srgbRed: 0.87, green: 0.93, blue: 0.98, alpha: 1),
        dark: NSColor(srgbRed: 0.14, green: 0.24, blue: 0.32, alpha: 1)
    )
    static let primary = adaptive(
        light: NSColor(srgbRed: 0.11, green: 0.43, blue: 0.72, alpha: 1),
        dark: NSColor(srgbRed: 0.32, green: 0.68, blue: 0.96, alpha: 1)
    )
    static let accent = adaptive(
        light: NSColor(srgbRed: 0.44, green: 0.32, blue: 0.72, alpha: 1),
        dark: NSColor(srgbRed: 0.67, green: 0.56, blue: 0.94, alpha: 1)
    )
    static let success = adaptive(
        light: NSColor(srgbRed: 0.12, green: 0.58, blue: 0.34, alpha: 1),
        dark: NSColor(srgbRed: 0.30, green: 0.78, blue: 0.49, alpha: 1)
    )
    static let warning = adaptive(
        light: NSColor(srgbRed: 0.78, green: 0.48, blue: 0.08, alpha: 1),
        dark: NSColor(srgbRed: 0.96, green: 0.68, blue: 0.25, alpha: 1)
    )
    static let danger = adaptive(
        light: NSColor(srgbRed: 0.76, green: 0.20, blue: 0.20, alpha: 1),
        dark: NSColor(srgbRed: 0.96, green: 0.39, blue: 0.39, alpha: 1)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }
}

struct LibrarySection: Identifiable {
    var id: String { source }
    let source: String
    var lines: [PracticeLine]
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case done
    case needsReview
    case new
    case realAudio
    case tts

    var id: String { rawValue }

    var dependsOnPracticeHistory: Bool {
        switch self {
        case .favorites, .done, .needsReview, .new:
            return true
        case .all, .realAudio, .tts:
            return false
        }
    }

    var label: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .done: return "Done"
        case .needsReview: return "Needs Review"
        case .new: return "New"
        case .realAudio: return "Real Audio"
        case .tts: return "TTS"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .favorites: return "star.fill"
        case .done: return "checkmark.circle.fill"
        case .needsReview: return "arrow.triangle.2.circlepath"
        case .new: return "circle"
        case .realAudio: return "waveform"
        case .tts: return "speaker.wave.2"
        }
    }
}
