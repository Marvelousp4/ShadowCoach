import Foundation

enum AzureSpeechClient {
    static func assess(audioURL: URL, referenceText: String, key: String, region: String) async throws -> AzurePronunciationAnalysis {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedRegion.isEmpty else {
            throw NSError(domain: "AzureSpeechClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Azure Speech key and region are required."])
        }

        let url = URL(string: "https://\(trimmedRegion).stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=en-US&format=detailed")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("audio/wav; codecs=audio/pcm; samplerate=16000", forHTTPHeaderField: "Content-Type")
        request.setValue(trimmedKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
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
        request.httpBody = try Data(contentsOf: audioURL)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(
                domain: "AzureSpeechClient",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: friendlyHTTPError(statusCode: http.statusCode, data: data)]
            )
        }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let analysis = parse(object)
        let status = (object["RecognitionStatus"] as? String) ?? ""
        if analysis.pronunciation == nil, analysis.words.isEmpty, !status.isEmpty, status.lowercased() != "success" {
            let details = (object["DisplayText"] as? String) ?? (object["ErrorDetails"] as? String) ?? status
            throw NSError(
                domain: "AzureSpeechClient",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Azure could not score this recording: \(details)"]
            )
        }
        if analysis.pronunciation == nil, analysis.words.isEmpty {
            throw NSError(
                domain: "AzureSpeechClient",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Azure returned no pronunciation scores. Try a clearer, longer recording, or check the reference text."]
            )
        }
        return analysis
    }

    private static func parse(_ object: [String: Any]) -> AzurePronunciationAnalysis {
        let best = (object["NBest"] as? [[String: Any]])?.first ?? [:]
        let assessment = best["PronunciationAssessment"] as? [String: Any] ?? [:]
        let words = (best["Words"] as? [[String: Any]] ?? []).map(parseWord)
        return AzurePronunciationAnalysis(
            pronunciation: number(assessment["PronScore"]) ?? number(best["PronScore"]),
            accuracy: number(assessment["AccuracyScore"]) ?? number(best["AccuracyScore"]),
            fluency: number(assessment["FluencyScore"]) ?? number(best["FluencyScore"]),
            completeness: number(assessment["CompletenessScore"]) ?? number(best["CompletenessScore"]),
            prosody: number(assessment["ProsodyScore"]) ?? number(best["ProsodyScore"]),
            display: (best["Display"] as? String) ?? (object["DisplayText"] as? String) ?? "",
            words: words,
            error: nil
        )
    }

    private static func parseWord(_ object: [String: Any]) -> AzurePronunciationWord {
        let assessment = object["PronunciationAssessment"] as? [String: Any] ?? [:]
        let syllables = object["Syllables"] as? [[String: Any]] ?? []
        let nestedPhonemes = syllables.flatMap { $0["Phonemes"] as? [[String: Any]] ?? [] }
        let directPhonemes = object["Phonemes"] as? [[String: Any]] ?? []
        let phonemes = (directPhonemes + nestedPhonemes).map { unit in
            let unitAssessment = unit["PronunciationAssessment"] as? [String: Any] ?? [:]
            return AzurePronunciationUnit(
                text: (unit["Phoneme"] as? String) ?? "",
                accuracy: number(unitAssessment["AccuracyScore"]) ?? number(unit["AccuracyScore"])
            )
        }
        return AzurePronunciationWord(
            text: (object["Word"] as? String) ?? "",
            accuracy: number(assessment["AccuracyScore"]) ?? number(object["AccuracyScore"]),
            errorType: (assessment["ErrorType"] as? String) ?? (object["ErrorType"] as? String),
            phonemes: phonemes
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func friendlyHTTPError(statusCode: Int, data: Data) -> String {
        let detail = String(data: data, encoding: .utf8) ?? ""
        switch statusCode {
        case 401, 403:
            return "Azure rejected the Speech key or region. Open Settings and confirm the Speech key matches region. Details: \(detail)"
        case 400:
            return "Azure could not read the request audio. Record again and make sure the recording is not empty. Details: \(detail)"
        case 408, 429:
            return "Azure is busy or rate-limited. Wait a moment and tap Analyze Again. Details: \(detail)"
        case 500...599:
            return "Azure service error. Try again in a moment. Details: \(detail)"
        default:
            return "Azure request failed with HTTP \(statusCode). Details: \(detail)"
        }
    }
}
