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

private enum LibraryDeletionTarget: Identifiable {
    case source(String)
    case line(PracticeLine)
    case attempt(RecordingAttempt)

    var id: String {
        switch self {
        case .source(let source): return "source-\(source)"
        case .line(let line): return "line-\(line.id.uuidString)"
        case .attempt(let attempt): return "attempt-\(attempt.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .source: return "Delete Library Folder?"
        case .line: return "Delete Sentence?"
        case .attempt: return "Delete Recording?"
        }
    }

    var message: String {
        switch self {
        case .source(let source):
            return "\(source) and its saved recordings, analysis, favorites, and unused source audio will be removed."
        case .line(let line):
            return "\(line.title) and its saved recordings and analysis will be removed."
        case .attempt:
            return "This recording and its cached analysis will be permanently removed."
        }
    }
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

private struct FeedbackTextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

private extension EnvironmentValues {
    var feedbackTextScale: CGFloat {
        get { self[FeedbackTextScaleKey.self] }
        set { self[FeedbackTextScaleKey.self] = newValue }
    }
}

private func scaledFeedbackFont(
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

enum RecordingLengthPolicy {
    static func shouldDiscard(recordingDuration: Double, referenceDuration: Double?) -> Bool {
        guard let referenceDuration,
              recordingDuration.isFinite,
              referenceDuration.isFinite,
              recordingDuration >= 0,
              referenceDuration > 0 else {
            return false
        }
        return recordingDuration < referenceDuration
    }
}

final class SpeechCoach: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate, NSSpeechSynthesizerDelegate {
    @Published var sentence = "The fastest way to improve your English is to listen carefully and repeat out loud."
    @Published var isSentenceVisible = false
    @Published var status = "Ready"
    @Published var isRecording = false
    @Published var hasRecording = false
    @Published var recordingDuration = 0.0
    @Published var apiKey = ""
    @Published var isAnalyzing = false
    @Published var analysis = ""
    @Published var recordingAnalysis: RecordingAnalysis?
    @Published var generatedLines: [PracticeLine] = []
    @Published var importedLines: [PracticeLine] = []
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
    private var coachConversationRequestID = UUID()
    private var analysisRunIDs: [String: UUID] = [:]
    private var reviewSessionLineIDs: [UUID] = []

    private let synthesizer = NSSpeechSynthesizer()
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var sourcePlayer: AVPlayer?
    private var sourceStopTimer: Timer?
    private var timer: Timer?
    private let persistenceQueue = DispatchQueue(label: "ShadowCoach.persistence", qos: .utility)
    private let persistenceLock = NSLock()
    private var practiceSaveVersion = 0
    private var librarySaveVersion = 0
    private var remainingListenRepeats = 0
    private let sourceAudioLeadPadding = 0.08
    private let sourceAudioTailPadding = 0.0
    private let sourceAudioMaxNextLineBleed = 0.24
    private let geminiModel = "gemini-2.5-flash-lite"
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

    private var recordingsDirectory: URL {
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

    private var appSupportDirectory: URL {
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
        selectedLineID = line.id
        selectedLine = line
        practiceStore.lastSelectedLineID = line.id
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
        savePracticeStore()
        status = "Sentence loaded. Listen first, then repeat from memory."
    }

    func restoreLastSelectedLine(from lines: [PracticeLine]) {
        guard selectedLine == nil else { return }
        if let lastSelectedLineID = practiceStore.lastSelectedLineID,
           let line = lines.first(where: { $0.id == lastSelectedLineID }) {
            choose(line)
            status = "Restored last sentence."
        } else if let firstLine = lines.first {
            choose(firstLine)
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
            practiceStore.lastSelectedLineID = nil
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
            practiceStore.lastSelectedLineID = nil
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
            practiceStore.lastSelectedLineID = nil
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
        timer?.invalidate()
        timer = nil
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
        status = "Recording cleared"
    }

    func discardCurrentRecording() {
        stopPlayback()
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
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

    var currentLearningCompletedCount: Int {
        LearningPathEngine.completedCount(for: currentProgress())
    }

    var currentLearningTargets: [LearningTarget] {
        if let cached = currentProgress().learningPath?.suggestedTargets {
            return cached
        }
        return LearningTargetExtractor.extract(from: sentence)
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
        if useAICoach,
           feedbackProvider == .codex,
           currentProgress().learningPath?.suggestedTargets == nil {
            findBetterLearningTargets()
        }
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
            ? "No standalone learning target saved. Practice this line as a complete message."
            : "Learning target saved. Listen again and copy the speaker's delivery."
    }

    func findBetterLearningTargets() {
        guard !isFindingLearningTargets, let selectedLineID else { return }
        let provider = feedbackProvider
        let apiKeySnapshot = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider == .gemini, apiKeySnapshot.isEmpty {
            status = "Add your Gemini API key in Settings, or switch the coach provider to Local Codex."
            return
        }

        let sentenceSnapshot = sentence
        let sourceSnapshot = selectedLine.map { "\($0.source) · \($0.title)" } ?? "Unknown source"
        let contextSnapshot = neighboringContext(for: selectedLine)
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
                let raw: String
                switch provider {
                case .codex:
                    raw = try await CodexFeedbackClient.run(
                        prompt: prompt,
                        model: CodexFeedbackClient.coachingModel,
                        reasoningEffort: CodexFeedbackClient.coachingReasoningEffort
                    )
                case .gemini:
                    raw = try await self.requestGeminiText(
                        prompt: prompt,
                        apiKey: apiKeySnapshot,
                        maxOutputTokens: 700
                    )
                }
                let targets = try LearningTargetAIParser.parse(raw, sentence: sentenceSnapshot)
                await MainActor.run {
                    guard self.selectedLineID == selectedLineID else {
                        self.isFindingLearningTargets = false
                        return
                    }
                    self.updateCurrentLearningPath { path in
                        path.suggestedTargets = targets
                        path.targetSuggestionModel = provider == .codex
                            ? CodexFeedbackClient.coachingModel
                            : self.geminiModel
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
                    self.isFindingLearningTargets = false
                    self.status = "Could not refine learning targets: \(error.localizedDescription)"
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
        let fallback = realUseFallbackFeedback(outcome: outcome, learningTarget: target)
        let coreReflection = RealUseReflection(
            createdAt: Date(),
            outcome: outcome,
            actualWords: words,
            coachFeedback: nil,
            feedbackProvider: provider.rawValue,
            coachModel: provider == .codex ? CodexFeedbackClient.coachingModel : nil
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
                        model: CodexFeedbackClient.coachingModel,
                        reasoningEffort: CodexFeedbackClient.coachingReasoningEffort
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
                    coachModel: provider == .codex ? CodexFeedbackClient.coachingModel : nil
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

    private func latestComparableAttempt() -> RecordingAttempt? {
        currentProgress().attempts.first { $0.resolvedActivity.comparesWithReference }
    }

    private func attempt(forRelativePath relativePath: String) -> RecordingAttempt? {
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
        }) else { return }
        let lineID = location.key
        let url = appSupportDirectory.appendingPathComponent(attempt.relativePath)
        try? FileManager.default.removeItem(at: url)
        if selectedAttemptRelativePathForAnalysis == attempt.relativePath {
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

    private func saveRecordingAttempt(activity: PracticeActivity) {
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

    private func isUsableRecording(at url: URL, minimumDuration: Double = 0.05) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 1_024 else {
            return false
        }

        guard let duration = try? AVAudioPlayer(contentsOf: url).duration else { return false }
        return duration.isFinite && duration >= minimumDuration
    }

    private func sourceReferenceDuration(for line: PracticeLine?) -> Double? {
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

    private func cachedAnalysis(for audioURL: URL) -> RecordingAnalysisCache? {
        guard let location = attemptLocation(for: audioURL) else { return nil }
        guard let attempts = practiceStore.progress[location.lineID]?.attempts,
              attempts.indices.contains(location.attemptIndex) else {
            return nil
        }
        return attempts[location.attemptIndex].analysisCache
    }

    private func cachedCoachFeedback(from cache: RecordingAnalysisCache) -> String {
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
           cachedModel != CodexFeedbackClient.coachingModel {
            return ""
        }
        return CoachFeedbackSanitizer.clean(cache.geminiFeedback ?? "")
    }

    private func cachedOpenResponseFeedback(from cache: OpenResponseAnalysisCache) -> String {
        guard useAICoach, cache.usedAICoach else { return "" }
        if let cachedProvider = cache.feedbackProvider, cachedProvider != feedbackProvider {
            return ""
        }
        if feedbackProvider == .codex,
           let cachedModel = cache.coachModel,
           cachedModel != CodexFeedbackClient.coachingModel {
            return ""
        }
        return CoachFeedbackSanitizer.clean(cache.coachFeedback ?? "")
    }

    private func resetCoachConversation() {
        coachConversationRequestID = UUID()
        coachConversation = []
        isAskingCodex = false
    }

    private func loadOpenResponseConversation(from cache: OpenResponseAnalysisCache) {
        coachConversationRequestID = UUID()
        coachConversation = cache.coachConversation ?? []
        isAskingCodex = false
    }

    private func loadCoachConversation(from cache: RecordingAnalysisCache) {
        coachConversationRequestID = UUID()
        coachConversation = cache.coachConversation ?? []
        isAskingCodex = false
    }

    private func perfectRecallStatus(for analysis: RecordingAnalysis, fallback: String) -> String {
        analysis.isPerfectWordRecall ? "100% word recall. Coach analysis was not needed." : fallback
    }

    private func saveAnalysisCache(_ cache: RecordingAnalysisCache, for audioURL: URL) {
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

    private func saveOpenResponseAnalysisCache(_ cache: OpenResponseAnalysisCache, for audioURL: URL) {
        guard let location = attemptLocation(for: audioURL),
              var progress = practiceStore.progress[location.lineID],
              progress.attempts.indices.contains(location.attemptIndex) else {
            return
        }
        progress.attempts[location.attemptIndex].openResponseAnalysisCache = cache
        practiceStore.progress[location.lineID] = progress
        savePracticeStore()
    }

    private func saveOpenResponseConversation(
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

    private func saveCoachConversation(_ messages: [CoachConversationMessage], for audioURL: URL) {
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

    private func attemptLocation(for audioURL: URL) -> (lineID: UUID, attemptIndex: Int)? {
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
                    model: CodexFeedbackClient.coachingModel,
                    reasoningEffort: CodexFeedbackClient.coachingReasoningEffort
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
                    model: CodexFeedbackClient.coachingModel,
                    reasoningEffort: CodexFeedbackClient.coachingReasoningEffort
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
                    coachModel: providerSnapshot == .codex ? CodexFeedbackClient.coachingModel : nil,
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
                        model: CodexFeedbackClient.coachingModel,
                        reasoningEffort: CodexFeedbackClient.coachingReasoningEffort,
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
                    coachModel: providerSnapshot == .codex ? CodexFeedbackClient.coachingModel : nil,
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
                    coachModel: feedbackProviderSnapshot == .codex ? CodexFeedbackClient.coachingModel : nil,
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
                        coachModel: feedbackProviderSnapshot == .codex ? CodexFeedbackClient.coachingModel : nil,
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

    private func displayAnalysis(_ analysis: RecordingAnalysis) -> RecordingAnalysis {
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

    private func sourceAudioURL(for line: PracticeLine?) -> URL? {
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

    private func neighboringContext(for line: PracticeLine?) -> (before: String?, after: String?) {
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

    private func lineIDFromRecordingURL(_ url: URL) -> UUID? {
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
            status = "Recording... read the sentence out loud"

            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let recorder = self.recorder else { return }
                self.recordingDuration = recorder.currentTime
            }
        } catch {
            status = "Could not start recording: \(error.localizedDescription)"
        }
    }

    private func stopPlayback() {
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

    private func requestGeminiText(
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
            model: CodexFeedbackClient.coachingModel,
            reasoningEffort: CodexFeedbackClient.coachingReasoningEffort,
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
        let raw = try await CodexFeedbackClient.run(prompt: prompt)
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

struct PracticeStore: Codable {
    var favorites: Set<UUID> = []
    var progress: [UUID: PracticeProgress] = [:]
    var lastSelectedLineID: UUID?
}

struct PracticeProgress: Codable {
    var practiceCount = 0
    var lastPracticedAt: Date?
    var attempts: [RecordingAttempt] = []
    var review: SentenceReviewProgress? = nil
    var learningPath: LearningPathProgress? = nil
}

struct RecordingAttempt: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let duration: Double
    let relativePath: String
    var activity: PracticeActivity? = nil
    var analysisCache: RecordingAnalysisCache? = nil
    var openResponseAnalysisCache: OpenResponseAnalysisCache? = nil

    var resolvedActivity: PracticeActivity {
        activity ?? .shadowing
    }
}

struct OpenResponseAnalysisCache: Codable, Hashable {
    let createdAt: Date
    let activity: PracticeActivity
    let transcript: String
    let learningTarget: LearningTarget?
    let coachFeedback: String?
    let feedbackProvider: CoachFeedbackProvider?
    let usedAICoach: Bool
    let coachModel: String?
    let transcriptModel: String
    var coachConversation: [CoachConversationMessage]? = nil
}

struct CoachConversationMessage: Identifiable, Codable, Hashable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), role: Role, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

struct RecordingAnalysisCache: Codable, Hashable {
    let createdAt: Date
    let localAnalysis: RecordingAnalysis
    // Keep the legacy JSON key so existing practice history continues to decode.
    let geminiFeedback: String?
    let feedbackProvider: CoachFeedbackProvider?
    let usedAzureAssessment: Bool?
    let usedProsodyAnalysis: Bool?
    let usedAICoach: Bool?
    let coachModel: String?
    let transcriptModel: String?
    var coachConversation: [CoachConversationMessage]?

    init(
        createdAt: Date,
        localAnalysis: RecordingAnalysis,
        geminiFeedback: String?,
        feedbackProvider: CoachFeedbackProvider? = nil,
        usedAzureAssessment: Bool? = nil,
        usedProsodyAnalysis: Bool? = nil,
        usedAICoach: Bool? = nil,
        coachModel: String? = nil,
        transcriptModel: String? = nil,
        coachConversation: [CoachConversationMessage]? = nil
    ) {
        self.createdAt = createdAt
        self.localAnalysis = localAnalysis
        self.geminiFeedback = geminiFeedback
        self.feedbackProvider = feedbackProvider
        self.usedAzureAssessment = usedAzureAssessment
        self.usedProsodyAnalysis = usedProsodyAnalysis
        self.usedAICoach = usedAICoach
        self.coachModel = coachModel
        self.transcriptModel = transcriptModel
        self.coachConversation = coachConversation
    }
}

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
    static var logURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShadowCoach", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("import.log")
    }

    static func write(_ message: String) {
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
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

enum CodexFeedbackClient {
    static let coachingModel = "gpt-5.6-terra"
    static let coachingReasoningEffort = "none"

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
                    reasoningEffort: reasoningEffort ?? coachingReasoningEffort,
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

struct ContentView: View {
    @EnvironmentObject private var coach: SpeechCoach
    @State private var expandedSources: Set<String> = []
    @State private var keyMonitor: Any?
    @State private var librarySearch = ""
    @State private var libraryFilter: LibraryFilter = .all
    @State private var showingGeneratePack = false
    @State private var showProsodyCurves = false
    @State private var showingAppSettings = false
    @State private var settingsSection: AppSettingsSection = .appearance
    @State private var showingPracticeStats = false
    @State private var showingAllAttempts = false
    @State private var hoveredAttemptID: UUID?
    @State private var sourceVisibleLimits: [String: Int] = [:]
    @State private var pendingLibraryDeletion: LibraryDeletionTarget?
    @State private var isLibrarySearchEditing = false
    @State private var coachQuestion = ""
    @AppStorage("isLibrarySidebarCollapsed") private var isLibrarySidebarCollapsed = false
    @AppStorage("isFeedbackSidebarCollapsed") private var isFeedbackSidebarCollapsed = false
    @AppStorage("AppAppearance") private var appAppearanceRaw = AppAppearanceOption.system.rawValue
    @AppStorage("FeedbackTextSize") private var feedbackTextSizeRaw = FeedbackTextSizeOption.large.rawValue
    @AppStorage("PracticeTextSize") private var practiceTextSizeRaw = PracticeTextSizeOption.standard.rawValue
    @FocusState private var focusedInput: FocusedInput?
    private let levels = ["A2", "B1", "B2", "C1"]

    private var visibleLines: [PracticeLine] {
        filteredLines(from: coach.importedLines + coach.generatedLines + PracticeLine.library)
    }

    private var allLines: [PracticeLine] {
        coach.importedLines + coach.generatedLines + PracticeLine.library
    }

    private var appAppearance: AppAppearanceOption {
        AppAppearanceOption(rawValue: appAppearanceRaw) ?? .system
    }

    private var feedbackTextSize: FeedbackTextSizeOption {
        FeedbackTextSizeOption(rawValue: feedbackTextSizeRaw) ?? .large
    }

    private var practiceTextSize: PracticeTextSizeOption {
        PracticeTextSizeOption(rawValue: practiceTextSizeRaw) ?? .standard
    }

    private var currentGroupLines: [PracticeLine] {
        guard let source = coach.selectedLine?.source else { return visibleLines }
        let lines = visibleLines.filter { $0.source == source }
        return lines.isEmpty ? visibleLines : lines
    }

    private var userSources: Set<String> {
        Set((coach.importedLines + coach.generatedLines).map(\.source))
    }

    private var selectedIndexText: String {
        guard let selectedLineID = coach.selectedLineID,
              let index = currentGroupLines.firstIndex(where: { $0.id == selectedLineID }) else {
            return "No sentence selected"
        }
        return "Sentence \(index + 1) of \(currentGroupLines.count)"
    }

    private var visibleSections: [LibrarySection] {
        var sourceOrder: [String] = []
        var grouped: [String: [PracticeLine]] = [:]
        for line in visibleLines {
            if grouped[line.source] == nil {
                sourceOrder.append(line.source)
            }
            grouped[line.source, default: []].append(line)
        }
        return sourceOrder.map { LibrarySection(source: $0, lines: grouped[$0] ?? []) }
    }

    var body: some View {
        HStack(spacing: 0) {
            libraryPanel
                .animation(.snappy(duration: 0.18), value: isLibrarySidebarCollapsed)

            VStack(spacing: 0) {
                topBar

                responsiveWorkspace
                .padding(24)
            }
        }
        .background(appBackground)
        .preferredColorScheme(appAppearance.colorScheme)
        .sheet(isPresented: $showingGeneratePack) {
            generatePackSheet
        }
        .sheet(isPresented: $showingAppSettings) {
            appSettingsSheet
        }
        .alert(item: $pendingLibraryDeletion) { target in
            Alert(
                title: Text(target.title),
                message: Text(target.message),
                primaryButton: .destructive(Text("Delete")) {
                    switch target {
                    case .source(let source):
                        coach.deleteSource(source)
                        expandedSources.remove(source)
                        sourceVisibleLimits.removeValue(forKey: source)
                    case .line(let line):
                        coach.deleteLine(line)
                    case .attempt(let attempt):
                        coach.deleteAttempt(attempt)
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .onAppear {
            if coach.feedbackProvider == .gemini {
                coach.loadApiKey()
            }
            coach.loadLibrary()
            coach.loadPracticeStore()
            coach.restoreLastSelectedLine(from: allLines)
            expandSelectedSource()
            coach.hasRecording = FileManager.default.fileExists(atPath: coach.recordingURL.path)
            installKeyboardMonitor()
            scheduleInitialFocusRelease()
        }
        .onChange(of: coach.selectedLineID) { _ in
            expandSelectedSource()
            showingAllAttempts = false
            hoveredAttemptID = nil
            coachQuestion = ""
        }
        .onChange(of: coach.selectedAttemptRelativePathForAnalysis) { _ in
            coachQuestion = ""
        }
        .onChange(of: coach.feedbackProvider) { provider in
            if provider == .gemini, coach.apiKey.isEmpty {
                coach.loadApiKey()
            }
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
    }

    private func installKeyboardMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                releaseTextInputFocus()
                return nil
            }

            let modifiers = shortcutModifiers(for: event)
            if modifiers == .command,
               event.charactersIgnoringModifiers?.lowercased() == "f" {
                isLibrarySearchEditing = true
                focusedInput = .librarySearch
                return nil
            }

            let isActivelyEditingText = isTextInputFirstResponder()
            let acceptsTextInput = focusedInput == .generationTopic
                || focusedInput == .sentenceEditor
                || focusedInput == .coachQuestion
                || focusedInput == .realUseWords
                || (focusedInput == .librarySearch && isLibrarySearchEditing)
            if acceptsTextInput, isActivelyEditingText {
                return event
            }

            // SwiftUI can leave either side of its focus bridge stale. Reconcile it
            // before dispatching a global practice shortcut.
            if focusedInput != nil {
                focusedInput = nil
            }
            isLibrarySearchEditing = false
            if isActivelyEditingText {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }

            guard let action = shortcutAction(for: event) else { return event }
            if event.isARepeat {
                switch action {
                case .listen, .toggleRecord:
                    return nil
                default:
                    break
                }
            }
            coach.performShortcut(action, visibleLines: currentGroupLines)
            return nil
        }
    }

    private func releaseTextInputFocus() {
        isLibrarySearchEditing = false
        focusedInput = nil
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private func scheduleInitialFocusRelease() {
        for delay in [0.0, 0.2, 0.7] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard !isLibrarySearchEditing else { return }
                focusedInput = nil
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    private func isTextInputFirstResponder() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    private func shortcutModifiers(for event: NSEvent) -> NSEvent.ModifierFlags {
        // Arrow keys carry .function/.numericPad flags on macOS even when the
        // user presses no modifier. Only these four flags represent a chord.
        event.modifierFlags.intersection([.command, .option, .control, .shift])
    }

    private func shortcutAction(for event: NSEvent) -> ShortcutAction? {
        let modifiers = shortcutModifiers(for: event)
        let isCommandOnly = modifiers == .command
        let noModifiers = modifiers.isEmpty

        if focusedInput == .sentenceEditor { return nil }
        let isEditingTopic = focusedInput == .generationTopic

        if noModifiers {
            switch event.keyCode {
            case 123:
                if isEditingTopic { return nil }
                return .previous
            case 124:
                if isEditingTopic { return nil }
                return .next
            case 126:
                if isEditingTopic { return nil }
                return .listen
            case 49:
                if isEditingTopic { return nil }
                return .toggleRecord
            default:
                guard !isEditingTopic, let characters = event.charactersIgnoringModifiers?.lowercased() else { return nil }
                switch characters {
                case "p":
                    return .playback
                case "h":
                    return .reveal
                case "f":
                    return .favorite
                default:
                    return nil
                }
            }
        }

        guard isCommandOnly, let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return nil
        }

        switch characters {
        case "l":
            return .listen
        case "p":
            return .playback
        case "r":
            return .reveal
        case "f":
            return .favorite
        default:
            return nil
        }
    }

    private var appBackground: Color {
        Theme.appBackground
    }

    private var subtleBackground: Color {
        Theme.subtle
    }

    private var statusAppearance: (icon: String, color: Color) {
        let value = coach.status.lowercased()
        if ["failed", "could not", "missing", "denied", "too short", "error"].contains(where: { value.contains($0) }) {
            return ("exclamationmark.triangle.fill", Theme.danger)
        }
        if ["analyzing", "importing", "generating", "recording", "playing", "checking", "downloading"].contains(where: { value.contains($0) }) {
            return ("circle.dotted.circle.fill", Theme.primary)
        }
        if ["ready", "saved", "loaded", "restored", "finished", "imported", "generated"].contains(where: { value.contains($0) }) {
            return ("checkmark.circle.fill", Theme.success)
        }
        return ("info.circle.fill", Color.secondary)
    }

    private var responsiveWorkspace: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 860 {
                HStack(alignment: .top, spacing: 20) {
                    practicePanel
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    if isFeedbackSidebarCollapsed {
                        collapsedFeedbackPanel
                    } else {
                        feedbackPanel
                            .frame(width: 380)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        practicePanel
                        if isFeedbackSidebarCollapsed {
                            Button {
                                isFeedbackSidebarCollapsed = false
                            } label: {
                                Label("Show Feedback", systemImage: "sidebar.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        } else {
                            feedbackPanel
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var topBar: some View {
        GeometryReader { proxy in
            topBarContent(showTimer: proxy.size.width >= 520)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 88)
        .padding(.horizontal, 24)
        .background(Theme.topBar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
        }
    }

    private func topBarContent(showTimer: Bool) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Shadow Coach")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: statusAppearance.icon)
                        .font(.caption)
                    Text(coach.status)
                        .lineLimit(1)
                }
                .font(.callout)
                .foregroundStyle(statusAppearance.color)
                .help(coach.status)
                Text(selectedIndexText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            if showTimer {
                HStack(spacing: 8) {
                    Image(systemName: coach.isRecording ? "waveform.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(coach.isRecording ? Theme.danger : Theme.success)
                    Text(formatDuration(coach.recordingDuration))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.pill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button {
                if coach.isReviewSessionActive {
                    coach.endReviewSession()
                } else {
                    coach.startReviewSession(in: allLines)
                }
            } label: {
                let count = coach.availableReviewCount(in: allLines)
                Label(
                    coach.isReviewSessionActive ? "End Review" : (count > 0 ? "Review \(count)" : "Review"),
                    systemImage: coach.isReviewSessionActive ? "xmark" : "brain.head.profile"
                )
            }
            .buttonStyle(SecondaryButtonStyle())
            .help(reviewButtonHelp)

            Button {
                settingsSection = .appearance
                showingAppSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(IconButtonStyle())
            .help("Settings")
        }
    }

    private var libraryPanel: some View {
        Group {
            if isLibrarySidebarCollapsed {
                collapsedLibraryPanel
            } else {
                expandedLibraryPanel
            }
        }
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)
        }
    }

    private var collapsedLibraryPanel: some View {
        VStack(spacing: 14) {
            Button {
                isLibrarySidebarCollapsed = false
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.primary)
            .background(Theme.primary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .help("Show library")

            Image(systemName: "books.vertical.fill")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("\(visibleLines.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(-90))
                .frame(width: 42, height: 42)

            Spacer()

            if let selectedLine = coach.selectedLine {
                Text(selectedLine.source)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 120, height: 34)
                    .help(selectedLine.source)
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(width: 56)
    }

    private var expandedLibraryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.primary.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "books.vertical.fill")
                        .foregroundStyle(Theme.primary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Library")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("\(visibleLines.count) of \(allLines.count) lines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isLibrarySidebarCollapsed = true
                } label: {
                    Image(systemName: "sidebar.left")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .help("Collapse library")

                Menu {
                    Button {
                        coach.importTranscript()
                    } label: {
                        Label("Import Transcript", systemImage: "doc.text")
                    }
                    Button {
                        coach.importMediaWithSubtitle()
                    } label: {
                        Label("Media + Subtitle", systemImage: "waveform.and.magnifyingglass")
                    }
                    Button {
                        coach.importURL()
                    } label: {
                        Label("Import URL", systemImage: "link.badge.plus")
                    }
                    Divider()
                    Button {
                        showingGeneratePack = true
                    } label: {
                        Label("Generate Practice Pack", systemImage: "wand.and.stars")
                    }
                    Divider()
                    Button {
                        coach.cleanUpUnusedStorage()
                    } label: {
                        Label("Clean Up Storage...", systemImage: "externaldrive.badge.minus")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 30, height: 30)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(Theme.primary)
                .background(Theme.primary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(coach.isImporting || coach.isGeneratingLines)
                .help("Add content")
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    TextField("Search sentences, sources...", text: $librarySearch)
                        .textFieldStyle(.plain)
                        .focused($focusedInput, equals: .librarySearch)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                isLibrarySearchEditing = true
                                focusedInput = .librarySearch
                            }
                        )
                        .onSubmit {
                            releaseTextInputFocus()
                        }
                    if !librarySearch.isEmpty {
                        Button {
                            librarySearch = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Picker("Filter", selection: $libraryFilter) {
                    ForEach(LibraryFilter.allCases) { filter in
                        Label(filter.label, systemImage: filter.systemImage).tag(filter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                if coach.isImporting || coach.isGeneratingLines {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(coach.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 12)

            ScrollView {
                LazyVStack(spacing: 10) {
                    if visibleSections.isEmpty {
                        emptyLibraryFilterState
                    } else {
                        ForEach(visibleSections) { section in
                            sectionView(section)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 300)
    }

    private func sectionView(_ section: LibrarySection) -> some View {
        let isCollapsed = !expandedSources.contains(section.source)
        let isUserSource = userSources.contains(section.source)

        let visibleLimit = sourceVisibleLimits[section.source] ?? 80

        return VStack(spacing: 8) {
            HStack(spacing: 4) {
                Button {
                    toggleSection(section.source)
                } label: {
                    HStack(spacing: 8) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: isUserSource ? "folder.fill" : "tray.full.fill")
                        .foregroundStyle(isUserSource ? .orange : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.source)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text("\(section.lines.count) lines")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isUserSource {
                    Menu {
                        Button(role: .destructive) {
                            pendingLibraryDeletion = .source(section.source)
                        } label: {
                            Label("Delete Folder...", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 26, height: 26)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Folder actions")
                }
            }

            if !isCollapsed {
                LazyVStack(spacing: 8) {
                    ForEach(Array(section.lines.prefix(visibleLimit))) { line in
                        lineButton(line)
                    }

                    if section.lines.count > visibleLimit {
                        Button {
                            sourceVisibleLimits[section.source] = min(visibleLimit + 80, section.lines.count)
                        } label: {
                            Label(
                                "Show \(min(80, section.lines.count - visibleLimit)) more",
                                systemImage: "chevron.down"
                            )
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.primary)
                        .background(Theme.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
                .padding(.leading, 8)
            }
        }
        .padding(10)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.border)
        )
    }

    private var emptyLibraryFilterState: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No matching sentences")
                .font(.callout.weight(.semibold))
            Text("Try a different search or filter.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func filteredLines(from lines: [PracticeLine]) -> [PracticeLine] {
        let query = librarySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lines.filter { line in
            matchesFilter(line) && matchesSearch(line, query: query)
        }
    }

    private func matchesSearch(_ line: PracticeLine, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return line.title.lowercased().contains(query)
            || line.text.lowercased().contains(query)
            || line.source.lowercased().contains(query)
            || qualityForLine(line).label.lowercased().contains(query)
    }

    private func matchesFilter(_ line: PracticeLine) -> Bool {
        switch libraryFilter {
        case .all:
            return true
        case .favorites:
            return coach.practiceStore.favorites.contains(line.id)
        case .done:
            return coach.progress(for: line).practiceCount > 0
        case .needsReview:
            if coach.isReviewDue(for: line) { return true }
            return coach.progress(for: line).attempts.first?.analysisCache?.localAnalysis.accuracy ?? 100 < 85
        case .new:
            return coach.progress(for: line).practiceCount == 0
        case .realAudio:
            return line.hasSourceAudio
        case .tts:
            return !line.hasSourceAudio
        }
    }

    private func toggleSection(_ source: String) {
        if expandedSources.contains(source) {
            expandedSources.remove(source)
        } else {
            expandedSources.insert(source)
        }
    }

    private func expandSelectedSource() {
        guard let source = coach.selectedLine?.source else { return }
        expandedSources.insert(source)
    }

    private func lineButton(_ line: PracticeLine) -> some View {
        let isSelected = coach.selectedLineID == line.id
        let isFavorite = coach.practiceStore.favorites.contains(line.id)
        let progress = coach.progress(for: line)
        let quality = qualityForLine(line)

        return Button {
            if coach.isReviewSessionActive {
                coach.endReviewSession()
            }
            coach.choose(line)
            expandedSources.insert(line.source)
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? Theme.primary : Color.clear)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(line.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(isSelected ? Theme.primary : .primary)
                        .lineLimit(1)
                    Text(line.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        tagPill(label: quality.label, systemImage: quality.systemImage)
                        if line.hasSourceAudio {
                            tagPill(label: "Real Audio", systemImage: "waveform")
                        } else {
                            tagPill(label: "TTS", systemImage: "speaker.wave.2")
                        }
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                    if coach.isReviewDue(for: line) {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
                            .help("Ready to review")
                    }
                    if progress.practiceCount > 0 {
                        Text("\(progress.practiceCount)x")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Theme.selected : Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Theme.primary.opacity(0.42) : Theme.border)
        )
        .contextMenu {
            Button {
                coach.toggleFavorite(for: line)
            } label: {
                Label(isFavorite ? "Remove Favorite" : "Favorite", systemImage: isFavorite ? "star.slash" : "star")
            }
            if userSources.contains(line.source) {
                Divider()
                Button(role: .destructive) {
                    pendingLibraryDeletion = .line(line)
                } label: {
                    Label("Delete Sentence...", systemImage: "trash")
                }
            }
        }
    }

    private func qualityForLine(_ line: PracticeLine) -> ImportQuality {
        line.quality ?? (line.hasSourceAudio ? .localSubtitle : .builtIn)
    }

    private func tagPill(label: String, systemImage: String) -> some View {
        Label(label, systemImage: systemImage)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.pill)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var generatePackSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.accent.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Generate Pack")
                        .font(.headline)
                    Text("Create a custom TTS set with \(coach.feedbackProvider.label).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingGeneratePack = false
                    focusedInput = nil
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }

            TextField("Topic", text: $coach.generationTopic)
                .textFieldStyle(.roundedBorder)
                .focused($focusedInput, equals: .generationTopic)

            Picker("Level", selection: $coach.generationLevel) {
                ForEach(levels, id: \.self) { level in
                    Text(level).tag(level)
                }
            }
            .pickerStyle(.segmented)

            if coach.feedbackProvider == .gemini {
                HStack {
                    SecureField("Gemini API key", text: $coach.apiKey)
                        .textFieldStyle(.roundedBorder)
                    Button(action: coach.saveApiKey) {
                        Image(systemName: "key.fill")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Save Gemini API key")
                }
            } else {
                Label("Uses your signed-in local Codex CLI.", systemImage: "terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                coach.generatePracticeLines()
            } label: {
                Label(coach.isGeneratingLines ? "Generating" : "Create 12 Lines", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.accent))
            .disabled(coach.isGeneratingLines)

            if coach.isGeneratingLines {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .frame(width: 360)
        .background(Theme.panel)
    }

    private var reviewButtonHelp: String {
        if coach.isReviewSessionActive { return "Pause this review session" }
        let total = coach.totalDueReviewCount(in: allLines)
        let available = coach.availableReviewCount(in: allLines)
        if total == 0 { return "No sentences are due" }
        if available == 0 { return "Today's review goal is complete" }
        if available < total { return "Start \(available) of \(total) due sentences" }
        return "Start \(available) due sentence\(available == 1 ? "" : "s")"
    }

    private var previousReviewLine: PracticeLine? {
        guard let selectedLine = coach.selectedLine else { return nil }
        let sourceLines = allLines.filter { $0.source == selectedLine.source }
        guard let index = sourceLines.firstIndex(where: { $0.id == selectedLine.id }), index > 0 else {
            return nil
        }
        return sourceLines[index - 1]
    }

    private var practicePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(coach.isReviewSessionActive ? "Review" : "Practice")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text(
                        coach.isReviewSessionActive
                            ? coach.reviewSessionProgressText
                            : (coach.currentLearningStage()?.title ?? "Learning path complete")
                    )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    coach.toggleFavorite()
                } label: {
                    Image(systemName: coach.selectedLineID.map { coach.practiceStore.favorites.contains($0) } == true ? "star.fill" : "star")
                }
                .buttonStyle(IconButtonStyle())
                .disabled(coach.selectedLineID == nil)
                .help("Favorite current sentence")

                if !coach.isReviewSessionActive {
                    Button {
                        coach.isSentenceVisible = true
                        coach.translateCurrentSentence()
                    } label: {
                        Label(coach.isTranslatingSentence ? "Translating" : "Translate", systemImage: "character.book.closed")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(coach.isTranslatingSentence)
                    .help("Translate the whole sentence")

                    Button {
                        coach.isSentenceVisible.toggle()
                    } label: {
                        Label(coach.isSentenceVisible ? "Hide Text" : "Reveal Text", systemImage: coach.isSentenceVisible ? "eye.slash.fill" : "eye.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }

            if !coach.isReviewSessionActive {
                learningCoachCard
            }

            sentenceStage

            if coach.isReviewSessionActive && coach.isReviewAnswerRevealed {
                reviewRatingBar
            }

            actionDock

            playbackControls

            recordingPanel

            Spacer()
        }
        .padding(2)
    }

    private var learningCoachCard: some View {
        let stage = coach.currentLearningStage()
        let completed = coach.currentLearningCompletedCount

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Theme.accent.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: stage?.systemImage ?? "checkmark.seal.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(stage == nil ? Theme.success : Theme.accent)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(stage == nil ? "Path complete" : "Next Coach")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(stage?.title ?? "Keep it alive through scheduled review")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer()

                Text("\(completed)/\(LearningPathStage.allCases.count)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(stage == nil ? Theme.success : Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background((stage == nil ? Theme.success : Theme.accent).opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            learningPathProgressStrip(activeStage: stage)

            if let stage {
                Text(learningInstruction(for: stage))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                learningStageOptions(stage)

                Button {
                    performLearningAction(stage)
                } label: {
                    Label(learningActionTitle(for: stage), systemImage: learningActionIcon(for: stage))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(color: learningActionColor(for: stage)))
                .disabled(learningActionDisabled(for: stage))
            } else {
                Text("This sentence now stays in your FSRS review queue. Reuse the saved learning target whenever a matching situation appears.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.border)
        )
    }

    private func learningPathProgressStrip(activeStage: LearningPathStage?) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(LearningPathStage.allCases.enumerated()), id: \.element.id) { index, stage in
                let isComplete = coach.isCurrentLearningStageComplete(stage)
                let isActive = activeStage == stage
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            isComplete
                                ? Theme.success.opacity(0.16)
                                : (isActive ? Theme.accent.opacity(0.16) : Theme.pill)
                        )
                    Image(systemName: isComplete ? "checkmark" : stage.systemImage)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isComplete ? Theme.success : (isActive ? Theme.accent : Color.secondary))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isActive ? Theme.accent.opacity(0.45) : Color.clear)
                )
                .help("\(index + 1). \(stage.title)")
            }
        }
    }

    @ViewBuilder
    private func learningStageOptions(_ stage: LearningPathStage) -> some View {
        switch stage {
        case .noticing:
            let targets = coach.currentLearningTargets
            VStack(alignment: .leading, spacing: 8) {
                if targets.isEmpty {
                    Label(
                        "No high-value standalone target found. This sentence is better practiced as a complete message.",
                        systemImage: "checkmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(targets) { target in
                        learningTargetRow(target)
                    }
                }

                Button {
                    coach.findBetterLearningTargets()
                } label: {
                    Label(
                        coach.isFindingLearningTargets ? "Inspecting the sentence..." : "Refine with \(coach.feedbackProvider.label)",
                        systemImage: "wand.and.stars"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .disabled(coach.isFindingLearningTargets)
            }

        case .transformation:
            VStack(alignment: .leading, spacing: 8) {
                learningTargetCallout
                Picker(
                    "New situation",
                    selection: Binding(
                        get: { coach.currentTransferContext },
                        set: { coach.setTransferContext($0) }
                    )
                ) {
                    ForEach(TransferContext.allCases) { context in
                        Text(context.label).tag(context)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

        case .freeExpression:
            learningTargetCallout

        case .realCommunication:
            VStack(alignment: .leading, spacing: 10) {
                learningTargetCallout
                Picker("How did it go?", selection: $coach.realUseOutcome) {
                    ForEach(RealUseOutcome.allCases) { outcome in
                        Label(outcome.label, systemImage: outcome.systemImage).tag(outcome)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                TextField(
                    "What did you actually say? (optional)",
                    text: $coach.realUseActualWords,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .focused($focusedInput, equals: .realUseWords)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Theme.border)
                )

                Text("Add your exact words for language feedback. Leave this blank to save only the real-use outcome.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        default:
            EmptyView()
        }
    }

    private func learningTargetRow(_ target: LearningTarget) -> some View {
        let selected = coach.currentLearningTarget?.id == target.id
        return Button {
            coach.selectLearningTarget(target)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? Theme.accent : Color.secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(target.kind.label.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(target.source == .ai ? Theme.accent : Color.secondary)
                        if target.source == .ai {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    Text(target.displayText)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if target.frame != nil, target.text.caseInsensitiveCompare(target.displayText) != .orderedSame {
                        Text("From: \(target.text)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text(target.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? Theme.accent.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var learningTargetCallout: some View {
        HStack(spacing: 8) {
            Image(systemName: "quote.opening")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(coach.currentLearningTarget?.displayText ?? "Transfer the main idea")
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                if let target = coach.currentLearningTarget {
                    Text(target.kind.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if coach.currentLearningTargets.count > 1 {
                Menu {
                    ForEach(coach.currentLearningTargets) { target in
                        Button(target.displayText) {
                            coach.selectLearningTarget(target)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("Change learning target")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func learningInstruction(for stage: LearningPathStage) -> String {
        let target = coach.currentLearningTarget?.displayText ?? "the main idea"
        switch stage {
        case .input:
            return "Listen for the situation and meaning first. Reveal or translate only when needed, then confirm that the line makes sense to you."
        case .noticing:
            return "Choose one reusable sentence frame, expression, or collocation. If none is worth isolating, keep the complete message instead."
        case .shadowing:
            return "Copy the speaker's timing and phrasing, not just the words. Listen once, then record the full line from memory."
        case .retrieval:
            return "Recall the line from its English context with the answer hidden. Chinese is available only as a rescue hint."
        case .spacedReview:
            return "Rate the recall honestly. FSRS will choose the next interval from your result."
        case .transformation:
            return "Keep \"\(target)\", but change the people, time, and details. Say one new sentence about \(coach.currentTransferContext.prompt)."
        case .freeExpression:
            return "Speak for 30-60 seconds about a related experience or opinion. Use \"\(target)\" naturally, without copying the original sentence."
        case .realCommunication:
            return "Use \"\(target)\" once in a real meeting, conversation, or voice message. Record what happened; this stage evaluates real communication, not exact recall."
        case .feedbackCorrection:
            return "Analyze an exact attempt, apply the most important feedback, then record one corrected retry. Optional Azure, prosody, and AI coaching stay under your settings."
        }
    }

    private func learningActionTitle(for stage: LearningPathStage) -> String {
        switch stage {
        case .input: return "I understand this line"
        case .noticing: return coach.currentLearningTarget == nil ? "Continue with whole sentence" : "Keep this target"
        case .shadowing: return "Listen, then shadow"
        case .retrieval, .spacedReview: return "Recall without prompt"
        case .transformation: return coach.isRecording ? "Stop recording" : "Record new sentence"
        case .freeExpression: return coach.isRecording ? "Stop recording" : "Start free speaking"
        case .realCommunication:
            return coach.realUseActualWords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Save real use"
                : "Review real use"
        case .feedbackCorrection: return coach.isRecording ? "Stop recording" : coach.feedbackCorrectionActionTitle
        }
    }

    private func learningActionIcon(for stage: LearningPathStage) -> String {
        if coach.isRecording, [.transformation, .freeExpression, .feedbackCorrection].contains(stage) {
            return "stop.fill"
        }
        switch stage {
        case .input: return "checkmark"
        case .noticing: return "scope"
        case .shadowing: return "speaker.wave.2.fill"
        case .retrieval, .spacedReview: return "brain.head.profile"
        case .transformation, .freeExpression: return "mic.fill"
        case .realCommunication: return "checkmark.message.fill"
        case .feedbackCorrection:
            return coach.feedbackCorrectionActionTitle.contains("Analyze")
                ? "waveform.badge.magnifyingglass"
                : "arrow.triangle.2.circlepath"
        }
    }

    private func learningActionColor(for stage: LearningPathStage) -> Color {
        if coach.isRecording { return Theme.danger }
        switch stage {
        case .realCommunication: return Theme.success
        case .feedbackCorrection: return Theme.accent
        default: return Theme.primary
        }
    }

    private func learningActionDisabled(for stage: LearningPathStage) -> Bool {
        if coach.selectedLineID == nil { return true }
        if stage == .feedbackCorrection || stage == .realCommunication { return coach.isAnalyzing }
        return false
    }

    private func performLearningAction(_ stage: LearningPathStage) {
        switch stage {
        case .input:
            coach.completeInputUnderstanding()
        case .noticing:
            coach.completeNoticing(with: coach.currentLearningTarget)
        case .shadowing:
            coach.speakSentence()
        case .retrieval, .spacedReview:
            coach.beginImmediateRecall()
        case .transformation:
            coach.isRecording
                ? coach.stopRecording(autoAnalyze: false)
                : coach.startRecording(activity: .transformation)
        case .freeExpression:
            coach.isRecording
                ? coach.stopRecording(autoAnalyze: false)
                : coach.startRecording(activity: .freeExpression)
        case .realCommunication:
            releaseTextInputFocus()
            coach.markRealCommunicationComplete()
        case .feedbackCorrection:
            if coach.isRecording {
                coach.stopRecording(autoAnalyze: false)
            } else {
                coach.performFeedbackCorrectionAction()
            }
        }
    }

    private var sentenceStage: some View {
        Group {
            if coach.isReviewSessionActive && !coach.isReviewAnswerRevealed {
                reviewCueStage
            } else if coach.isSentenceVisible {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        InteractiveSentenceView(text: coach.sentence, fontSize: practiceTextSize.pointSize)
                            .id(coach.selectedLineID)

                        if !coach.sentenceTranslation.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("Sentence Translation", systemImage: "character.book.closed")
                                        .font(.callout.weight(.semibold))
                                    Spacer()
                                    Button {
                                        coach.sentenceTranslation = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                }

                                ScrollView {
                                    Text(coach.sentenceTranslation)
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.trailing, 4)
                                }
                                .frame(maxHeight: 180)
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
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 430, alignment: .topLeading)
                .background(subtleBackground)
            } else {
                VStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(Theme.primary.opacity(0.12))
                            .frame(width: 74, height: 74)
                        Image(systemName: "ear.and.waveform")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(Theme.primary)
                    }
                    Text("Sentence Hidden")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    HStack(spacing: 8) {
                        ForEach(Array(["Listen", "Repeat", "Review"].enumerated()), id: \.offset) { index, step in
                            HStack(spacing: 6) {
                                Text("\(index + 1)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 16, height: 16)
                                    .background(Theme.primary.opacity(0.72))
                                    .clipShape(Circle())
                                Text(step)
                            }
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                            .background(Theme.panel.opacity(0.88))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 210)
                .background(subtleBackground)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.border)
        )
    }

    private var reviewCueStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recall from context")
                            .font(.headline)
                        Text(coach.selectedLine?.source ?? "Review")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                if let previousReviewLine {
                    Label("Previous line", systemImage: "text.insert")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(previousReviewLine.text)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label("Opening line", systemImage: "text.badge.plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(coach.selectedLine?.title ?? "First sentence")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                }

                if coach.isReviewChineseHintVisible {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Chinese rescue hint", systemImage: "character.book.closed")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.warning)
                        Text(coach.sentenceTranslation.isEmpty ? "Translating..." : coach.sentenceTranslation)
                            .font(.callout)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 430, alignment: .topLeading)
        .background(subtleBackground)
    }

    private var reviewRatingBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("How was recall?", systemImage: "checkmark.circle")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("Use Again when any part was forgotten")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(ReviewRating.allCases) { rating in
                        reviewRatingButton(rating)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(ReviewRating.allCases) { rating in
                        reviewRatingButton(rating)
                    }
                }
            }
        }
        .padding(12)
        .background(subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.border)
        )
    }

    private func reviewRatingButton(_ rating: ReviewRating) -> some View {
        let color = reviewRatingColor(rating)
        return Button {
            coach.rateCurrentReview(rating, in: allLines)
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: reviewRatingIcon(rating))
                    Text(rating.label)
                }
                .font(.callout.weight(.semibold))
                Text(coach.reviewIntervalDescription(for: rating))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(color)
        .background(color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.3))
        )
        .help(rating.recallDescription)
    }

    private func reviewRatingColor(_ rating: ReviewRating) -> Color {
        switch rating {
        case .again: return Theme.danger
        case .hard: return Theme.warning
        case .good: return Theme.primary
        case .easy: return Theme.success
        }
    }

    private func reviewRatingIcon(_ rating: ReviewRating) -> String {
        switch rating {
        case .again: return "arrow.counterclockwise"
        case .hard: return "exclamationmark"
        case .good: return "checkmark"
        case .easy: return "bolt.fill"
        }
    }

    private var actionDock: some View {
        GeometryReader { proxy in
            actionRow(compact: proxy.size.width < 520)
        }
        .frame(height: 64)
    }

    private func actionRow(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 10) {
            if coach.isReviewSessionActive && !coach.isReviewAnswerRevealed {
                actionButton(icon: "character.book.closed", title: "Hint", shortcut: "", color: Theme.warning, compact: compact) {
                    coach.showReviewChineseHint()
                }
                actionButton(icon: coach.isRecording ? "stop.fill" : "mic.fill", title: coach.isRecording ? "Stop" : "Record", shortcut: "Space", color: coach.isRecording ? Theme.danger : Theme.success, compact: compact) {
                    coach.toggleRecording()
                }
                actionButton(icon: "eye.fill", title: "Reveal", shortcut: "H", color: Theme.primary, compact: compact) {
                    coach.revealReviewAnswer()
                }
            } else if coach.isReviewSessionActive {
                actionButton(icon: "speaker.wave.2.fill", title: "Listen", shortcut: "↑", color: Theme.primary, compact: compact) {
                    coach.speakSentence()
                }
                actionButton(icon: coach.isRecording ? "stop.fill" : "mic.fill", title: coach.isRecording ? "Stop" : "Record", shortcut: "Space", color: coach.isRecording ? Theme.danger : Theme.success, compact: compact) {
                    coach.toggleRecording()
                }
                actionButton(icon: "play.fill", title: "Playback", shortcut: "P", color: .gray, compact: compact) {
                    coach.playRecording()
                }
            } else {
                actionButton(icon: "speaker.wave.2.fill", title: "Listen", shortcut: "↑", color: Theme.primary, compact: compact) {
                    coach.speakSentence()
                }
                actionButton(
                    icon: coach.isRecording ? "stop.fill" : "mic.fill",
                    title: coach.isRecording ? "Stop" : guidedRecordTitle,
                    shortcut: "Space",
                    color: coach.isRecording ? Theme.danger : Theme.success,
                    compact: compact
                ) {
                    coach.toggleRecording()
                }
                actionButton(icon: "chevron.right", title: "Next", shortcut: "→", color: .gray, compact: compact) {
                    coach.chooseNext(in: currentGroupLines)
                }
            }
        }
    }

    private var guidedRecordTitle: String {
        switch coach.currentLearningStage() {
        case .transformation: return "Transform"
        case .freeExpression: return "Free Speak"
        case .feedbackCorrection: return "Retry"
        default: return "Record"
        }
    }

    private func actionButton(icon: String, title: String, shortcut: String, color: Color, compact: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: compact ? 0 : 5) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 20 : 22, weight: .semibold))
                    .frame(height: compact ? 22 : 24)

                if !compact {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minWidth: compact ? 46 : 76, minHeight: compact ? 46 : 64)
            .overlay(alignment: .topTrailing) {
                if !compact && !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(color == .gray ? Color.secondary : Color.white.opacity(0.88))
                        .padding(.top, 7)
                        .padding(.trailing, 8)
                }
            }
        }
        .buttonStyle(ActionTileButtonStyle(color: color))
        .help(shortcut.isEmpty ? title : "\(title) (\(shortcut))")
    }

    private var playbackControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    referenceAudioHeading
                    Spacer()
                    automationToggles
                }
                VStack(alignment: .leading, spacing: 10) {
                    referenceAudioHeading
                    automationToggles
                }
            }

            if coach.selectedLine?.hasSourceAudio == true {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .foregroundStyle(Theme.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Original source clip")
                            .font(.callout.weight(.semibold))
                        Text("Voice and TTS speed are bypassed for this sentence.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    repeatStepper
                }
                .padding(10)
                .background(Theme.panel.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        voicePicker
                        speedPicker
                        repeatStepper
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        voicePicker
                        speedPicker
                        repeatStepper
                    }
                }
            }
        }
        .padding(14)
        .background(subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var referenceAudioHeading: some View {
        Label(
            coach.selectedLine?.hasSourceAudio == true ? "Source Audio" : "TTS Voice",
            systemImage: coach.selectedLine?.hasSourceAudio == true ? "waveform" : "speaker.wave.2"
        )
        .font(.headline)
    }

    private var automationToggles: some View {
        HStack(spacing: 12) {
            Toggle("Auto record", isOn: $coach.autoRecordAfterListen)
                .toggleStyle(.switch)
            Toggle("Auto analyze", isOn: $coach.autoAnalyzeAfterRecording)
                .toggleStyle(.switch)
        }
    }

    private var repeatStepper: some View {
        Stepper("Repeat \(coach.listenRepeats)x", value: $coach.listenRepeats, in: 1...5)
            .frame(width: 120)
    }

    private var speedPicker: some View {
        HStack(spacing: 10) {
            Text("Speed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Speed", selection: $coach.speechRate) {
                Text("Slow").tag(135.0)
                Text("Calm").tag(155.0)
                Text("Normal").tag(175.0)
                Text("Fast").tag(200.0)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
        }
    }

    private var voicePicker: some View {
        HStack(spacing: 10) {
            Text("Voice")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Voice", selection: $coach.selectedVoiceIdentifier) {
                ForEach(coach.englishVoices) { voice in
                    Text(voice.displayName).tag(voice.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 180)
        }
    }

    private var recordingPanel: some View {
        let attempts = coach.currentProgress().attempts
        let visibleAttempts = showingAllAttempts ? attempts : Array(attempts.prefix(5))

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: coach.isRecording ? "waveform.circle.fill" : (coach.hasRecording ? "waveform.badge.checkmark" : "waveform"))
                    .font(.title2)
                    .foregroundStyle(coach.isRecording ? Theme.danger : (coach.hasRecording ? Theme.success : Color.secondary))
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(recordingTitle)
                        .font(.headline)
                    Text(progressSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if coach.hasRecording && !coach.isRecording {
                    Button(action: coach.playRecording) {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Play latest recording")
                }

                if coach.hasRecording || coach.isRecording {
                    Button(action: coach.discardCurrentRecording) {
                        Image(systemName: coach.isRecording ? "xmark" : "trash")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help(coach.isRecording ? "Discard this recording" : "Delete the latest temporary recording")
                }
            }

            if !attempts.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Saved Attempts")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(attempts.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(visibleAttempts) { attempt in
                        savedAttemptRow(attempt)
                    }

                    if attempts.count > 5 {
                        Button {
                            withAnimation(.snappy(duration: 0.18)) {
                                showingAllAttempts.toggle()
                            }
                        } label: {
                            Label(
                                showingAllAttempts ? "Show Recent" : "Show All \(attempts.count)",
                                systemImage: showingAllAttempts ? "chevron.up" : "chevron.down"
                            )
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.primary)
                    }
                }
            }
        }
        .padding(14)
        .background(subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func savedAttemptRow(_ attempt: RecordingAttempt) -> some View {
        let isSelected = coach.selectedAttemptRelativePathForAnalysis == attempt.relativePath
        let isHovered = hoveredAttemptID == attempt.id
        let score = attempt.analysisCache?.localAnalysis.accuracy

        return HStack(spacing: 9) {
            Button {
                coach.playAttempt(attempt)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? Color.white : Theme.primary)
                    .frame(width: 27, height: 27)
                    .background(isSelected ? Theme.primary : Theme.primary.opacity(0.11))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Play this recording")

            Button {
                coach.selectAttempt(attempt)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatAttemptDate(attempt.date))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(attemptDetail(attempt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    if let score {
                        Text("\(Int(score.rounded()))%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(scoreColor(score))
                            .monospacedDigit()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                pendingLibraryDeletion = .attempt(attempt)
            } label: {
                Image(systemName: "trash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.danger)
                    .frame(width: 25, height: 25)
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isSelected ? 1 : 0)
            .accessibilityHidden(!(isHovered || isSelected))
            .help("Delete this recording")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            isSelected
                ? Theme.primary.opacity(0.10)
                : (isHovered ? Theme.panel.opacity(0.72) : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.primary)
                    .frame(width: 3)
                    .padding(.vertical, 7)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredAttemptID = hovering ? attempt.id : nil
        }
        .contextMenu {
            Button {
                coach.selectAttempt(attempt)
            } label: {
                Label("Load Analysis", systemImage: "chart.bar.doc.horizontal")
            }
            Button {
                coach.playAttempt(attempt)
            } label: {
                Label("Play Recording", systemImage: "play.fill")
            }
            Divider()
            Button(role: .destructive) {
                pendingLibraryDeletion = .attempt(attempt)
            } label: {
                Label("Delete Recording", systemImage: "trash")
            }
        }
    }

    private func attemptDetail(_ attempt: RecordingAttempt) -> String {
        let analysisState: String
        if attempt.resolvedActivity.comparesWithReference {
            analysisState = attempt.analysisCache == nil ? "Not analyzed" : "Analysis saved"
        } else {
            if let cache = attempt.openResponseAnalysisCache {
                analysisState = cache.coachFeedback == nil ? "Transcript saved" : "Feedback saved"
            } else {
                analysisState = "Not analyzed"
            }
        }
        return "\(formatAttemptDuration(attempt.duration)) · \(attempt.resolvedActivity.label) · \(analysisState)"
    }

    private var progressSummary: String {
        if coach.isRecording {
            return "Speak clearly, then press Space to stop"
        }
        let progress = coach.currentProgress()
        if let last = progress.lastPracticedAt {
            return "\(progress.practiceCount) attempts, last \(last.formatted(date: .abbreviated, time: .shortened))"
        }
        return "No saved attempts yet"
    }

    private var recordingTitle: String {
        if coach.isRecording {
            return "Recording \(coach.activeRecordingActivity.label)..."
        }
        if coach.hasRecording {
            return "Recording Ready"
        }
        if coach.analyzableRecordingURL != nil {
            return "Saved Attempt Available"
        }
        return "No Recording"
    }

    private var collapsedFeedbackPanel: some View {
        VStack(spacing: 14) {
            Button {
                isFeedbackSidebarCollapsed = false
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .background(Theme.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .help("Show feedback")

            Image(systemName: "quote.bubble.fill")
                .font(.title3)
                .foregroundStyle(.secondary)

            if let score = coach.recordingAnalysis?.accuracy {
                Text("\(Int(score.rounded()))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(scoreColor(score))
                    .rotationEffect(.degrees(90))
                    .frame(width: 42, height: 42)
            }

            Spacer()
        }
        .padding(.top, 4)
        .frame(width: 56)
    }

    private var feedbackPipelineSummary: String {
        if let activity = selectedOpenResponseActivity {
            var parts = ["Whisper small", activity.label]
            if coach.useAICoach { parts.append(coach.feedbackProvider.label) }
            return parts.joined(separator: " · ")
        }
        var parts = ["Whisper small"]
        if coach.useProsodyAnalysis { parts.append("Rhythm") }
        if coach.useAzureAssessment { parts.append("Azure") }
        if coach.useAICoach { parts.append("Meaning: \(coach.feedbackProvider.label)") }
        return parts.joined(separator: " · ")
    }

    private var feedbackPanel: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Feedback")
                            .font(scaledFeedbackFont(20, scale: feedbackTextSize.scale, weight: .semibold, design: .rounded))
                        Text(feedbackPipelineSummary)
                            .font(scaledFeedbackFont(11, scale: feedbackTextSize.scale))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if coach.isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        settingsSection = .analysis
                        showingAppSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Analysis settings")

                    Button {
                        isFeedbackSidebarCollapsed = true
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Collapse feedback")
                }

                Button {
                    coach.analyzeSelectedAttempt(forceRefresh: true)
                } label: {
                    Label(
                        coach.isAnalyzing ? "Analyzing..." : feedbackAnalyzeTitle,
                        systemImage: "waveform.badge.magnifyingglass"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.accent))
                .disabled(coach.isAnalyzing || coach.isRecording || coach.analyzableRecordingURL == nil)

                if coach.isAnalyzing {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                        Text(coach.status)
                            .font(scaledFeedbackFont(12, scale: feedbackTextSize.scale))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .transition(.opacity)
                }

                if let recordingAnalysis = coach.recordingAnalysis {
                    recordingAnalysisPanel(recordingAnalysis)
                }

                if let openResponse = coach.selectedOpenResponseAnalysis {
                    openResponseTranscriptPanel(openResponse)
                }

                if coach.analysis.isEmpty && coach.recordingAnalysis == nil {
                    VStack(spacing: 14) {
                        Image(systemName: feedbackEmptyIcon)
                            .font(.system(size: 38))
                            .foregroundStyle(Theme.accent.opacity(0.55))
                        Text(feedbackEmptyTitle)
                            .font(scaledFeedbackFont(15, scale: feedbackTextSize.scale, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(feedbackEmptyMessage)
                            .font(scaledFeedbackFont(12, scale: feedbackTextSize.scale))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 140, maxHeight: 220)
                    .background(subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if !coach.analysis.isEmpty {
                    CoachFeedbackView(markdown: coach.analysis)
                        .equatable()
                        .textSelection(.enabled)
                }

                if coach.recordingAnalysis != nil || coach.selectedOpenResponseAnalysis != nil {
                    codexFollowUpPanel
                }

                statsPanel
            }
            .padding(2)
        }
        .environment(\.feedbackTextScale, feedbackTextSize.scale)
    }

    private var selectedOpenResponseActivity: PracticeActivity? {
        guard let activity = coach.selectedAttemptActivity, !activity.comparesWithReference else { return nil }
        return activity
    }

    private var feedbackAnalyzeTitle: String {
        if let activity = selectedOpenResponseActivity {
            return coach.selectedOpenResponseAnalysis == nil
                ? "Analyze \(activity.label)"
                : "Analyze \(activity.label) Again"
        }
        return coach.recordingAnalysis == nil ? "Analyze Shadowing" : "Analyze Shadowing Again"
    }

    private func openResponseTranscriptPanel(_ cache: OpenResponseAnalysisCache) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: cache.activity == .transformation ? "arrow.triangle.branch" : "quote.bubble.fill")
                    .foregroundStyle(Theme.accent)
                Text("What the app recognized")
                    .font(scaledFeedbackFont(13, scale: feedbackTextSize.scale, weight: .semibold))
                Spacer()
                Text(cache.activity.label)
                    .font(scaledFeedbackFont(10, scale: feedbackTextSize.scale, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(cache.transcript.isEmpty ? "No speech recognized." : cache.transcript)
                .font(scaledFeedbackFont(13, scale: feedbackTextSize.scale))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text("Open responses are judged by task success and natural English, not word-for-word recall.")
                .font(scaledFeedbackFont(10, scale: feedbackTextSize.scale))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .background(subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var feedbackEmptyIcon: String {
        if selectedOpenResponseActivity != nil { return "quote.bubble" }
        return coach.analyzableRecordingURL == nil ? "mic" : "waveform.badge.magnifyingglass"
    }

    private var feedbackEmptyTitle: String {
        if let activity = selectedOpenResponseActivity { return "\(activity.label) saved" }
        return coach.analyzableRecordingURL == nil ? "Record a sentence first" : "Ready to analyze"
    }

    private var feedbackEmptyMessage: String {
        if selectedOpenResponseActivity != nil {
            return "Analyze this response for stage-specific feedback. It will not be scored as an incorrect copy of the reference."
        }
        return coach.analyzableRecordingURL == nil
            ? "Listen, record your answer, then come back here."
            : "Word comparison is local. Optional services run only when enabled."
    }

    private var codexFollowUpPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(scaledFeedbackFont(13, scale: feedbackTextSize.scale, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ask Codex")
                        .font(scaledFeedbackFont(14, scale: feedbackTextSize.scale, weight: .semibold))
                    Text(
                        selectedOpenResponseActivity == nil
                            ? "Continue with this recording's evidence"
                            : "Continue with this stage's transcript and goal"
                    )
                        .font(scaledFeedbackFont(10, scale: feedbackTextSize.scale))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if coach.isAskingCodex {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if coach.recordingAnalysis?.isPerfectWordRecall == true,
               coach.coachConversation.isEmpty {
                Label("100% word recall. Ask only if you want a deeper explanation.", systemImage: "checkmark.circle.fill")
                    .font(scaledFeedbackFont(12, scale: feedbackTextSize.scale))
                    .foregroundStyle(Theme.success)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(coach.coachConversation) { message in
                CoachConversationMessageView(message: message)
            }

            HStack(spacing: 8) {
                TextField("Ask about wording, meaning, or memory...", text: $coachQuestion)
                    .font(scaledFeedbackFont(13, scale: feedbackTextSize.scale))
                    .textFieldStyle(.plain)
                    .focused($focusedInput, equals: .coachQuestion)
                    .onSubmit(sendCoachQuestion)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.border)
                    )

                Button(action: sendCoachQuestion) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(coachQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coach.isAskingCodex)
                .opacity(coachQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coach.isAskingCodex ? 0.45 : 1)
                .help("Ask local Codex")
            }
        }
        .padding(11)
        .background(subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sendCoachQuestion() {
        let question = coachQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !coach.isAskingCodex else { return }
        coachQuestion = ""
        releaseTextInputFocus()
        coach.askCodex(question)
    }

    private var appSettingsSheet: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.primary)
                Text("Settings")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Spacer()
                Button("Done") {
                    showingAppSettings = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Picker("Settings section", selection: $settingsSection) {
                ForEach(AppSettingsSection.allCases) { section in
                    Label(section.label, systemImage: section.icon).tag(section)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                settingsContent
                    .padding(20)
            }
        }
        .frame(width: 570, height: 520)
        .background(Theme.appBackground)
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch settingsSection {
        case .appearance:
            appearanceSettings
        case .practice:
            practiceSettings
        case .analysis:
            analysisSettings
        }
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsTitle("Appearance", icon: "paintbrush.fill")

            settingsRow("Color theme", icon: "circle.lefthalf.filled") {
                Picker("Color theme", selection: Binding(
                    get: { appAppearance },
                    set: { appAppearanceRaw = $0.rawValue }
                )) {
                    ForEach(AppAppearanceOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            settingsDivider

            settingsRow("Feedback text", icon: "sidebar.right") {
                Picker("Feedback text", selection: Binding(
                    get: { feedbackTextSize },
                    set: { feedbackTextSizeRaw = $0.rawValue }
                )) {
                    ForEach(FeedbackTextSizeOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            settingsDivider

            settingsRow("Practice text", icon: "textformat.size") {
                Picker("Practice text", selection: Binding(
                    get: { practiceTextSize },
                    set: { practiceTextSizeRaw = $0.rawValue }
                )) {
                    ForEach(PracticeTextSizeOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
        }
    }

    private var practiceSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsTitle("Practice", icon: "mic.fill")

            settingsRow("TTS voice", icon: "person.wave.2") {
                Picker("TTS voice", selection: $coach.selectedVoiceIdentifier) {
                    ForEach(coach.englishVoices) { voice in
                        Text(voice.displayName).tag(voice.id)
                    }
                }
                .labelsHidden()
                .frame(width: 260)
            }
            settingsDivider

            settingsRow("TTS speed", icon: "speedometer") {
                Picker("TTS speed", selection: $coach.speechRate) {
                    Text("Slow").tag(135.0)
                    Text("Calm").tag(155.0)
                    Text("Normal").tag(175.0)
                    Text("Fast").tag(200.0)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            settingsDivider

            settingsRow("Listen repeats", icon: "repeat") {
                Stepper("\(coach.listenRepeats)x", value: $coach.listenRepeats, in: 1...5)
                    .frame(width: 110)
            }
            settingsDivider

            settingsRow("Auto record", icon: "record.circle") {
                Toggle("Auto record", isOn: $coach.autoRecordAfterListen)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            settingsDivider

            settingsRow("Auto analyze", icon: "waveform.badge.magnifyingglass") {
                Toggle("Auto analyze", isOn: $coach.autoAnalyzeAfterRecording)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            settingsDivider

            settingsRow("Require full recording", icon: "timer") {
                Toggle("Require full recording", isOn: $coach.requireFullReferenceLength)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            settingsDivider

            settingsRow("Review scheduler", icon: "brain.head.profile") {
                Label("Adaptive FSRS-6", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.success)
            }
            settingsDivider

            settingsRow("Memory target", icon: "target") {
                Picker("Memory target", selection: $coach.desiredReviewRetention) {
                    ForEach(ReviewRetentionOption.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            settingsDivider

            settingsRow("Daily review cap", icon: "calendar.badge.clock") {
                Picker("Daily review cap", selection: $coach.dailyReviewLimit) {
                    ForEach([10, 20, 30, 50], id: \.self) { limit in
                        Text("\(limit)").tag(limit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
        }
    }

    private var analysisSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsTitle("Analysis", icon: "waveform.badge.magnifyingglass")

            settingsRow("Content comparison", icon: "text.badge.checkmark") {
                Label("Always on", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.success)
            }
            settingsDivider

            settingsRow("Rhythm & pitch", icon: "metronome") {
                Toggle("Rhythm & pitch", isOn: $coach.useProsodyAnalysis)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            settingsDivider

            settingsRow("Azure pronunciation", icon: "waveform.badge.magnifyingglass") {
                Toggle("Azure pronunciation", isOn: $coach.useAzureAssessment)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            settingsDivider

            settingsRow("Meaning & memory", icon: "brain.head.profile") {
                Toggle("Meaning & memory", isOn: $coach.useAICoach)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if coach.useAICoach {
                settingsDivider
                settingsRow("Coach depth", icon: "text.alignleft") {
                    Picker("Coach depth", selection: $coach.coachFeedbackDepth) {
                        ForEach(CoachFeedbackDepth.allCases) { depth in
                            Text(depth.label).tag(depth)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }

                settingsDivider
                settingsRow("AI coach", icon: "sparkles") {
                    Picker("AI coach", selection: $coach.feedbackProvider) {
                        ForEach(CoachFeedbackProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }

                settingsDivider
                if coach.feedbackProvider == .gemini {
                    settingsRow("Gemini key", icon: "key.fill") {
                        HStack(spacing: 8) {
                            SecureField("API key", text: $coach.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 210)
                            Button(action: coach.saveApiKey) {
                                Image(systemName: "checkmark")
                            }
                            .buttonStyle(IconButtonStyle())
                            .help("Save Gemini API key")
                        }
                    }
                } else {
                    settingsRow("Local model", icon: "bolt.fill") {
                        Text("GPT-5.6 Terra")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .disabled(coach.isAnalyzing)
    }

    private func settingsTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .padding(.bottom, 14)
    }

    private func settingsRow<Control: View>(
        _ title: String,
        icon: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.primary)
                .frame(width: 24)
            Text(title)
                .font(.body)
            Spacer(minLength: 16)
            control()
        }
        .frame(minHeight: 46)
    }

    private var settingsDivider: some View {
        Divider()
            .padding(.leading, 36)
    }

    private func recordingAnalysisPanel(_ result: RecordingAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Recall Match", systemImage: "text.badge.checkmark")
                    .font(scaledFeedbackFont(15, scale: feedbackTextSize.scale, weight: .semibold))
                Spacer()
                Text("WORDS ONLY")
                    .font(scaledFeedbackFont(9, scale: feedbackTextSize.scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.pill)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Image(systemName: "info.circle")
                    .font(scaledFeedbackFont(12, scale: feedbackTextSize.scale))
                    .foregroundStyle(.secondary)
                    .help("Compares recognized words only. Punctuation and capitalization are ignored. Recognition can be imperfect.")
                Text("\(Int(result.accuracy.rounded()))%")
                    .font(scaledFeedbackFont(22, scale: feedbackTextSize.scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(scoreColor(result.accuracy))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("System heard")
                    .font(scaledFeedbackFont(12, scale: feedbackTextSize.scale, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(result.transcript.isEmpty ? "No stable transcript" : result.transcript)
                    .font(scaledFeedbackFont(14, scale: feedbackTextSize.scale))
                    .textSelection(.enabled)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                alignment: .leading,
                spacing: 7
            ) {
                diffLegend(label: "Matched", color: Theme.success, filled: true)
                diffLegend(label: "Different", color: Theme.warning, filled: true)
                diffLegend(label: "Not heard", color: Theme.danger, filled: true)
                diffLegend(label: "Added", color: Theme.danger, filled: false)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Reference vs You")
                    .font(scaledFeedbackFont(12, scale: feedbackTextSize.scale, weight: .semibold))
                    .foregroundStyle(.secondary)
                WordComparisonView(referenceText: result.referenceText, userText: result.transcript, items: result.items)
            }
            .padding(10)
            .background(Theme.panel.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let substitutions = result.substitutions, !substitutions.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Wording difference", systemImage: "arrow.left.arrow.right")
                        .font(scaledFeedbackFont(12, scale: feedbackTextSize.scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(substitutions) { substitution in
                        HStack(spacing: 8) {
                            Text(substitution.spoken)
                                .font(scaledFeedbackFont(14, scale: feedbackTextSize.scale, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "arrow.right")
                                .font(scaledFeedbackFont(12, scale: feedbackTextSize.scale, weight: .bold))
                                .foregroundStyle(Theme.warning)

                            Text(substitution.expected)
                                .font(scaledFeedbackFont(14, scale: feedbackTextSize.scale, weight: .semibold))
                                .foregroundStyle(Theme.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(7)
                        .background(Theme.warning.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
                .padding(10)
                .background(Theme.panel.opacity(0.78))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if coach.useAzureAssessment, let azure = result.azure, azure.enabled {
                AzurePronunciationPanel(analysis: azure, issues: result.pronunciationIssues ?? [])
            }

            if !result.issueHints.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("What to fix")
                        .font(scaledFeedbackFont(12, scale: feedbackTextSize.scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(result.issueHints, id: \.self) { hint in
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(scaledFeedbackFont(12, scale: feedbackTextSize.scale))
                                .foregroundStyle(Theme.danger)
                                .padding(.top, 1)
                            Text(hint)
                                .font(scaledFeedbackFont(12, scale: feedbackTextSize.scale))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(10)
                .background(Theme.panel.opacity(0.78))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let prosody = result.prosody {
                prosodyPanel(prosody)
            }
        }
        .padding(12)
        .background(subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func prosodyPanel(_ prosody: ProsodyAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Label("Rhythm Compare", systemImage: "metronome")
                    .font(scaledFeedbackFont(12, scale: feedbackTextSize.scale, weight: .semibold))
                Spacer()
                if let reference = prosody.reference {
                    Text("Ref \(Int(reference.speakingRateWpm)) wpm · You \(Int(prosody.user.speakingRateWpm)) wpm")
                        .font(scaledFeedbackFont(10, scale: feedbackTextSize.scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("You \(Int(prosody.user.speakingRateWpm)) wpm")
                        .font(scaledFeedbackFont(10, scale: feedbackTextSize.scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let reference = prosody.reference, reference.speakingRateWpm > 0 {
                RhythmMetricCard(
                    label: "Speed",
                    unit: "wpm",
                    referenceValue: reference.speakingRateWpm,
                    userValue: prosody.user.speakingRateWpm,
                    idealTolerance: max(8, reference.speakingRateWpm * 0.18),
                    warningTolerance: max(14, reference.speakingRateWpm * 0.28),
                    verdict: rhythmSpeedVerdict(user: prosody.user.speakingRateWpm, reference: reference.speakingRateWpm)
                )
                RhythmMetricCard(
                    label: "Pauses",
                    unit: "",
                    referenceValue: Double(reference.pauseCount),
                    userValue: Double(prosody.user.pauseCount),
                    idealTolerance: 1.0,
                    warningTolerance: 2.0,
                    verdict: rhythmPauseVerdict(user: prosody.user.pauseCount, reference: reference.pauseCount)
                )
                RhythmMetricCard(
                    label: "Pause time",
                    unit: "s",
                    referenceValue: reference.pauseDuration,
                    userValue: prosody.user.pauseDuration,
                    idealTolerance: 0.45,
                    warningTolerance: 0.9,
                    verdict: rhythmPauseTimeVerdict(user: prosody.user.pauseDuration, reference: reference.pauseDuration)
                )
            } else {
                HStack(spacing: 8) {
                    statTile(title: "Pauses", value: "\(prosody.user.pauseCount)")
                    statTile(title: "Pause s", value: String(format: "%.1f", prosody.user.pauseDuration))
                    statTile(title: "WPM", value: "\(Int(prosody.user.speakingRateWpm))")
                }
            }

            if !prosody.userStressCandidates.isEmpty {
                Text("Words that sounded more prominent: \(prosody.userStressCandidates.joined(separator: ", "))")
                    .font(scaledFeedbackFont(12, scale: feedbackTextSize.scale))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    showProsodyCurves.toggle()
                } label: {
                    HStack {
                        Label("Pitch / loudness curves", systemImage: showProsodyCurves ? "chevron.down" : "chevron.right")
                        Spacer()
                        Text(showProsodyCurves ? "Hide" : "Show")
                            .font(scaledFeedbackFont(10, scale: feedbackTextSize.scale, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .font(scaledFeedbackFont(12, scale: feedbackTextSize.scale, weight: .semibold))
                }
                .buttonStyle(.plain)

                if showProsodyCurves {
                    Text("Solid line is you. Dashed gray line is the reference. Use these to compare rise/fall, loudness peaks, and where the phrase loses energy.")
                        .font(scaledFeedbackFont(10, scale: feedbackTextSize.scale))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ProsodyCurveView(
                        title: "Pitch contour",
                        userPoints: prosody.user.pitchCurve,
                        referencePoints: prosody.reference?.pitchCurve,
                        color: Theme.primary
                    )
                    .frame(height: 58)
                    ProsodyCurveView(
                        title: "Intensity / loudness",
                        userPoints: prosody.user.intensityCurve,
                        referencePoints: prosody.reference?.intensityCurve,
                        color: Theme.success
                    )
                    .frame(height: 58)
                }
            }
            .padding(9)
            .background(Theme.panel.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func rhythmSpeedVerdict(user: Double, reference: Double) -> String {
        let ratio = user / max(reference, 1)
        if ratio < 0.82 { return "Slower than the reference. Keep the words clear, then compress the phrase." }
        if ratio > 1.22 { return "Faster than the reference. Slow down and keep the ending words clear." }
        return "Close to the reference speed."
    }

    private func rhythmPauseVerdict(user: Int, reference: Int) -> String {
        let delta = user - reference
        if delta >= 2 { return "More pauses than the reference. Try grouping words into longer chunks." }
        if delta <= -2 { return "Fewer pauses than the reference. Make sure you are not rushing through phrase boundaries." }
        return "Pause count is close to the reference."
    }

    private func rhythmPauseTimeVerdict(user: Double, reference: Double) -> String {
        let delta = user - reference
        if delta > 0.6 { return "Your pauses are longer. Practice the transition between phrase chunks." }
        if delta < -0.6 { return "Your pauses are shorter. Leave a little room where the reference breathes." }
        return "Total pause time is close to the reference."
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 85...:
            return Theme.success
        case 65..<85:
            return Theme.primary
        default:
            return Theme.danger
        }
    }

    private func diffLegend(label: String, color: Color, filled: Bool) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3)
                .fill(filled ? color.opacity(0.18) : Color.clear)
                .frame(width: 13, height: 13)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(color.opacity(0.45))
                )
            Text(label)
                .font(scaledFeedbackFont(10, scale: feedbackTextSize.scale, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var statsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    showingPracticeStats.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Label("Practice Stats", systemImage: "calendar")
                        .font(scaledFeedbackFont(14, scale: feedbackTextSize.scale, weight: .semibold))
                    Spacer()
                    Text("\(coach.attempts(on: Date())) today · \(coach.currentStreak())d streak")
                        .font(scaledFeedbackFont(12, scale: feedbackTextSize.scale))
                        .foregroundStyle(.secondary)
                    Image(systemName: showingPracticeStats ? "chevron.down" : "chevron.right")
                        .font(scaledFeedbackFont(12, scale: feedbackTextSize.scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showingPracticeStats {
                Divider()
                HStack(spacing: 8) {
                    statTile(title: "Today", value: "\(coach.attempts(on: Date()))")
                    statTile(title: "Streak", value: "\(coach.currentStreak())d")
                    statTile(title: "Total", value: "\(coach.allAttempts().count)")
                }

                calendarHeatmap
            }
        }
        .padding(11)
        .background(subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(scaledFeedbackFont(18, scale: feedbackTextSize.scale, weight: .semibold, design: .rounded))
            Text(title)
                .font(scaledFeedbackFont(10, scale: feedbackTextSize.scale, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.panel.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var calendarHeatmap: some View {
        let days = coach.recentDailyCounts()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

        return LazyVGrid(columns: columns, spacing: 5) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, item in
                RoundedRectangle(cornerRadius: 3)
                    .fill(heatColor(for: item.count))
                    .frame(height: 14)
                    .help("\(item.date.formatted(date: .abbreviated, time: .omitted)): \(item.count) attempts")
            }
        }
    }

    private func heatColor(for count: Int) -> Color {
        switch count {
        case 0:
            return Theme.panel.opacity(0.75)
        case 1:
            return Theme.success.opacity(0.28)
        case 2...3:
            return Theme.success.opacity(0.48)
        case 4...6:
            return Theme.success.opacity(0.68)
        default:
            return Theme.success
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func formatAttemptDate(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            return "Today · \(date.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday · \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private func formatAttemptDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 {
            return "\(total)s"
        }
        return formatDuration(seconds)
    }
}

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
    @Environment(\.feedbackTextScale) private var textScale
    let markdown: String

    static func == (lhs: CoachFeedbackView, rhs: CoachFeedbackView) -> Bool {
        lhs.markdown == rhs.markdown
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
                            CoachFeedbackItemRow(item: item, tint: section.tint)
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
    @Environment(\.feedbackTextScale) private var textScale
    let item: CoachFeedbackItem
    let tint: Color

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
