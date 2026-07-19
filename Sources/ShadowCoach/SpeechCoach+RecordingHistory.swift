import AVFoundation
import Foundation

extension SpeechCoach {
    func latestComparableAttempt() -> RecordingAttempt? {
        currentProgress().attempts.first { $0.resolvedActivity.comparesWithReference }
    }

    func attempt(forRelativePath relativePath: String) -> RecordingAttempt? {
        practiceStore.progress.values
            .lazy
            .flatMap(\.attempts)
            .first { $0.relativePath == relativePath }
    }

    func allAttempts() -> [RecordingAttempt] {
        practiceStore.progress.values.flatMap(\.attempts)
    }

    func attempts(on day: Date, calendar: Calendar = .current) -> Int {
        allAttempts().filter { calendar.isDate($0.date, inSameDayAs: day) }.count
    }

    func recentDailyCounts(days: Int = 35, calendar: Calendar = .current) -> [(date: Date, count: Int)] {
        let today = calendar.startOfDay(for: Date())
        let countsByDay = Dictionary(grouping: allAttempts()) { attempt in
            calendar.startOfDay(for: attempt.date)
        }
        .mapValues(\.count)
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (date, countsByDay[date] ?? 0)
        }
    }

    func currentStreak(calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: Date())
        let activeDays = Set(allAttempts().map { calendar.startOfDay(for: $0.date) })
        var streak = 0
        var cursor = today

        while activeDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }


    func playAttempt(_ attempt: RecordingAttempt) {
        let url = appSupportDirectory.appendingPathComponent(attempt.relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            status = "Recording file missing"
            return
        }

        do {
            stopPlayback()
            selectedAttemptRelativePathForAnalysis = attempt.relativePath
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()
            if let cache = attempt.analysisCache {
                let displayedAnalysis = displayAnalysis(cache.localAnalysis)
                recordingAnalysis = displayedAnalysis
                analysis = cachedCoachFeedback(from: cache)
                loadCoachConversation(from: cache)
                status = analysis.isEmpty
                    ? perfectRecallStatus(for: displayedAnalysis, fallback: "Playing saved attempt. Local analysis loaded; analyze to refresh coach feedback.")
                    : "Playing saved attempt. Loaded saved analysis."
            } else if let cache = attempt.openResponseAnalysisCache {
                recordingAnalysis = nil
                analysis = cachedOpenResponseFeedback(from: cache)
                loadOpenResponseConversation(from: cache)
                status = analysis.isEmpty
                    ? "Playing \(attempt.resolvedActivity.label.lowercased()). Transcript loaded."
                    : "Playing \(attempt.resolvedActivity.label.lowercased()). Stage feedback loaded."
            } else {
                recordingAnalysis = nil
                analysis = ""
                resetCoachConversation()
                status = attempt.resolvedActivity.comparesWithReference
                    ? "Playing saved attempt"
                    : "Playing \(attempt.resolvedActivity.label.lowercased()) response"
            }
        } catch {
            status = "Could not play saved recording: \(error.localizedDescription)"
        }
    }

    func selectAttempt(_ attempt: RecordingAttempt) {
        let url = appSupportDirectory.appendingPathComponent(attempt.relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            status = "Recording file missing"
            return
        }

        selectedAttemptRelativePathForAnalysis = attempt.relativePath
        if let cache = attempt.analysisCache {
            let displayedAnalysis = displayAnalysis(cache.localAnalysis)
            recordingAnalysis = displayedAnalysis
            analysis = cachedCoachFeedback(from: cache)
            loadCoachConversation(from: cache)
            status = analysis.isEmpty
                ? perfectRecallStatus(for: displayedAnalysis, fallback: "Selected saved attempt. Local analysis loaded; analyze to refresh coach feedback.")
                : "Selected saved attempt. Loaded saved analysis."
        } else if let cache = attempt.openResponseAnalysisCache {
            recordingAnalysis = nil
            analysis = cachedOpenResponseFeedback(from: cache)
            loadOpenResponseConversation(from: cache)
            status = analysis.isEmpty
                ? "Selected \(attempt.resolvedActivity.label.lowercased()). Transcript loaded."
                : "Selected \(attempt.resolvedActivity.label.lowercased()). Stage feedback loaded."
        } else {
            recordingAnalysis = nil
            analysis = ""
            resetCoachConversation()
            status = attempt.resolvedActivity.comparesWithReference
                ? "Selected saved attempt"
                : "Selected \(attempt.resolvedActivity.label.lowercased()). Exact comparison is off for open responses."
        }
    }

    func deleteAttempt(_ attempt: RecordingAttempt) {
        guard let location = practiceStore.progress.first(where: { _, progress in
            progress.attempts.contains(where: { $0.id == attempt.id })
        }) else {
            status = "This recording is no longer in the saved history."
            return
        }
        let lineID = location.key
        let url = appSupportDirectory.appendingPathComponent(attempt.relativePath)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                status = "Could not delete recording: \(error.localizedDescription)"
                return
            }
        }
        if selectedAttemptRelativePathForAnalysis == attempt.relativePath {
            stopPlayback()
            selectedAttemptRelativePathForAnalysis = nil
            recordingAnalysis = nil
            analysis = ""
            resetCoachConversation()
        }

        var progress = location.value
        progress.attempts.removeAll { $0.id == attempt.id }
        progress.practiceCount = max(0, progress.practiceCount - 1)
        progress.lastPracticedAt = progress.attempts.first?.date
        practiceStore.progress[lineID] = progress
        savePracticeStore()
        status = "Deleted saved attempt"
    }

    func saveRecordingAttempt(activity: PracticeActivity) {
        guard let selectedLineID else { return }
        guard isUsableRecording(at: recordingURL, minimumDuration: 0.25) else {
            status = "Recording too short. Try again."
            return
        }

        let fileName = "\(selectedLineID.uuidString)-\(Int(Date().timeIntervalSince1970)).m4a"
        let destination = recordingsDirectory.appendingPathComponent(fileName)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: recordingURL, to: destination)
            let relativePath = "Recordings/\(fileName)"
            let attempt = RecordingAttempt(
                id: UUID(),
                date: Date(),
                duration: recordingDuration,
                relativePath: relativePath,
                activity: activity
            )
            var progress = practiceStore.progress[selectedLineID] ?? PracticeProgress()
            progress.practiceCount += 1
            progress.lastPracticedAt = Date()
            progress.attempts.insert(attempt, at: 0)
            var learningPath = progress.learningPath ?? LearningPathProgress()
            switch activity {
            case .shadowing:
                learningPath.mark(.shadowing)
            case .transformation:
                learningPath.mark(.transformation)
            case .freeExpression:
                learningPath.mark(.freeExpression)
            case .correction:
                break
            }
            progress.learningPath = learningPath
            if progress.review == nil {
                progress.review = SentenceReviewProgress()
            }
            selectedAttemptRelativePathForAnalysis = relativePath
            if progress.attempts.count > 20 {
                let expiredAttempts = progress.attempts.dropFirst(20)
                for expiredAttempt in expiredAttempts {
                    try? FileManager.default.removeItem(at: appSupportDirectory.appendingPathComponent(expiredAttempt.relativePath))
                }
                progress.attempts = Array(progress.attempts.prefix(20))
            }
            practiceStore.progress[selectedLineID] = progress
            savePracticeStore()
        } catch {
            status = "Could not archive recording: \(error.localizedDescription)"
        }
    }

    func isUsableRecording(at url: URL, minimumDuration: Double = 0.05) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 1_024 else {
            return false
        }

        guard let duration = try? AVAudioPlayer(contentsOf: url).duration else { return false }
        return duration.isFinite && duration >= minimumDuration
    }

    func sourceReferenceDuration(for line: PracticeLine?) -> Double? {
        guard let line,
              sourceAudioURL(for: line) != nil,
              let start = line.sourceStartTime,
              let end = line.sourceEndTime,
              end > start else {
            return nil
        }

        let paddedStart = max(0, start - sourceAudioLeadPadding)
        let paddedEnd = max(end + sourceAudioTailPadding, paddedStart + 1.0)
        let duration = paddedEnd - paddedStart
        return duration.isFinite ? duration : nil
    }

    func cachedAnalysis(for audioURL: URL) -> RecordingAnalysisCache? {
        guard let location = attemptLocation(for: audioURL) else { return nil }
        guard let attempts = practiceStore.progress[location.lineID]?.attempts,
              attempts.indices.contains(location.attemptIndex) else {
            return nil
        }
        return attempts[location.attemptIndex].analysisCache
    }

    func cachedCoachFeedback(from cache: RecordingAnalysisCache) -> String {
        guard useAICoach else { return "" }
        if let cachedCoachSetting = cache.usedAICoach, cachedCoachSetting != useAICoach {
            return ""
        }
        if let cachedProvider = cache.feedbackProvider, cachedProvider != feedbackProvider {
            return ""
        }
        if let cachedAzureSetting = cache.usedAzureAssessment, cachedAzureSetting != useAzureAssessment {
            return ""
        }
        if let cachedProsodySetting = cache.usedProsodyAnalysis, cachedProsodySetting != useProsodyAnalysis {
            return ""
        }
        if feedbackProvider == .codex,
           let cachedModel = cache.coachModel,
           cachedModel != CodexFeedbackClient.route(for: .exactCoaching).model {
            return ""
        }
        return CoachFeedbackSanitizer.clean(cache.geminiFeedback ?? "")
    }

    func cachedOpenResponseFeedback(from cache: OpenResponseAnalysisCache) -> String {
        guard useAICoach, cache.usedAICoach else { return "" }
        if let cachedProvider = cache.feedbackProvider, cachedProvider != feedbackProvider {
            return ""
        }
        if feedbackProvider == .codex,
           let cachedModel = cache.coachModel,
           cachedModel != CodexFeedbackClient.route(
                for: CodexWorkload.feedback(for: cache.activity)
           ).model {
            return ""
        }
        return CoachFeedbackSanitizer.clean(cache.coachFeedback ?? "")
    }

    func resetCoachConversation() {
        coachConversationRequestID = UUID()
        coachConversation = []
        isAskingCodex = false
    }

    func loadOpenResponseConversation(from cache: OpenResponseAnalysisCache) {
        coachConversationRequestID = UUID()
        coachConversation = cache.coachConversation ?? []
        isAskingCodex = false
    }

    func loadCoachConversation(from cache: RecordingAnalysisCache) {
        coachConversationRequestID = UUID()
        coachConversation = cache.coachConversation ?? []
        isAskingCodex = false
    }

    func perfectRecallStatus(for analysis: RecordingAnalysis, fallback: String) -> String {
        analysis.isPerfectWordRecall ? "100% word recall. Coach analysis was not needed." : fallback
    }

    func saveAnalysisCache(_ cache: RecordingAnalysisCache, for audioURL: URL) {
        guard let location = attemptLocation(for: audioURL),
              var progress = practiceStore.progress[location.lineID],
              progress.attempts.indices.contains(location.attemptIndex) else {
            return
        }

        progress.attempts[location.attemptIndex].analysisCache = cache
        let analyzedAttempt = progress.attempts[location.attemptIndex]
        if analyzedAttempt.resolvedActivity == .correction || cache.localAnalysis.isPerfectWordRecall {
            var learningPath = progress.learningPath ?? LearningPathProgress()
            learningPath.mark(.feedbackCorrection)
            progress.learningPath = learningPath
        }
        practiceStore.progress[location.lineID] = progress
        savePracticeStore()
    }

    func saveOpenResponseAnalysisCache(_ cache: OpenResponseAnalysisCache, for audioURL: URL) {
        guard let location = attemptLocation(for: audioURL),
              var progress = practiceStore.progress[location.lineID],
              progress.attempts.indices.contains(location.attemptIndex) else {
            return
        }
        progress.attempts[location.attemptIndex].openResponseAnalysisCache = cache
        practiceStore.progress[location.lineID] = progress
        savePracticeStore()
    }

    func saveOpenResponseConversation(
        _ messages: [CoachConversationMessage],
        for audioURL: URL
    ) {
        guard let location = attemptLocation(for: audioURL),
              var progress = practiceStore.progress[location.lineID],
              progress.attempts.indices.contains(location.attemptIndex),
              var cache = progress.attempts[location.attemptIndex].openResponseAnalysisCache else {
            return
        }
        cache.coachConversation = messages
        progress.attempts[location.attemptIndex].openResponseAnalysisCache = cache
        practiceStore.progress[location.lineID] = progress
        savePracticeStore()
    }

    func saveCoachConversation(_ messages: [CoachConversationMessage], for audioURL: URL) {
        guard let location = attemptLocation(for: audioURL),
              var progress = practiceStore.progress[location.lineID],
              progress.attempts.indices.contains(location.attemptIndex),
              var cache = progress.attempts[location.attemptIndex].analysisCache else {
            return
        }

        cache.coachConversation = messages
        progress.attempts[location.attemptIndex].analysisCache = cache
        practiceStore.progress[location.lineID] = progress
        savePracticeStore()
    }

    func attemptLocation(for audioURL: URL) -> (lineID: UUID, attemptIndex: Int)? {
        if audioURL.lastPathComponent == recordingURL.lastPathComponent,
           let selectedLineID,
           let firstAttempt = practiceStore.progress[selectedLineID]?.attempts.first,
           isUsableRecording(at: appSupportDirectory.appendingPathComponent(firstAttempt.relativePath)) {
            return (selectedLineID, 0)
        }

        for (lineID, progress) in practiceStore.progress {
            if let index = progress.attempts.firstIndex(where: { attempt in
                appSupportDirectory.appendingPathComponent(attempt.relativePath).standardizedFileURL.path == audioURL.standardizedFileURL.path
            }) {
                return (lineID, index)
            }
        }

        if let lineID = lineIDFromRecordingURL(audioURL),
           let progress = practiceStore.progress[lineID],
           let index = progress.attempts.firstIndex(where: { attempt in
               appSupportDirectory.appendingPathComponent(attempt.relativePath).lastPathComponent == audioURL.lastPathComponent
           }) {
            return (lineID, index)
        }

        return nil
    }


}
