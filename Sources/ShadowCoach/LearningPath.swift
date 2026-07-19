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

enum LearningTargetKind: String, Codable, Hashable {
    case sentenceFrame
    case fixedExpression
    case collocation
    case phrasalVerb
    case discourseMarker

    var label: String {
        switch self {
        case .sentenceFrame: return "Sentence frame"
        case .fixedExpression: return "Fixed expression"
        case .collocation: return "Collocation"
        case .phrasalVerb: return "Phrasal verb"
        case .discourseMarker: return "Linking expression"
        }
    }
}

enum LearningTargetSource: String, Codable, Hashable {
    case local
    case ai
    case legacy
}

struct LearningTarget: Codable, Hashable, Identifiable {
    let text: String
    let kind: LearningTargetKind
    let frame: String?
    let note: String
    let source: LearningTargetSource

    var id: String {
        "\(kind.rawValue)|\(text.lowercased())|\(frame?.lowercased() ?? "")"
    }

    var displayText: String {
        if let frame, !frame.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return frame
        }
        return text
    }

    init(
        text: String,
        kind: LearningTargetKind,
        frame: String? = nil,
        note: String,
        source: LearningTargetSource = .local
    ) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = kind
        let cleanedFrame = frame?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.frame = cleanedFrame?.isEmpty == false ? cleanedFrame : nil
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
    }
}

enum RealUseOutcome: String, CaseIterable, Codable, Identifiable, Hashable {
    case worked
    case hesitated
    case didNotLand

    var id: String { rawValue }

    var label: String {
        switch self {
        case .worked: return "Worked"
        case .hesitated: return "Hesitated"
        case .didNotLand: return "Didn't land"
        }
    }

    var systemImage: String {
        switch self {
        case .worked: return "checkmark.circle"
        case .hesitated: return "pause.circle"
        case .didNotLand: return "questionmark.circle"
        }
    }
}

struct RealUseReflection: Codable, Hashable {
    let createdAt: Date
    let outcome: RealUseOutcome
    let actualWords: String
    let coachFeedback: String?
    let feedbackProvider: String?
    let coachModel: String?
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
    var selectedTarget: LearningTarget?
    var suggestedTargets: [LearningTarget]?
    var targetSuggestionModel: String?
    var transferContext: TransferContext?
    var realUseReflection: RealUseReflection?

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
    static func isApplicable(_ stage: LearningPathStage, progress: PracticeProgress) -> Bool {
        guard [.transformation, .freeExpression, .realCommunication].contains(stage) else {
            return true
        }
        guard let path = progress.learningPath,
              path.noticingCompletedAt != nil else {
            return true
        }
        let hasStructuredTarget = path.selectedTarget != nil
        let hasLegacyTarget = !(path.selectedChunk?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return hasStructuredTarget || hasLegacyTarget
    }

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
        LearningPathStage.allCases.first {
            isApplicable($0, progress: progress) && !isComplete($0, progress: progress)
        }
    }

    static func completedCount(for progress: PracticeProgress) -> Int {
        LearningPathStage.allCases.filter {
            !isApplicable($0, progress: progress) || isComplete($0, progress: progress)
        }.count
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

enum LearningTargetExtractor {
    private struct Rule {
        let pattern: String
        let kind: LearningTargetKind
        let frame: String?
        let note: String
        let score: Int
        let capturesWholeSentence: Bool

        init(
            _ pattern: String,
            kind: LearningTargetKind,
            frame: String? = nil,
            note: String,
            score: Int,
            capturesWholeSentence: Bool = false
        ) {
            self.pattern = pattern
            self.kind = kind
            self.frame = frame
            self.note = note
            self.score = score
            self.capturesWholeSentence = capturesWholeSentence
        }
    }

    private struct Candidate {
        let target: LearningTarget
        let score: Int
        let range: NSRange
    }

    private static let rules: [Rule] = [
        Rule(#"\bon the way to\b"#, kind: .fixedExpression, frame: "on the way to [place/goal]", note: "A reusable way to describe movement toward a destination.", score: 100),
        Rule(#"\bat the same time\b"#, kind: .discourseMarker, note: "Links two actions or facts that happen together.", score: 98),
        Rule(#"\bas a result\b"#, kind: .discourseMarker, note: "Introduces a consequence clearly.", score: 98),
        Rule(#"\bin other words\b"#, kind: .discourseMarker, note: "Introduces a clearer restatement.", score: 98),
        Rule(#"\bon the other hand\b"#, kind: .discourseMarker, note: "Introduces a contrast in a balanced explanation.", score: 98),
        Rule(#"\bfor example\b"#, kind: .discourseMarker, note: "Introduces a concrete example.", score: 96),
        Rule(#"\beven though\b"#, kind: .discourseMarker, frame: "even though [contrast], [main point]", note: "Builds a useful concession pattern.", score: 96),
        Rule(#"\brather than\b"#, kind: .discourseMarker, frame: "[choice A] rather than [choice B]", note: "Contrasts the preferred choice with an alternative.", score: 96),
        Rule(#"\bnot only\b.+\bbut also\b"#, kind: .sentenceFrame, frame: "not only [A], but also [B]", note: "Adds two parallel points with emphasis.", score: 110),
        Rule(#"\bthe more\b.+\bthe more\b"#, kind: .sentenceFrame, frame: "the more [condition], the more [result]", note: "Expresses two changes that move together.", score: 110),
        Rule(#"\b(make|makes|made|making) sure\b"#, kind: .collocation, frame: "make sure (that) [result]", note: "A high-frequency verb pattern for checking or ensuring something.", score: 104),
        Rule(#"\b(take|takes|took|taken|taking) into account\b"#, kind: .collocation, frame: "take [factor] into account", note: "A useful decision-making collocation.", score: 106),
        Rule(#"\b(pay|pays|paid|paying) attention to\b"#, kind: .collocation, frame: "pay attention to [detail]", note: "A common collocation for deliberate focus.", score: 104),
        Rule(#"\b(be|am|is|are|was|were|been|being) able to\b"#, kind: .collocation, frame: "be able to [action]", note: "A reusable way to express practical ability.", score: 90),
        Rule(#"\b(be|am|is|are|was|were|been|being) responsible for\b"#, kind: .collocation, frame: "be responsible for [task/result]", note: "A common professional responsibility pattern.", score: 104),
        Rule(#"\b(be|am|is|are|was|were|been|being) likely to\b"#, kind: .collocation, frame: "be likely to [action]", note: "Expresses probability in neutral professional English.", score: 102),
        Rule(#"\b(lead|leads|led|leading) to\b"#, kind: .collocation, frame: "[cause] lead to [result]", note: "A compact cause-and-effect pattern.", score: 104),
        Rule(#"\b(result|results|resulted|resulting) in\b"#, kind: .collocation, frame: "[cause] result in [outcome]", note: "A common formal cause-and-effect collocation.", score: 104),
        Rule(#"\b(prevent|prevents|prevented|preventing)\s+(?:[\w'-]+\s+){1,5}from\b"#, kind: .sentenceFrame, frame: "prevent [person/thing] from [action]", note: "A reusable pattern for describing a blocked action.", score: 104),
        Rule(#"\b(allow|allows|allowed|allowing)\s+(?:[\w'-]+\s+){1,5}to\b"#, kind: .sentenceFrame, frame: "allow [person/thing] to [action]", note: "A reusable permission or enablement pattern.", score: 101),
        Rule(#"\b(deal|deals|dealt|dealing) with\b"#, kind: .phrasalVerb, frame: "deal with [issue/person]", note: "A high-frequency phrasal verb for handling something.", score: 105),
        Rule(#"\b(find|finds|found|finding) out\b"#, kind: .phrasalVerb, frame: "find out [information]", note: "A common phrasal verb for discovering information.", score: 105),
        Rule(#"\b(figure|figures|figured|figuring) out\b"#, kind: .phrasalVerb, frame: "figure out [problem/answer]", note: "A common spoken phrasal verb for understanding or solving.", score: 106),
        Rule(#"\b(look|looks|looked|looking) into\b"#, kind: .phrasalVerb, frame: "look into [issue]", note: "A useful professional phrasal verb for investigating.", score: 106),
        Rule(#"\b(rule|rules|ruled|ruling) out\b"#, kind: .phrasalVerb, frame: "rule out [possible cause]", note: "A useful diagnostic phrasal verb for eliminating a possibility.", score: 108),
        Rule(#"\b(carry|carries|carried|carrying) out\b"#, kind: .phrasalVerb, frame: "carry out [test/plan]", note: "A common professional phrasal verb for executing work.", score: 105),
        Rule(#"\b(set|sets|setting) up\b"#, kind: .phrasalVerb, frame: "set up [system/process]", note: "A common phrasal verb for preparing or arranging something.", score: 103),
        Rule(#"\b(follow|follows|followed|following) up\b"#, kind: .phrasalVerb, frame: "follow up on [issue]", note: "A useful professional phrasal verb for continuing an action.", score: 104),
        Rule(#"\b(work|works|worked|working) on\b"#, kind: .collocation, frame: "work on [task/problem]", note: "A reusable verb-preposition collocation.", score: 88),
        Rule(#"\b(depends?|depended|depending) on\b"#, kind: .collocation, frame: "depend on [condition]", note: "A high-frequency way to express a condition.", score: 101),
        Rule(#"\b(ask|asks|asked|asking)\s+(?:[\w'-]+\s+){1,5}to\b"#, kind: .sentenceFrame, frame: "ask [person] to [action]", note: "A core reporting pattern for requests.", score: 98),
        Rule(#"\b\w+ times? (a|per) (day|week|month|year|night|shift)\b"#, kind: .sentenceFrame, frame: "[number] times a/per [period]", note: "A reusable frequency pattern.", score: 102),
        Rule(#"\bthere (is|are|was|were)\b"#, kind: .sentenceFrame, frame: "there is/are [something]", note: "A core pattern for introducing information.", score: 84),
        Rule(#"\bthat is why\b"#, kind: .discourseMarker, frame: "[cause]. That is why [result].", note: "Links a cause to its result in spoken English.", score: 101),
        Rule(#"\bwhat\b.+\b(is|was)\b.+"#, kind: .sentenceFrame, frame: "What [clause] is/was [focus]", note: "A cleft-style frame that puts the important point at the end.", score: 108, capturesWholeSentence: true),
        Rule(#"\bthe reason\b.+\b(is|was)\b.+"#, kind: .sentenceFrame, frame: "The reason [clause] is/was [explanation]", note: "A clear frame for explaining cause.", score: 108, capturesWholeSentence: true),
        Rule(#"\bif\b.+\bthen\b.+"#, kind: .sentenceFrame, frame: "If [condition], then [result]", note: "Makes a condition and consequence explicit.", score: 106, capturesWholeSentence: true),
        Rule(#"\b.+\bbut\b.+"#, kind: .sentenceFrame, frame: "[claim], but [contrast/evidence]", note: "A reusable contrast frame when both sides form a meaningful pattern.", score: 90, capturesWholeSentence: true)
    ]

    static func extract(from sentence: String, limit: Int = 3) -> [LearningTarget] {
        let cleaned = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, limit > 0 else { return [] }
        let fullRange = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
        var candidates: [Candidate] = []

        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]) else {
                continue
            }
            for match in regex.matches(in: cleaned, range: fullRange) {
                let selectedRange = rule.capturesWholeSentence ? fullRange : match.range
                guard let swiftRange = Range(selectedRange, in: cleaned) else { continue }
                let text = String(cleaned[swiftRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                guard text.split(separator: " ").count >= 2 else { continue }
                let target = LearningTarget(
                    text: text,
                    kind: rule.kind,
                    frame: rule.frame,
                    note: rule.note
                )
                guard LearningTargetQuality.isAcceptable(
                    text: target.text,
                    kind: target.kind,
                    frame: target.frame
                ) else { continue }
                candidates.append(Candidate(
                    target: target,
                    score: rule.score,
                    range: selectedRange
                ))
            }
        }

        var result: [LearningTarget] = []
        for candidate in candidates.sorted(by: candidateOrder) {
            guard candidate.score >= 96 else { continue }
            guard !result.contains(where: { existing in
                existing.id == candidate.target.id
                    || existing.text.localizedCaseInsensitiveContains(candidate.target.text)
                    || candidate.target.text.localizedCaseInsensitiveContains(existing.text)
            }) else { continue }
            result.append(candidate.target)
            if result.count == limit { break }
        }
        return result
    }

    private static func candidateOrder(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.range.length != rhs.range.length { return lhs.range.length < rhs.range.length }
        return lhs.target.text.localizedCaseInsensitiveCompare(rhs.target.text) == .orderedAscending
    }
}

enum LearningTargetPrompt {
    static func make(
        sentence: String,
        source: String,
        contextBefore: String?,
        contextAfter: String?
    ) -> String {
        """
        Select genuinely reusable English learning targets for a Chinese native speaker around B2 level. The goal is transfer to new situations, not highlighting memorable-looking fragments.

        Sentence: "\(sentence)"
        Source: \(source)
        Previous sentence: \(contextBefore ?? "not available")
        Next sentence: \(contextAfter ?? "not available")

        Return a JSON array with 0 to 3 items. Zero is a valid and preferred answer when this sentence has nothing worth isolating.

        A valuable target must be one of these:
        - sentenceFrame: a productive grammatical frame with replaceable slots
        - fixedExpression: a conventional multiword expression
        - collocation: words that are naturally learned together
        - phrasalVerb: a verb-particle or verb-preposition unit whose combination is useful
        - discourseMarker: an expression that organizes logic or conversation

        Hard rules:
        - Never select an arbitrary contiguous fragment merely because it contains several content words.
        - Never select names, IDs, isolated technical nouns, raw numbers, or topic-specific noun phrases unless they form a broadly reusable collocation.
        - Do not return a generic subject + verb fragment such as "different robots stopped".
        - Do not return transparent beginner combinations such as "be able to", "work on", or "there is" unless the larger construction teaches a non-obvious pattern.
        - A sentence frame must contain replaceable slots and preserve a meaningful grammatical or logical relationship. Generic labels such as "[subject] + [verb]" are invalid.
        - Prefer one excellent target over three mediocre targets. Return [] when none would deserve deliberate review.
        - `text` must be an exact contiguous substring of the sentence, preserving the original words.
        - Prefer 2-6 words for expressions. A sentenceFrame may use a longer exact span only when the whole construction is genuinely reusable.
        - `frame` should replace changeable content with clear slots such as `[cause]`, `[person]`, or `[result]`. Use null when no frame helps.
        - `note` must give one concrete reason this target transfers to other situations. Keep it under 18 English words.
        - Do not create multiple targets that teach the same construction.
        - Output JSON only. No Markdown and no explanation outside the array.

        JSON shape:
        [
          {
            "text": "exact words from the sentence",
            "kind": "sentenceFrame|fixedExpression|collocation|phrasalVerb|discourseMarker",
            "frame": "generalized frame or null",
            "note": "why it is reusable"
          }
        ]
        """
    }
}

enum LearningTargetAIParser {
    private struct Item: Decodable {
        let text: String
        let kind: LearningTargetKind
        let frame: String?
        let note: String
    }

    static func parse(_ raw: String, sentence: String) throws -> [LearningTarget] {
        guard let start = raw.firstIndex(of: "["), let end = raw.lastIndex(of: "]"), start <= end else {
            throw NSError(
                domain: "LearningTargetAIParser",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "The coach did not return a JSON array."]
            )
        }
        let json = String(raw[start...end])
        let items = try JSONDecoder().decode([Item].self, from: Data(json.utf8))
        var seen: Set<String> = []
        var targets: [LearningTarget] = []

        for item in items.prefix(6) {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard LearningTargetQuality.isAcceptable(
                    text: text,
                    kind: item.kind,
                    frame: item.frame
                  ),
                  sentence.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil,
                  !note.isEmpty else {
                continue
            }
            let target = LearningTarget(
                text: text,
                kind: item.kind,
                frame: item.frame,
                note: note,
                source: .ai
            )
            guard seen.insert(target.id).inserted else { continue }
            targets.append(target)
            if targets.count == 3 { break }
        }
        return targets
    }
}

enum LearningTargetQuality {
    private static let weakStandaloneTargets: Set<String> = [
        "be able to", "work on", "there is", "there are", "a lot of", "some of the"
    ]

    static func isAcceptable(text: String, kind: LearningTargetKind, frame: String?) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count >= 2, words.count <= (kind == .sentenceFrame ? 18 : 8) else { return false }
        if kind != .sentenceFrame {
            guard text.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        }
        guard !weakStandaloneTargets.contains(text.lowercased()) else { return false }

        if kind == .sentenceFrame {
            guard let frame else { return false }
            let slotCount = frame.filter { $0 == "[" }.count
            guard slotCount > 0, frame.contains("]") else { return false }
        }

        let identifierLike = words.contains { token in
            let raw = token.trimmingCharacters(in: .punctuationCharacters)
            return raw.count >= 3
                && raw.range(of: #"^[A-Z]{2,}\d*$"#, options: .regularExpression) != nil
        }
        return kind == .sentenceFrame || !identifierLike
    }
}

enum OpenResponseCoachPrompt {
    static func make(
        activity: PracticeActivity,
        transcript: String,
        learningTarget: LearningTarget?,
        originalIdea: String,
        contextBefore: String?,
        contextAfter: String?
    ) -> String {
        let target = learningTarget.map {
            "\($0.displayText) (source wording: \($0.text); type: \($0.kind.label))"
        } ?? "No standalone target; transfer the main idea naturally."
        let context = [contextBefore, contextAfter]
            .compactMap { $0 }
            .joined(separator: " / ")
        let common = """
        You are an English speaking coach for a Chinese native speaker around B2 level.
        You do not have access to the audio. The transcript is uncertain ASR evidence, so never claim that you heard pronunciation, stress, rhythm, pauses, or emotion.
        This is an open-response task. Never score exact recall, never compare punctuation or capitalization, and never penalize the learner for not copying the original sentence.
        Reply in concise, polished Chinese with English examples. No greetings, tables, raw logs, provider names, or generic encouragement.

        Original material (context only): "\(originalIdea)"
        Nearby context: \(context.isEmpty ? "not available" : context)
        Learning target: \(target)
        Recognized learner response: "\(transcript)"
        """

        switch activity {
        case .transformation:
            return common + """

            The learner's task was to use the target in a genuinely different situation. Judge three things separately: whether the situation changed, whether the target kept its grammar and meaning, and whether the new sentence is natural and clear.
            Do not reward a sentence that merely swaps one noun while copying everything else. Do not demand the exact source wording when a natural variation works.

            Use exactly this structure:
            ## 任务完成度
            One direct sentence: 完成 / 部分完成 / 需要重来, followed by the specific reason.

            ## 目标表达
            Explain whether the target was used naturally and what slot or relationship changed. If no target was selected, assess transfer of the main idea instead.

            ## 优先修改
            Give at most two high-impact corrections. Omit this section if no meaningful correction is needed.

            ## 更自然版本
            Give one simple B2-level version that preserves the learner's intended new situation. Do not turn it into formal essay English.

            ## 马上重说
            Give one short instruction and the exact sentence to repeat now.
            """
        case .freeExpression:
            return common + """

            The learner's task was to communicate a related experience or opinion in their own words. Judge communication first: understandable main point, logical flow, natural phrasing, and appropriate use of the target. Do not turn this into a shadowing comparison.
            Prioritize only errors that affect meaning, grammar, or reusable spoken English. Ignore harmless spoken fragments and do not rewrite everything into an essay.

            Use exactly this structure:
            ## 沟通效果
            State what message came through and the single biggest obstacle, if any.

            ## 目标表达
            Explain whether the learning target was used naturally. If it was not used, suggest one natural insertion without calling the whole response wrong.

            ## 优先修改
            Give at most two high-impact corrections. Omit this section if none is needed.

            ## 更自然版本
            Give a compact spoken B2-level version of the learner's intended message, not a memorized copy of the source.

            ## 30 秒重说
            Give a three-beat speaking outline using short English chunks, then one direct retry instruction.
            """
        case .shadowing, .correction:
            return common
        }
    }
}

enum RealUseCoachPrompt {
    static func make(
        outcome: RealUseOutcome,
        actualWords: String,
        learningTarget: LearningTarget?,
        originalSentence: String
    ) -> String {
        let target = learningTarget?.displayText ?? "the main idea"
        return """
        You are reviewing a Chinese native English learner's self-reported real-world use. You have no recording and no independent evidence beyond the report below.

        Original learning sentence: "\(originalSentence)"
        Intended reusable target: "\(target)"
        Learner-reported outcome: \(outcome.label)
        What the learner says they actually said: "\(actualWords)"

        Evaluate whether the wording fits a real interaction, not whether it exactly matches the original. Never discuss pronunciation, rhythm, or exact recall. Do not invent the listener's reaction. Treat the reported outcome as context, not proof of a linguistic error.
        Reply in concise Chinese with English examples. No greetings, tables, scores, or generic praise.

        Use exactly this structure:
        ## 真实使用
        State what the wording successfully communicated and whether the target fit this use.

        ## 这次卡点
        Give at most one likely language issue supported by the actual words. If the wording is already natural, say so and identify a fluency strategy instead. Do not diagnose psychology.

        ## 下次一句话
        Give one short, natural B2-level sentence the learner can use in the next similar situation.
        """
    }
}

enum OpenResponseFollowUpPrompt {
    static func make(
        question: String,
        cache: OpenResponseAnalysisCache,
        existingFeedback: String,
        conversation: [CoachConversationMessage]
    ) -> String {
        let previous = conversation.dropLast().suffix(8).map { message in
            "\(message.role == .user ? "Learner" : "Coach"): \(message.text)"
        }
        .joined(separator: "\n")
        let target = cache.learningTarget?.displayText ?? "No standalone target was selected."
        let objective = cache.activity == .transformation
            ? "Judge transfer to a genuinely new situation and natural use of the target."
            : "Judge communication, organization, natural spoken English, and target use."

        return """
        Continue an English coaching conversation with a Chinese native speaker around B2 level.
        Answer only the latest question in concise, natural Chinese, using short English examples where useful. Do not regenerate the full report unless asked. No greetings or tables.

        Stage: \(cache.activity.label)
        Stage objective: \(objective)
        Recognized open response: "\(cache.transcript)"
        Learning target: "\(target)"
        Existing stage feedback: \(existingFeedback.isEmpty ? "none" : existingFeedback)
        Previous conversation: \(previous.isEmpty ? "none" : previous)
        Latest learner question: \(question)

        Hard limits:
        - This is not exact shadowing. Never give a word-recall score or penalize paraphrasing.
        - You cannot hear the audio. Never claim pronunciation, stress, rhythm, or pause evidence.
        - ASR may be wrong; use cautious wording when the question depends on one recognized word.
        - Explain meaning, grammar, collocation, register, or transfer according to this stage's objective.
        - Usually answer in 80-220 Chinese characters.
        """
    }
}
