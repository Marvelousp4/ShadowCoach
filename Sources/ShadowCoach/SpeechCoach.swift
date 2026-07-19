import AVFoundation
import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class SpeechCoach: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate, NSSpeechSynthesizerDelegate {
    @Published var sentence = "The fastest way to improve your English is to listen carefully and repeat out loud."
    @Published var isSentenceVisible = false
    @Published var status = "Ready"
    @Published var isRecording = false
    @Published var hasRecording = false
    @Published var recordingDuration = 0.0
    @Published private(set) var recordingStartedAt: Date?
    @Published var apiKey = ""
    @Published var isAnalyzing = false
    @Published var analysis = ""
    @Published var recordingAnalysis: RecordingAnalysis?
    @Published var generatedLines: [PracticeLine] = []
    @Published var importedLines: [PracticeLine] = []
    @Published private(set) var libraryRevision = 0
    @Published private(set) var practiceRevision = 0
    @Published var selectedLineID: UUID?
    @Published var selectedLine: PracticeLine?
    @Published var practiceStore = PracticeStore()
    @Published var generationTopic = "robotics project meeting"
    @Published var generationLevel = "B2"
    @Published var isGeneratingLines = false
    @Published var isImporting = false
    @Published var speechRate = UserDefaults.standard.object(forKey: "SpeechRate") == nil ? 175.0 : UserDefaults.standard.double(forKey: "SpeechRate") {
        didSet { UserDefaults.standard.set(speechRate, forKey: "SpeechRate") }
    }
    @Published var selectedVoiceIdentifier = UserDefaults.standard.string(forKey: "SelectedVoiceIdentifier") ?? NSSpeechSynthesizer.defaultVoice.rawValue {
        didSet { UserDefaults.standard.set(selectedVoiceIdentifier, forKey: "SelectedVoiceIdentifier") }
    }
    @Published var listenRepeats: Int = {
        let stored = UserDefaults.standard.integer(forKey: "ListenRepeats")
        return stored > 0 ? min(stored, 5) : 1
    }() {
        didSet { UserDefaults.standard.set(listenRepeats, forKey: "ListenRepeats") }
    }
    @Published var autoRecordAfterListen = UserDefaults.standard.bool(forKey: "AutoRecordAfterListen") {
        didSet { UserDefaults.standard.set(autoRecordAfterListen, forKey: "AutoRecordAfterListen") }
    }
    @Published var autoAnalyzeAfterRecording = UserDefaults.standard.bool(forKey: "AutoAnalyzeAfterRecording") {
        didSet { UserDefaults.standard.set(autoAnalyzeAfterRecording, forKey: "AutoAnalyzeAfterRecording") }
    }
    @Published var requireFullReferenceLength = UserDefaults.standard.object(forKey: "RequireFullReferenceLength") == nil ? true : UserDefaults.standard.bool(forKey: "RequireFullReferenceLength") {
        didSet { UserDefaults.standard.set(requireFullReferenceLength, forKey: "RequireFullReferenceLength") }
    }
    @Published var feedbackProvider = CoachFeedbackProvider(rawValue: UserDefaults.standard.string(forKey: "CoachFeedbackProvider") ?? "") ?? .codex {
        didSet { UserDefaults.standard.set(feedbackProvider.rawValue, forKey: "CoachFeedbackProvider") }
    }
    @Published var coachFeedbackDepth = CoachFeedbackDepth(rawValue: UserDefaults.standard.string(forKey: "CoachFeedbackDepth") ?? "") ?? .focused {
        didSet { UserDefaults.standard.set(coachFeedbackDepth.rawValue, forKey: "CoachFeedbackDepth") }
    }
    @Published var useAzureAssessment = UserDefaults.standard.object(forKey: "UseAzureAssessment") == nil ? false : UserDefaults.standard.bool(forKey: "UseAzureAssessment") {
        didSet { UserDefaults.standard.set(useAzureAssessment, forKey: "UseAzureAssessment") }
    }
    @Published var useProsodyAnalysis = UserDefaults.standard.object(forKey: "UseProsodyAnalysis") == nil ? false : UserDefaults.standard.bool(forKey: "UseProsodyAnalysis") {
        didSet { UserDefaults.standard.set(useProsodyAnalysis, forKey: "UseProsodyAnalysis") }
    }
    @Published var useAICoach = UserDefaults.standard.object(forKey: "UseAICoach") == nil ? false : UserDefaults.standard.bool(forKey: "UseAICoach") {
        didSet { UserDefaults.standard.set(useAICoach, forKey: "UseAICoach") }
    }
    @Published var desiredReviewRetention: Double = {
        let stored = UserDefaults.standard.double(forKey: "DesiredReviewRetention")
        return ReviewRetentionOption(rawValue: stored)?.rawValue ?? ReviewRetentionOption.balanced.rawValue
    }() {
        didSet { UserDefaults.standard.set(desiredReviewRetention, forKey: "DesiredReviewRetention") }
    }
    @Published var dailyReviewLimit: Int = {
        let stored = UserDefaults.standard.integer(forKey: "DailyReviewLimit")
        return [10, 20, 30, 50].contains(stored) ? stored : 20
    }() {
        didSet { UserDefaults.standard.set(dailyReviewLimit, forKey: "DailyReviewLimit") }
    }
    @Published private(set) var isReviewSessionActive = false
    @Published private(set) var isReviewAnswerRevealed = false
    @Published private(set) var isReviewChineseHintVisible = false
    @Published private(set) var reviewSessionPosition = 0
    @Published private(set) var reviewSessionTotal = 0
    @Published private(set) var activeRecordingActivity: PracticeActivity = .shadowing
    @Published private(set) var isFindingLearningTargets = false
    @Published var realUseOutcome: RealUseOutcome = .worked
    @Published var realUseActualWords = ""
    @Published var selectedAttemptRelativePathForAnalysis: String?
    @Published var phraseTranslation = ""
    @Published var isTranslatingPhrase = false
    @Published var sentenceTranslation = ""
    @Published var isTranslatingSentence = false
    @Published var lookupSummary = ""
    @Published var isLookingUpWord = false
    @Published var coachConversation: [CoachConversationMessage] = []
    @Published var isAskingCodex = false

    private var phraseTranslationRequestID = UUID()
    private var sentenceTranslationRequestID = UUID()
    private var wordLookupRequestID = UUID()
    private var learningTargetRequestID = UUID()
    var coachConversationRequestID = UUID()
    var analysisRunIDs: [String: UUID] = [:]
    private var reviewSessionLineIDs: [UUID] = []

    private let synthesizer = NSSpeechSynthesizer()
    private var recorder: AVAudioRecorder?
    var player: AVAudioPlayer?
    private var sourcePlayer: AVPlayer?
    private var sourceStopTimer: Timer?
    private let persistenceQueue = DispatchQueue(label: "ShadowCoach.persistence", qos: .utility)
    private let persistenceLock = NSLock()
    private var practiceSaveVersion = 0
    private var librarySaveVersion = 0
    private var remainingListenRepeats = 0
    let sourceAudioLeadPadding = 0.08
    let sourceAudioTailPadding = 0.0
    private let sourceAudioMaxNextLineBleed = 0.24
    let geminiModel = "gemini-2.5-flash-lite"
    private let lastSelectedLineDefaultsKey = "LastSelectedLineID"
    let speechRateOptions = [135.0, 155.0, 175.0, 200.0]

    var englishVoices: [SpeechVoice] {
        NSSpeechSynthesizer.availableVoices
            .compactMap { identifier -> SpeechVoice? in
                let attributes = NSSpeechSynthesizer.attributes(forVoice: identifier)
                let locale = attributes[.localeIdentifier] as? String ?? ""
                let rawIdentifier = identifier.rawValue
                let name = attributes[.name] as? String ?? rawIdentifier.components(separatedBy: ".").last ?? rawIdentifier
                guard locale.lowercased().hasPrefix("en") || rawIdentifier.lowercased().contains(".en") else { return nil }
                return SpeechVoice(id: rawIdentifier, name: name, locale: locale)
            }
            .sorted { lhs, rhs in
                if lhs.locale == rhs.locale { return lhs.name < rhs.name }
                return lhs.locale < rhs.locale
            }
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var recordingURL: URL {
        appSupportDirectory.appendingPathComponent("latest-recording.m4a")
    }

    var analysisRecordingURL: URL? {
        if let selectedAttemptRelativePathForAnalysis {
            guard attempt(forRelativePath: selectedAttemptRelativePathForAnalysis)?.resolvedActivity.comparesWithReference == true else {
                return nil
            }
            let url = appSupportDirectory.appendingPathComponent(selectedAttemptRelativePathForAnalysis)
            if isUsableRecording(at: url) {
                return url
            }
            return nil
        }
        for attempt in currentProgress().attempts where attempt.resolvedActivity.comparesWithReference {
            let url = appSupportDirectory.appendingPathComponent(attempt.relativePath)
            if isUsableRecording(at: url) {
                return url
            }
        }
        if activeRecordingActivity.comparesWithReference, isUsableRecording(at: recordingURL) {
            return recordingURL
        }
        return nil
    }

    var selectedAttemptActivity: PracticeActivity? {
        guard let selectedAttemptRelativePathForAnalysis else { return nil }
        return attempt(forRelativePath: selectedAttemptRelativePathForAnalysis)?.resolvedActivity
    }

    var selectedAttemptRecordingURL: URL? {
        guard let selectedAttemptRelativePathForAnalysis else { return nil }
        let url = appSupportDirectory.appendingPathComponent(selectedAttemptRelativePathForAnalysis)
        return isUsableRecording(at: url) ? url : nil
    }

    var analyzableRecordingURL: URL? {
        selectedAttemptRecordingURL ?? analysisRecordingURL
    }

    var selectedOpenResponseAnalysis: OpenResponseAnalysisCache? {
        guard let selectedAttemptRelativePathForAnalysis,
              let attempt = attempt(forRelativePath: selectedAttemptRelativePathForAnalysis),
              !attempt.resolvedActivity.comparesWithReference else {
            return nil
        }
        return attempt.openResponseAnalysisCache
    }

    var libraryURL: URL {
        appSupportDirectory.appendingPathComponent("library.json")
    }

    var practiceURL: URL {
        appSupportDirectory.appendingPathComponent("practice.json")
    }

    var recordingsDirectory: URL {
        let directory = appSupportDirectory.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private var mediaDirectory: URL {
        let directory = appSupportDirectory.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private var urlImportDirectory: URL {
        let directory = appSupportDirectory.appendingPathComponent("URL Imports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    var appSupportDirectory: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShadowCoach", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func speakSentence() {
        guard !isReviewSessionActive || isReviewAnswerRevealed else {
            status = "Recall the line before listening to the answer."
            return
        }
        stopPlayback()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking()
        }
        isSentenceVisible = false
        remainingListenRepeats = max(1, listenRepeats)
        status = "Playing reference sentence"
        playReferenceOnce()
    }

    private func playReferenceOnce() {
        if let selectedLine, selectedLine.hasSourceAudio {
            playSourceSegmentOnce(selectedLine)
            return
        }

        playTTSReferenceOnce()
    }

    private func playTTSReferenceOnce() {
        if !selectedVoiceIdentifier.isEmpty {
            synthesizer.setVoice(NSSpeechSynthesizer.VoiceName(rawValue: selectedVoiceIdentifier))
        }
        synthesizer.rate = Float(speechRate)
        synthesizer.volume = 1.0
        synthesizer.startSpeaking(sentence)
    }

    func choose(_ line: PracticeLine) {
        // Archive an active recording against the sentence it belongs to before
        // changing selection. The archived file also lets analysis continue safely.
        clearRecording()
        learningTargetRequestID = UUID()
        isFindingLearningTargets = false
        selectedLineID = line.id
        selectedLine = line
        rememberLastSelectedLine(line.id)
        sentence = line.text
        isSentenceVisible = false
        analysis = ""
        recordingAnalysis = nil
        resetCoachConversation()
        sentenceTranslation = ""
        sentenceTranslationRequestID = UUID()
        clearPhraseLookup()
        if let reflection = practiceStore.progress[line.id]?.learningPath?.realUseReflection {
            realUseOutcome = reflection.outcome
            realUseActualWords = reflection.actualWords
            analysis = reflection.coachFeedback
                ?? realUseFallbackFeedback(outcome: reflection.outcome, learningTarget: currentLearningTarget)
        } else {
            realUseOutcome = .worked
            realUseActualWords = ""
        }
        activeRecordingActivity = LearningPathEngine.recordingActivity(for: currentLearningStage())
        status = "Sentence loaded. Listen first, then repeat from memory."
        findLearningTargetsIfNeeded()
    }

    func restoreLastSelectedLine(from lines: [PracticeLine]) {
        guard selectedLine == nil else { return }
        let defaultsID = UserDefaults.standard.string(forKey: lastSelectedLineDefaultsKey)
            .flatMap { UUID(uuidString: $0) }
        for rememberedID in [defaultsID, practiceStore.lastSelectedLineID].compactMap({ $0 }) {
            if let line = lines.first(where: { $0.id == rememberedID }) {
                choose(line)
                status = "Restored last sentence."
                return
            }
        }
        if let firstLine = lines.first {
            choose(firstLine)
        }
    }

    private func rememberLastSelectedLine(_ lineID: UUID?) {
        practiceStore.lastSelectedLineID = lineID
        if let lineID {
            UserDefaults.standard.set(lineID.uuidString, forKey: lastSelectedLineDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastSelectedLineDefaultsKey)
        }
    }

    func chooseNext(in lines: [PracticeLine]) {
        if isReviewSessionActive {
            endReviewSession()
        }
        guard !lines.isEmpty else { return }
        guard let index = lines.firstIndex(where: { $0.id == selectedLineID }) else {
            choose(lines[0])
            return
        }
        guard index + 1 < lines.count else {
            status = "Already at the last sentence in this folder."
            return
        }
        choose(lines[index + 1])
    }

    func choosePrevious(in lines: [PracticeLine]) {
        if isReviewSessionActive {
            endReviewSession()
        }
        guard !lines.isEmpty else { return }
        guard let index = lines.firstIndex(where: { $0.id == selectedLineID }) else {
            choose(lines[0])
            return
        }
        guard index > 0 else {
            status = "Already at the first sentence in this folder."
            return
        }
        choose(lines[index - 1])
    }

    func toggleFavorite() {
        guard let selectedLineID else { return }
        toggleFavorite(lineID: selectedLineID)
    }

    func toggleFavorite(for line: PracticeLine) {
        toggleFavorite(lineID: line.id)
    }

    private func toggleFavorite(lineID: UUID) {
        if practiceStore.favorites.contains(lineID) {
            practiceStore.favorites.remove(lineID)
            status = "Removed from favorites"
        } else {
            practiceStore.favorites.insert(lineID)
            status = "Added to favorites"
        }
        savePracticeStore()
    }

    func performShortcut(_ action: ShortcutAction, visibleLines: [PracticeLine]) {
        switch action {
        case .listen:
            speakSentence()
        case .toggleRecord:
            toggleRecording()
        case .playback:
            playRecording()
        case .reveal:
            if isReviewSessionActive {
                revealReviewAnswer()
            } else {
                isSentenceVisible.toggle()
            }
        case .favorite:
            toggleFavorite()
        case .previous:
            choosePrevious(in: visibleLines)
        case .next:
            chooseNext(in: visibleLines)
        }
    }

    func loadLibrary() {
        ImportLogger.write("loadLibrary start path=\(libraryURL.path)")
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return }
        do {
            let data = try Data(contentsOf: libraryURL)
            let persisted = try JSONDecoder().decode(PersistedLibrary.self, from: data)
            importedLines = persisted.importedLines
            generatedLines = persisted.generatedLines
            libraryRevision &+= 1
            status = "Library loaded"
            ImportLogger.write("loadLibrary success imported=\(importedLines.count) generated=\(generatedLines.count)")
        } catch {
            status = "Could not load saved library: \(error.localizedDescription)"
            ImportLogger.write("loadLibrary error \(error.localizedDescription)")
        }
    }

    func loadPracticeStore() {
        guard FileManager.default.fileExists(atPath: practiceURL.path) else { return }
        do {
            let data = try Data(contentsOf: practiceURL)
            practiceStore = try JSONDecoder().decode(PracticeStore.self, from: data)
            practiceRevision &+= 1
            if migrateLegacyReviewCards() {
                savePracticeStore()
            }
        } catch {
            status = "Could not load practice history: \(error.localizedDescription)"
        }
    }

    private func migrateLegacyReviewCards() -> Bool {
        var changed = false
        for lineID in Array(practiceStore.progress.keys) {
            guard var progress = practiceStore.progress[lineID],
                  progress.practiceCount > 0,
                  progress.review == nil else {
                continue
            }
            var card = FSRSReviewCard()
            card.due = progress.lastPracticedAt ?? Date()
            progress.review = SentenceReviewProgress(card: card)
            practiceStore.progress[lineID] = progress
            changed = true
        }
        return changed
    }

    func savePracticeStore() {
        practiceRevision &+= 1
        let snapshot = practiceStore
        let destination = practiceURL
        persistenceLock.lock()
        practiceSaveVersion += 1
        let version = practiceSaveVersion
        persistenceLock.unlock()

        persistenceQueue.async { [weak self] in
            guard let self else { return }
            self.persistenceLock.lock()
            let isLatest = version == self.practiceSaveVersion
            self.persistenceLock.unlock()
            guard isLatest else { return }

            do {
                let data = try JSONEncoder.storage.encode(snapshot)
                try data.write(to: destination, options: .atomic)
            } catch {
                DispatchQueue.main.async {
                    self.status = "Could not save practice history: \(error.localizedDescription)"
                }
            }
        }
    }

    func saveLibrary() {
        libraryRevision &+= 1
        let start = Date()
        ImportLogger.write("saveLibrary start imported=\(importedLines.count) generated=\(generatedLines.count)")
        let snapshot = PersistedLibrary(importedLines: importedLines, generatedLines: generatedLines)
        let destination = libraryURL
        persistenceLock.lock()
        librarySaveVersion += 1
        let version = librarySaveVersion
        persistenceLock.unlock()

        persistenceQueue.async { [weak self] in
            guard let self else { return }
            self.persistenceLock.lock()
            let isLatest = version == self.librarySaveVersion
            self.persistenceLock.unlock()
            guard isLatest else { return }

            do {
                let data = try JSONEncoder.storage.encode(snapshot)
                try data.write(to: destination, options: .atomic)
                ImportLogger.write("saveLibrary success bytes=\(data.count) elapsed=\(Date().timeIntervalSince(start))")
            } catch {
                ImportLogger.write("saveLibrary error \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.status = "Could not save library: \(error.localizedDescription)"
                }
            }
        }
    }

    private func replaceImportedLines(_ newLines: [PracticeLine], sourceName: String) {
        let previousLines = importedLines.filter { $0.source == sourceName }
        let previousMediaPaths = Set(previousLines.compactMap(\.sourceMediaRelativePath))
        var previousByText = Dictionary(grouping: previousLines, by: importMatchKey)
        var stabilizedLines: [PracticeLine] = []
        var reusedIDs: Set<UUID> = []

        for line in newLines {
            let key = importMatchKey(line)
            if var matches = previousByText[key], let previous = matches.first {
                matches.removeFirst()
                previousByText[key] = matches
                stabilizedLines.append(line.replacingID(with: previous.id))
                reusedIDs.insert(previous.id)
            } else {
                stabilizedLines.append(line)
            }
        }

        let removedIDs = Set(previousLines.map(\.id)).subtracting(reusedIDs)
        if !removedIDs.isEmpty {
            removePracticeData(for: removedIDs)
        }

        importedLines.removeAll { $0.source == sourceName }
        importedLines = stabilizedLines + importedLines
        removeUnusedMedia(at: previousMediaPaths)

        if let selectedLine, selectedLine.source == sourceName {
            if let updated = stabilizedLines.first(where: { $0.id == selectedLine.id }) {
                self.selectedLine = updated
                sentence = updated.text
            } else if let replacement = stabilizedLines.first {
                choose(replacement)
            }
        }

        saveLibrary()
        if !removedIDs.isEmpty {
            savePracticeStore()
        }
    }

    private func importMatchKey(_ line: PracticeLine) -> String {
        line.text
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9']+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func deleteSource(_ source: String) {
        let removedLines = (importedLines + generatedLines).filter { $0.source == source }
        guard !removedLines.isEmpty else { return }
        let removedIDs = Set(removedLines.map(\.id))
        let mediaPaths = Set(removedLines.compactMap(\.sourceMediaRelativePath))
        let selectedWasRemoved = selectedLineID.map(removedIDs.contains) == true

        removePracticeData(for: removedIDs)
        importedLines.removeAll { $0.source == source }
        generatedLines.removeAll { $0.source == source }
        saveLibrary()
        savePracticeStore()
        removeUnusedMedia(at: mediaPaths)

        if selectedWasRemoved {
            selectedLine = nil
            selectedLineID = nil
            rememberLastSelectedLine(nil)
            if let replacement = (importedLines + generatedLines + PracticeLine.library).first {
                choose(replacement)
            }
        }
        status = "Removed \(source) and its saved practice data"
    }

    func deleteLine(_ line: PracticeLine) {
        let isUserLine = importedLines.contains(where: { $0.id == line.id })
            || generatedLines.contains(where: { $0.id == line.id })
        guard isUserLine else { return }

        let selectedWasRemoved = selectedLineID == line.id
        removePracticeData(for: [line.id])
        importedLines.removeAll { $0.id == line.id }
        generatedLines.removeAll { $0.id == line.id }
        saveLibrary()
        savePracticeStore()
        if let mediaPath = line.sourceMediaRelativePath {
            removeUnusedMedia(at: [mediaPath])
        }

        if selectedWasRemoved {
            selectedLine = nil
            selectedLineID = nil
            rememberLastSelectedLine(nil)
            if let replacement = (importedLines + generatedLines + PracticeLine.library).first {
                choose(replacement)
            }
        }
        status = "Deleted \(line.title)"
    }

    func cleanUpUnusedStorage() {
        guard !isImporting else {
            status = "Wait for the current import to finish before cleaning storage."
            return
        }

        let candidates = unusedStorageFiles()
        guard !candidates.isEmpty else {
            status = "Storage is already clean"
            return
        }

        let totalBytes = candidates.reduce(Int64(0)) { partial, url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            return partial + size
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let formattedSize = formatter.string(fromByteCount: totalBytes)

        let alert = NSAlert()
        alert.messageText = "Clean Up Unused Files?"
        alert.informativeText = "Remove \(candidates.count) unreferenced downloads and media files (\(formattedSize)). Your library, active source audio, recordings, and analysis history will stay intact."
        alert.addButton(withTitle: "Clean Up")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let temporaryImportDirectory = urlImportDirectory
        status = "Cleaning unused storage..."
        Task.detached(priority: .utility) {
            for url in candidates {
                try? FileManager.default.removeItem(at: url)
            }
            try? FileManager.default.removeItem(at: temporaryImportDirectory)
            await MainActor.run {
                self.status = "Cleaned \(formattedSize) of unused files"
            }
        }
    }

    private func removePracticeData(for lineIDs: Set<UUID>) {
        for lineID in lineIDs {
            if let progress = practiceStore.progress.removeValue(forKey: lineID) {
                for attempt in progress.attempts {
                    try? FileManager.default.removeItem(at: appSupportDirectory.appendingPathComponent(attempt.relativePath))
                }
            }
            practiceStore.favorites.remove(lineID)
        }
        if let lastSelectedLineID = practiceStore.lastSelectedLineID, lineIDs.contains(lastSelectedLineID) {
            rememberLastSelectedLine(nil)
        }
    }

    private func removeUnusedMedia(at relativePaths: Set<String>) {
        let pathsStillInUse = Set((importedLines + generatedLines).compactMap(\.sourceMediaRelativePath))
        for path in relativePaths where !pathsStillInUse.contains(path) {
            try? FileManager.default.removeItem(at: appSupportDirectory.appendingPathComponent(path))
        }
    }

    private func unusedStorageFiles() -> [URL] {
        let referencedMedia = Set((importedLines + generatedLines).compactMap(\.sourceMediaRelativePath))
        let referencedRecordings = Set(practiceStore.progress.values.flatMap(\.attempts).map(\.relativePath))
        let referencedPaths = referencedMedia.union(referencedRecordings)
        var files: [URL] = []

        for directory in [mediaDirectory, recordingsDirectory] {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let prefix = appSupportDirectory.path + "/"
                let relativePath = url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.lastPathComponent
                if !referencedPaths.contains(relativePath) {
                    files.append(url)
                }
            }
        }

        if let enumerator = FileManager.default.enumerator(
            at: urlImportDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    files.append(url)
                }
            }
        }
        return files
    }

    func toggleRecording() {
        isRecording ? stopRecording(autoAnalyze: autoAnalyzeAfterRecording) : startRecording()
    }

    func startRecording(activity: PracticeActivity? = nil) {
        stopPlayback()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking()
        }
        activeRecordingActivity = activity
            ?? LearningPathEngine.recordingActivity(for: currentLearningStage())
        selectedAttemptRelativePathForAnalysis = nil
        analysis = ""
        recordingAnalysis = nil
        resetCoachConversation()

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.beginRecording() : self?.setMicrophoneDenied()
                }
            }
        default:
            setMicrophoneDenied()
        }
    }

    func stopRecording(autoAnalyze: Bool = false) {
        guard recorder != nil || isRecording else { return }
        recorder?.stop()
        recorder = nil
        recordingStartedAt = nil
        isRecording = false
        if let capturedDuration = try? AVAudioPlayer(contentsOf: recordingURL).duration,
           capturedDuration.isFinite {
            recordingDuration = capturedDuration
        }
        hasRecording = isUsableRecording(at: recordingURL, minimumDuration: 0.25)
        if hasRecording {
            let referenceDuration = sourceReferenceDuration(for: selectedLine)
            if activeRecordingActivity.comparesWithReference,
               requireFullReferenceLength && RecordingLengthPolicy.shouldDiscard(
                recordingDuration: recordingDuration,
                referenceDuration: referenceDuration
            ), let referenceDuration {
                let discardedDuration = recordingDuration
                ImportLogger.write(
                    String(
                        format: "recording rejectedShort duration=%.2f reference=%.2f line=%@",
                        discardedDuration,
                        referenceDuration,
                        selectedLineID?.uuidString ?? "unknown"
                    )
                )
                try? FileManager.default.removeItem(at: recordingURL)
                hasRecording = false
                recordingDuration = 0
                status = String(
                    format: "Recording not saved: %.1fs is shorter than the %.1fs reference",
                    discardedDuration,
                    referenceDuration
                )
                return
            }
            let savedActivity = activeRecordingActivity
            saveRecordingAttempt(activity: savedActivity)
            if autoAnalyze && savedActivity.comparesWithReference {
                analyzeRecording()
            } else {
                status = "\(savedActivity.label) recording saved"
            }
            activeRecordingActivity = LearningPathEngine.recordingActivity(for: currentLearningStage())
            findLearningTargetsIfNeeded()
        } else {
            try? FileManager.default.removeItem(at: recordingURL)
            status = "Recording too short. Try again."
        }
    }

    func playRecording() {
        guard isUsableRecording(at: recordingURL) else {
            status = "Record yourself first"
            return
        }

        do {
            stopPlayback()
            player = try AVAudioPlayer(contentsOf: recordingURL)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()
            status = "Playing your recording"
        } catch {
            status = "Could not play recording: \(error.localizedDescription)"
        }
    }

    func clearRecording() {
        stopPlayback()
        if isRecording || recorder != nil {
            stopRecording(autoAnalyze: false)
        }
        selectedAttemptRelativePathForAnalysis = nil
        try? FileManager.default.removeItem(at: recordingURL)
        hasRecording = false
        recordingDuration = 0
        recordingStartedAt = nil
        status = "Recording cleared"
    }

    func discardCurrentRecording() {
        stopPlayback()
        recorder?.stop()
        recorder = nil
        recordingStartedAt = nil
        isRecording = false
        try? FileManager.default.removeItem(at: recordingURL)
        hasRecording = false
        recordingDuration = 0
        status = "Recording discarded"
    }

    func currentProgress() -> PracticeProgress {
        guard let selectedLineID else { return PracticeProgress() }
        return practiceStore.progress[selectedLineID] ?? PracticeProgress()
    }

    func progress(for line: PracticeLine) -> PracticeProgress {
        practiceStore.progress[line.id] ?? PracticeProgress()
    }

    func currentLearningStage() -> LearningPathStage? {
        LearningPathEngine.nextStage(for: currentProgress())
    }

    func isCurrentLearningStageComplete(_ stage: LearningPathStage) -> Bool {
        LearningPathEngine.isComplete(stage, progress: currentProgress())
    }

    func isCurrentLearningStageSkipped(_ stage: LearningPathStage) -> Bool {
        !LearningPathEngine.isApplicable(stage, progress: currentProgress())
    }

    var currentLearningCompletedCount: Int {
        LearningPathEngine.completedCount(for: currentProgress())
    }

    var currentLearningTargets: [LearningTarget] {
        let localTargets = LearningTargetExtractor.extract(from: sentence)
        if let path = currentProgress().learningPath {
            if path.targetSuggestionRevision == LearningTargetExtractor.selectionRevision,
               let cached = path.suggestedTargets {
                return cached
            }
            if let cached = path.suggestedTargets, !cached.isEmpty {
                return LearningTargetExtractor.merge(primary: cached, fallback: localTargets)
            }
        }
        return localTargets
    }

    var currentLearningTarget: LearningTarget? {
        if let selectedTarget = currentProgress().learningPath?.selectedTarget {
            return selectedTarget
        }
        if let legacyChunk = currentProgress().learningPath?.selectedChunk,
           !legacyChunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LearningTarget(
                text: legacyChunk,
                kind: .collocation,
                note: "Saved by an earlier Shadow Coach version.",
                source: .legacy
            )
        }
        return currentLearningTargets.first
    }

    var currentTransferContext: TransferContext {
        currentProgress().learningPath?.transferContext ?? .work
    }

    func completeInputUnderstanding() {
        markCurrentLearningStage(.input)
        isSentenceVisible = true
        status = "Meaning confirmed. Now notice one reusable expression."
        findLearningTargetsIfNeeded()
    }

    private func needsLearningTargetRefresh() -> Bool {
        currentProgress().learningPath?.targetSuggestionRevision
            != LearningTargetExtractor.selectionRevision
    }

    func findLearningTargetsIfNeeded() {
        guard useAICoach,
              feedbackProvider == .codex,
              currentLearningStage() == .noticing,
              needsLearningTargetRefresh() else {
            return
        }
        findBetterLearningTargets()
    }

    func selectLearningTarget(_ target: LearningTarget) {
        updateCurrentLearningPath { path in
            path.selectedTarget = target
            path.selectedChunk = target.text
        }
        status = "Selected \"\(target.displayText)\""
    }

    func completeNoticing(with target: LearningTarget?) {
        updateCurrentLearningPath { path in
            path.selectedTarget = target
            path.selectedChunk = target?.text
            path.mark(.noticing)
        }
        activeRecordingActivity = .shadowing
        status = target == nil
            ? "No reusable target saved. Transfer stages will be skipped for this sentence."
            : "Learning target saved. Listen again and copy the speaker's delivery."
    }

    func findBetterLearningTargets() {
        guard let selectedLineID else { return }
        let provider = feedbackProvider
        let apiKeySnapshot = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider == .gemini, apiKeySnapshot.isEmpty {
            status = "Add your Gemini API key in Settings, or switch the coach provider to Local Codex."
            return
        }

        let sentenceSnapshot = sentence
        let sourceSnapshot = selectedLine.map { "\($0.source) · \($0.title)" } ?? "Unknown source"
        let contextSnapshot = neighboringContext(for: selectedLine)
        let localTargets = LearningTargetExtractor.extract(from: sentenceSnapshot)
        let requestID = UUID()
        learningTargetRequestID = requestID
        isFindingLearningTargets = true
        status = "Finding genuinely reusable language..."

        Task.detached(priority: .userInitiated) {
            do {
                let prompt = LearningTargetPrompt.make(
                    sentence: sentenceSnapshot,
                    source: sourceSnapshot,
                    contextBefore: contextSnapshot.before,
                    contextAfter: contextSnapshot.after
                )
                var aiTargets: [LearningTarget]
                var model: String
                switch provider {
                case .codex:
                    let firstPass = try await CodexFeedbackClient.run(
                        prompt: prompt,
                        workload: .learningTargetSelection
                    )
                    aiTargets = try LearningTargetAIParser.parse(firstPass, sentence: sentenceSnapshot)
                    model = CodexFeedbackClient.route(for: .learningTargetSelection).model

                    if aiTargets.isEmpty, localTargets.isEmpty {
                        let secondPass = try await CodexFeedbackClient.run(
                            prompt: prompt,
                            workload: .learningTargetRecovery
                        )
                        aiTargets = try LearningTargetAIParser.parse(secondPass, sentence: sentenceSnapshot)
                        model = CodexFeedbackClient.route(for: .learningTargetRecovery).model
                    }
                case .gemini:
                    let raw = try await self.requestGeminiText(
                        prompt: prompt,
                        apiKey: apiKeySnapshot,
                        maxOutputTokens: 700
                    )
                    aiTargets = try LearningTargetAIParser.parse(raw, sentence: sentenceSnapshot)
                    model = self.geminiModel
                }
                let targets = LearningTargetExtractor.merge(primary: aiTargets, fallback: localTargets)
                let selectedModel = model
                await MainActor.run {
                    guard self.learningTargetRequestID == requestID,
                          self.selectedLineID == selectedLineID else { return }
                    self.updateCurrentLearningPath { path in
                        path.suggestedTargets = targets
                        path.targetSuggestionModel = selectedModel
                        path.targetSuggestionRevision = LearningTargetExtractor.selectionRevision
                        if let selected = path.selectedTarget,
                           !targets.contains(where: { $0.id == selected.id }) {
                            path.selectedTarget = nil
                            path.selectedChunk = nil
                        }
                    }
                    self.isFindingLearningTargets = false
                    self.status = targets.isEmpty
                        ? "No standalone high-value learning target found. Practice the sentence as a whole."
                        : "Found \(targets.count) reusable learning target\(targets.count == 1 ? "" : "s")"
                }
            } catch {
                await MainActor.run {
                    guard self.learningTargetRequestID == requestID,
                          self.selectedLineID == selectedLineID else { return }
                    self.isFindingLearningTargets = false
                    self.status = "Could not find learning targets: \(error.localizedDescription)"
                }
            }
        }
    }

    func setTransferContext(_ context: TransferContext) {
        updateCurrentLearningPath { path in
            path.transferContext = context
        }
    }

    func beginImmediateRecall() {
        guard let line = selectedLine else {
            status = "Select a sentence first"
            return
        }
        reviewSessionLineIDs = [line.id]
        reviewSessionPosition = 0
        reviewSessionTotal = 1
        isReviewSessionActive = true
        prepareReviewPrompt()
        status = "Recall it from context before revealing the answer."
    }

    func markRealCommunicationComplete() {
        guard !isAnalyzing, let selectedLineID else { return }
        let words = realUseActualWords.trimmingCharacters(in: .whitespacesAndNewlines)
        let outcome = realUseOutcome
        let target = currentLearningTarget
        let sentenceSnapshot = sentence
        let provider = feedbackProvider
        let apiKeySnapshot = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldUseAI = useAICoach && !words.isEmpty
        let providerIsReady = provider == .codex || !apiKeySnapshot.isEmpty
        let codexModel = provider == .codex
            ? CodexFeedbackClient.route(for: .realUseFeedback).model
            : nil
        let fallback = realUseFallbackFeedback(outcome: outcome, learningTarget: target)
        let coreReflection = RealUseReflection(
            createdAt: Date(),
            outcome: outcome,
            actualWords: words,
            coachFeedback: nil,
            feedbackProvider: provider.rawValue,
            coachModel: codexModel
        )
        saveRealUseReflection(coreReflection, for: selectedLineID)
        analysis = fallback

        guard shouldUseAI else {
            status = words.isEmpty
                ? "Real use saved. Add what you said next time for precise language feedback."
                : "Real use saved. Enable AI Coach for wording feedback."
            return
        }
        guard providerIsReady else {
            status = "Real use saved. Add a Gemini key or switch to Local Codex for wording feedback."
            return
        }

        isAnalyzing = true
        status = "Reviewing how the target worked in real use..."
        let prompt = RealUseCoachPrompt.make(
            outcome: outcome,
            actualWords: words,
            learningTarget: target,
            originalSentence: sentenceSnapshot
        )
        Task.detached(priority: .userInitiated) {
            do {
                let raw: String
                switch provider {
                case .codex:
                    raw = try await CodexFeedbackClient.run(
                        prompt: prompt,
                        workload: .realUseFeedback
                    )
                case .gemini:
                    raw = try await self.requestGeminiText(
                        prompt: prompt,
                        apiKey: apiKeySnapshot,
                        maxOutputTokens: 700
                    )
                }
                let cleaned = CoachFeedbackSanitizer.clean(raw)
                let completed = RealUseReflection(
                    createdAt: coreReflection.createdAt,
                    outcome: outcome,
                    actualWords: words,
                    coachFeedback: cleaned,
                    feedbackProvider: provider.rawValue,
                    coachModel: codexModel
                )
                await MainActor.run {
                    self.saveRealUseReflection(completed, for: selectedLineID)
                    if self.selectedLineID == selectedLineID {
                        self.analysis = cleaned
                        self.status = "Real-use feedback ready"
                    }
                    self.isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    if self.selectedLineID == selectedLineID {
                        self.analysis = fallback
                        self.status = "Real use saved. Coach feedback failed: \(error.localizedDescription)"
                    }
                    self.isAnalyzing = false
                }
            }
        }
    }

    private func saveRealUseReflection(_ reflection: RealUseReflection, for lineID: UUID) {
        var progress = practiceStore.progress[lineID] ?? PracticeProgress()
        var path = progress.learningPath ?? LearningPathProgress()
        path.realUseReflection = reflection
        path.mark(.realCommunication)
        progress.learningPath = path
        practiceStore.progress[lineID] = progress
        savePracticeStore()
    }

    private func realUseFallbackFeedback(
        outcome: RealUseOutcome,
        learningTarget: LearningTarget?
    ) -> String {
        let target = learningTarget?.displayText ?? "the main idea"
        let nextStep: String
        switch outcome {
        case .worked:
            nextStep = "在另一个真实场景再用一次 **\(target)**，把一次成功变成可调用的表达。"
        case .hesitated:
            nextStep = "先准备一个只含一个信息点的短句，再用 **\(target)** 完成它。"
        case .didNotLand:
            nextStep = "下次先用更短的句子表达核心意思，再补充细节并确认对方是否理解。"
        }
        return """
        ## 真实使用记录
        已记录结果：**\(outcome.label)**。这一步评价真实调用，而不是逐字复述。

        ## 下一次
        \(nextStep)
        """
    }

    var feedbackCorrectionActionTitle: String {
        guard let attempt = latestComparableAttempt() else { return "Record a retry" }
        if attempt.analysisCache == nil { return "Analyze attempt" }
        if attempt.analysisCache?.localAnalysis.isPerfectWordRecall == true { return "Finish" }
        if attempt.resolvedActivity == .correction { return "Finish" }
        return "Record corrected retry"
    }

    func performFeedbackCorrectionAction() {
        guard let attempt = latestComparableAttempt() else {
            startRecording(activity: .correction)
            return
        }
        if attempt.analysisCache == nil {
            selectedAttemptRelativePathForAnalysis = attempt.relativePath
            analyzeRecording()
            return
        }
        if attempt.analysisCache?.localAnalysis.isPerfectWordRecall == true
            || attempt.resolvedActivity == .correction {
            markCurrentLearningStage(.feedbackCorrection)
            status = "Learning loop complete. Future reviews stay in the FSRS queue."
            return
        }
        startRecording(activity: .correction)
    }

    private func markCurrentLearningStage(_ stage: LearningPathStage) {
        updateCurrentLearningPath { path in
            path.mark(stage)
        }
        activeRecordingActivity = LearningPathEngine.recordingActivity(for: currentLearningStage())
    }

    private func updateCurrentLearningPath(_ update: (inout LearningPathProgress) -> Void) {
        guard let selectedLineID else { return }
        var progress = practiceStore.progress[selectedLineID] ?? PracticeProgress()
        var path = progress.learningPath ?? LearningPathProgress()
        update(&path)
        progress.learningPath = path
        practiceStore.progress[selectedLineID] = progress
        savePracticeStore()
    }

    var reviewSessionProgressText: String {
        guard isReviewSessionActive, reviewSessionTotal > 0 else { return "" }
        return "Review \(reviewSessionPosition + 1) of \(reviewSessionTotal)"
    }

    func isReviewDue(for line: PracticeLine, at date: Date = Date()) -> Bool {
        guard let review = practiceStore.progress[line.id]?.review else { return false }
        return review.card.due <= date
    }

    func totalDueReviewCount(in lines: [PracticeLine], at date: Date = Date()) -> Int {
        lines.reduce(into: 0) { count, line in
            if isReviewDue(for: line, at: date) {
                count += 1
            }
        }
    }

    func availableReviewCount(in lines: [PracticeLine], at date: Date = Date()) -> Int {
        reviewQueue(in: lines, at: date).count
    }

    func startReviewSession(in lines: [PracticeLine], at date: Date = Date()) {
        let queue = reviewQueue(in: lines, at: date)
        guard let firstLine = queue.first else {
            if totalDueReviewCount(in: lines, at: date) > 0 {
                status = "Daily review goal complete"
            } else {
                status = "Review queue is clear"
            }
            return
        }

        reviewSessionLineIDs = queue.map(\.id)
        reviewSessionPosition = 0
        reviewSessionTotal = queue.count
        choose(firstLine)
        isReviewSessionActive = true
        prepareReviewPrompt()
        status = "\(reviewSessionProgressText). Recall it before revealing the answer."
    }

    func endReviewSession() {
        guard isReviewSessionActive else { return }
        isReviewSessionActive = false
        isReviewAnswerRevealed = false
        isReviewChineseHintVisible = false
        reviewSessionLineIDs = []
        reviewSessionPosition = 0
        reviewSessionTotal = 0
        isSentenceVisible = false
        sentenceTranslation = ""
        status = "Review paused"
    }

    func revealReviewAnswer() {
        guard isReviewSessionActive else {
            isSentenceVisible.toggle()
            return
        }
        isReviewAnswerRevealed = true
        isSentenceVisible = true
        status = "Compare your recall, then rate how it felt."
    }

    func showReviewChineseHint() {
        guard isReviewSessionActive, !isReviewAnswerRevealed else { return }
        isReviewChineseHintVisible = true
        translateCurrentSentence()
    }

    func rateCurrentReview(
        _ rating: ReviewRating,
        in lines: [PracticeLine],
        at date: Date = Date()
    ) {
        guard isReviewSessionActive, isReviewAnswerRevealed, let selectedLineID else { return }

        var progress = practiceStore.progress[selectedLineID] ?? PracticeProgress()
        var review = progress.review ?? SentenceReviewProgress()
        let scheduler = FSRS6Scheduler(desiredRetention: desiredReviewRetention)
        let result = scheduler.schedule(card: review.card, rating: rating, at: date)
        review.card = result.card
        review.history.append(result.event)
        if review.history.count > 1_000 {
            review.history.removeFirst(review.history.count - 1_000)
        }
        progress.review = review
        var learningPath = progress.learningPath ?? LearningPathProgress()
        learningPath.mark(.retrieval, at: date)
        learningPath.mark(.spacedReview, at: date)
        progress.learningPath = learningPath
        practiceStore.progress[selectedLineID] = progress
        savePracticeStore()

        let completed = reviewSessionPosition + 1
        var nextPosition = completed
        while nextPosition < reviewSessionLineIDs.count {
            let nextID = reviewSessionLineIDs[nextPosition]
            if let nextLine = lines.first(where: { $0.id == nextID }) {
                reviewSessionPosition = nextPosition
                choose(nextLine)
                isReviewSessionActive = true
                prepareReviewPrompt()
                status = "\(reviewSessionProgressText). Recall it before revealing the answer."
                return
            }
            nextPosition += 1
        }

        let total = reviewSessionTotal
        isReviewSessionActive = false
        isReviewAnswerRevealed = false
        isReviewChineseHintVisible = false
        reviewSessionLineIDs = []
        reviewSessionPosition = 0
        reviewSessionTotal = 0
        isSentenceVisible = false
        sentenceTranslation = ""
        status = "Review complete: \(total) line\(total == 1 ? "" : "s")"
    }

    func reviewIntervalDescription(for rating: ReviewRating, at date: Date = Date()) -> String {
        let card = currentProgress().review?.card ?? FSRSReviewCard()
        let result = FSRS6Scheduler(desiredRetention: desiredReviewRetention)
            .schedule(card: card, rating: rating, at: date)
        return compactInterval(result.event.scheduledInterval)
    }

    private func prepareReviewPrompt() {
        isReviewAnswerRevealed = false
        isReviewChineseHintVisible = false
        isSentenceVisible = false
        sentenceTranslation = ""
        sentenceTranslationRequestID = UUID()
    }

    private func reviewQueue(in lines: [PracticeLine], at date: Date) -> [PracticeLine] {
        let remainingLimit = max(0, dailyReviewLimit - reviewsCompleted(on: date))
        guard remainingLimit > 0 else { return [] }
        let lineOrder = Dictionary(uniqueKeysWithValues: lines.enumerated().map { ($0.element.id, $0.offset) })
        return lines
            .filter { isReviewDue(for: $0, at: date) }
            .sorted { lhs, rhs in
                let lhsDue = practiceStore.progress[lhs.id]?.review?.card.due ?? .distantPast
                let rhsDue = practiceStore.progress[rhs.id]?.review?.card.due ?? .distantPast
                if lhsDue != rhsDue { return lhsDue < rhsDue }
                return (lineOrder[lhs.id] ?? 0) < (lineOrder[rhs.id] ?? 0)
            }
            .prefix(remainingLimit)
            .map { $0 }
    }

    private func reviewsCompleted(on date: Date, calendar: Calendar = .current) -> Int {
        practiceStore.progress.values.reduce(into: 0) { total, progress in
            total += progress.review?.history.filter {
                calendar.isDate($0.reviewedAt, inSameDayAs: date)
            }.count ?? 0
        }
    }

    private func compactInterval(_ interval: TimeInterval) -> String {
        if interval < 3_600 {
            return "\(max(1, Int((interval / 60).rounded())))m"
        }
        if interval < 86_400 {
            return "\(max(1, Int((interval / 3_600).rounded())))h"
        }
        return "\(max(1, Int((interval / 86_400).rounded())))d"
    }

    func loadApiKey() {
        apiKey = KeychainStore.read(service: "ShadowCoach", account: "GeminiAPIKey") ?? ""
    }

    func saveApiKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = trimmed
        if trimmed.isEmpty {
            KeychainStore.delete(service: "ShadowCoach", account: "GeminiAPIKey")
            status = "Gemini API key removed"
        } else {
            KeychainStore.save(trimmed, service: "ShadowCoach", account: "GeminiAPIKey")
            status = "Gemini API key saved in Keychain"
        }
    }

    func translatePhrase(_ phrase: String) {
        let trimmedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPhrase.isEmpty else { return }

        let requestID = UUID()
        phraseTranslationRequestID = requestID
        isTranslatingPhrase = true
        phraseTranslation = "Translating..."
        Task {
            do {
                let translated = try await PhraseTranslatorClient.translate(
                    trimmedPhrase,
                    shadowCoachAppSupportDirectory: self.appSupportDirectory
                )
                await MainActor.run {
                    guard self.phraseTranslationRequestID == requestID else { return }
                    self.phraseTranslation = translated
                    self.isTranslatingPhrase = false
                }
            } catch {
                await MainActor.run {
                    guard self.phraseTranslationRequestID == requestID else { return }
                    self.phraseTranslation = "Translation failed: \(error.localizedDescription)"
                    self.isTranslatingPhrase = false
                }
            }
        }
    }

    func translateCurrentSentence() {
        let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSentence.isEmpty else { return }

        let requestID = UUID()
        sentenceTranslationRequestID = requestID
        isTranslatingSentence = true
        sentenceTranslation = "Translating..."
        Task {
            do {
                let translated = try await PhraseTranslatorClient.translate(
                    trimmedSentence,
                    shadowCoachAppSupportDirectory: self.appSupportDirectory
                )
                await MainActor.run {
                    guard self.sentenceTranslationRequestID == requestID else { return }
                    self.sentenceTranslation = translated
                    self.isTranslatingSentence = false
                }
            } catch {
                await MainActor.run {
                    guard self.sentenceTranslationRequestID == requestID else { return }
                    self.sentenceTranslation = "Translation failed: \(error.localizedDescription)"
                    self.isTranslatingSentence = false
                }
            }
        }
    }

    func lookupWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let requestID = UUID()
        wordLookupRequestID = requestID
        isLookingUpWord = true
        lookupSummary = "Looking up..."
        Task {
            let result = await DictionaryLookupClient.lookup(trimmed)
            await MainActor.run {
                guard self.wordLookupRequestID == requestID else { return }
                self.lookupSummary = result
                self.isLookingUpWord = false
            }
        }
    }

    func clearPhraseLookup() {
        phraseTranslationRequestID = UUID()
        wordLookupRequestID = UUID()
        if !phraseTranslation.isEmpty { phraseTranslation = "" }
        if !lookupSummary.isEmpty { lookupSummary = "" }
        isTranslatingPhrase = false
        isLookingUpWord = false
    }

    func generatePracticeLines() {
        let provider = feedbackProvider
        guard provider != .gemini || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Add your Gemini API key first"
            return
        }

        isGeneratingLines = true
        status = "Generating practice lines with \(provider.label)"

        Task {
            do {
                let prompt = practiceLinesPrompt()
                let lines: [PracticeLine]
                switch provider {
                case .codex:
                    lines = try await requestCodexPracticeLines(prompt: prompt)
                case .gemini:
                    lines = try await requestGeminiPracticeLines(prompt: prompt)
                }
                await MainActor.run {
                    self.generatedLines = lines + self.generatedLines
                    self.saveLibrary()
                    self.status = "Generated \(lines.count) practice lines"
                    self.isGeneratingLines = false
                }
            } catch {
                await MainActor.run {
                    self.status = "Generation failed: \(error.localizedDescription)"
                    self.isGeneratingLines = false
                }
            }
        }
    }

    func importMediaWithSubtitle() {
        guard !isImporting else { return }

        let mediaPanel = NSOpenPanel()
        mediaPanel.title = "Choose Source Media"
        mediaPanel.allowedContentTypes = ["mp4", "mov", "m4a", "mp3"].compactMap { UTType(filenameExtension: $0) }
        mediaPanel.allowsMultipleSelection = false
        mediaPanel.canChooseDirectories = false
        guard mediaPanel.runModal() == .OK, let mediaURL = mediaPanel.url else { return }

        let subtitlePanel = NSOpenPanel()
        subtitlePanel.title = "Choose Subtitle"
        subtitlePanel.allowedContentTypes = ["srt", "vtt", "xlsx"].compactMap { UTType(filenameExtension: $0) }
        subtitlePanel.allowsMultipleSelection = false
        subtitlePanel.canChooseDirectories = false
        guard subtitlePanel.runModal() == .OK, let subtitleURL = subtitlePanel.url else { return }

        isImporting = true
        status = "Importing media and subtitles"

        Task.detached(priority: .userInitiated) {
            var copiedMediaURL: URL?
            var shouldKeepCopiedMedia = false
            defer {
                if !shouldKeepCopiedMedia, let copiedMediaURL {
                    try? FileManager.default.removeItem(at: copiedMediaURL)
                }
            }
            do {
                let mediaFileName = "\(UUID().uuidString)-\(mediaURL.lastPathComponent)"
                let destination = self.mediaDirectory.appendingPathComponent(mediaFileName)
                copiedMediaURL = destination
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: mediaURL, to: destination)
                let relativeMediaPath = "Media/\(mediaFileName)"

                let timedSubtitles: [TimedSubtitle]
                if subtitleURL.pathExtension.lowercased() == "xlsx" {
                    timedSubtitles = try XlsxTextExtractor.extractTimedSubtitles(from: subtitleURL)
                } else {
                    let raw = try String(contentsOf: subtitleURL, encoding: .utf8)
                    timedSubtitles = TimedSubtitleParser.parse(raw)
                }

                let sourceName = "\(mediaURL.deletingPathExtension().lastPathComponent) + \(subtitleURL.deletingPathExtension().lastPathComponent)"
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
                            quality: .localSubtitle
                        )
                    }

                guard !lines.isEmpty else {
                    throw NSError(
                        domain: "MediaImport",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No usable timed subtitles found. Check that the subtitle file contains valid timestamps."]
                    )
                }
                await MainActor.run {
                    self.isImporting = false
                    self.replaceImportedLines(lines, sourceName: sourceName)
                    self.status = "Imported \(lines.count) real-audio clips"
                }
                shouldKeepCopiedMedia = true
            } catch {
                await MainActor.run {
                    self.isImporting = false
                    self.status = "Media import failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func importURL() {
        guard !isImporting else { return }
        guard let rawURL = promptForImportURL() else { return }
        guard let sourceURL = URL(string: rawURL), sourceURL.scheme?.hasPrefix("http") == true else {
            status = "Paste a valid YouTube, TED, or VOA URL"
            return
        }

        isImporting = true
        status = "Checking URL metadata"
        ImportLogger.write("importURL start url=\(sourceURL.absoluteString)")

        Task.detached(priority: .userInitiated) {
            let start = Date()
            do {
                let preview = try URLMediaImporter.previewURL(sourceURL)
                let shouldImport = await MainActor.run {
                    self.confirmURLImport(preview)
                }
                guard shouldImport else {
                    await MainActor.run {
                        self.isImporting = false
                        self.status = "URL import cancelled"
                    }
                    return
                }

                await MainActor.run {
                    self.status = preview.pipeline == .whisperX
                        ? "Downloading media. WhisperX will rebuild the transcript."
                        : "Downloading URL media and subtitles"
                }

                let result = try await URLMediaImporter.importURL(sourceURL, importDirectory: self.urlImportDirectory, mediaDirectory: self.mediaDirectory)
                await MainActor.run {
                    self.isImporting = false
                    self.replaceImportedLines(result.lines, sourceName: result.sourceName)
                    self.status = result.usedEstimatedTiming
                        ? "Imported \(result.lines.count) URL clips with estimated timing"
                        : "Imported \(result.lines.count) URL clips"
                    ImportLogger.write("importURL success lines=\(result.lines.count) estimated=\(result.usedEstimatedTiming) elapsed=\(Date().timeIntervalSince(start))")
                }
            } catch {
                await MainActor.run {
                    self.isImporting = false
                    self.status = self.actionableImportStatus(for: error)
                    ImportLogger.write("importURL error \(error.localizedDescription) elapsed=\(Date().timeIntervalSince(start))")
                }
            }
        }
    }

    private func promptForImportURL() -> String? {
        let alert = NSAlert()
        alert.messageText = "Import URL"
        alert.informativeText = "Paste a YouTube, TED, or VOA page URL. Use content you are allowed to download for personal study."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        field.placeholderString = "https://..."
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds > 0 else { return "Unknown" }
        let total = Int(seconds.rounded())
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func confirmURLImport(_ preview: URLImportPreview) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Preview URL Import"
        alert.informativeText = [
            preview.title,
            "Duration: \(formatDuration(preview.duration))",
            "Transcript: \(preview.pipeline.label)",
            preview.warning
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func actionableImportStatus(for error: Error) -> String {
        let message = error.localizedDescription
        let lowercased = message.lowercased()
        if lowercased.contains("sign in to confirm") || lowercased.contains("not a bot") || lowercased.contains("cookies") {
            return "YouTube needs verification. Open Chrome, sign in to YouTube, then retry this URL."
        }
        if lowercased.contains("429") || lowercased.contains("too many requests") {
            return "YouTube rate limited this import. Wait a few minutes, then retry or use Media + Subtitle."
        }
        if lowercased.contains("403") || lowercased.contains("forbidden") {
            return "YouTube blocked this download. Open the video in Chrome once, then retry."
        }
        if lowercased.contains("no usable english subtitles") {
            return "No usable English transcript found. Try a video with captions or import local media plus SRT/VTT."
        }
        if lowercased.contains("playable media file") {
            return "No playable audio was downloaded. Check that yt-dlp can access this URL."
        }
        return "URL import failed: \(message)"
    }

    func importTranscript() {
        guard !isImporting else { return }
        ImportLogger.write("importTranscript openPanel start")

        let panel = NSOpenPanel()
        panel.title = "Import Transcript"
        panel.allowedContentTypes = ["txt", "srt", "vtt", "csv", "xlsx"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            ImportLogger.write("importTranscript openPanel cancelled")
            return
        }

        isImporting = true
        status = "Importing \(url.lastPathComponent)"
        let selectedPath = url.path
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: selectedPath)[.size] as? NSNumber)?.intValue ?? -1
        ImportLogger.write("importTranscript selected path=\(selectedPath) bytes=\(fileSize)")

        Task.detached(priority: .userInitiated) {
            let totalStart = Date()
            do {
                let raw: String
                if url.pathExtension.lowercased() == "xlsx" {
                    ImportLogger.write("importTranscript xlsx extract start")
                    raw = try XlsxTextExtractor.extractText(from: url)
                    ImportLogger.write("importTranscript xlsx extract done chars=\(raw.count) elapsed=\(Date().timeIntervalSince(totalStart))")
                } else {
                    let readStart = Date()
                    ImportLogger.write("importTranscript text read start")
                    raw = try String(contentsOf: url, encoding: .utf8)
                    ImportLogger.write("importTranscript text read done chars=\(raw.count) elapsed=\(Date().timeIntervalSince(readStart))")
                }

                let sourceName = url.deletingPathExtension().lastPathComponent
                let parseStart = Date()
                ImportLogger.write("importTranscript parse start source=\(sourceName)")
                let lines = TranscriptParser.parse(raw, sourceName: sourceName)
                ImportLogger.write("importTranscript parse done lines=\(lines.count) elapsed=\(Date().timeIntervalSince(parseStart))")

                await MainActor.run {
                    ImportLogger.write("importTranscript main update start elapsed=\(Date().timeIntervalSince(totalStart))")
                    self.isImporting = false
                    guard !lines.isEmpty else {
                        self.status = "No usable English sentences found in \(url.lastPathComponent)"
                        ImportLogger.write("importTranscript no lines")
                        return
                    }

                    self.replaceImportedLines(lines, sourceName: sourceName)
                    self.status = "Imported \(lines.count) lines from \(url.lastPathComponent)"
                    ImportLogger.write("importTranscript success totalElapsed=\(Date().timeIntervalSince(totalStart))")
                }
            } catch {
                await MainActor.run {
                    self.isImporting = false
                    self.status = "Import failed: \(error.localizedDescription)"
                    ImportLogger.write("importTranscript error \(error.localizedDescription) totalElapsed=\(Date().timeIntervalSince(totalStart))")
                }
            }
        }
    }

    private func beginRecording() {
        do {
            try? FileManager.default.removeItem(at: recordingURL)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            recorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            recorder?.delegate = self
            recorder?.prepareToRecord()
            recorder?.record()
            isRecording = true
            hasRecording = false
            recordingDuration = 0
            recordingStartedAt = Date()
            status = "Recording... read the sentence out loud"
        } catch {
            status = "Could not start recording: \(error.localizedDescription)"
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        sourceStopTimer?.invalidate()
        sourceStopTimer = nil
        sourcePlayer?.pause()
        sourcePlayer = nil
    }

    private func playSourceSegmentOnce(_ line: PracticeLine) {
        guard let relativePath = line.sourceMediaRelativePath,
              let start = line.sourceStartTime else {
            status = "No source audio for this sentence"
            return
        }

        let url = appSupportDirectory.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            status = "Source audio file missing. Falling back to TTS."
            playTTSReferenceOnce()
            return
        }

        let paddedStart = max(0, start - sourceAudioLeadPadding)
        let rawEnd = line.sourceEndTime ?? (start + 4.0)
        let nextStart = nextSourceStart(after: line)
        let maxEnd = nextStart.map { max(rawEnd, $0 + sourceAudioMaxNextLineBleed) }
        let paddedEnd = max(min(rawEnd + sourceAudioTailPadding, maxEnd ?? .greatestFiniteMagnitude), paddedStart + 1.0)
        sourceStopTimer?.invalidate()
        let player = AVPlayer(url: url)
        sourcePlayer = player
        status = "Playing source audio"

        player.seek(to: CMTime(seconds: paddedStart, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] _ in
            DispatchQueue.main.async {
                guard let self, let player, self.sourcePlayer === player else { return }
                player.play()
                self.sourceStopTimer = Timer.scheduledTimer(withTimeInterval: paddedEnd - paddedStart, repeats: false) { [weak self] _ in
                    self?.sourcePlayer?.pause()
                    self?.sourcePlayer = nil
                    self?.finishReferencePlayback()
                }
            }
        }
    }

    private func nextSourceStart(after line: PracticeLine) -> Double? {
        guard let source = line.sourceStartTime else { return nil }
        return (importedLines + generatedLines + PracticeLine.library)
            .filter { $0.sourceMediaRelativePath == line.sourceMediaRelativePath }
            .compactMap(\.sourceStartTime)
            .filter { $0 > source }
            .min()
    }

    private func finishReferencePlayback() {
        remainingListenRepeats -= 1
        if remainingListenRepeats > 0 {
            playReferenceOnce()
        } else if autoRecordAfterListen {
            status = "Reference finished. Recording starts now."
            startRecording()
        } else {
            status = "Reference finished"
        }
    }

    private func setMicrophoneDenied() {
        status = "Microphone permission is needed. Enable it in System Settings > Privacy & Security > Microphone."
    }

    private func practiceLinesPrompt() -> String {
        """
        Generate 12 original English shadowing practice sentences.
        Topic: \(generationTopic)
        Level: \(generationLevel)

        Requirements:
        - Original sentences only. Do not quote copyrighted film or TV dialogue.
        - Each sentence should be 8 to 18 words.
        - Mix practical, memorable, and spoken English.
        - Useful for a Chinese native speaker practicing listening and pronunciation.
        - Return only valid JSON. No Markdown, no preface.

        JSON shape:
        [
          {"title":"short title","source":"\(generationLevel) - \(generationTopic)","text":"sentence"}
        ]
        """
    }

    private func requestCodexPracticeLines(prompt: String) async throws -> [PracticeLine] {
        let raw = try await CodexFeedbackClient.run(
            prompt: prompt,
            workload: .practiceGeneration
        )
        return try decodePracticeLines(raw)
    }

    private func requestGeminiPracticeLines(prompt: String) async throws -> [PracticeLine] {
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": prompt]]
                ]
            ],
            "generationConfig": [
                "temperature": 0.8,
                "maxOutputTokens": 1200,
                "responseMimeType": "application/json"
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
        guard let raw = decoded.candidates.first?.content.parts.compactMap(\.text).joined(), !raw.isEmpty else {
            throw NSError(domain: "Gemini", code: -1, userInfo: [NSLocalizedDescriptionKey: "No generated lines returned"])
        }

        return try decodePracticeLines(raw)
    }

    private func decodePracticeLines(_ raw: String) throws -> [PracticeLine] {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```JSON", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let generated = try JSONDecoder().decode([GeneratedPracticeLine].self, from: Data(cleaned.utf8))
        return generated
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { PracticeLine(title: $0.title, source: $0.source, text: $0.text, quality: .generated) }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        status = flag ? "Playback finished" : "Playback stopped"
    }

    func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        guard finishedSpeaking else { return }
        finishReferencePlayback()
    }
}
