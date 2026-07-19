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
            contentsOf: repositoryRoot().appendingPathComponent("Sources/ShadowCoach/ShadowCoachApp.swift"),
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

    func testOpenResponseConversationRoundTripsWithStageCache() throws {
        let conversation = [
            CoachConversationMessage(role: .user, text: "Why does this sound formal?"),
            CoachConversationMessage(role: .assistant, text: "Use this shorter spoken version instead.")
        ]
        let cache = OpenResponseAnalysisCache(
            createdAt: Date(),
            activity: .freeExpression,
            transcript: "I ruled out the first cause and checked the logs.",
            learningTarget: nil,
            coachFeedback: "## 沟通效果\n意思清楚。",
            feedbackProvider: .codex,
            usedAICoach: true,
            coachModel: "test-model",
            transcriptModel: "test-transcriber",
            coachConversation: conversation
        )

        let decoded = try JSONDecoder().decode(
            OpenResponseAnalysisCache.self,
            from: JSONEncoder().encode(cache)
        )
        XCTAssertEqual(decoded.activity, .freeExpression)
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

    func testFSRS6UsesOfficialShortLearningSteps() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduler = FSRS6Scheduler(desiredRetention: 0.9)

        let first = scheduler.schedule(card: FSRSReviewCard(), rating: .good, at: now)
        XCTAssertEqual(first.card.state, .learning)
        XCTAssertEqual(first.card.step, 1)
        XCTAssertEqual(first.card.stability ?? -1, FSRS6Scheduler.defaultParameters[2], accuracy: 0.000_001)
        XCTAssertEqual(first.event.scheduledInterval, 10 * 60, accuracy: 0.001)

        let second = scheduler.schedule(
            card: first.card,
            rating: .good,
            at: now.addingTimeInterval(10 * 60)
        )
        XCTAssertEqual(second.card.state, .review)
        XCTAssertNil(second.card.step)
        XCTAssertEqual(second.event.scheduledInterval, 2 * 86_400, accuracy: 0.001)
    }

    func testFSRS6AgainUsesRelearningInsteadOfPretendingRecall() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var card = FSRSReviewCard(
            state: .review,
            step: nil,
            stability: 10,
            difficulty: 5,
            due: now,
            lastReview: now.addingTimeInterval(-10 * 86_400),
            reviewCount: 4,
            lapseCount: 0
        )
        let result = FSRS6Scheduler().schedule(card: card, rating: .again, at: now)
        card = result.card

        XCTAssertEqual(card.state, .relearning)
        XCTAssertEqual(card.step, 0)
        XCTAssertEqual(card.lapseCount, 1)
        XCTAssertEqual(result.event.scheduledInterval, 10 * 60, accuracy: 0.001)
    }

    func testHigherFSRSRetentionSchedulesEarlierReview() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let card = FSRSReviewCard(
            state: .review,
            step: nil,
            stability: 20,
            difficulty: 5,
            due: now,
            lastReview: now.addingTimeInterval(-20 * 86_400),
            reviewCount: 8,
            lapseCount: 0
        )

        let relaxed = FSRS6Scheduler(desiredRetention: 0.85).schedule(card: card, rating: .good, at: now)
        let strong = FSRS6Scheduler(desiredRetention: 0.95).schedule(card: card, rating: .good, at: now)

        XCTAssertLessThan(strong.event.scheduledInterval, relaxed.event.scheduledInterval)
    }

    func testLegacyPracticeProgressDecodesWithoutReviewState() throws {
        let data = try XCTUnwrap(#"{"practiceCount":2,"attempts":[]}"#.data(using: .utf8))
        let progress = try JSONDecoder().decode(PracticeProgress.self, from: data)

        XCTAssertEqual(progress.practiceCount, 2)
        XCTAssertNil(progress.review)
        XCTAssertNil(progress.learningPath)
    }

    func testLegacyRecordingAttemptDefaultsToShadowing() throws {
        let attempt = RecordingAttempt(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 4.2,
            relativePath: "Recordings/example.m4a"
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(attempt)) as? [String: Any]
        )
        object.removeValue(forKey: "activity")

        let decoded = try JSONDecoder().decode(
            RecordingAttempt.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(decoded.resolvedActivity, .shadowing)
        XCTAssertTrue(decoded.resolvedActivity.comparesWithReference)
    }

    func testOpenResponseRecordingsDoNotUseReferenceComparison() {
        XCTAssertFalse(PracticeActivity.transformation.comparesWithReference)
        XCTAssertFalse(PracticeActivity.freeExpression.comparesWithReference)
        XCTAssertTrue(PracticeActivity.shadowing.comparesWithReference)
        XCTAssertTrue(PracticeActivity.correction.comparesWithReference)
    }

    func testSelectingOpenResponseDoesNotFallBackToAnotherAttemptForAnalysis() {
        let lineID = UUID()
        let openResponse = RecordingAttempt(
            id: UUID(),
            date: Date(),
            duration: 20,
            relativePath: "Recordings/open-response.m4a",
            activity: .freeExpression
        )
        let shadowing = RecordingAttempt(
            id: UUID(),
            date: Date().addingTimeInterval(-60),
            duration: 5,
            relativePath: "Recordings/shadowing.m4a",
            activity: .shadowing
        )
        let coach = SpeechCoach()
        coach.selectedLineID = lineID
        coach.practiceStore.progress[lineID] = PracticeProgress(attempts: [openResponse, shadowing])
        coach.selectedAttemptRelativePathForAnalysis = openResponse.relativePath

        XCTAssertNil(coach.analysisRecordingURL)
        XCTAssertEqual(coach.selectedAttemptActivity, .freeExpression)
    }

    func testLearningPathAdvancesThroughRealUseAndCorrection() {
        var progress = PracticeProgress()
        XCTAssertEqual(LearningPathEngine.nextStage(for: progress), .input)

        var path = LearningPathProgress()
        path.mark(.input)
        progress.learningPath = path
        XCTAssertEqual(LearningPathEngine.nextStage(for: progress), .noticing)

        path.selectedTarget = LearningTarget(
            text: "rule out",
            kind: .phrasalVerb,
            frame: "rule out [possible cause]",
            note: "Useful for eliminating a possible cause."
        )
        path.selectedChunk = "rule out"
        path.mark(.noticing)
        progress.learningPath = path
        XCTAssertEqual(LearningPathEngine.nextStage(for: progress), .shadowing)

        progress.attempts = [
            RecordingAttempt(
                id: UUID(),
                date: Date(),
                duration: 5,
                relativePath: "Recordings/shadow.m4a",
                activity: .shadowing
            )
        ]
        XCTAssertEqual(LearningPathEngine.nextStage(for: progress), .retrieval)

        let event = ReviewEvent(
            reviewedAt: Date(),
            rating: .good,
            elapsedDays: 0,
            scheduledInterval: 600
        )
        progress.review = SentenceReviewProgress(history: [event])
        XCTAssertEqual(LearningPathEngine.nextStage(for: progress), .transformation)

        progress.attempts.insert(
            RecordingAttempt(
                id: UUID(),
                date: Date(),
                duration: 8,
                relativePath: "Recordings/transform.m4a",
                activity: .transformation
            ),
            at: 0
        )
        XCTAssertEqual(LearningPathEngine.nextStage(for: progress), .freeExpression)

        progress.attempts.insert(
            RecordingAttempt(
                id: UUID(),
                date: Date(),
                duration: 35,
                relativePath: "Recordings/free.m4a",
                activity: .freeExpression
            ),
            at: 0
        )
        XCTAssertEqual(LearningPathEngine.nextStage(for: progress), .realCommunication)

        path = progress.learningPath ?? LearningPathProgress()
        path.mark(.realCommunication)
        progress.learningPath = path
        XCTAssertEqual(LearningPathEngine.nextStage(for: progress), .feedbackCorrection)

        path.mark(.feedbackCorrection)
        progress.learningPath = path
        XCTAssertNil(LearningPathEngine.nextStage(for: progress))
        XCTAssertEqual(LearningPathEngine.completedCount(for: progress), 9)
    }

    func testLearningPathSkipsTransferStagesWithoutReusableTarget() {
        var path = LearningPathProgress()
        path.mark(.input)
        path.mark(.noticing)
        var progress = PracticeProgress(
            attempts: [
                RecordingAttempt(
                    id: UUID(),
                    date: Date(),
                    duration: 5,
                    relativePath: "Recordings/shadow.m4a",
                    activity: .shadowing
                )
            ],
            review: SentenceReviewProgress(history: [
                ReviewEvent(
                    reviewedAt: Date(),
                    rating: .good,
                    elapsedDays: 0,
                    scheduledInterval: 600
                )
            ]),
            learningPath: path
        )

        XCTAssertFalse(LearningPathEngine.isApplicable(.transformation, progress: progress))
        XCTAssertFalse(LearningPathEngine.isApplicable(.freeExpression, progress: progress))
        XCTAssertFalse(LearningPathEngine.isApplicable(.realCommunication, progress: progress))
        XCTAssertEqual(LearningPathEngine.nextStage(for: progress), .feedbackCorrection)
        XCTAssertEqual(LearningPathEngine.completedCount(for: progress), 8)

        path.selectedTarget = LearningTarget(
            text: "rule out",
            kind: .phrasalVerb,
            frame: "rule out [possible cause]",
            note: "Useful for eliminating a possible cause."
        )
        progress.learningPath = path
        XCTAssertTrue(LearningPathEngine.isApplicable(.transformation, progress: progress))
        XCTAssertEqual(LearningPathEngine.nextStage(for: progress), .transformation)
    }

    func testLearningTargetExtractorFindsReusableExpression() {
        let targets = LearningTargetExtractor.extract(
            from: "The robot was on the way to the target when the position check failed."
        )

        XCTAssertTrue(targets.contains(where: { $0.text.lowercased() == "on the way to" }))
        XCTAssertEqual(targets.first?.kind, .fixedExpression)
        XCTAssertLessThanOrEqual(targets.count, 3)
        XCTAssertEqual(Set(targets.map(\.id)).count, targets.count)
    }

    func testLearningTargetExtractorDoesNotInventValueForPlainFact() {
        XCTAssertTrue(LearningTargetExtractor.extract(from: "I am Linhao Bai.").isEmpty)
        XCTAssertTrue(LearningTargetExtractor.extract(from: "The robot is LM174.").isEmpty)
    }

    func testLearningTargetExtractorReturnsGeneralizedSentenceFrame() {
        let targets = LearningTargetExtractor.extract(
            from: "The more carefully I checked the logs, the more clearly the pattern appeared."
        )
        let contrast = targets.first(where: { $0.kind == .sentenceFrame })

        XCTAssertEqual(contrast?.frame, "the more [condition], the more [result]")
        XCTAssertTrue(contrast?.note.contains("together") == true)
    }

    func testLearningTargetAIParserRejectsWeakOrIdentifierBasedFragments() throws {
        let sentence = "LM174 was there, but I had to rule out a mapping issue."
        let raw = """
        [
          {"text":"LM174 was there","kind":"collocation","frame":null,"note":"Looks specific."},
          {"text":"rule out","kind":"phrasalVerb","frame":"rule out [possible cause]","note":"Useful for eliminating a possible cause."}
        ]
        """

        let targets = try LearningTargetAIParser.parse(raw, sentence: sentence)

        XCTAssertEqual(targets.map(\.text), ["rule out"])
    }

    func testOpenResponsePromptsUseDifferentLearningObjectives() {
        let target = LearningTarget(
            text: "rule out",
            kind: .phrasalVerb,
            frame: "rule out [possible cause]",
            note: "Useful for eliminating a possible cause."
        )
        let transformation = OpenResponseCoachPrompt.make(
            activity: .transformation,
            transcript: "I ruled out a battery problem at work.",
            learningTarget: target,
            originalIdea: "I ruled out a mapping issue.",
            contextBefore: nil,
            contextAfter: nil
        )
        let freeSpeaking = OpenResponseCoachPrompt.make(
            activity: .freeExpression,
            transcript: "Last week I had to rule out several causes before restarting the robot.",
            learningTarget: target,
            originalIdea: "I ruled out a mapping issue.",
            contextBefore: nil,
            contextAfter: nil
        )

        XCTAssertTrue(transformation.contains("## 任务完成度"))
        XCTAssertTrue(transformation.contains("genuinely different situation"))
        XCTAssertTrue(freeSpeaking.contains("## 沟通效果"))
        XCTAssertTrue(freeSpeaking.contains("communication first"))
        XCTAssertTrue(transformation.contains("Never score exact recall"))
        XCTAssertTrue(freeSpeaking.contains("Never score exact recall"))
        XCTAssertNotEqual(transformation, freeSpeaking)
    }

    func testRealUsePromptNeverPretendsToHaveAudioEvidence() {
        let prompt = RealUseCoachPrompt.make(
            outcome: .hesitated,
            actualWords: "I want to rule out one more cause.",
            learningTarget: nil,
            originalSentence: "We should rule out a mapping issue first."
        )

        XCTAssertTrue(prompt.contains("no recording"))
        XCTAssertTrue(prompt.contains("Never discuss pronunciation"))
        XCTAssertTrue(prompt.contains("## 下次一句话"))
    }

    func testCodexRouterUsesFastModelForSelectionAndGeneration() {
        let available: Set<String> = ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]

        let selection = CodexModelRouter.route(
            for: .learningTargetSelection,
            availableModels: available
        )
        let generation = CodexModelRouter.route(
            for: .practiceGeneration,
            availableModels: available
        )

        XCTAssertEqual(selection.model, "gpt-5.6-luna")
        XCTAssertEqual(generation.model, "gpt-5.6-luna")
        XCTAssertEqual(selection.tier, .fast)
        XCTAssertEqual(selection.reasoningEffort, "none")
    }

    func testCodexRouterKeepsNuancedJudgmentOnBalancedModel() {
        let available: Set<String> = ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]

        let exact = CodexModelRouter.route(for: .exactCoaching, availableModels: available)
        let freeSpeaking = CodexModelRouter.route(for: .freeSpeakingFeedback, availableModels: available)

        XCTAssertEqual(exact.model, "gpt-5.6-terra")
        XCTAssertEqual(freeSpeaking.model, "gpt-5.6-terra")
        XCTAssertEqual(exact.tier, .nuanced)
    }

    func testCodexRouterFallsBackWithoutChoosingSparkOverKnownModels() {
        let available: Set<String> = ["gpt-5.3-codex-spark", "gpt-5.4-mini", "gpt-5.4"]

        XCTAssertEqual(
            CodexModelRouter.route(for: .transformationFeedback, availableModels: available).model,
            "gpt-5.4-mini"
        )
        XCTAssertEqual(
            CodexModelRouter.route(for: .exactCoaching, availableModels: available).model,
            "gpt-5.4"
        )
    }

    func testOpenResponseWorkloadsMatchLearningObjective() {
        XCTAssertEqual(CodexWorkload.feedback(for: .transformation), .transformationFeedback)
        XCTAssertEqual(CodexWorkload.feedback(for: .freeExpression), .freeSpeakingFeedback)
        XCTAssertEqual(CodexWorkload.followUp(for: .transformation), .transformationFollowUp)
        XCTAssertEqual(CodexWorkload.followUp(for: .freeExpression), .freeSpeakingFollowUp)
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
