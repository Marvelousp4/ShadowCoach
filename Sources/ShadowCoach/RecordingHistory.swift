import Foundation

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

    var bestAnalyzedAccuracy: Double? {
        attempts.compactMap { attempt in
            guard let accuracy = attempt.analysisCache?.localAnalysis.accuracy,
                  accuracy.isFinite else { return nil }
            return min(100, max(0, accuracy))
        }.max()
    }
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
