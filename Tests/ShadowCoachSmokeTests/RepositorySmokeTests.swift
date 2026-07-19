import Foundation
import XCTest
@testable import ShadowCoach

final class RepositorySmokeTests: XCTestCase {
    func testExampleProviderConfigContainsNoCredentialValues() throws {
        let root = repositoryRoot()
        let data = try Data(contentsOf: root.appendingPathComponent("config/provider-config.example.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let azure = try XCTUnwrap(object["azure"] as? [String: Any])

        XCTAssertEqual(azure["speech_key"] as? String, "")
        XCTAssertEqual(azure["translator_key"] as? String, "")
    }

    func testPublicRepositoryDoesNotContainPersonalRuntimeData() {
        let root = repositoryRoot()
        let forbidden = [
            "provider-config.json",
            "ShadowCoachMobileDocuments",
            "ShadowCoach-iPhone-MVP-3Sources.shadowcoachbundle"
        ]

        for name in forbidden {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path))
        }
    }

    func testSpokenNumberWordsMatchTranscriptDigits() {
        let cases = [
            (reference: "twenty", transcript: "20"),
            (reference: "five", transcript: "5"),
            (reference: "six hundred", transcript: "600"),
            (reference: "one thousand", transcript: "1,000"),
            (reference: "one hundred and five", transcript: "105"),
            (reference: "twenty twenty six", transcript: "2026")
        ]

        for item in cases {
            let result = WordDiffEngine.analyze(
                targetWords: WordDiffEngine.tokenize(item.reference),
                userWords: WordDiffEngine.tokenize(item.transcript)
            )
            XCTAssertEqual(result.accuracy, 100, item.reference)
            XCTAssertTrue(result.missingWords.isEmpty, item.reference)
            XCTAssertTrue(result.extraWords.isEmpty, item.reference)
            XCTAssertEqual(result.items.first?.counterpartText, item.transcript, item.reference)
            XCTAssertEqual(
                WordDiffEngine.comparisonText(item.reference),
                WordDiffEngine.comparisonText(item.transcript),
                item.reference
            )
        }
    }

    func testDifferentWordAtSamePositionIsASelectionNotMissingPlusExtra() {
        let result = WordDiffEngine.analyze(
            targetWords: WordDiffEngine.tokenize("The robot stopped near LM 174"),
            userWords: WordDiffEngine.tokenize("The robot stopped around LM 174")
        )

        XCTAssertTrue(result.missingWords.isEmpty)
        XCTAssertTrue(result.extraWords.isEmpty)
        XCTAssertEqual(result.substitutions.count, 1)
        XCTAssertEqual(result.substitutions.first?.spoken, "around")
        XCTAssertEqual(result.substitutions.first?.expected, "near")
        XCTAssertEqual(result.items.first(where: { $0.status == .substituted })?.counterpartText, "around")
    }

    func testPunctuationAndCapitalizationNeverAffectRecallScore() {
        let result = WordDiffEngine.analyze(
            targetWords: WordDiffEngine.tokenize("Every night, about twenty events occurred."),
            userWords: WordDiffEngine.tokenize("every night about twenty events occurred")
        )

        XCTAssertEqual(result.accuracy, 100)
        XCTAssertTrue(result.missingWords.isEmpty)
        XCTAssertTrue(result.extraWords.isEmpty)
        XCTAssertTrue(result.substitutions.isEmpty)
        XCTAssertEqual(
            WordDiffEngine.spokenText("Every night, about twenty events occurred."),
            "Every night about twenty events occurred"
        )
    }

    func testTypographicApostrophesMatchSpeechRecognizerContractions() {
        let result = WordDiffEngine.analyze(
            targetWords: WordDiffEngine.tokenize("They’ve already checked it."),
            userWords: WordDiffEngine.tokenize("they've already checked it")
        )

        XCTAssertEqual(result.accuracy, 100)
        XCTAssertTrue(result.missingWords.isEmpty)
        XCTAssertTrue(result.extraWords.isEmpty)
    }

    func testCompoundSpacingDoesNotAffectRecallScore() {
        let cases = [
            (reference: "I worked on site.", transcript: "I worked onsite"),
            (reference: "The on-site operator checked it.", transcript: "the onsite operator checked it"),
            (reference: "I shared an update at every checkpoint.", transcript: "I shared an update at every check point"),
            (reference: "The checkpoints were clear.", transcript: "the check points were clear")
        ]

        for item in cases {
            let result = WordDiffEngine.analyze(
                targetWords: WordDiffEngine.tokenize(item.reference),
                userWords: WordDiffEngine.tokenize(item.transcript)
            )
            XCTAssertEqual(result.accuracy, 100, item.reference)
            XCTAssertTrue(result.missingWords.isEmpty, item.reference)
            XCTAssertTrue(result.extraWords.isEmpty, item.reference)
            XCTAssertTrue(result.substitutions.isEmpty, item.reference)
            XCTAssertEqual(
                WordDiffEngine.comparisonText(item.reference),
                WordDiffEngine.comparisonText(item.transcript),
                item.reference
            )
        }
    }

    func testCoachFeedbackRemovesPunctuationCriticismButKeepsUsefulJudgment() {
        let feedback = """
        ## 核心判断
        逐字复述不完全一致：你漏了逗号，但词汇和语序一致。
        你的表达语法自然，原意完整保留。
        """

        let cleaned = CoachFeedbackSanitizer.clean(feedback)
        XCTAssertFalse(cleaned.contains("逗号"))
        XCTAssertTrue(cleaned.contains("你的表达语法自然"))
        XCTAssertTrue(cleaned.contains("## 核心判断"))
    }

    func testPerfectWordRecallCanSkipCoachAnalysis() {
        let perfect = makeRecordingAnalysis(
            reference: "The robot reached the target.",
            transcript: "the robot reached the target"
        )
        let changed = makeRecordingAnalysis(
            reference: "The robot reached the target.",
            transcript: "the robot reached a target"
        )

        XCTAssertTrue(perfect.isPerfectWordRecall)
        XCTAssertFalse(changed.isPerfectWordRecall)
    }

    func testCoachFeedbackDepthAdaptsToRecallAccuracy() {
        let nearlyPerfect = CoachFeedbackPolicy.outputGuidance(accuracy: 96, depth: .focused)
        XCTAssertTrue(nearlyPerfect.contains("120-220"))
        XCTAssertTrue(nearlyPerfect.contains("at most 2"))
        XCTAssertTrue(nearlyPerfect.contains("Skip speculative memory diagnosis"))

        let difficultAttempt = CoachFeedbackPolicy.outputGuidance(accuracy: 58, depth: .deep)
        XCTAssertTrue(difficultAttempt.contains("420-650"))
        XCTAssertTrue(difficultAttempt.contains("at most 4"))
        XCTAssertTrue(difficultAttempt.contains("深入理解"))
    }

    func testCoachPromptUsesAdaptiveOutputGuidance() throws {
        let source = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Sources/ShadowCoach/main.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(#"\(outputGuidance)"#))
        XCTAssertTrue(source.contains(#"\(referenceOrigin)"#))
        XCTAssertTrue(source.contains("## 参考句检查"))
        XCTAssertTrue(source.contains("noisy alignment hints, not ground truth"))
        XCTAssertFalse(source.contains("\n        (outputGuidance)\n"))
    }

    func testReferenceOriginDistinguishesLocalSubtitleFromHumanCaptions() {
        let localSubtitle = ReferenceOriginPolicy.guidance(
            quality: .localSubtitle,
            hasSourceAudio: true
        )
        let humanCaptions = ReferenceOriginPolicy.guidance(
            quality: .humanCaptions,
            hasSourceAudio: true
        )

        XCTAssertTrue(localSubtitle.contains("TTS"))
        XCTAssertTrue(localSubtitle.contains("does not prove native"))
        XCTAssertTrue(humanCaptions.contains("Published source audio"))
    }

    func testFeedbackTextSizesUseVisiblePointScaleDifferences() {
        XCTAssertLessThan(FeedbackTextSizeOption.compact.scale, FeedbackTextSizeOption.standard.scale)
        XCTAssertGreaterThan(FeedbackTextSizeOption.large.scale, FeedbackTextSizeOption.standard.scale)
        XCTAssertGreaterThanOrEqual(FeedbackTextSizeOption.large.scale, 1.15)
    }

    func testRecordingMustReachReferenceDurationBeforeItIsSaved() {
        XCTAssertTrue(RecordingLengthPolicy.shouldDiscard(recordingDuration: 4.99, referenceDuration: 5.0))
        XCTAssertFalse(RecordingLengthPolicy.shouldDiscard(recordingDuration: 5.0, referenceDuration: 5.0))
        XCTAssertFalse(RecordingLengthPolicy.shouldDiscard(recordingDuration: 5.01, referenceDuration: 5.0))
        XCTAssertFalse(RecordingLengthPolicy.shouldDiscard(recordingDuration: 0.5, referenceDuration: nil))
    }

    func testCoachConversationRoundTripsInsideAnalysisCache() throws {
        let analysis = makeRecordingAnalysis(reference: "I want to go.", transcript: "I want to go")
        let conversation = [
            CoachConversationMessage(role: .user, text: "Why is this phrase natural?"),
            CoachConversationMessage(role: .assistant, text: "It uses a common spoken chunk.")
        ]
        let cache = RecordingAnalysisCache(
            createdAt: Date(),
            localAnalysis: analysis,
            geminiFeedback: nil,
            coachConversation: conversation
        )

        let decoded = try JSONDecoder().decode(
            RecordingAnalysisCache.self,
            from: JSONEncoder().encode(cache)
        )
        XCTAssertEqual(decoded.coachConversation, conversation)
    }

    func testOlderAnalysisCacheDecodesWithoutReferenceOriginField() throws {
        let analysis = makeRecordingAnalysis(reference: "I checked the records.", transcript: "I checked records")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(analysis)) as? [String: Any]
        )
        object.removeValue(forKey: "reference_has_source_audio")
        object.removeValue(forKey: "reference_quality")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(RecordingAnalysis.self, from: legacyData)
        XCTAssertNil(decoded.referenceHasSourceAudio)
        XCTAssertNil(decoded.referenceQuality)
    }

    func testTrueOmissionsAndInsertionsRemainSeparate() {
        let omission = WordDiffEngine.analyze(
            targetWords: WordDiffEngine.tokenize("I really want to go"),
            userWords: WordDiffEngine.tokenize("I want to go")
        )
        XCTAssertEqual(omission.missingWords, ["really"])
        XCTAssertTrue(omission.substitutions.isEmpty)

        let insertion = WordDiffEngine.analyze(
            targetWords: WordDiffEngine.tokenize("I want to go"),
            userWords: WordDiffEngine.tokenize("I really want to go")
        )
        XCTAssertEqual(insertion.extraWords, ["really"])
        XCTAssertTrue(insertion.substitutions.isEmpty)
    }

    func testSpeechRecognitionHintsOnlyExposeTechnicalTerms() {
        let hints = SpeechRecognitionHints.terms(
            in: "I reviewed PAT near LM174 with a LiDAR scan and a normal site check."
        )

        XCTAssertEqual(hints, ["PAT", "LM174", "LiDAR"])
        XCTAssertFalse(hints.contains("site"))
        XCTAssertFalse(hints.contains("check"))
    }

    func testSpeechRecognitionHintsIncludeAmbiguousCompoundsFromReference() {
        let hints = SpeechRecognitionHints.terms(
            in: "The on-site operator stopped at the checkpoint."
        )

        XCTAssertEqual(hints, ["on-site", "onsite", "checkpoint", "checkpoints"])
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeRecordingAnalysis(reference: String, transcript: String) -> RecordingAnalysis {
        let diff = WordDiffEngine.analyze(
            targetWords: WordDiffEngine.tokenize(reference),
            userWords: WordDiffEngine.tokenize(transcript)
        )
        return RecordingAnalysis(
            referenceText: reference,
            sourceTitle: nil,
            referenceHasSourceAudio: false,
            referenceQuality: nil,
            contextBefore: nil,
            contextAfter: nil,
            transcript: transcript,
            accuracy: diff.accuracy,
            items: diff.items,
            missingWords: diff.missingWords,
            extraWords: diff.extraWords,
            substitutions: diff.substitutions,
            issueHints: [],
            whisperXRawJSON: nil,
            azure: nil,
            pronunciationIssues: nil,
            prosody: nil
        )
    }
}
