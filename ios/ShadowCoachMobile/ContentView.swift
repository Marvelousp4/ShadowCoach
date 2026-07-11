import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var audio: AudioCoach
    @State private var showingImporter = false
    @State private var showingSettings = false
    @State private var searchText = ""
    @State private var filter: LibraryFilter = .all

    var body: some View {
        NavigationStack {
            List {
                if store.lines.isEmpty {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "No Library",
                            systemImage: "tray.and.arrow.down",
                            description: Text("Import a .shadowcoachbundle from Files, Google Drive, or AirDrop.")
                        )
                        if !store.localBundles.isEmpty {
                            ForEach(store.localBundles, id: \.self) { url in
                                Button {
                                    store.importLocalBundle(url)
                                } label: {
                                    Label("Import \(url.deletingPathExtension().lastPathComponent)", systemImage: "tray.and.arrow.down.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .padding(.vertical, 20)
                    .listRowSeparator(.hidden)
                } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        ForEach(filteredLines(store.lines)) { line in
                            NavigationLink(value: line.id) {
                                LineRow(line: line, progress: store.progress(for: line), isFavorite: store.isFavorite(line))
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                store.delete(filteredLines(store.lines)[index])
                            }
                        }
                    } header: {
                        Text("\(filteredLines(store.lines).count) results")
                    }
                } else {
                    Section {
                        ForEach(libraryFolders) { folder in
                            NavigationLink(value: LibraryDestination.folder(folder.id)) {
                                FolderRow(folder: folder)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search sentences")
            .navigationTitle("Shadow Coach")
            .safeAreaInset(edge: .top) {
                Picker("Filter", selection: $filter) {
                    ForEach(LibraryFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.thinMaterial)
            }
            .navigationDestination(for: UUID.self) { id in
                if let line = store.lines.first(where: { $0.id == id }) {
                    PracticeView(line: line)
                }
            }
            .navigationDestination(for: LibraryDestination.self) { destination in
                switch destination {
                case .folder(let folderID):
                    if let folder = libraryFolders.first(where: { $0.id == folderID }) {
                        FolderDetailView(
                            folder: folder,
                            filter: filter,
                            searchText: searchText
                        )
                    }
                case .source(let source, let folderID):
                    SourceDetailView(
                        source: source,
                        folderID: folderID,
                        filter: filter,
                        searchText: searchText
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(store.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.thinMaterial)
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                store.importBundle(from: url)
            }
        }
            .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private var libraryFolders: [LibraryFolder] {
        let visibleLines = filteredLines(store.lines)
        var folderMap: [String: [PracticeLine]] = [:]
        for line in visibleLines {
            folderMap[LibraryFolder.category(for: line)] = (folderMap[LibraryFolder.category(for: line)] ?? []) + [line]
        }

        let contentFolders = folderMap
            .map { LibraryFolder(id: $0.key, title: $0.key, subtitle: "\($0.value.count) sentences", systemImage: LibraryFolder.icon(for: $0.key), lines: $0.value) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        let favorites = visibleLines.filter { store.isFavorite($0) }
        let recent = visibleLines.filter { store.progress(for: $0).practiceCount > 0 }
            .sorted { lhs, rhs in
                (store.progress(for: lhs).lastPracticedAt ?? .distantPast) > (store.progress(for: rhs).lastPracticedAt ?? .distantPast)
            }

        return [
            LibraryFolder(id: "Favorites", title: "Favorites", subtitle: "\(favorites.count) saved", systemImage: "star.fill", lines: favorites),
            LibraryFolder(id: "Recently Practiced", title: "Recently Practiced", subtitle: "\(recent.count) practiced", systemImage: "clock.fill", lines: recent)
        ].filter { !$0.lines.isEmpty } + contentFolders
    }

    private func filteredLines(_ lines: [PracticeLine]) -> [PracticeLine] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.sortedLines(lines.filter { line in
            let matchesQuery = query.isEmpty
                || line.text.lowercased().contains(query)
                || line.title.lowercased().contains(query)
                || line.source.lowercased().contains(query)
            guard matchesQuery else { return false }
            switch filter {
            case .all:
                return true
            case .unpracticed:
                return store.progress(for: line).practiceCount == 0
            case .practiced:
                return store.progress(for: line).practiceCount > 0
            case .favorites:
                return store.isFavorite(line)
            case .hasAudio:
                return line.hasSourceAudio
            }
        })
    }
}

struct LineRow: View {
    @EnvironmentObject private var store: LibraryStore
    let line: PracticeLine
    let progress: PracticeProgress
    let isFavorite: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(line.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if line.hasSourceAudio {
                    Image(systemName: "waveform")
                        .foregroundStyle(.blue)
                }
                if isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }
                if progress.practiceCount > 0 {
                    Text("\(progress.practiceCount)x")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(line.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let score = progress.attempts.first?.analysis?.pronunciation {
                ScoreStrip(score: score)
            }
        }
        .padding(.vertical, 3)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                store.toggleFavorite(line)
            } label: {
                Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "star.slash" : "star")
            }
            .tint(.yellow)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                store.delete(line)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct FolderRow: View {
    let folder: LibraryFolder

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: folder.systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(.white)
                .background(.blue.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(folder.title)
                    .font(.headline)
                Text(folder.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 5)
    }
}

struct FolderDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    let folder: LibraryFolder
    let filter: LibraryFilter
    let searchText: String

    var body: some View {
        List {
            let sources = Dictionary(grouping: folder.lines, by: \.source)
            ForEach(sources.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { source in
                let lines = sources[source] ?? []
                NavigationLink(value: LibraryDestination.source(source, folder.id)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(source)
                                .font(.headline)
                            Text(sourceSubtitle(lines))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(lines.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        store.deleteSource(source)
                    } label: {
                        Label("Delete Source", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(folder.title)
    }

    private func sourceSubtitle(_ lines: [PracticeLine]) -> String {
        let practiced = lines.filter { store.progress(for: $0).practiceCount > 0 }.count
        return "\(practiced) practiced"
    }
}

struct SourceDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    let source: String
    let folderID: String
    let filter: LibraryFilter
    let searchText: String

    var body: some View {
        List {
            ForEach(lines) { line in
                NavigationLink(value: line.id) {
                    LineRow(line: line, progress: store.progress(for: line), isFavorite: store.isFavorite(line))
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    store.delete(lines[index])
                }
            }
        }
        .navigationTitle(source)
    }

    private var lines: [PracticeLine] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.sortedLines(store.lines
            .filter { $0.source == source }
            .filter { line in
                if folderID != "Favorites", folderID != "Recently Practiced", LibraryFolder.category(for: line) != folderID { return false }
                if folderID == "Favorites", !store.isFavorite(line) { return false }
                if folderID == "Recently Practiced", store.progress(for: line).practiceCount == 0 { return false }
                if !query.isEmpty, !line.text.lowercased().contains(query), !line.title.lowercased().contains(query), !line.source.lowercased().contains(query) { return false }
                switch filter {
                case .all:
                    return true
                case .unpracticed:
                    return store.progress(for: line).practiceCount == 0
                case .practiced:
                    return store.progress(for: line).practiceCount > 0
                case .favorites:
                    return store.isFavorite(line)
                case .hasAudio:
                    return line.hasSourceAudio
                }
            })
    }
}

struct ScoreStrip: View {
    let score: Double

    var body: some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(color.opacity(0.2))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color)
                        .frame(width: max(8, CGFloat(score) / 100 * 120), height: 6)
                }
                .frame(width: 120)
            Text("\(Int(score.rounded()))")
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
        }
    }

    private var color: Color {
        if score >= 85 { return .green }
        if score >= 70 { return .blue }
        return .red
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case unpracticed
    case practiced
    case favorites
    case hasAudio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .unpracticed: return "New"
        case .practiced: return "Done"
        case .favorites: return "Fav"
        case .hasAudio: return "Audio"
        }
    }
}

struct LibraryFolder: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let lines: [PracticeLine]

    static func category(for line: PracticeLine) -> String {
        let haystack = "\(line.source) \(line.title)".lowercased()
        if haystack.contains("ted") || haystack.contains("vulnerability") || haystack.contains("shame") || haystack.contains("wrong") || haystack.contains("believing") {
            return "TED Talks"
        }
        if haystack.contains("youtube") || haystack.contains("huberman") || haystack.contains("interview") || haystack.contains("career") {
            return "YouTube Interviews"
        }
        if haystack.contains("breaking bad") || haystack.contains("better call saul") {
            return "Film & TV"
        }
        if line.quality == .builtIn || haystack.contains("quote") {
            return "Classic Lines"
        }
        return "Imported Packs"
    }

    static func icon(for category: String) -> String {
        switch category {
        case "TED Talks": return "person.wave.2.fill"
        case "YouTube Interviews": return "play.rectangle.fill"
        case "Film & TV": return "film.fill"
        case "Classic Lines": return "quote.bubble.fill"
        case "Favorites": return "star.fill"
        case "Recently Practiced": return "clock.fill"
        default: return "folder.fill"
        }
    }
}

enum LibraryDestination: Hashable {
    case folder(String)
    case source(String, String)
}

struct PracticeView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var audio: AudioCoach
    let line: PracticeLine
    @State private var revealText = false
    @State private var isAnalyzing = false
    @State private var analysis: AzurePronunciationAnalysis?
    @State private var currentAttemptID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(line.source)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(line.title)
                                .font(.title2.weight(.semibold))
                        }
                        Spacer()
                        Button {
                            store.toggleFavorite(line)
                        } label: {
                            Image(systemName: store.isFavorite(line) ? "star.fill" : "star")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(store.isFavorite(line) ? .yellow : .secondary)
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                    }
                    if revealText {
                        Text(line.text)
                            .font(.title3)
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "ear.and.waveform")
                                .font(.system(size: 44))
                                .foregroundStyle(.blue)
                            Text("Listen first. Repeat from memory.")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        audio.playReference(line: line, mediaURL: store.mediaURL(for: line))
                    } label: {
                        Label("Listen", systemImage: "speaker.wave.2.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        if audio.isRecording {
                            audio.stopRecording()
                            saveCurrentRecording()
                        } else {
                            analysis = nil
                            currentAttemptID = nil
                            audio.startRecording()
                        }
                    } label: {
                        Label(audio.isRecording ? "Stop Recording" : "Record Your Repeat", systemImage: audio.isRecording ? "stop.fill" : "mic.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(audio.isRecording ? .red : .green)
                }

                HStack(spacing: 12) {
                    Button {
                        revealText.toggle()
                    } label: {
                        Label(revealText ? "Hide Text" : "Reveal Text", systemImage: revealText ? "eye.slash" : "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        audio.playRecording()
                    } label: {
                        Label("Playback", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!audio.hasRecording || audio.isRecording)
                }

                HStack {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                if let analysis {
                    AzureResultView(analysis: analysis)
                }

                let attempts = store.progress(for: line).attempts
                if !attempts.isEmpty {
                    AttemptHistoryView(
                        line: line,
                        attempts: Array(attempts.prefix(5)),
                        selectedAnalysis: $analysis
                    )
                }
            }
            .padding()
            .padding(.bottom, 84)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: store.azureSpeechKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .foregroundStyle(store.azureSpeechKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .orange : .green)
                    Text(store.azureSpeechKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Azure key missing" : "Azure ready: \(store.azureSpeechRegion)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Button {
                    analyze(force: true)
                } label: {
                    Label(analyzeButtonTitle, systemImage: "waveform.badge.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!audio.hasRecording || audio.isRecording || isAnalyzing)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.thinMaterial)
        }
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.choose(line)
            let latestAttempt = store.latestAttempt(for: line)
            currentAttemptID = latestAttempt?.id
            analysis = latestAttempt?.analysis
        }
    }

    private var statusText: String {
        if audio.isRecording {
            return String(format: "Recording %.1fs", audio.recordingDuration)
        }
        if isAnalyzing {
            return "Analyzing pronunciation with Azure..."
        }
        if analysis != nil {
            return store.latestAttempt(for: line)?.analysis == analysis ? "Loaded saved analysis" : "Analysis ready"
        }
        return audio.status
    }

    private var analyzeButtonTitle: String {
        if isAnalyzing { return "Analyzing..." }
        if !audio.hasRecording { return "Record First" }
        if analysis != nil { return "Analyze Again" }
        return "Analyze with Azure"
    }

    private func saveCurrentRecording() {
        guard audio.hasRecording else { return }
        let attempt = store.saveAttempt(line: line, recordingURL: audio.recordingURL, duration: audio.recordingDuration, analysis: nil)
        currentAttemptID = attempt?.id
        analysis = nil
    }

    private func analyze(force: Bool) {
        _ = force
        guard audio.hasRecording, !audio.isRecording, !isAnalyzing else { return }
        isAnalyzing = true
        analysis = nil
        Task {
            do {
                let result = try await AzureSpeechClient.assess(
                    audioURL: audio.recordingURL,
                    referenceText: line.text,
                    key: store.azureSpeechKey,
                    region: store.azureSpeechRegion
                )
                await MainActor.run {
                    analysis = result
                    if let currentAttemptID {
                        store.updateAttemptAnalysis(currentAttemptID, for: line, analysis: result)
                    } else {
                        let attempt = store.saveAttempt(line: line, recordingURL: audio.recordingURL, duration: audio.recordingDuration, analysis: result)
                        currentAttemptID = attempt?.id
                    }
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    let failed = AzurePronunciationAnalysis(pronunciation: nil, accuracy: nil, fluency: nil, completeness: nil, prosody: nil, display: "", words: [], error: error.localizedDescription)
                    analysis = failed
                    if let currentAttemptID {
                        store.updateAttemptAnalysis(currentAttemptID, for: line, analysis: failed)
                    } else {
                        let attempt = store.saveAttempt(line: line, recordingURL: audio.recordingURL, duration: audio.recordingDuration, analysis: failed)
                        currentAttemptID = attempt?.id
                    }
                    isAnalyzing = false
                }
            }
        }
    }
}

struct AzureResultView: View {
    let analysis: AzurePronunciationAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Analysis")
                    .font(.headline)
                Spacer()
                if analysis.error == nil {
                    Text(summaryLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(scoreColor(analysis.pronunciation))
                        .background(scoreColor(analysis.pronunciation).opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            if let error = analysis.error {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Analysis failed", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                    Text("Check Settings for Azure Speech key/region, make sure the recording is not silent, then tap Analyze Again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                CoachSummaryView(analysis: analysis)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                    scoreTile("Pron", analysis.pronunciation, systemImage: "waveform")
                    scoreTile("Acc", analysis.accuracy, systemImage: "scope")
                    scoreTile("Flu", analysis.fluency, systemImage: "speedometer")
                    scoreTile("Comp", analysis.completeness, systemImage: "checklist")
                    scoreTile("Prosody", analysis.prosody, systemImage: "music.quarternote.3")
                }
                if !analysis.display.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Azure heard")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(analysis.display)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.background.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                if !analysis.words.isEmpty {
                    Text("Words")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                        ForEach(analysis.words) { word in
                            VStack(spacing: 3) {
                                Text(word.text)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(scoreText(word.accuracy))
                                    .font(.caption2.weight(.bold))
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(scoreColor(word.accuracy).opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    Text("Word details")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    VStack(spacing: 8) {
                        ForEach(analysis.words) { word in
                            WordDetailRow(word: word, scoreText: scoreText, scoreColor: scoreColor)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var summaryLabel: String {
        guard let pronunciation = analysis.pronunciation else { return "Scored" }
        if pronunciation >= 85 { return "Strong" }
        if pronunciation >= 70 { return "Needs polish" }
        return "Needs work"
    }

    private func scoreTile(_ title: String, _ value: Double?, systemImage: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(scoreColor(value))
            Text(scoreText(value))
                .font(.title3.weight(.semibold))
                .foregroundStyle(scoreColor(value))
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(scoreColor(value).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func scoreText(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))" } ?? "--"
    }

    private func scoreColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        if value >= 85 { return .green }
        if value >= 70 { return .blue }
        return .red
    }
}

struct AttemptHistoryView: View {
    @EnvironmentObject private var store: LibraryStore
    let line: PracticeLine
    let attempts: [RecordingAttempt]
    @Binding var selectedAnalysis: AzurePronunciationAnalysis?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(.headline)
            ForEach(attempts) { attempt in
                Button {
                    selectedAnalysis = attempt.analysis
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(attempt.date, style: .time)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(String(format: "%.1fs recording", attempt.duration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let score = attempt.analysis?.pronunciation {
                            Text("\(Int(score.rounded()))")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(scoreColor(score))
                        } else if attempt.analysis?.error != nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        } else {
                            Text("--")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            store.deleteAttempt(attempt, for: line)
                            if selectedAnalysis == attempt.analysis {
                                selectedAnalysis = store.latestAttempt(for: line)?.analysis
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.red)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        store.deleteAttempt(attempt, for: line)
                        if selectedAnalysis == attempt.analysis {
                            selectedAnalysis = store.latestAttempt(for: line)?.analysis
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func scoreColor(_ value: Double) -> Color {
        if value >= 85 { return .green }
        if value >= 70 { return .blue }
        return .red
    }
}

struct CoachSummaryView: View {
    let analysis: AzurePronunciationAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Top fixes", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
            }
            ForEach(Array(fixes.enumerated()), id: \.offset) { index, fix in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(fix.color)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fix.title)
                            .font(.subheadline.weight(.semibold))
                        Text(fix.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(fix.color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var fixes: [CoachFix] {
        var output: [CoachFix] = []

        let weakWords = analysis.words
            .filter { ($0.accuracy ?? 100) < 75 || (($0.errorType ?? "").lowercased() != "none" && !($0.errorType ?? "").isEmpty) }
            .sorted { ($0.accuracy ?? 100) < ($1.accuracy ?? 100) }

        for word in weakWords.prefix(3) {
            let weakPhoneme = word.phonemes
                .filter { ($0.accuracy ?? 100) < 70 }
                .sorted { ($0.accuracy ?? 100) < ($1.accuracy ?? 100) }
                .first
            let errorType = word.errorType.flatMap { $0.lowercased() == "none" ? nil : $0 }
            if let phoneme = weakPhoneme {
                output.append(CoachFix(
                    title: "Repair \"\(word.text)\"",
                    detail: "The sound /\(phoneme.text)/ is weak. Slow that word down once, then connect it back into the sentence.",
                    color: .red
                ))
            } else if let errorType {
                output.append(CoachFix(
                    title: "Check \"\(word.text)\"",
                    detail: "Azure marked this as \(errorType). Replay the reference and match that word exactly.",
                    color: .orange
                ))
            } else {
                output.append(CoachFix(
                    title: "Polish \"\(word.text)\"",
                    detail: "This word scored \(Int((word.accuracy ?? 0).rounded())). Repeat just this word, then the full phrase.",
                    color: .orange
                ))
            }
        }

        if output.isEmpty {
            if let prosody = analysis.prosody, prosody < 75 {
                output.append(CoachFix(
                    title: "Add more rhythm",
                    detail: "Your words are mostly right. Now copy the speaker's rise, fall, and pauses.",
                    color: .blue
                ))
            } else {
                output.append(CoachFix(
                    title: "Good pass",
                    detail: "Do one more repetition, slightly faster, while keeping the same clarity.",
                    color: .green
                ))
            }
        }

        return Array(output.prefix(3))
    }
}

struct CoachFix {
    let title: String
    let detail: String
    let color: Color
}

struct WordDetailRow: View {
    let word: AzurePronunciationWord
    let scoreText: (Double?) -> String
    let scoreColor: (Double?) -> Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(word.text)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(scoreText(word.accuracy))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(scoreColor(word.accuracy))
            }
            if let errorType = word.errorType, !errorType.isEmpty, errorType.lowercased() != "none" {
                Text(errorType)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
            if !word.phonemes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(word.phonemes) { phoneme in
                            VStack(spacing: 2) {
                                Text(phoneme.text)
                                    .font(.caption.weight(.semibold))
                                Text(scoreText(phoneme.accuracy))
                                    .font(.caption2.weight(.bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(scoreColor(phoneme.accuracy).opacity(0.14))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(.background.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Azure Speech") {
                    SecureField("Speech key", text: $store.azureSpeechKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Region", text: $store.azureSpeechRegion)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Use the same Speech key/region as the Mac app. Region is usually eastus.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
