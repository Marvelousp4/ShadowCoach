import Foundation
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published var lines: [PracticeLine] = []
    @Published var selectedLineID: UUID?
    @Published var status = "Import a Shadow Coach bundle to begin."
    @Published var practiceState = PersistedPracticeState()
    @Published var localBundles: [URL] = []
    @AppStorage("azureSpeechKey") var azureSpeechKey = ""
    @AppStorage("azureSpeechRegion") var azureSpeechRegion = "eastus"

    private let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    var selectedLine: PracticeLine? {
        guard let selectedLineID else { return lines.first }
        return lines.first { $0.id == selectedLineID } ?? lines.first
    }

    var groupedSources: [String] {
        Array(Set(lines.map(\.source))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func lines(for source: String) -> [PracticeLine] {
        sortedLines(lines.filter { $0.source == source })
    }

    func progress(for line: PracticeLine) -> PracticeProgress {
        practiceState.progress[line.id] ?? PracticeProgress()
    }

    func latestAttempt(for line: PracticeLine) -> RecordingAttempt? {
        progress(for: line).attempts.first
    }

    func isFavorite(_ line: PracticeLine) -> Bool {
        practiceState.favorites.contains(line.id)
    }

    func toggleFavorite(_ line: PracticeLine) {
        if practiceState.favorites.contains(line.id) {
            practiceState.favorites.remove(line.id)
        } else {
            practiceState.favorites.insert(line.id)
        }
        try? savePractice()
    }

    func recordingURL(for attempt: RecordingAttempt) -> URL {
        documentsURL
            .appendingPathComponent("Recordings", isDirectory: true)
            .appendingPathComponent(attempt.fileName)
    }

    func sortedLines(_ input: [PracticeLine]) -> [PracticeLine] {
        input.sorted { lhs, rhs in
            if lhs.source != rhs.source {
                return lhs.source.localizedStandardCompare(rhs.source) == .orderedAscending
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    func choose(_ line: PracticeLine) {
        selectedLineID = line.id
        status = "Loaded: \(line.title)"
    }

    func load() {
        do {
            refreshLocalBundles()
            let libraryURL = documentsURL.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath: libraryURL.path) {
                let data = try Data(contentsOf: libraryURL)
                lines = sortedLines(try JSONDecoder.shadowCoach.decode([PracticeLine].self, from: data))
                selectedLineID = selectedLineID ?? lines.first?.id
                status = "Loaded \(lines.count) lines."
            }
            let practiceURL = documentsURL.appendingPathComponent("practice.json")
            if FileManager.default.fileExists(atPath: practiceURL.path) {
                let data = try Data(contentsOf: practiceURL)
                practiceState = try JSONDecoder.shadowCoach.decode(PersistedPracticeState.self, from: data)
            }
            let providerURL = documentsURL.appendingPathComponent("provider-config.json")
            if FileManager.default.fileExists(atPath: providerURL.path) {
                let data = try Data(contentsOf: providerURL)
                let config = try JSONDecoder.shadowCoach.decode(MobileProviderConfig.self, from: data)
                if let azure = config.azure {
                    if let speechKey = azure.speechKey, !speechKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        azureSpeechKey = speechKey
                    }
                    if let region = azure.region, !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        azureSpeechRegion = region
                    }
                }
            }
        } catch {
            status = "Load failed: \(error.localizedDescription)"
        }
    }

    func refreshLocalBundles() {
        let searchRoots = [
            documentsURL,
            documentsURL.appendingPathComponent("Import Bundles", isDirectory: true),
            documentsURL.appendingPathComponent("Inbox", isDirectory: true)
        ]
        var found: [URL] = []
        for root in searchRoots where FileManager.default.fileExists(atPath: root.path) {
            if let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let url as URL in enumerator where url.pathExtension == "shadowcoachbundle" {
                    found.append(url)
                }
            }
        }
        localBundles = Array(Set(found)).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func importLocalBundle(_ url: URL) {
        importBundle(from: url)
        refreshLocalBundles()
    }

    func importBundle(from url: URL) {
        do {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            let bundle = try JSONDecoder.shadowCoach.decode(ShadowCoachBundle.self, from: data)
            guard bundle.format == "shadowcoach.bundle.v1" else {
                throw NSError(domain: "ShadowCoachBundle", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported bundle format."])
            }

            let mediaDirectory = documentsURL.appendingPathComponent("Media", isDirectory: true)
            try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
            for media in bundle.mediaFiles {
                guard let mediaData = Data(base64Encoded: media.base64) else { continue }
                let output = documentsURL.appendingPathComponent(media.relativePath)
                try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                try mediaData.write(to: output, options: .atomic)
            }
            if let azure = bundle.providerConfig?.azure {
                if let speechKey = azure.speechKey, !speechKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    azureSpeechKey = speechKey
                }
                if let region = azure.region, !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    azureSpeechRegion = region
                }
            }

            var byID = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0) })
            for line in bundle.lines {
                byID[line.id] = line
            }
            lines = sortedLines(Array(byID.values))
            selectedLineID = selectedLineID ?? lines.first?.id
            try saveLibrary()
            status = "Imported \(bundle.lines.count) lines from \(bundle.sources.count) sources."
            refreshLocalBundles()
        } catch {
            status = "Import failed: \(error.localizedDescription)"
        }
    }

    func delete(_ line: PracticeLine) {
        lines.removeAll { $0.id == line.id }
        practiceState.favorites.remove(line.id)
        if let progress = practiceState.progress.removeValue(forKey: line.id) {
            for attempt in progress.attempts {
                try? FileManager.default.removeItem(at: recordingURL(for: attempt))
            }
        }
        if selectedLineID == line.id {
            selectedLineID = lines.first?.id
        }
        do {
            try saveLibrary()
            try savePractice()
            status = "Deleted \(line.title)."
        } catch {
            status = "Delete failed: \(error.localizedDescription)"
        }
    }

    func deleteSource(_ source: String) {
        let sourceLines = lines.filter { $0.source == source }
        for line in sourceLines {
            practiceState.favorites.remove(line.id)
            if let progress = practiceState.progress.removeValue(forKey: line.id) {
                for attempt in progress.attempts {
                    try? FileManager.default.removeItem(at: recordingURL(for: attempt))
                }
            }
        }
        lines.removeAll { $0.source == source }
        if let selectedLineID, sourceLines.contains(where: { $0.id == selectedLineID }) {
            self.selectedLineID = lines.first?.id
        }
        do {
            try saveLibrary()
            try savePractice()
            status = "Deleted \(sourceLines.count) sentences from \(source)."
        } catch {
            status = "Delete failed: \(error.localizedDescription)"
        }
    }

    func deleteAttempt(_ attempt: RecordingAttempt, for line: PracticeLine) {
        guard var progress = practiceState.progress[line.id] else { return }
        progress.attempts.removeAll { $0.id == attempt.id }
        progress.practiceCount = max(0, progress.practiceCount - 1)
        progress.lastPracticedAt = progress.attempts.first?.date
        practiceState.progress[line.id] = progress
        try? FileManager.default.removeItem(at: recordingURL(for: attempt))
        do {
            try savePractice()
            status = "Deleted recording."
        } catch {
            status = "Could not delete recording: \(error.localizedDescription)"
        }
    }

    func mediaURL(for line: PracticeLine) -> URL? {
        guard let relative = line.sourceMediaRelativePath else { return nil }
        let url = documentsURL.appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @discardableResult
    func saveAttempt(line: PracticeLine, recordingURL: URL, duration: Double, analysis: AzurePronunciationAnalysis?) -> RecordingAttempt? {
        do {
            let directory = documentsURL.appendingPathComponent("Recordings", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileName = "\(line.id.uuidString)-\(Int(Date().timeIntervalSince1970)).wav"
            let destination = directory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: recordingURL, to: destination)
            var progress = practiceState.progress[line.id] ?? PracticeProgress()
            progress.practiceCount += 1
            progress.lastPracticedAt = Date()
            let attempt = RecordingAttempt(id: UUID(), date: Date(), duration: duration, fileName: fileName, analysis: analysis)
            progress.attempts.insert(
                attempt,
                at: 0
            )
            progress.attempts = Array(progress.attempts.prefix(20))
            practiceState.progress[line.id] = progress
            try savePractice()
            return attempt
        } catch {
            status = "Could not save attempt: \(error.localizedDescription)"
            return nil
        }
    }

    func updateAttemptAnalysis(_ attemptID: UUID, for line: PracticeLine, analysis: AzurePronunciationAnalysis) {
        guard var progress = practiceState.progress[line.id],
              let index = progress.attempts.firstIndex(where: { $0.id == attemptID })
        else {
            return
        }
        progress.attempts[index].analysis = analysis
        practiceState.progress[line.id] = progress
        do {
            try savePractice()
        } catch {
            status = "Could not save analysis: \(error.localizedDescription)"
        }
    }

    private func saveLibrary() throws {
            let data = try JSONEncoder.pretty.encode(lines)
            try data.write(to: documentsURL.appendingPathComponent("library.json"), options: .atomic)
    }

    func savePractice() throws {
        let data = try JSONEncoder.pretty.encode(practiceState)
        try data.write(to: documentsURL.appendingPathComponent("practice.json"), options: .atomic)
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var shadowCoach: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
