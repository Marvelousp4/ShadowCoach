import AppKit
import Foundation
import SwiftUI

private enum LibraryDeletionTarget: Identifiable {
    case source(String)
    case line(PracticeLine)

    var id: String {
        switch self {
        case .source(let source): return "source-\(source)"
        case .line(let line): return "line-\(line.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .source: return "Delete Library Folder?"
        case .line: return "Delete Sentence?"
        }
    }

    var message: String {
        switch self {
        case .source(let source):
            return "\(source) and its saved recordings, analysis, favorites, and unused source audio will be removed."
        case .line(let line):
            return "\(line.title) and its saved recordings and analysis will be removed."
        }
    }
}


private struct RecordingDurationText: View {
    let startedAt: Date?
    let savedDuration: Double

    var body: some View {
        Group {
            if let startedAt {
                TimelineView(.periodic(from: .now, by: 0.2)) { context in
                    Text(formatted(max(0, context.date.timeIntervalSince(startedAt))))
                }
            } else {
                Text(formatted(savedDuration))
            }
        }
    }

    private func formatted(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct LibraryViewIndex {
    let allLines: [PracticeLine]
    let visibleLines: [PracticeLine]
    let allLinesBySource: [String: [PracticeLine]]
    let visibleLinesBySource: [String: [PracticeLine]]
    let visibleSections: [LibrarySection]
    let userSources: Set<String>

    static let empty = LibraryViewIndex(
        allLines: [],
        visibleLines: [],
        allLinesBySource: [:],
        visibleLinesBySource: [:],
        visibleSections: [],
        userSources: []
    )
}

private struct DailyPracticeCount: Identifiable {
    var id: Date { date }
    let date: Date
    let count: Int
}

private struct PracticeDashboardSnapshot {
    let dueReviewCount: Int
    let availableReviewCount: Int
    let attemptsToday: Int
    let currentStreak: Int
    let totalAttempts: Int
    let recentDailyCounts: [DailyPracticeCount]

    static let empty = PracticeDashboardSnapshot(
        dueReviewCount: 0,
        availableReviewCount: 0,
        attemptsToday: 0,
        currentStreak: 0,
        totalAttempts: 0,
        recentDailyCounts: []
    )
}

struct ContentView: View {
    @EnvironmentObject private var coach: SpeechCoach
    @State private var libraryIndex = LibraryViewIndex.empty
    @State private var practiceDashboard = PracticeDashboardSnapshot.empty
    @State private var expandedSources: Set<String> = []
    @State private var keyMonitor: Any?
    @State private var librarySearch = ""
    @State private var libraryFilter: LibraryFilter = .all
    @State private var showingGeneratePack = false
    @State private var showProsodyCurves = false
    @State private var showingAppSettings = false
    @State private var settingsSection: AppSettingsSection = .appearance
    @State private var showingPracticeStats = false
    @State private var showingRecordingHistory = false
    @State private var showingAllAttempts = false
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
        libraryIndex.visibleLines
    }

    private var allLines: [PracticeLine] {
        libraryIndex.allLines
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
        let lines = libraryIndex.visibleLinesBySource[source] ?? []
        return lines.isEmpty ? visibleLines : lines
    }

    private var userSources: Set<String> {
        libraryIndex.userSources
    }

    private var selectedIndexText: String {
        guard let selectedLineID = coach.selectedLineID,
              let index = currentGroupLines.firstIndex(where: { $0.id == selectedLineID }) else {
            return "No sentence selected"
        }
        return "Sentence \(index + 1) of \(currentGroupLines.count)"
    }

    private var visibleSections: [LibrarySection] {
        libraryIndex.visibleSections
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
        .sheet(isPresented: $showingRecordingHistory) {
            RecordingHistorySheet(isPresented: $showingRecordingHistory)
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
            let loadedLines = coach.importedLines + coach.generatedLines + PracticeLine.library
            refreshLibraryIndex(using: loadedLines)
            refreshPracticeDashboard(using: loadedLines)
            coach.restoreLastSelectedLine(from: loadedLines)
            expandSelectedSource()
            coach.hasRecording = FileManager.default.fileExists(atPath: coach.recordingURL.path)
            installKeyboardMonitor()
            scheduleInitialFocusRelease()
        }
        .onChange(of: coach.libraryRevision) { _ in
            refreshLibraryIndex()
            refreshPracticeDashboard()
        }
        .onChange(of: coach.practiceRevision) { _ in
            if libraryFilter.dependsOnPracticeHistory {
                refreshLibraryIndex()
            }
            refreshPracticeDashboard()
        }
        .onChange(of: librarySearch) { _ in
            refreshLibraryIndex()
        }
        .onChange(of: libraryFilter) { _ in
            refreshLibraryIndex()
        }
        .onChange(of: coach.dailyReviewLimit) { _ in
            refreshPracticeDashboard()
        }
        .onChange(of: coach.selectedLineID) { _ in
            expandSelectedSource()
            showingAllAttempts = false
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPracticeDashboard()
            if libraryFilter == .needsReview {
                refreshLibraryIndex()
            }
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
    }

    private func refreshLibraryIndex(using suppliedLines: [PracticeLine]? = nil) {
        let userLines = coach.importedLines + coach.generatedLines
        let lines = suppliedLines ?? (userLines + PracticeLine.library)
        let visible = filteredLines(from: lines)
        let allGroups = groupLinesBySource(lines)
        let visibleGroups = groupLinesBySource(visible)

        libraryIndex = LibraryViewIndex(
            allLines: lines,
            visibleLines: visible,
            allLinesBySource: allGroups.groups,
            visibleLinesBySource: visibleGroups.groups,
            visibleSections: visibleGroups.order.map {
                LibrarySection(source: $0, lines: visibleGroups.groups[$0] ?? [])
            },
            userSources: Set(userLines.map(\.source))
        )
    }

    private func refreshPracticeDashboard(using suppliedLines: [PracticeLine]? = nil) {
        let lines = suppliedLines ?? libraryIndex.allLines
        let dailyCounts = coach.recentDailyCounts().map {
            DailyPracticeCount(date: $0.date, count: $0.count)
        }
        practiceDashboard = PracticeDashboardSnapshot(
            dueReviewCount: coach.totalDueReviewCount(in: lines),
            availableReviewCount: coach.availableReviewCount(in: lines),
            attemptsToday: coach.attempts(on: Date()),
            currentStreak: coach.currentStreak(),
            totalAttempts: coach.allAttempts().count,
            recentDailyCounts: dailyCounts
        )
    }

    private func groupLinesBySource(
        _ lines: [PracticeLine]
    ) -> (order: [String], groups: [String: [PracticeLine]]) {
        var order: [String] = []
        var groups: [String: [PracticeLine]] = [:]
        for line in lines {
            if groups[line.source] == nil {
                order.append(line.source)
            }
            groups[line.source, default: []].append(line)
        }
        return (order, groups)
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
                    RecordingDurationText(
                        startedAt: coach.recordingStartedAt,
                        savedDuration: coach.recordingDuration
                    )
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
                let count = practiceDashboard.availableReviewCount
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

            List {
                if visibleSections.isEmpty {
                    emptyLibraryFilterState
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(visibleSections) { section in
                        sectionView(section)
                            .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
        let bestAccuracy = progress.bestAnalyzedAccuracy

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
                    if let bestAccuracy {
                        Text("\(Int(bestAccuracy.rounded()))%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(scoreColor(bestAccuracy))
                            .monospacedDigit()
                            .help("Best analyzed accuracy")
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
        let total = practiceDashboard.dueReviewCount
        let available = practiceDashboard.availableReviewCount
        if total == 0 { return "No sentences are due" }
        if available == 0 { return "Today's review goal is complete" }
        if available < total { return "Start \(available) of \(total) due sentences" }
        return "Start \(available) due sentence\(available == 1 ? "" : "s")"
    }

    private var previousReviewLine: PracticeLine? {
        guard let selectedLine = coach.selectedLine else { return nil }
        let sourceLines = libraryIndex.allLinesBySource[selectedLine.source] ?? []
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

                if !coach.currentProgress().attempts.isEmpty {
                    Button {
                        showingRecordingHistory = true
                    } label: {
                        Image(systemName: "waveform.path")
                            .overlay(alignment: .topTrailing) {
                                Text("\(coach.currentProgress().attempts.count)")
                                    .font(.system(size: 8, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 3)
                                    .frame(minWidth: 14, minHeight: 14)
                                    .background(Theme.accent)
                                    .clipShape(Capsule())
                                    .offset(x: 8, y: -7)
                            }
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Show saved recordings")
                }

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
                let isSkipped = coach.isCurrentLearningStageSkipped(stage)
                let isActive = activeStage == stage
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            isComplete
                                ? Theme.success.opacity(0.16)
                                : (isActive ? Theme.accent.opacity(0.16) : Theme.pill)
                        )
                    Image(systemName: isSkipped ? "minus" : (isComplete ? "checkmark" : stage.systemImage))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(
                            isSkipped
                                ? Color.secondary
                                : (isComplete ? Theme.success : (isActive ? Theme.accent : Color.secondary))
                        )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isActive ? Theme.accent.opacity(0.45) : Color.clear)
                )
                .help(isSkipped ? "\(index + 1). \(stage.title) · skipped without a reusable target" : "\(index + 1). \(stage.title)")
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
                    if coach.isFindingLearningTargets {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Looking for a reusable pattern...")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Label(
                            "No useful pattern selected for this line. Whole-sentence practice is still worthwhile.",
                            systemImage: "checkmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    ForEach(targets) { target in
                        learningTargetRow(target)
                    }
                }

                Button {
                    coach.findBetterLearningTargets()
                } label: {
                    Label(
                        learningTargetSearchTitle(hasTargets: !targets.isEmpty),
                        systemImage: coach.isFindingLearningTargets ? "sparkles" : "arrow.clockwise"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .disabled(coach.isFindingLearningTargets)
                .help("Run target selection again and replace the cached suggestions")
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

    private func learningTargetSearchTitle(hasTargets: Bool) -> String {
        if coach.isFindingLearningTargets {
            return "Checking this sentence..."
        }
        if coach.feedbackProvider == .gemini {
            return hasTargets ? "Ask Gemini for alternatives" : "Try Gemini"
        }
        return hasTargets ? "Find another option" : "Check again"
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
        if stage == .noticing && coach.isFindingLearningTargets { return true }
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
                        SavedAttemptRowView(attempt: attempt)
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
                    CoachFeedbackView(
                        markdown: coach.analysis,
                        textScale: feedbackTextSize.scale
                    )
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
                    settingsRow("Local models", icon: "bolt.fill") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(CodexModelRouter.settingsSummary)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Automatically matched to each task")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
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
                    Text("\(practiceDashboard.attemptsToday) today · \(practiceDashboard.currentStreak)d streak")
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
                    statTile(title: "Today", value: "\(practiceDashboard.attemptsToday)")
                    statTile(title: "Streak", value: "\(practiceDashboard.currentStreak)d")
                    statTile(title: "Total", value: "\(practiceDashboard.totalAttempts)")
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
        let days = practiceDashboard.recentDailyCounts
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
}
