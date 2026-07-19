import Foundation

extension SpeechCoach {
    func askCodex(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAskingCodex else { return }
        if let audioURL = selectedAttemptRecordingURL,
           let cache = selectedOpenResponseAnalysis {
            askCodexAboutOpenResponse(trimmed, cache: cache, audioURL: audioURL)
            return
        }
        guard let audioURL = analysisRecordingURL,
              let currentAnalysis = recordingAnalysis else {
            status = "Analyze a recording before asking Codex."
            return
        }

        let userMessage = CoachConversationMessage(role: .user, text: trimmed)
        let conversation = Array((coachConversation + [userMessage]).suffix(12))
        let requestID = UUID()
        coachConversationRequestID = requestID
        coachConversation = conversation
        isAskingCodex = true
        saveCoachConversation(conversation, for: audioURL)
        status = "Asking Codex about this result..."

        let prompt = codexFollowUpPrompt(
            question: trimmed,
            localAnalysis: currentAnalysis,
            existingFeedback: analysis,
            conversation: conversation
        )

        Task.detached(priority: .userInitiated) {
            do {
                let rawAnswer = try await CodexFeedbackClient.run(
                    prompt: prompt,
                    workload: .exactFollowUp
                )
                let answer = CoachFeedbackSanitizer.clean(rawAnswer)
                let completedConversation = Array(
                    (conversation + [CoachConversationMessage(role: .assistant, text: answer)]).suffix(12)
                )
                await MainActor.run {
                    self.saveCoachConversation(completedConversation, for: audioURL)
                    guard self.coachConversationRequestID == requestID else { return }
                    self.coachConversation = completedConversation
                    self.isAskingCodex = false
                    self.status = "Codex follow-up ready"
                }
            } catch {
                await MainActor.run {
                    guard self.coachConversationRequestID == requestID else { return }
                    self.isAskingCodex = false
                    self.status = "Codex follow-up failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func askCodexAboutOpenResponse(
        _ question: String,
        cache: OpenResponseAnalysisCache,
        audioURL: URL
    ) {
        let userMessage = CoachConversationMessage(role: .user, text: question)
        let conversation = Array((coachConversation + [userMessage]).suffix(12))
        let requestID = UUID()
        coachConversationRequestID = requestID
        coachConversation = conversation
        isAskingCodex = true
        saveOpenResponseConversation(conversation, for: audioURL)
        status = "Asking Codex about this \(cache.activity.label.lowercased()) response..."
        let prompt = OpenResponseFollowUpPrompt.make(
            question: question,
            cache: cache,
            existingFeedback: analysis,
            conversation: conversation
        )

        Task.detached(priority: .userInitiated) {
            do {
                let raw = try await CodexFeedbackClient.run(
                    prompt: prompt,
                    workload: CodexWorkload.followUp(for: cache.activity)
                )
                let answer = CoachFeedbackSanitizer.clean(raw)
                let completed = Array(
                    (conversation + [CoachConversationMessage(role: .assistant, text: answer)]).suffix(12)
                )
                await MainActor.run {
                    self.saveOpenResponseConversation(completed, for: audioURL)
                    guard self.coachConversationRequestID == requestID else { return }
                    self.coachConversation = completed
                    self.isAskingCodex = false
                    self.status = "Codex follow-up ready"
                }
            } catch {
                await MainActor.run {
                    guard self.coachConversationRequestID == requestID else { return }
                    self.isAskingCodex = false
                    self.status = "Codex follow-up failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func analyzeSelectedAttempt(forceRefresh: Bool = false) {
        if let activity = selectedAttemptActivity, !activity.comparesWithReference {
            analyzeOpenResponse(forceRefresh: forceRefresh)
        } else {
            analyzeRecording(forceRefresh: forceRefresh)
        }
    }

    private func analyzeOpenResponse(forceRefresh: Bool = false) {
        guard !isAnalyzing else { return }
        guard let audioURL = selectedAttemptRecordingURL,
              let location = attemptLocation(for: audioURL),
              let progress = practiceStore.progress[location.lineID],
              progress.attempts.indices.contains(location.attemptIndex) else {
            status = "Select a saved New Situation or Free Speaking recording first."
            return
        }
        let attempt = progress.attempts[location.attemptIndex]
        let activity = attempt.resolvedActivity
        guard !activity.comparesWithReference else {
            analyzeRecording(forceRefresh: forceRefresh)
            return
        }
        if !forceRefresh, let cache = attempt.openResponseAnalysisCache {
            recordingAnalysis = nil
            analysis = cachedOpenResponseFeedback(from: cache)
            loadOpenResponseConversation(from: cache)
            status = analysis.isEmpty
                ? "Loaded saved transcript. Enable AI Coach or analyze again for stage feedback."
                : "Loaded saved \(activity.label.lowercased()) feedback"
            return
        }

        let learningTarget = savedLearningTarget(from: progress)
        let analysisLine = currentAnalysisLine(for: audioURL)
        let originalIdea = analysisLine?.text ?? sentence
        let context = neighboringContext(for: analysisLine)
        let providerSnapshot = feedbackProvider
        let apiKeySnapshot = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let useAICoachSnapshot = useAICoach
        let selectedPathSnapshot = attempt.relativePath
        let providerIsReady = providerSnapshot == .codex || !apiKeySnapshot.isEmpty
        let codexWorkload = CodexWorkload.feedback(for: activity)
        let codexModel = providerSnapshot == .codex
            ? CodexFeedbackClient.route(for: codexWorkload).model
            : nil

        isAnalyzing = true
        recordingAnalysis = nil
        analysis = ""
        resetCoachConversation()
        status = activity == .transformation
            ? "Transcribing your new sentence..."
            : "Transcribing your free speaking..."

        Task.detached(priority: .userInitiated) {
            do {
                let detailed = try await FastWhisperTranscriber.transcribeDetailed(
                    audioURL,
                    referenceText: learningTarget?.text ?? ""
                )
                let coreCache = OpenResponseAnalysisCache(
                    createdAt: Date(),
                    activity: activity,
                    transcript: detailed.transcript,
                    learningTarget: learningTarget,
                    coachFeedback: nil,
                    feedbackProvider: providerSnapshot,
                    usedAICoach: useAICoachSnapshot,
                    coachModel: codexModel,
                    transcriptModel: FastWhisperTranscriber.cacheIdentifier,
                    coachConversation: attempt.openResponseAnalysisCache?.coachConversation
                )

                await MainActor.run {
                    self.saveOpenResponseAnalysisCache(coreCache, for: audioURL)
                    if self.selectedAttemptRelativePathForAnalysis == selectedPathSnapshot {
                        self.analysis = ""
                        if useAICoachSnapshot && providerIsReady {
                            self.status = "Transcript ready. Generating \(activity.label.lowercased()) feedback..."
                        } else if useAICoachSnapshot {
                            self.status = "Transcript saved. Add a Gemini key or switch to Local Codex for stage feedback."
                        } else {
                            self.status = "Transcript saved. Enable AI Coach for stage-specific feedback."
                        }
                    }
                }

                guard useAICoachSnapshot, providerIsReady else {
                    await MainActor.run { self.isAnalyzing = false }
                    return
                }

                let prompt = OpenResponseCoachPrompt.make(
                    activity: activity,
                    transcript: detailed.transcript,
                    learningTarget: learningTarget,
                    originalIdea: originalIdea,
                    contextBefore: context.before,
                    contextAfter: context.after
                )
                let feedback: String
                switch providerSnapshot {
                case .codex:
                    feedback = try await CodexFeedbackClient.run(
                        prompt: prompt,
                        workload: codexWorkload,
                        onPartial: { [weak self] partial in
                            Task { @MainActor in
                                guard let self,
                                      self.selectedAttemptRelativePathForAnalysis == selectedPathSnapshot else { return }
                                self.analysis = CoachFeedbackSanitizer.clean(partial)
                            }
                        }
                    )
                case .gemini:
                    feedback = try await self.requestGeminiText(
                        prompt: prompt,
                        apiKey: apiKeySnapshot,
                        maxOutputTokens: self.coachFeedbackDepth.maxOutputTokens
                    )
                }
                let completedCache = OpenResponseAnalysisCache(
                    createdAt: Date(),
                    activity: activity,
                    transcript: detailed.transcript,
                    learningTarget: learningTarget,
                    coachFeedback: CoachFeedbackSanitizer.clean(feedback),
                    feedbackProvider: providerSnapshot,
                    usedAICoach: useAICoachSnapshot,
                    coachModel: codexModel,
                    transcriptModel: FastWhisperTranscriber.cacheIdentifier,
                    coachConversation: attempt.openResponseAnalysisCache?.coachConversation
                )
                await MainActor.run {
                    self.saveOpenResponseAnalysisCache(completedCache, for: audioURL)
                    if self.selectedAttemptRelativePathForAnalysis == selectedPathSnapshot {
                        self.analysis = self.cachedOpenResponseFeedback(from: completedCache)
                        self.status = "\(activity.label) feedback ready"
                    }
                    self.isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    if self.selectedAttemptRelativePathForAnalysis == selectedPathSnapshot {
                        self.analysis = ""
                        self.status = "\(activity.label) analysis failed: \(error.localizedDescription)"
                    }
                    self.isAnalyzing = false
                }
            }
        }
    }

    private func savedLearningTarget(from progress: PracticeProgress) -> LearningTarget? {
        if let selected = progress.learningPath?.selectedTarget { return selected }
        if let legacy = progress.learningPath?.selectedChunk,
           !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LearningTarget(
                text: legacy,
                kind: .collocation,
                note: "Saved by an earlier Shadow Coach version.",
                source: .legacy
            )
        }
        return nil
    }

    func analyzeRecording(forceRefresh: Bool = false) {
        guard !isAnalyzing else { return }
        guard let audioURL = analysisRecordingURL else {
            status = "Record yourself first"
            return
        }
        guard isUsableRecording(at: audioURL) else {
            status = "Recording file is incomplete. Record again, then analyze."
            return
        }
        let expectedTranscriptModel = useProsodyAnalysis
            ? WhisperXTranscriber.alignedCacheIdentifier
            : FastWhisperTranscriber.cacheIdentifier
        if !forceRefresh,
           let cache = cachedAnalysis(for: audioURL),
           cache.transcriptModel == expectedTranscriptModel {
            let displayedAnalysis = displayAnalysis(cache.localAnalysis)
            recordingAnalysis = displayedAnalysis
            analysis = cachedCoachFeedback(from: cache)
            loadCoachConversation(from: cache)
            status = analysis.isEmpty
                ? perfectRecallStatus(for: displayedAnalysis, fallback: "Loaded local analysis. Analyze again for current coach settings.")
                : "Loaded saved analysis"
            return
        }

        isAnalyzing = true
        analysis = ""
        recordingAnalysis = nil
        resetCoachConversation()
        status = "Analyzing transcript..."
        let analysisLine = currentAnalysisLine(for: audioURL)
        let analysisLineID = attemptLocation(for: audioURL)?.lineID ?? analysisLine?.id
        let analysisTitle = analysisLine?.title ?? "previous sentence"
        let targetSentence = analysisLine?.text ?? currentTargetSentence(for: audioURL)
        let analysisContext = neighboringContext(for: analysisLine)
        let analysisSource = analysisLine.map { "\($0.source) · \($0.title)" }
        let referenceAudioURL = sourceAudioURL(for: analysisLine)
        let referenceStart = analysisLine?.sourceStartTime
        let referenceEnd = analysisLine?.sourceEndTime
        let apiKeySnapshot = apiKey
        let feedbackProviderSnapshot = feedbackProvider
        let useAzureAssessmentSnapshot = useAzureAssessment
        let useProsodyAnalysisSnapshot = useProsodyAnalysis
        let useAICoachSnapshot = useAICoach
        let codexModel = feedbackProviderSnapshot == .codex
            ? CodexFeedbackClient.route(for: .exactCoaching).model
            : nil
        let analysisRunID = UUID()
        analysisRunIDs[analysisRunKey(for: audioURL)] = analysisRunID
        ImportLogger.write("recordingAnalysis targetSentenceSnapshot=\(targetSentence)")

        Task.detached(priority: .userInitiated) {
            do {
                let transcriptStartedAt = Date()
                let detailed: DetailedTranscript
                let transcriptModelIdentifier: String
                if useProsodyAnalysisSnapshot {
                    ImportLogger.write("recordingAnalysis whisperx aligned start audio=\(audioURL.path)")
                    detailed = try await WhisperXTranscriber.transcribeDetailed(
                        audioURL,
                        referenceText: targetSentence
                    )
                    transcriptModelIdentifier = WhisperXTranscriber.alignedCacheIdentifier
                    ImportLogger.write("recordingAnalysis whisperx aligned done seconds=\(String(format: "%.2f", Date().timeIntervalSince(transcriptStartedAt))) transcriptChars=\(detailed.transcript.count) words=\(detailed.words.count)")
                } else {
                    ImportLogger.write("recordingAnalysis fast transcript start audio=\(audioURL.path)")
                    do {
                        detailed = try await FastWhisperTranscriber.transcribeDetailed(
                            audioURL,
                            referenceText: targetSentence
                        )
                        transcriptModelIdentifier = FastWhisperTranscriber.cacheIdentifier
                    } catch {
                        ImportLogger.write("recordingAnalysis fast transcript failed; falling back to WhisperX: \(error.localizedDescription)")
                        detailed = try await WhisperXTranscriber.transcribeDetailed(
                            audioURL,
                            alignWords: false,
                            referenceText: targetSentence
                        )
                        transcriptModelIdentifier = WhisperXTranscriber.unalignedCacheIdentifier
                    }
                    ImportLogger.write("recordingAnalysis fast transcript done seconds=\(String(format: "%.2f", Date().timeIntervalSince(transcriptStartedAt))) transcriptChars=\(detailed.transcript.count)")
                }
                let targetWords = WordDiffEngine.tokenize(targetSentence)
                ImportLogger.write("recordingAnalysis targetWords=\(targetWords.map { $0.normalized }.joined(separator: "|"))")
                guard !targetWords.isEmpty else {
                    throw NSError(domain: "RecordingAnalysis", code: -10, userInfo: [NSLocalizedDescriptionKey: "Target sentence is empty. Select a sentence from the library, then analyze again."])
                }
                let azure: AzurePronunciationAnalysis?
                if useAzureAssessmentSnapshot {
                    await MainActor.run {
                        self.updateAnalysisStatus("Checking pronunciation with Azure...", for: audioURL, lineID: analysisLineID)
                    }
                    do {
                        azure = try await AzurePronunciationClient.assess(
                            audioURL: audioURL,
                            referenceText: targetSentence,
                            shadowCoachAppSupportDirectory: self.appSupportDirectory
                        )
                        ImportLogger.write("recordingAnalysis azure done enabled=\(azure?.enabled == true) words=\(azure?.words.count ?? 0)")
                    } catch {
                        ImportLogger.write("recordingAnalysis azure failed \(error.localizedDescription)")
                        azure = AzurePronunciationAnalysis(
                            enabled: true,
                            error: error.localizedDescription,
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
                } else {
                    ImportLogger.write("recordingAnalysis azure skipped")
                    azure = nil
                }
                var userWords = detailed.words
                var local = WordDiffEngine.analyze(targetWords: targetWords, userWords: userWords)
                if local.accuracy == 0, !detailed.transcript.isEmpty {
                    let transcriptWords = WordDiffEngine.tokenize(detailed.transcript)
                    let transcriptLocal = WordDiffEngine.analyze(targetWords: targetWords, userWords: transcriptWords)
                    if transcriptLocal.accuracy > local.accuracy {
                        ImportLogger.write("recordingAnalysis using transcript token fallback oldWords=\(userWords.map { $0.normalized }.joined(separator: "|")) transcriptWords=\(transcriptWords.map { $0.normalized }.joined(separator: "|"))")
                        userWords = transcriptWords
                        local = transcriptLocal
                    }
                }
                ImportLogger.write("recordingAnalysis diff accuracy=\(local.accuracy) missing=\(local.missingWords.count) extra=\(local.extraWords.count)")
                let prosody: ProsodyAnalysis?
                if useProsodyAnalysisSnapshot {
                    await MainActor.run {
                        self.updateAnalysisStatus("Analyzing rhythm and pitch...", for: audioURL, lineID: analysisLineID)
                    }
                    do {
                        prosody = try ProsodyAnalyzer.analyze(
                            userAudioURL: audioURL,
                            referenceAudioURL: referenceAudioURL,
                            referenceStart: referenceStart,
                            referenceEnd: referenceEnd,
                            userWords: userWords,
                            targetWordCount: targetWords.count
                        )
                        ImportLogger.write("recordingAnalysis prosody done")
                    } catch {
                        ImportLogger.write("recordingAnalysis prosody failed \(error.localizedDescription)")
                        prosody = nil
                    }
                } else {
                    ImportLogger.write("recordingAnalysis prosody skipped")
                    prosody = nil
                }
                let pronunciationIssues = PronunciationRuleEngine.analyze(
                    referenceText: targetSentence,
                    azure: azure,
                    prosody: prosody
                )
                let recordingAnalysis = RecordingAnalysis(
                    referenceText: targetSentence,
                    sourceTitle: analysisSource,
                    referenceHasSourceAudio: referenceAudioURL != nil,
                    referenceQuality: analysisLine?.quality,
                    contextBefore: analysisContext.before,
                    contextAfter: analysisContext.after,
                    transcript: detailed.transcript,
                    accuracy: local.accuracy,
                    items: local.items,
                    missingWords: local.missingWords,
                    extraWords: local.extraWords,
                    substitutions: local.substitutions,
                    issueHints: RecordingIssueBuilder.hints(
                        targetSentence: targetSentence,
                        transcript: detailed.transcript,
                        missingWords: local.missingWords,
                        extraWords: local.extraWords,
                        azure: azure,
                        pronunciationIssues: pronunciationIssues,
                        prosody: prosody
                    ),
                    whisperXRawJSON: detailed.rawJSON,
                    azure: azure,
                    pronunciationIssues: pronunciationIssues,
                    prosody: prosody
                )
                let providerIsReady = feedbackProviderSnapshot == .codex || !apiKeySnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let shouldSkipCoach = recordingAnalysis.isPerfectWordRecall
                let shouldAskCoach = useAICoachSnapshot && providerIsReady && !shouldSkipCoach
                ImportLogger.write("recordingAnalysis feedback provider=\(feedbackProviderSnapshot.rawValue) enabled=\(shouldAskCoach)")

                let coreCache = RecordingAnalysisCache(
                    createdAt: Date(),
                    localAnalysis: recordingAnalysis,
                    geminiFeedback: nil,
                    feedbackProvider: feedbackProviderSnapshot,
                    usedAzureAssessment: useAzureAssessmentSnapshot,
                    usedProsodyAnalysis: useProsodyAnalysisSnapshot,
                    usedAICoach: useAICoachSnapshot,
                    coachModel: codexModel,
                    transcriptModel: transcriptModelIdentifier
                )
                let shouldContinueWithCoach = await MainActor.run { () -> Bool in
                    guard self.isCurrentAnalysisRun(analysisRunID, for: audioURL) else {
                        self.isAnalyzing = false
                        return false
                    }
                    self.saveAnalysisCache(coreCache, for: audioURL)
                    if self.shouldPresentAnalysis(for: audioURL, lineID: analysisLineID) {
                        self.recordingAnalysis = self.displayAnalysis(recordingAnalysis)
                        self.analysis = ""
                        if shouldSkipCoach {
                            self.status = "100% word recall. Coach analysis skipped."
                        } else if shouldAskCoach {
                            self.status = "Content comparison ready. Meaning and memory analysis is finishing in the background..."
                        } else if useAICoachSnapshot && !providerIsReady {
                            self.status = "Content comparison ready. Add a Gemini key to run meaning and memory analysis."
                        } else {
                            self.status = "Content comparison ready"
                        }
                    } else if !self.isRecording && !self.status.lowercased().contains("playing") {
                        self.status = "Background content analysis saved for \(analysisTitle)"
                    }
                    self.isAnalyzing = false
                    if !shouldAskCoach {
                        self.finishAnalysisRun(analysisRunID, for: audioURL)
                    }
                    return shouldAskCoach
                }
                guard shouldContinueWithCoach else { return }

                let coachFeedback: String?
                var coachError: Error?
                let coachStartedAt = Date()
                switch feedbackProviderSnapshot {
                case .codex:
                    do {
                        coachFeedback = try await self.requestCodexFeedback(
                            localAnalysis: recordingAnalysis,
                            onPartial: { [weak self] partial in
                                Task { @MainActor in
                                    guard let self,
                                          self.isCurrentAnalysisRun(analysisRunID, for: audioURL),
                                          self.shouldPresentAnalysis(for: audioURL, lineID: analysisLineID) else {
                                        return
                                    }
                                    self.analysis = partial
                                    self.status = "Meaning and memory analysis..."
                                }
                            }
                        )
                    } catch {
                        coachFeedback = nil
                        coachError = error
                        ImportLogger.write("recordingAnalysis codex failed \(error.localizedDescription)")
                    }
                case .gemini:
                    do {
                        coachFeedback = try await self.requestGeminiFeedback(
                            localAnalysis: recordingAnalysis,
                            audioURL: audioURL,
                            apiKey: apiKeySnapshot
                        )
                    } catch {
                        coachFeedback = nil
                        coachError = error
                        ImportLogger.write("recordingAnalysis gemini failed \(error.localizedDescription)")
                    }
                }
                ImportLogger.write("recordingAnalysis coach done provider=\(feedbackProviderSnapshot.rawValue) seconds=\(String(format: "%.2f", Date().timeIntervalSince(coachStartedAt))) success=\(coachFeedback != nil)")
                let coachErrorMessage = coachError.map { String($0.localizedDescription.prefix(180)) }

                await MainActor.run {
                    guard self.isCurrentAnalysisRun(analysisRunID, for: audioURL) else { return }
                    let currentConversation = self.cachedAnalysis(for: audioURL)?.coachConversation
                    let completedCache = RecordingAnalysisCache(
                        createdAt: Date(),
                        localAnalysis: recordingAnalysis,
                        geminiFeedback: coachFeedback,
                        feedbackProvider: feedbackProviderSnapshot,
                        usedAzureAssessment: useAzureAssessmentSnapshot,
                        usedProsodyAnalysis: useProsodyAnalysisSnapshot,
                        usedAICoach: useAICoachSnapshot,
                        coachModel: codexModel,
                        transcriptModel: transcriptModelIdentifier,
                        coachConversation: currentConversation
                    )
                    self.saveAnalysisCache(completedCache, for: audioURL)
                    if self.shouldPresentAnalysis(for: audioURL, lineID: analysisLineID) {
                        self.recordingAnalysis = self.displayAnalysis(recordingAnalysis)
                        self.analysis = self.cachedCoachFeedback(from: completedCache)
                        if let coachErrorMessage {
                            self.status = "Content is saved. AI coach failed: \(coachErrorMessage)"
                        } else {
                            self.status = "Recording analysis ready"
                        }
                    }
                    self.finishAnalysisRun(analysisRunID, for: audioURL)
                }
            } catch {
                ImportLogger.write("recordingAnalysis failed \(error.localizedDescription)")
                await MainActor.run {
                    guard self.isCurrentAnalysisRun(analysisRunID, for: audioURL) else { return }
                    if self.shouldPresentAnalysis(for: audioURL, lineID: analysisLineID) {
                        self.analysis = ""
                        self.recordingAnalysis = nil
                        self.status = self.actionableRecordingAnalysisStatus(for: error)
                    } else if !self.isRecording && !self.status.lowercased().contains("playing") {
                        self.status = "Background analysis failed for \(analysisTitle)"
                    }
                    self.isAnalyzing = false
                    self.finishAnalysisRun(analysisRunID, for: audioURL)
                }
            }
        }
    }

    func displayAnalysis(_ analysis: RecordingAnalysis) -> RecordingAnalysis {
        let refreshedDiff = WordDiffEngine.analyze(
            targetWords: WordDiffEngine.tokenize(analysis.referenceText),
            userWords: WordDiffEngine.tokenize(analysis.transcript)
        )
        let visibleAzure = useAzureAssessment ? analysis.azure : nil
        let visibleProsody = useProsodyAnalysis ? analysis.prosody : nil
        let visiblePronunciationIssues = PronunciationRuleEngine.analyze(
            referenceText: analysis.referenceText,
            azure: visibleAzure,
            prosody: visibleProsody
        )
        let localHints = RecordingIssueBuilder.hints(
            targetSentence: analysis.referenceText,
            transcript: analysis.transcript,
            missingWords: refreshedDiff.missingWords,
            extraWords: refreshedDiff.extraWords,
            azure: visibleAzure,
            pronunciationIssues: visiblePronunciationIssues,
            prosody: visibleProsody
        )
        return RecordingAnalysis(
            referenceText: analysis.referenceText,
            sourceTitle: analysis.sourceTitle,
            referenceHasSourceAudio: analysis.referenceHasSourceAudio,
            referenceQuality: analysis.referenceQuality,
            contextBefore: analysis.contextBefore,
            contextAfter: analysis.contextAfter,
            transcript: analysis.transcript,
            accuracy: refreshedDiff.accuracy,
            items: refreshedDiff.items,
            missingWords: refreshedDiff.missingWords,
            extraWords: refreshedDiff.extraWords,
            substitutions: refreshedDiff.substitutions,
            issueHints: localHints,
            whisperXRawJSON: analysis.whisperXRawJSON,
            azure: visibleAzure,
            pronunciationIssues: visiblePronunciationIssues.isEmpty ? nil : visiblePronunciationIssues,
            prosody: visibleProsody
        )
    }

    func sourceAudioURL(for line: PracticeLine?) -> URL? {
        guard let relativePath = line?.sourceMediaRelativePath else { return nil }
        let url = appSupportDirectory.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func selectedLineSourceAudioURL() -> URL? {
        sourceAudioURL(for: selectedLine)
    }

    private func currentAnalysisLine(for audioURL: URL) -> PracticeLine? {
        if let lineID = lineIDFromRecordingURL(audioURL) {
            let allLines = importedLines + generatedLines + PracticeLine.library
            if let line = allLines.first(where: { $0.id == lineID }) {
                return line
            }
            if let line = loadLineFromLibrary(id: lineID) {
                return line
            }
        }
        if let selectedLineID {
            let allLines = importedLines + generatedLines + PracticeLine.library
            if let line = allLines.first(where: { $0.id == selectedLineID }) {
                return line
            }
        }
        return selectedLine
    }

    private func currentTargetSentence(for audioURL: URL) -> String {
        if let line = currentAnalysisLine(for: audioURL),
           !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return line.text
        }
        return sentence
    }

    func neighboringContext(for line: PracticeLine?) -> (before: String?, after: String?) {
        guard let line else { return (nil, nil) }
        let allLines = importedLines + generatedLines + PracticeLine.library
        let sameSource = allLines.filter { $0.source == line.source }
        guard let index = sameSource.firstIndex(where: { $0.id == line.id }) else {
            return (nil, nil)
        }
        let before = index > sameSource.startIndex ? sameSource[sameSource.index(before: index)].text : nil
        let nextIndex = sameSource.index(after: index)
        let after = nextIndex < sameSource.endIndex ? sameSource[nextIndex].text : nil
        return (before, after)
    }

    private func shouldPresentAnalysis(for audioURL: URL, lineID: UUID?) -> Bool {
        guard let lineID,
              selectedLineID == lineID,
              let currentURL = analysisRecordingURL else {
            return false
        }
        return currentURL.standardizedFileURL.path == audioURL.standardizedFileURL.path
    }

    private func updateAnalysisStatus(_ message: String, for audioURL: URL, lineID: UUID?) {
        guard shouldPresentAnalysis(for: audioURL, lineID: lineID) else { return }
        status = message
    }

    private func analysisRunKey(for audioURL: URL) -> String {
        audioURL.standardizedFileURL.path
    }

    private func isCurrentAnalysisRun(_ id: UUID, for audioURL: URL) -> Bool {
        analysisRunIDs[analysisRunKey(for: audioURL)] == id
    }

    private func finishAnalysisRun(_ id: UUID, for audioURL: URL) {
        let key = analysisRunKey(for: audioURL)
        guard analysisRunIDs[key] == id else { return }
        analysisRunIDs.removeValue(forKey: key)
    }

    func lineIDFromRecordingURL(_ url: URL) -> UUID? {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.count >= 36 else { return nil }
        return UUID(uuidString: String(name.prefix(36)))
    }

    private func loadLineFromLibrary(id: UUID) -> PracticeLine? {
        guard let data = try? Data(contentsOf: libraryURL) else {
            return nil
        }
        if let persisted = try? JSONDecoder().decode(PersistedLibrary.self, from: data),
           let line = (persisted.importedLines + persisted.generatedLines).first(where: { $0.id == id }) {
            return line
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for key in ["importedLines", "generatedLines"] {
            guard let rows = root[key] as? [[String: Any]] else { continue }
            for row in rows where row["id"] as? String == id.uuidString {
                guard let title = row["title"] as? String,
                      let source = row["source"] as? String,
                      let text = row["text"] as? String else { continue }
                return PracticeLine(
                    id: id,
                    title: title,
                    source: source,
                    text: text,
                    sourceMediaRelativePath: row["sourceMediaRelativePath"] as? String,
                    sourceStartTime: row["sourceStartTime"] as? Double,
                    sourceEndTime: row["sourceEndTime"] as? Double
                )
            }
        }
        return nil
    }

    private func actionableRecordingAnalysisStatus(for error: Error) -> String {
        let message = error.localizedDescription
        let lowercased = message.lowercased()
        if lowercased.contains("whisperx") || lowercased.contains("did not create") {
            return "WhisperX did not return a transcript. Check the local WhisperX install, then retry."
        }
        if lowercased.contains("parselmouth") || lowercased.contains("no module named") {
            return "Prosody dependency missing. Install praat-parselmouth in the analysis Python environment."
        }
        return "Recording analysis failed: \(message)"
    }


    private func requestGeminiFeedback(
        localAnalysis: RecordingAnalysis,
        audioURL: URL,
        apiKey: String
    ) async throws -> String {
        let audioData = try Data(contentsOf: audioURL)
        let prompt = coachFeedbackPrompt(localAnalysis: localAnalysis, includeAudioInstruction: true)
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": "audio/aac",
                                "data": audioData.base64EncodedString()
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": coachFeedbackDepth.maxOutputTokens
            ]
        ]

        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(geminiModel):generateContent")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "Gemini", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: detail])
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let text = decoded.candidates.first?.content.parts.compactMap(\.text).joined(separator: "\n")
        guard let text, !text.isEmpty else {
            throw NSError(domain: "Gemini", code: -1, userInfo: [NSLocalizedDescriptionKey: "No text feedback returned"])
        }
        return CoachFeedbackSanitizer.clean(text)
    }

    func requestGeminiText(
        prompt: String,
        apiKey: String,
        maxOutputTokens: Int
    ) async throws -> String {
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": prompt]]
                ]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": maxOutputTokens
            ]
        ]

        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(geminiModel):generateContent")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "Gemini", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: detail])
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let text = decoded.candidates.first?.content.parts.compactMap(\.text).joined(separator: "\n")
        guard let text, !text.isEmpty else {
            throw NSError(domain: "Gemini", code: -1, userInfo: [NSLocalizedDescriptionKey: "No text response returned"])
        }
        return text
    }

    private func requestCodexFeedback(
        localAnalysis: RecordingAnalysis,
        onPartial: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let prompt = coachFeedbackPrompt(localAnalysis: localAnalysis, includeAudioInstruction: false)
        let sanitizedPartial = onPartial.map { callback -> @Sendable (String) -> Void in
            { @Sendable partial in
                callback(CoachFeedbackSanitizer.clean(partial))
            }
        }
        let response = try await CodexFeedbackClient.run(
            prompt: prompt,
            workload: .exactCoaching,
            onPartial: sanitizedPartial
        )
        return CoachFeedbackSanitizer.clean(response)
    }

    private func coachFeedbackPrompt(localAnalysis: RecordingAnalysis, includeAudioInstruction: Bool) -> String {
        let spokenReference = WordDiffEngine.comparisonText(localAnalysis.referenceText)
        let spokenTranscript = WordDiffEngine.comparisonText(localAnalysis.transcript)
        let azureSummary: String
        if let azure = localAnalysis.azure, azure.enabled, azure.error == nil {
            let weakWords = azure.words
                .filter { ($0.accuracy ?? 100) < 75 || ($0.errorType ?? "None") != "None" }
                .prefix(8)
                .map { word in
                    "\(word.text)(accuracy:\(Int((word.accuracy ?? 0).rounded())), error:\(word.errorType ?? "None"))"
                }
                .joined(separator: ", ")
            azureSummary = """
            Azure Pronunciation Assessment:
            - PronScore: \(scoreText(localAnalysis.azure?.pronunciation))
            - Accuracy: \(scoreText(localAnalysis.azure?.accuracy))
            - Fluency: \(scoreText(localAnalysis.azure?.fluency))
            - Completeness: \(scoreText(localAnalysis.azure?.completeness))
            - Prosody: \(scoreText(localAnalysis.azure?.prosody))
            - Weak words: \(weakWords.isEmpty ? "none flagged" : weakWords)
            """
        } else {
            azureSummary = ""
        }
        let ruleSummary = (localAnalysis.pronunciationIssues ?? [])
            .prefix(6)
            .map { issue in
                "- \(issue.title): \(issue.evidence) Coach note: \(issue.coachNote)"
            }
            .joined(separator: "\n")
        let substitutionSummary = (localAnalysis.substitutions ?? [])
            .prefix(4)
            .map { "- User said \"\($0.spoken)\" where the reference uses \"\($0.expected)\"." }
            .joined(separator: "\n")
        let sentenceContext = [
            localAnalysis.sourceTitle.map { "- Material: \($0)" },
            localAnalysis.contextBefore.map { "- Previous sentence: \"\($0)\"" },
            localAnalysis.contextAfter.map { "- Next sentence: \"\($0)\"" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        let referenceOrigin = ReferenceOriginPolicy.guidance(
            quality: localAnalysis.referenceQuality,
            hasSourceAudio: localAnalysis.referenceHasSourceAudio
        )
        let outputGuidance = CoachFeedbackPolicy.outputGuidance(
            accuracy: localAnalysis.accuracy,
            depth: coachFeedbackDepth
        )
        return """
        You are an English shadowing coach for a Chinese native speaker.
        Return only polished coach feedback. Do not include greetings, prefaces, roleplay, raw logs, JSON, tool names, or phrases like "好的", "请听我说", "Here is", or "Sure".
        Original sentence (use for meaning only; its punctuation and capitalization are not speech evidence):
        "\(localAnalysis.referenceText)"

        Reference origin:
        \(referenceOrigin)

        Spoken-word comparison (this is the only text allowed for recall comparison):
        - Reference words: "\(spokenReference)"
        - Recognized user words: "\(spokenTranscript)"

        Nearby context (use it only to interpret meaning, reference, and emphasis):
        \(sentenceContext.isEmpty ? "not available" : sentenceContext)

        Local transcript analysis:
        - Accuracy: \(Int(localAnalysis.accuracy.rounded()))/100
        - Reference words not recognized: \(localAnalysis.missingWords.joined(separator: ", "))
        - Additional recognized words: \(localAnalysis.extraWords.joined(separator: ", "))
        - Word substitutions:
        \(substitutionSummary.isEmpty ? "none" : substitutionSummary)

        \(azureSummary.isEmpty ? "" : azureSummary)

        Rule engine evidence:
        \(ruleSummary.isEmpty ? "No specific rule issue found." : ruleSummary)

        \(includeAudioInstruction ? "Listen to the user's recording and use the evidence above." : "Use only the evidence above. You do not have direct access to the user's audio, so do not claim you heard the recording.")
        HARD RULE: speech does not provide reliable commas, periods, other punctuation, or capitalization. Never say the learner missed, added, or changed punctuation/capitalization, even if the raw strings differ. Never infer punctuation from a pause. If the word substitutions, not-recognized words, and additional words are all empty, state that the spoken-word recall is complete and do not invent another textual difference.
        Treat recognition as uncertain evidence. A word listed as not recognized may be an ASR error; use cautious wording unless audio or pronunciation evidence confirms an omission.
        Analyze this as a shadowing attempt, not merely a transcription diff. The learner needs to know what changed, how serious it is, and exactly what to say next.
        Return clear Markdown in Chinese. Keep it practical, specific, and app-friendly. Avoid tables.
        Do not mention Azure, WhisperX, Praat, or Gemini in the visible feedback. Say "系统识别" if you need to refer to evidence.
        Keep three judgments separate:
        1. Spoken-word recall: whether the learner reproduced the reference words. Punctuation and capitalization never count.
        2. English quality: whether the learner's own wording is grammatical and natural.
        3. Meaning fidelity: whether the learner preserved, broadened, narrowed, or changed the speaker's meaning.
        A wording difference is not automatically an English mistake. If the learner's version is natural and preserves the meaning, explicitly call it a recall difference rather than a language error.
        Before writing, silently compare the two complete propositions: actor, polarity, action, object/scope, logical relation, and time/location. State exactly which slots stayed the same and which changed. Never say the conclusion changed when its polarity and outcome were preserved.
        Validate the reference before defending it:
        - If it is natural and clear, do not comment on its quality.
        - If authentic audio contains ordinary spontaneous phrasing, preserve it and briefly label it as spoken style rather than rewriting it into essay English.
        - If a script/TTS/local-subtitle reference is understandable but awkward, ambiguous, or unidiomatic, do not make the learner memorize it. Add a short `## 参考句检查` section immediately after `## 核心判断`, name the construction problem, and give one simpler natural target that preserves the intended meaning.
        - Rewrite a reference only for a real quality problem, not a personal style preference. When context is insufficient, say the intended relationship is unclear instead of inventing one.
        - If a reference vaguely says that one thing "connects A with B" when the context appears to mean "explains both A and B", flag the relationship as unclear instead of teaching the vague wording as a collocation.
        Rank differences by learning impact, not by their order in the sentence:
        1. Critical: polarity or conclusion reversal, especially lost or added no/not/never/without; changed modality, logical relation, subject, action, or time.
        2. Important: grammar or collocation that makes the wording unnatural or changes a relationship between ideas.
        3. Minor: lost precision or detail that does not change the main conclusion.
        4. Acceptable paraphrase: natural English with similar meaning but not exact shadowing recall.
        Do not exaggerate a vocabulary distinction. Words such as change/modification or different/several can both be natural; judge the complete phrase and exact context. Never invent an extra meaning such as "different types" unless the context actually says that.
        Negative constructions can be equivalent: `found no change` and `didn't find any change` are both natural and normally preserve the same negative conclusion. Distinguish a valid construction from an execution error such as `didn't found`, which must be `didn't find`.
        Never bury a polarity reversal under general comments such as "the meaning changed a little". State the reversed conclusion directly.
        The substitution, missing-word, and extra-word lists are noisy alignment hints, not ground truth. Always verify them against the two complete word strings. Ignore any token pair that conflicts with the actual phrase order, and merge neighboring or overlapping edits into one phrase-level correction. Never output a mechanical token correction such as `physical → the` when the real issue is a reordered phrase.
        Explain only differences that change the learner's next attempt. Do not analyze every token, repeat the same point in multiple sections, or claim the reference is universally better. Repair an obvious local grammar error mentally before comparing the larger meaning, then discuss that grammar error only once. Do not create a broad phrase item and a second narrow item that repeat the same correction.
        Do not diagnose why the learner remembered something from a single attempt. Only present a memory cause as a possibility when the text gives strong evidence; otherwise omit it.

        Output budget:
        \(outputGuidance)

        Use this structure:

        ## 核心判断
        最多两句。先具体说用户保留正确了什么，再直接指出最严重的含义或复述问题；第二句说明用户自己的英文是否自然。不要使用“略有变化”掩盖真正的结论反转，也不要把仍然保留的结论误判为反转。

        ## 优先修改
        只列最值得修改的差异，并按严重程度排序。每项必须使用一个 `- ` 项目：`- **[关键/重要/轻微/可接受改写] 用户表达 → 原句表达**：一句具体解释。` 对自然的同义改写明确写“可接受改写”，不要称为错误。如果没有有意义的差异，省略本节。

        ## 记忆骨架
        只给一行，用 2-4 个可直接复述的语块和箭头保留句法与逻辑关系。可以用方括号显示槽位，例如 `checked [recent records] → found no [configuration change] → that matched [the timing]`。必须保留关键介词、否定词和关系从句，不能只堆孤立关键词。若你修正了参考句，记忆骨架必须来自修正版。

        ## 马上重说
        先给最关键的正确语块，再给完整目标句。若参考句检查提供了修正版，这里使用修正版；否则使用原句。总共不超过两行，不要再解释。

        For Balanced or Deep output only, you may add this section when it is genuinely useful:
        ## 深入理解
        用 1-3 条解释必要的语法、搭配、语域，或有充分文本证据支持的记忆模式。Focused 模式禁止生成本节。

        Be practical and do not overclaim. Only discuss pronunciation or rhythm when the supplied evidence supports it. Use short paragraphs or bullets so it remains easy to scan.
        """
    }

    private func codexFollowUpPrompt(
        question: String,
        localAnalysis: RecordingAnalysis,
        existingFeedback: String,
        conversation: [CoachConversationMessage]
    ) -> String {
        let substitutions = (localAnalysis.substitutions ?? [])
            .map { "\($0.spoken) -> \($0.expected)" }
            .joined(separator: ", ")
        let previousConversation = conversation.dropLast().suffix(8).map { message in
            "\(message.role == .user ? "Learner" : "Coach"): \(message.text)"
        }
        .joined(separator: "\n")
        let evidence = localAnalysis.issueHints.prefix(6).joined(separator: "\n")

        return """
        You are continuing a focused English shadowing conversation with a Chinese native speaker.
        Answer only the learner's latest question. Do not regenerate the full report unless explicitly asked. Use concise, natural Chinese, with English examples where useful. Avoid tables, greetings, and generic encouragement.

        Evidence for this exact recording:
        - Reference words: \(WordDiffEngine.comparisonText(localAnalysis.referenceText))
        - Recognized learner words: \(WordDiffEngine.comparisonText(localAnalysis.transcript))
        - Word recall: \(Int(localAnalysis.accuracy.rounded()))/100
        - Reference words not recognized: \(localAnalysis.missingWords.joined(separator: ", "))
        - Additional recognized words: \(localAnalysis.extraWords.joined(separator: ", "))
        - Substitutions: \(substitutions.isEmpty ? "none" : substitutions)
        - Other available evidence:
        \(evidence.isEmpty ? "none" : evidence)

        Existing coach feedback:
        \(CoachFeedbackSanitizer.clean(existingFeedback).isEmpty ? "none" : CoachFeedbackSanitizer.clean(existingFeedback))

        Previous conversation:
        \(previousConversation.isEmpty ? "none" : previousConversation)

        Latest learner question:
        \(question)

        Hard limits:
        - Punctuation and capitalization are not speech evidence and must never be treated as recall errors.
        - Transcript evidence can be wrong. Distinguish a likely ASR error from a confirmed learner error.
        - You cannot hear the audio. Discuss pronunciation, stress, or rhythm only when the supplied evidence supports it.
        - When comparing two expressions, explain meaning, grammar, collocation, register, and why one fits this exact sentence better.
        - Usually answer in 80-220 Chinese characters. Give a short drill only when useful or requested.
        """
    }

    private func scoreText(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "not returned"
    }


}
