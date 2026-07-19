import SwiftUI

struct RecordingHistorySheet: View {
    @EnvironmentObject private var coach: SpeechCoach
    @Binding var isPresented: Bool

    var body: some View {
        let attempts = coach.currentProgress().attempts

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.primary.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: "waveform.path")
                        .foregroundStyle(Theme.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Recordings")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("\(coach.selectedLine?.title ?? "Current sentence") · \(attempts.count) saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconButtonStyle())
                .help("Close recording history")
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(attempts) { attempt in
                        SavedAttemptRowView(attempt: attempt)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 420, idealHeight: 560)
        .background(Theme.appBackground)
    }
}
struct SavedAttemptRowView: View {
    @EnvironmentObject private var coach: SpeechCoach
    @State private var isHovered = false
    @State private var isConfirmingDeletion = false
    let attempt: RecordingAttempt

    private var isSelected: Bool {
        coach.selectedAttemptRelativePathForAnalysis == attempt.relativePath
    }

    private var score: Double? {
        attempt.analysisCache?.localAnalysis.accuracy
    }

    var body: some View {
        HStack(spacing: 9) {
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
                        Text(formattedDate(attempt.date))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(attemptDetail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    if let score {
                        Text("\(Int(score.rounded()))%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(color(for: score))
                            .monospacedDigit()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            if isConfirmingDeletion {
                Button(role: .destructive) {
                    isConfirmingDeletion = false
                    coach.deleteAttempt(attempt)
                } label: {
                    Text("Delete")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 25)
                        .background(Theme.danger)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Permanently delete this recording and its analysis")

                Button {
                    isConfirmingDeletion = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 25, height: 25)
                }
                .buttonStyle(.plain)
                .help("Cancel deletion")
            } else {
                Button {
                    isConfirmingDeletion = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.danger)
                        .frame(width: 25, height: 25)
                }
                .buttonStyle(.plain)
                .opacity(isHovered || isSelected ? 1 : 0.55)
                .help("Delete this recording")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            isConfirmingDeletion
                ? Theme.danger.opacity(0.08)
                : isSelected
                ? Theme.primary.opacity(0.10)
                : (isHovered ? Theme.panel.opacity(0.72) : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(alignment: .leading) {
            if isConfirmingDeletion || isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isConfirmingDeletion ? Theme.danger : Theme.primary)
                    .frame(width: 3)
                    .padding(.vertical, 7)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
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
                isConfirmingDeletion = true
            } label: {
                Label("Delete Recording", systemImage: "trash")
            }
        }
    }

    private var attemptDetail: String {
        let analysisState: String
        if attempt.resolvedActivity.comparesWithReference {
            analysisState = attempt.analysisCache == nil ? "Not analyzed" : "Analysis saved"
        } else if let cache = attempt.openResponseAnalysisCache {
            analysisState = cache.coachFeedback == nil ? "Transcript saved" : "Feedback saved"
        } else {
            analysisState = "Not analyzed"
        }
        return "\(formattedDuration(attempt.duration)) · \(attempt.resolvedActivity.label) · \(analysisState)"
    }

    private func formattedDate(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            return "Today · \(date.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday · \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 {
            return "\(total)s"
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func color(for score: Double) -> Color {
        if score >= 85 { return Theme.success }
        if score >= 65 { return Theme.primary }
        return Theme.danger
    }
}
