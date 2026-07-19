import Foundation

struct TimedWord: Identifiable, Codable, Hashable {
    let id = UUID()
    let text: String
    let normalized: String
    let start: Double?
    let end: Double?

    enum CodingKeys: String, CodingKey {
        case text
        case normalized
        case start
        case end
    }
}
enum WordDiffStatus: String, Codable, Hashable {
    case matched
    case substituted
    case missing
    case extra
}

struct WordDiffItem: Identifiable, Codable, Hashable {
    let id = UUID()
    let text: String
    let status: WordDiffStatus
    let counterpartText: String?

    init(text: String, status: WordDiffStatus, counterpartText: String? = nil) {
        self.text = text
        self.status = status
        self.counterpartText = counterpartText
    }

    enum CodingKeys: String, CodingKey {
        case text
        case status
        case counterpartText
    }
}

struct WordSubstitution: Identifiable, Codable, Hashable {
    let id = UUID()
    let expected: String
    let spoken: String

    enum CodingKeys: String, CodingKey {
        case expected
        case spoken
    }
}

struct RecordingAnalysis: Codable, Hashable {
    let referenceText: String
    let sourceTitle: String?
    let referenceHasSourceAudio: Bool?
    let referenceQuality: ImportQuality?
    let contextBefore: String?
    let contextAfter: String?
    let transcript: String
    let accuracy: Double
    let items: [WordDiffItem]
    let missingWords: [String]
    let extraWords: [String]
    let substitutions: [WordSubstitution]?
    let issueHints: [String]
    let whisperXRawJSON: String?
    let azure: AzurePronunciationAnalysis?
    let pronunciationIssues: [PronunciationRuleIssue]?
    let prosody: ProsodyAnalysis?

    enum CodingKeys: String, CodingKey {
        case referenceText
        case sourceTitle
        case referenceHasSourceAudio = "reference_has_source_audio"
        case referenceQuality = "reference_quality"
        case contextBefore
        case contextAfter
        case transcript
        case accuracy
        case items
        case missingWords
        case extraWords
        case substitutions
        case issueHints
        case whisperXRawJSON = "whisperx_raw_json"
        case azure
        case pronunciationIssues = "pronunciation_issues"
        case prosody
    }
}

extension RecordingAnalysis {
    var isPerfectWordRecall: Bool {
        accuracy >= 99.5
            && missingWords.isEmpty
            && extraWords.isEmpty
            && (substitutions?.isEmpty ?? true)
    }
}

struct PronunciationRuleIssue: Identifiable, Codable, Hashable {
    let id = UUID()
    let wordIndex: Int?
    let word: String?
    let kind: PronunciationRuleKind
    let severity: PronunciationRuleSeverity
    let title: String
    let evidence: String
    let coachNote: String

    enum CodingKeys: String, CodingKey {
        case wordIndex = "word_index"
        case word
        case kind
        case severity
        case title
        case evidence
        case coachNote = "coach_note"
    }
}

enum PronunciationRuleKind: String, Codable, Hashable {
    case lowPhoneme
    case finalConsonant
    case brokenLinking
    case unexpectedBreak
    case missingBreak
    case functionWordStress
    case flatProsody
}

enum PronunciationRuleSeverity: String, Codable, Hashable {
    case info
    case warning
    case strong
}

struct AzurePronunciationAnalysis: Codable, Hashable {
    let enabled: Bool
    let error: String?
    let rawStatus: String?
    let display: String
    let accuracy: Double?
    let fluency: Double?
    let completeness: Double?
    let prosody: Double?
    let pronunciation: Double?
    let words: [AzurePronunciationWord]
    let rawJSON: String?

    enum CodingKeys: String, CodingKey {
        case enabled
        case error
        case rawStatus = "raw_status"
        case display
        case accuracy
        case fluency
        case completeness
        case prosody
        case pronunciation
        case words
        case rawJSON = "raw_json"
    }
}

struct AzurePronunciationWord: Identifiable, Codable, Hashable {
    let id = UUID()
    let text: String
    let accuracy: Double?
    let errorType: String?
    let offsetSeconds: Double?
    let durationSeconds: Double?
    let syllables: [AzurePronunciationUnit]
    let phonemes: [AzurePronunciationUnit]

    enum CodingKeys: String, CodingKey {
        case text
        case accuracy
        case errorType = "error_type"
        case offsetSeconds = "offset_seconds"
        case durationSeconds = "duration_seconds"
        case syllables
        case phonemes
    }
}

struct AzurePronunciationUnit: Identifiable, Codable, Hashable {
    let id = UUID()
    let text: String
    let accuracy: Double?
    let offsetSeconds: Double?
    let durationSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case text
        case accuracy
        case offsetSeconds = "offset_seconds"
        case durationSeconds = "duration_seconds"
    }
}

struct ProsodyAnalysis: Codable, Hashable {
    let user: ProsodyTrack
    let reference: ProsodyTrack?
    let userStressCandidates: [String]
    let referenceStressCandidates: [String]
}

struct ProsodyTrack: Codable, Hashable {
    let duration: Double
    let speakingRateWpm: Double
    let pauseCount: Int
    let pauseDuration: Double
    let meanPitch: Double
    let meanIntensity: Double
    let pitchCurve: [ProsodyPoint]
    let intensityCurve: [ProsodyPoint]
    let emphasisWindows: [TimeWindow]
}

struct ProsodyPoint: Codable, Hashable {
    let time: Double
    let value: Double
}

struct TimeWindow: Codable, Hashable {
    let start: Double
    let end: Double
}

struct DetailedTranscript {
    let transcript: String
    let words: [TimedWord]
    let rawJSON: String?
}

enum WordDiffEngine {
    private struct ComparisonWord {
        let text: String
        let normalized: String
    }

    static func tokenize(_ text: String) -> [TimedWord] {
        words(in: text)
            .map { word in
                TimedWord(text: word, normalized: normalize(word), start: nil, end: nil)
            }
            .filter { !$0.normalized.isEmpty }
    }

    static func spokenText(_ text: String) -> String {
        tokenize(text).map(\.text).joined(separator: " ")
    }

    static func comparisonText(_ text: String) -> String {
        comparisonWords(from: tokenize(text)).map(\.normalized).joined(separator: " ")
    }

    private enum AlignmentStep {
        case matched(target: Int, user: Int)
        case substituted(target: Int, user: Int)
        case missing(target: Int)
        case extra(user: Int)
    }

    static func analyze(targetWords: [TimedWord], userWords: [TimedWord]) -> (accuracy: Double, items: [WordDiffItem], missingWords: [String], extraWords: [String], substitutions: [WordSubstitution]) {
        let targetUnits = comparisonWords(from: targetWords)
        let userUnits = comparisonWords(from: userWords)
        let target = targetUnits.map(\.normalized)
        let user = userUnits.map(\.normalized)
        let steps = alignmentSteps(target, user)

        var items: [WordDiffItem] = []
        var missingWords: [String] = []
        var extraWords: [String] = []
        var substitutions: [WordSubstitution] = []
        var matchedCount = 0
        for step in steps {
            switch step {
            case let .matched(targetIndex, userIndex):
                matchedCount += 1
                items.append(WordDiffItem(
                    text: targetUnits[targetIndex].text,
                    status: .matched,
                    counterpartText: userUnits[userIndex].text
                ))
            case let .substituted(targetIndex, userIndex):
                let substitution = WordSubstitution(
                    expected: targetUnits[targetIndex].text,
                    spoken: userUnits[userIndex].text
                )
                substitutions.append(substitution)
                items.append(WordDiffItem(
                    text: substitution.expected,
                    status: .substituted,
                    counterpartText: substitution.spoken
                ))
            case let .missing(targetIndex):
                missingWords.append(targetUnits[targetIndex].text)
                items.append(WordDiffItem(text: targetUnits[targetIndex].text, status: .missing))
            case let .extra(userIndex):
                extraWords.append(userUnits[userIndex].text)
                items.append(WordDiffItem(text: userUnits[userIndex].text, status: .extra))
            }
        }

        let denominator = max(targetUnits.count, 1)
        let penalty = Double(missingWords.count)
            + Double(extraWords.count) * 0.6
            + Double(substitutions.count) * 1.6
        let accuracy = max(0, min(100, (Double(matchedCount) - penalty * 0.35) / Double(denominator) * 100))
        return (accuracy, items, missingWords, extraWords, substitutions)
    }

    static func normalize(_ word: String) -> String {
        let cleaned = word.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9']"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        if let number = cardinalNumberWords[cleaned] ?? scaleNumberWords[cleaned] {
            return String(number)
        }
        return cleaned
    }

    private static let cardinalNumberWords: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30,
        "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
        "eighty": 80, "ninety": 90
    ]

    private static let scaleNumberWords: [String: Int] = [
        "hundred": 100,
        "thousand": 1_000,
        "million": 1_000_000,
        "billion": 1_000_000_000
    ]

    // Speech recognizers legitimately vary between closed, open, and hyphenated
    // compounds. Keep that spelling choice out of the recall score.
    private static let compoundAliases: [String: String] = [
        "on site": "onsite",
        "check point": "checkpoint",
        "check points": "checkpoints"
    ]

    private static func comparisonWords(from words: [TimedWord]) -> [ComparisonWord] {
        var result: [ComparisonWord] = []
        var index = 0

        while index < words.count {
            if index + 1 < words.count {
                let phraseKey = "\(words[index].normalized) \(words[index + 1].normalized)"
                if let canonical = compoundAliases[phraseKey] {
                    result.append(ComparisonWord(
                        text: "\(words[index].text) \(words[index + 1].text)",
                        normalized: canonical
                    ))
                    index += 2
                    continue
                }
            }

            if let phrase = numberPhrase(startingAt: index, in: words) {
                result.append(ComparisonWord(text: phrase.text, normalized: String(phrase.value)))
                index = phrase.endIndex
            } else {
                result.append(ComparisonWord(text: words[index].text, normalized: words[index].normalized))
                index += 1
            }
        }
        return result
    }

    private static func numberPhrase(startingAt start: Int, in words: [TimedWord]) -> (text: String, value: Int, endIndex: Int)? {
        guard words.indices.contains(start) else { return nil }
        var tokens: [String] = []
        var end = start
        var containsNumberWord = false
        var containsScale = false

        while end < words.count {
            let token = lexicalToken(words[end].text)
            if cardinalNumberWords[token] != nil {
                tokens.append(token)
                containsNumberWord = true
                end += 1
            } else if scaleNumberWords[token] != nil {
                tokens.append(token)
                containsNumberWord = true
                containsScale = true
                end += 1
            } else if Int(token) != nil {
                tokens.append(token)
                end += 1
            } else if token == "and",
                      !tokens.isEmpty,
                      end + 1 < words.count,
                      isNumberToken(lexicalToken(words[end + 1].text)) {
                tokens.append(token)
                end += 1
            } else {
                break
            }
        }

        guard !tokens.isEmpty else { return nil }
        if tokens.count > 1, !containsNumberWord, !containsScale {
            end = start + 1
            tokens = [tokens[0]]
        }
        guard let value = parseNumberPhrase(tokens) else { return nil }
        let text = words[start..<end].map(\.text).joined(separator: " ")
        return (text, value, end)
    }

    private static func parseNumberPhrase(_ tokens: [String]) -> Int? {
        let meaningful = tokens.filter { $0 != "and" }
        guard !meaningful.isEmpty else { return nil }

        if meaningful.count > 1,
           meaningful.allSatisfy({ token in
               guard let value = cardinalNumberWords[token] else { return false }
               return value <= 9
           }) {
            return Int(meaningful.compactMap { cardinalNumberWords[$0] }.map(String.init).joined())
        }

        let hasScale = meaningful.contains { scaleNumberWords[$0] != nil }
        if !hasScale,
           meaningful.count >= 2,
           let first = cardinalNumberWords[meaningful[0]],
           (10...99).contains(first) {
            let remainder = meaningful.dropFirst().compactMap { cardinalNumberWords[$0] }.reduce(0, +)
            if (10...99).contains(remainder) {
                return first * 100 + remainder
            }
        }

        var total = 0
        var current = 0
        for token in meaningful {
            if let value = cardinalNumberWords[token] ?? Int(token) {
                current += value
            } else if let scale = scaleNumberWords[token] {
                if scale == 100 {
                    current = max(current, 1) * scale
                } else {
                    total += max(current, 1) * scale
                    current = 0
                }
            } else {
                return nil
            }
        }
        return total + current
    }

    private static func isNumberToken(_ token: String) -> Bool {
        cardinalNumberWords[token] != nil || scaleNumberWords[token] != nil || Int(token) != nil
    }

    private static func lexicalToken(_ word: String) -> String {
        word.lowercased().replacingOccurrences(of: #"[^a-z0-9]"#, with: "", options: .regularExpression)
    }

    private static func words(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"[0-9]{1,3}(?:,[0-9]{3})+|[A-Za-z0-9]+(?:'[A-Za-z]+)?"#
        ) else { return [] }
        let searchable = text
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
        let range = NSRange(searchable.startIndex..<searchable.endIndex, in: searchable)
        return regex.matches(in: searchable, range: range).compactMap { match in
            guard let wordRange = Range(match.range, in: searchable) else { return nil }
            return String(searchable[wordRange])
        }
    }

    private static func alignmentSteps(_ target: [String], _ user: [String]) -> [AlignmentStep] {
        var dp = Array(repeating: Array(repeating: 0, count: user.count + 1), count: target.count + 1)
        for index in target.indices {
            dp[index][user.count] = target.count - index
        }
        for index in user.indices {
            dp[target.count][index] = user.count - index
        }
        for i in stride(from: target.count - 1, through: 0, by: -1) {
            for j in stride(from: user.count - 1, through: 0, by: -1) {
                if target[i] == user[j] {
                    dp[i][j] = dp[i + 1][j + 1]
                } else {
                    dp[i][j] = 1 + min(dp[i + 1][j + 1], dp[i + 1][j], dp[i][j + 1])
                }
            }
        }

        var steps: [AlignmentStep] = []
        var i = 0
        var j = 0
        while i < target.count && j < user.count {
            if target[i] == user[j] {
                steps.append(.matched(target: i, user: j))
                i += 1
                j += 1
                continue
            }

            let substitutionCost = dp[i + 1][j + 1]
            let missingCost = dp[i + 1][j]
            let extraCost = dp[i][j + 1]
            if substitutionCost < missingCost && substitutionCost < extraCost {
                steps.append(.substituted(target: i, user: j))
                i += 1
                j += 1
            } else if missingCost <= extraCost {
                steps.append(.missing(target: i))
                i += 1
            } else {
                steps.append(.extra(user: j))
                j += 1
            }
        }
        while i < target.count {
            steps.append(.missing(target: i))
            i += 1
        }
        while j < user.count {
            steps.append(.extra(user: j))
            j += 1
        }
        return steps
    }
}

enum CoachFeedbackSanitizer {
    private static let forbiddenTerms = [
        "标点", "逗号", "句号", "问号", "冒号", "分号", "感叹号", "引号", "大小写",
        "punctuation", "comma", "full stop", "question mark", "semicolon", "capitalization",
        "capitalisation", "uppercase", "lowercase"
    ]

    static func clean(_ feedback: String) -> String {
        guard !feedback.isEmpty else { return feedback }
        let cleanedLines = feedback.components(separatedBy: .newlines).compactMap { rawLine -> String? in
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            if trimmed.hasPrefix("#") { return trimmed }

            let fragments = sentenceFragments(in: trimmed)
                .filter { !containsForbiddenTerm($0) }
            let cleaned = fragments.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }

        return cleanedLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsForbiddenTerm(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return forbiddenTerms.contains { lowercased.contains($0) }
    }

    private static func sentenceFragments(in line: String) -> [String] {
        let characters = Array(line)
        var fragments: [String] = []
        var current = ""

        for index in characters.indices {
            let character = characters[index]
            current.append(character)
            let isTerminal = "。！？!?".contains(character)
                || (character == "." && (index == characters.index(before: characters.endIndex) || characters[index + 1].isWhitespace))
            if isTerminal {
                fragments.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            }
        }

        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fragments.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return fragments
    }
}

enum PronunciationRuleEngine {
    private static let finalConsonants = Set(["t", "d", "k", "g", "p", "b", "s", "z", "f", "v", "m", "n", "ŋ", "ch", "jh", "sh", "zh", "th", "dh"])
    private static let vowelStarts = Set(["a", "e", "i", "o", "u"])
    private static let functionWords = Set(["a", "an", "the", "to", "of", "for", "and", "or", "but", "in", "on", "at", "as", "is", "are", "was", "were", "be", "been", "can", "could", "would", "should", "have", "has", "had", "do", "does", "did"])
    private static let commonLinkingPairs: Set<String> = [
        "want to", "going to", "got to", "have to", "used to", "kind of", "sort of",
        "out of", "lot of", "get out", "pick it", "turn it", "put it", "take it"
    ]

    static func analyze(referenceText: String, azure: AzurePronunciationAnalysis?, prosody: ProsodyAnalysis?) -> [PronunciationRuleIssue] {
        guard let azure, azure.enabled, azure.error == nil else { return [] }
        var issues: [PronunciationRuleIssue] = []
        let words = azure.words

        for (index, word) in words.enumerated() {
            if let errorType = word.errorType, errorType == "UnexpectedBreak" || errorType == "MissingBreak" {
                issues.append(breakIssue(word: word, index: index, errorType: errorType))
            }

            if let weakest = weakestPhoneme(in: word), (weakest.accuracy ?? 100) < 65 {
                issues.append(lowPhonemeIssue(word: word, phoneme: weakest, index: index))
            }

            if let final = word.phonemes.last,
               let score = final.accuracy,
               score < 68,
               isFinalConsonant(final.text),
               (word.accuracy ?? 100) < 82 {
                issues.append(finalConsonantIssue(word: word, phoneme: final, index: index))
            }

            if isFunctionWord(word.text),
               let duration = word.durationSeconds,
               duration > 0.42,
               (word.accuracy ?? 100) >= 75 {
                issues.append(functionWordStressIssue(word: word, index: index, duration: duration))
            }
        }

        for index in words.indices.dropLast() {
            let current = words[index]
            let next = words[index + 1]
            guard let gap = boundaryGap(after: current, before: next), gap > 0.16 else { continue }
            if shouldLink(current, next) {
                issues.append(linkingIssue(current: current, next: next, index: index, gap: gap))
            }
        }

        if let azureProsody = azure.prosody, azureProsody < 75 {
            issues.append(PronunciationRuleIssue(
                wordIndex: nil,
                word: nil,
                kind: .flatProsody,
                severity: azureProsody < 62 ? .strong : .warning,
                title: "Prosody is the main sentence-level issue",
                evidence: "Azure ProsodyScore \(Int(azureProsody.rounded()))/100.",
                coachNote: "The words may be mostly right, but the rhythm, stress, or intonation is not close enough yet. Imitate the rise/fall and energy shape of the reference."
            ))
        } else if let prosody, prosody.user.meanPitch > 0, prosody.user.pitchCurve.count > 3 {
            let range = pitchRange(prosody.user.pitchCurve)
            if range < 28 {
                issues.append(PronunciationRuleIssue(
                    wordIndex: nil,
                    word: nil,
                    kind: .flatProsody,
                    severity: .info,
                    title: "Pitch movement may be too flat",
                    evidence: "Local pitch range is about \(Int(range.rounded())) Hz.",
                    coachNote: "Try copying the reference melody, not only the words. Exaggerate the stressed words slightly, then make it natural."
                ))
            }
        }

        return Array(issues.prefix(10))
    }

    private static func weakestPhoneme(in word: AzurePronunciationWord) -> AzurePronunciationUnit? {
        word.phonemes
            .filter { $0.accuracy != nil }
            .min { ($0.accuracy ?? 100) < ($1.accuracy ?? 100) }
    }

    private static func isFinalConsonant(_ phoneme: String) -> Bool {
        let normalized = phoneme.lowercased().replacingOccurrences(of: #"[^a-zŋ]"#, with: "", options: .regularExpression)
        return finalConsonants.contains(normalized)
    }

    private static func isFunctionWord(_ word: String) -> Bool {
        functionWords.contains(WordDiffEngine.normalize(word))
    }

    private static func shouldLink(_ current: AzurePronunciationWord, _ next: AzurePronunciationWord) -> Bool {
        let pair = "\(WordDiffEngine.normalize(current.text)) \(WordDiffEngine.normalize(next.text))"
        if commonLinkingPairs.contains(pair) { return true }
        guard let lastCharacter = WordDiffEngine.normalize(current.text).last,
              let firstCharacter = WordDiffEngine.normalize(next.text).first else { return false }
        return !vowelStarts.contains(String(lastCharacter)) && vowelStarts.contains(String(firstCharacter))
    }

    private static func boundaryGap(after current: AzurePronunciationWord, before next: AzurePronunciationWord) -> Double? {
        guard let start = current.offsetSeconds,
              let duration = current.durationSeconds,
              let nextStart = next.offsetSeconds else { return nil }
        return max(0, nextStart - (start + duration))
    }

    private static func lowPhonemeIssue(word: AzurePronunciationWord, phoneme: AzurePronunciationUnit, index: Int) -> PronunciationRuleIssue {
        PronunciationRuleIssue(
            wordIndex: index,
            word: word.text,
            kind: .lowPhoneme,
            severity: (phoneme.accuracy ?? 100) < 50 ? .strong : .warning,
            title: "Weak phoneme: \(phoneme.text)",
            evidence: "\(word.text) / \(phoneme.text) scored \(Int((phoneme.accuracy ?? 0).rounded()))/100 in Azure.",
            coachNote: "Slow down this word and isolate the sound \(phoneme.text). Once it is clear, put the word back into the whole phrase."
        )
    }

    private static func finalConsonantIssue(word: AzurePronunciationWord, phoneme: AzurePronunciationUnit, index: Int) -> PronunciationRuleIssue {
        PronunciationRuleIssue(
            wordIndex: index,
            word: word.text,
            kind: .finalConsonant,
            severity: .strong,
            title: "Final consonant may be weak or missing",
            evidence: "Final phoneme \(phoneme.text) scored \(Int((phoneme.accuracy ?? 0).rounded()))/100.",
            coachNote: "Your \(word.text) may sound unfinished. Make the final \(phoneme.text) clearer, or link it deliberately into the next word instead of letting it disappear."
        )
    }

    private static func linkingIssue(current: AzurePronunciationWord, next: AzurePronunciationWord, index: Int, gap: Double) -> PronunciationRuleIssue {
        PronunciationRuleIssue(
            wordIndex: index,
            word: current.text,
            kind: .brokenLinking,
            severity: gap > 0.26 ? .strong : .warning,
            title: "Linking sounds broken",
            evidence: "Gap before \(next.text) is \(String(format: "%.2f", gap))s.",
            coachNote: "Do not restart before \(next.text). Practice \(current.text) \(next.text) as one chunk, then put it back into the full sentence."
        )
    }

    private static func breakIssue(word: AzurePronunciationWord, index: Int, errorType: String) -> PronunciationRuleIssue {
        PronunciationRuleIssue(
            wordIndex: index,
            word: word.text,
            kind: errorType == "UnexpectedBreak" ? .unexpectedBreak : .missingBreak,
            severity: .warning,
            title: errorType == "UnexpectedBreak" ? "Unexpected break" : "Missing phrase break",
            evidence: "Azure marked \(word.text) with \(errorType).",
            coachNote: errorType == "UnexpectedBreak"
                ? "This spot sounds too chopped. Connect it more smoothly to the surrounding words."
                : "This spot may need a clearer phrase boundary. Leave a tiny breath without losing rhythm."
        )
    }

    private static func functionWordStressIssue(word: AzurePronunciationWord, index: Int, duration: Double) -> PronunciationRuleIssue {
        PronunciationRuleIssue(
            wordIndex: index,
            word: word.text,
            kind: .functionWordStress,
            severity: .info,
            title: "Function word may be too heavy",
            evidence: "\(word.text) lasts \(String(format: "%.2f", duration))s.",
            coachNote: "Function words like \(word.text) are usually lighter and shorter in natural speech. Try reducing it and give more energy to the content words."
        )
    }

    private static func pitchRange(_ points: [ProsodyPoint]) -> Double {
        let values = points.map(\.value).filter { $0.isFinite && $0 > 0 }
        guard let min = values.min(), let max = values.max() else { return 0 }
        return max - min
    }
}

enum RecordingIssueBuilder {
    static func hints(
        targetSentence: String,
        transcript: String,
        missingWords: [String],
        extraWords: [String],
        azure: AzurePronunciationAnalysis?,
        pronunciationIssues: [PronunciationRuleIssue],
        prosody: ProsodyAnalysis?
    ) -> [String] {
        var hints: [String] = []
        let target = targetSentence.lowercased()
        let user = transcript.lowercased()

        if target.contains("22") && (user.contains("20 to") || user.contains("twenty to")) {
            hints.append("22 被识别成了 20 to：重点练 twenty-two 的 two /tuː/。")
        }
        if contains(pattern: #"\bbe\b"#, in: target) && contains(pattern: #"\bb\??\b"#, in: user) {
            hints.append("末尾 be 被识别成 B：结尾元音需要更完整，不要只剩字母音。")
        }
        if !missingWords.isEmpty {
            hints.append("未识别到：\(missingWords.prefix(5).joined(separator: ", "))（可能是漏词，也可能是识别误差）")
        }
        if !extraWords.isEmpty {
            hints.append("额外识别到：\(extraWords.prefix(5).joined(separator: ", "))")
        }
        if let azure, azure.enabled, azure.error == nil {
            if let completeness = azure.completeness, completeness < 80 {
                hints.append("Azure 完整度偏低：先把原句完整复述出来，再追求语调。")
            }
            if let accuracy = azure.accuracy, accuracy < 80 {
                hints.append("Azure 发音准确度偏低：优先看红色词和低分音素。")
            }
            if let fluency = azure.fluency, fluency < 80 {
                hints.append("Azure 流利度偏低：减少不必要停顿，把词连成语块。")
            }
            if let azureProsody = azure.prosody, azureProsody < 80 {
                hints.append("Azure 韵律分偏低：重点练重音、语调起伏和节奏。")
            }
        }
        for issue in pronunciationIssues.prefix(3) {
            if let word = issue.word {
                hints.append("\(word)：\(issue.coachNote)")
            } else {
                hints.append(issue.coachNote)
            }
        }
        if let prosody {
            if prosody.user.pauseCount >= 2 {
                hints.append("停顿偏多：这句尽量分成 2 个语块，而不是每几个词停一下。")
            }
            if let reference = prosody.reference, reference.speakingRateWpm > 0 {
                let ratio = prosody.user.speakingRateWpm / reference.speakingRateWpm
                if ratio < 0.78 {
                    hints.append("语速慢于原音频约 \(Int((1 - ratio) * 100))%：先保证准确，再逐步提速。")
                } else if ratio > 1.25 {
                    hints.append("语速快于原音频约 \(Int((ratio - 1) * 100))%：放慢一点，保留清晰度。")
                }
                let pauseDelta = prosody.user.pauseCount - reference.pauseCount
                if pauseDelta >= 2 {
                    hints.append("停顿比原音频多 \(pauseDelta) 次：试着把相邻词连成更完整的语块。")
                }
                let pauseDurationDelta = prosody.user.pauseDuration - reference.pauseDuration
                if pauseDurationDelta > 0.6 {
                    hints.append("总停顿比原音频长 \(String(format: "%.1f", pauseDurationDelta)) 秒：主要练流畅度。")
                }
            }
            if !prosody.userStressCandidates.isEmpty {
                hints.append("你声音更突出的词：\(prosody.userStressCandidates.prefix(5).joined(separator: ", "))")
            }
        }

        if hints.isEmpty {
            hints.append("主要词序和内容匹配不错，下一步重点听节奏和连读。")
        }
        return hints
    }

    private static func contains(pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
