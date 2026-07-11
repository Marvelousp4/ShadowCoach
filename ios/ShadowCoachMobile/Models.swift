import Foundation

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
}

struct PracticeLine: Identifiable, Codable, Hashable {
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
}

struct ShadowCoachBundle: Codable {
    let format: String
    let id: String
    let createdAt: Int
    let sources: [String]
    let lineCount: Int
    let mediaCount: Int
    let lines: [PracticeLine]
    let mediaFiles: [BundleMediaFile]
    let providerConfig: MobileProviderConfig?
}

struct BundleMediaFile: Codable {
    let relativePath: String
    let fileName: String
    let mimeType: String
    let base64: String
}

struct MobileProviderConfig: Codable {
    let azure: MobileAzureConfig?
}

struct MobileAzureConfig: Codable {
    let speechKey: String?
    let region: String?

    enum CodingKeys: String, CodingKey {
        case speechKey = "speech_key"
        case region
    }
}

struct PracticeProgress: Codable, Hashable {
    var practiceCount = 0
    var lastPracticedAt: Date?
    var attempts: [RecordingAttempt] = []
}

struct RecordingAttempt: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let duration: Double
    let fileName: String
    var analysis: AzurePronunciationAnalysis?
}

struct PersistedPracticeState: Codable {
    var favorites: Set<UUID> = []
    var progress: [UUID: PracticeProgress] = [:]
}

struct AzurePronunciationAnalysis: Codable, Hashable {
    var pronunciation: Double?
    var accuracy: Double?
    var fluency: Double?
    var completeness: Double?
    var prosody: Double?
    var display: String
    var words: [AzurePronunciationWord]
    var error: String?
}

struct AzurePronunciationWord: Identifiable, Codable, Hashable {
    var id = UUID()
    let text: String
    let accuracy: Double?
    let errorType: String?
    let phonemes: [AzurePronunciationUnit]

    enum CodingKeys: String, CodingKey {
        case text
        case accuracy
        case errorType
        case phonemes
    }
}

struct AzurePronunciationUnit: Identifiable, Codable, Hashable {
    var id = UUID()
    let text: String
    let accuracy: Double?

    enum CodingKeys: String, CodingKey {
        case text
        case accuracy
    }
}
