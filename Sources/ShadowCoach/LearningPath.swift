import Foundation

enum LearningPathStage: String, CaseIterable, Codable, Identifiable, Hashable {
    case input
    case noticing
    case shadowing
    case retrieval
    case spacedReview
    case transformation
    case freeExpression
    case realCommunication
    case feedbackCorrection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .input: return "Understand the input"
        case .noticing: return "Notice how it works"
        case .shadowing: return "Shadow the speaker"
        case .retrieval: return "Recall without a prompt"
        case .spacedReview: return "Schedule the memory"
        case .transformation: return "Change the situation"
        case .freeExpression: return "Speak in your own words"
        case .realCommunication: return "Use it for real"
        case .feedbackCorrection: return "Correct and retry"
        }
    }

    var shortTitle: String {
        switch self {
        case .input: return "Input"
        case .noticing: return "Notice"
        case .shadowing: return "Shadow"
        case .retrieval: return "Recall"
        case .spacedReview: return "Review"
        case .transformation: return "Transform"
        case .freeExpression: return "Free speak"
        case .realCommunication: return "Use it"
        case .feedbackCorrection: return "Correct"
        }
    }

    var systemImage: String {
        switch self {
        case .input: return "ear.and.waveform"
        case .noticing: return "scope"
        case .shadowing: return "person.wave.2"
        case .retrieval: return "brain.head.profile"
        case .spacedReview: return "calendar.badge.clock"
        case .transformation: return "arrow.triangle.branch"
        case .freeExpression: return "quote.bubble"
        case .realCommunication: return "person.2.wave.2"
        case .feedbackCorrection: return "arrow.triangle.2.circlepath"
        }
    }
}

enum PracticeActivity: String, Codable, Hashable {
    case shadowing
    case transformation
    case freeExpression
    case correction

    var comparesWithReference: Bool {
        self == .shadowing || self == .correction
    }

    var label: String {
        switch self {
        case .shadowing: return "Shadowing"
        case .transformation: return "New situation"
        case .freeExpression: return "Free speaking"
        case .correction: return "Corrected retry"
        }
    }
}

enum TransferContext: String, CaseIterable, Codable, Identifiable, Hashable {
    case work
    case dailyLife
    case pastExperience

    var id: String { rawValue }

    var label: String {
        switch self {
        case .work: return "Work"
        case .dailyLife: return "Daily life"
        case .pastExperience: return "A past event"
        }
    }

    var prompt: String {
        switch self {
        case .work: return "something from your current work"
        case .dailyLife: return "an ordinary situation outside work"
        case .pastExperience: return "something that actually happened to you"
        }
    }
}

struct LearningPathProgress: Codable, Hashable {
    var inputCompletedAt: Date?
    var noticingCompletedAt: Date?
    var shadowingCompletedAt: Date?
    var retrievalCompletedAt: Date?
    var spacedReviewCompletedAt: Date?
    var transformationCompletedAt: Date?
    var freeExpressionCompletedAt: Date?
    var realCommunicationCompletedAt: Date?
    var feedbackCorrectionCompletedAt: Date?
    var selectedChunk: String?
    var transferContext: TransferContext?

    func completedAt(for stage: LearningPathStage) -> Date? {
        switch stage {
        case .input: return inputCompletedAt
        case .noticing: return noticingCompletedAt
        case .shadowing: return shadowingCompletedAt
        case .retrieval: return retrievalCompletedAt
        case .spacedReview: return spacedReviewCompletedAt
        case .transformation: return transformationCompletedAt
        case .freeExpression: return freeExpressionCompletedAt
        case .realCommunication: return realCommunicationCompletedAt
        case .feedbackCorrection: return feedbackCorrectionCompletedAt
        }
    }

    mutating func mark(_ stage: LearningPathStage, at date: Date = Date()) {
        switch stage {
        case .input: inputCompletedAt = inputCompletedAt ?? date
        case .noticing: noticingCompletedAt = noticingCompletedAt ?? date
        case .shadowing: shadowingCompletedAt = shadowingCompletedAt ?? date
        case .retrieval: retrievalCompletedAt = retrievalCompletedAt ?? date
        case .spacedReview: spacedReviewCompletedAt = spacedReviewCompletedAt ?? date
        case .transformation: transformationCompletedAt = transformationCompletedAt ?? date
        case .freeExpression: freeExpressionCompletedAt = freeExpressionCompletedAt ?? date
        case .realCommunication: realCommunicationCompletedAt = realCommunicationCompletedAt ?? date
        case .feedbackCorrection: feedbackCorrectionCompletedAt = feedbackCorrectionCompletedAt ?? date
        }
    }
}

enum LearningPathEngine {
    static func isComplete(_ stage: LearningPathStage, progress: PracticeProgress) -> Bool {
        if progress.learningPath?.completedAt(for: stage) != nil {
            return true
        }

        switch stage {
        case .input:
            return !progress.attempts.isEmpty
        case .noticing:
            return false
        case .shadowing:
            return progress.attempts.contains { $0.resolvedActivity == .shadowing }
        case .retrieval, .spacedReview:
            return !(progress.review?.history.isEmpty ?? true)
        case .transformation:
            return progress.attempts.contains { $0.resolvedActivity == .transformation }
        case .freeExpression:
            return progress.attempts.contains { $0.resolvedActivity == .freeExpression }
        case .realCommunication, .feedbackCorrection:
            return false
        }
    }

    static func nextStage(for progress: PracticeProgress) -> LearningPathStage? {
        LearningPathStage.allCases.first { !isComplete($0, progress: progress) }
    }

    static func completedCount(for progress: PracticeProgress) -> Int {
        LearningPathStage.allCases.filter { isComplete($0, progress: progress) }.count
    }

    static func recordingActivity(for stage: LearningPathStage?) -> PracticeActivity {
        switch stage {
        case .transformation: return .transformation
        case .freeExpression: return .freeExpression
        case .feedbackCorrection: return .correction
        default: return .shadowing
        }
    }
}

enum LearningChunkExtractor {
    private struct Candidate {
        let text: String
        let normalized: String
        let score: Int
    }

    private static let reusablePatterns = [
        "as a result", "as soon as", "at the same time", "be able to", "because of",
        "by the time", "even though", "have to", "in order to", "instead of",
        "it depends on", "make sure", "on the way to", "one of the", "so that",
        "the same as", "there is", "there are", "that is why", "used to",
        "want to", "need to", "a lot of", "according to", "at least"
    ]

    private static let connectors: Set<String> = [
        "about", "after", "against", "around", "at", "before", "between", "by",
        "during", "for", "from", "in", "into", "near", "of", "on", "over",
        "through", "to", "under", "until", "with", "without"
    ]

    private static let auxiliaries: Set<String> = [
        "am", "are", "be", "been", "being", "can", "could", "did", "do", "does",
        "had", "has", "have", "is", "may", "might", "must", "should", "was",
        "were", "will", "would"
    ]

    private static let weakWords: Set<String> = [
        "a", "an", "and", "as", "at", "but", "for", "from", "in", "of", "on",
        "or", "the", "to", "with"
    ]

    static func extract(from sentence: String, limit: Int = 3) -> [String] {
        let words = WordDiffEngine.tokenize(sentence).map(\.text)
        guard words.count >= 2, limit > 0 else { return [] }
        let normalized = words.map { $0.lowercased() }
        var candidates: [Candidate] = []

        for pattern in reusablePatterns {
            let patternWords = pattern.split(separator: " ").map(String.init)
            guard patternWords.count <= normalized.count else { continue }
            for start in 0...(normalized.count - patternWords.count) where
                Array(normalized[start..<(start + patternWords.count)]) == patternWords {
                candidates.append(candidate(words, start: start, length: patternWords.count, score: 100 + patternWords.count))
            }
        }

        if words.count >= 3 {
            for length in stride(from: min(5, words.count), through: 3, by: -1) {
                for start in 0...(words.count - length) {
                    let slice = Array(normalized[start..<(start + length)])
                    let contentCount = slice.filter { !weakWords.contains($0) }.count
                    guard contentCount >= 2 else { continue }
                    let connectorBonus = slice.contains(where: connectors.contains) ? 8 : 0
                    let auxiliaryBonus = slice.contains(where: auxiliaries.contains) ? 4 : 0
                    let verbBonus = slice.contains(where: looksLikeVerb) ? 6 : 0
                    let weakBoundaryPenalty = (weakWords.contains(slice.first ?? "") ? 3 : 0)
                        + (weakWords.contains(slice.last ?? "") ? 3 : 0)
                    let score = contentCount * 4 + connectorBonus + auxiliaryBonus + verbBonus + length - weakBoundaryPenalty
                    candidates.append(candidate(words, start: start, length: length, score: score))
                }
            }
        }

        var result: [String] = []
        var selectedNormalized: [String] = []
        for candidate in candidates.sorted(by: candidateOrder) {
            guard !selectedNormalized.contains(where: { existing in
                existing == candidate.normalized
                    || existing.contains(candidate.normalized)
                    || candidate.normalized.contains(existing)
            }) else { continue }
            result.append(candidate.text)
            selectedNormalized.append(candidate.normalized)
            if result.count == limit { break }
        }

        if result.isEmpty {
            return [words.prefix(min(4, words.count)).joined(separator: " ")]
        }
        return result
    }

    private static func candidate(_ words: [String], start: Int, length: Int, score: Int) -> Candidate {
        let text = words[start..<(start + length)].joined(separator: " ")
        return Candidate(text: text, normalized: text.lowercased(), score: score)
    }

    private static func candidateOrder(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.text.count != rhs.text.count { return lhs.text.count < rhs.text.count }
        return lhs.normalized < rhs.normalized
    }

    private static func looksLikeVerb(_ word: String) -> Bool {
        auxiliaries.contains(word)
            || word.hasSuffix("ed")
            || word.hasSuffix("ing")
            || ["check", "find", "get", "give", "go", "keep", "know", "make", "need", "say", "see", "take", "think", "use", "want", "work"].contains(word)
    }
}
