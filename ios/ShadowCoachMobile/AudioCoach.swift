import AVFoundation
import Foundation

@MainActor
final class AudioCoach: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    @Published var isRecording = false
    @Published var hasRecording = false
    @Published var recordingDuration = 0.0
    @Published var isPlayingReference = false
    @Published var status = "Ready"

    private var player: AVAudioPlayer?
    private var sourcePlayer: AVPlayer?
    private var sourceStopTask: Task<Void, Never>?
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private let tts = AVSpeechSynthesizer()

    override init() {
        super.init()
        tts.delegate = self
    }

    var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("shadowcoach-recording.wav")
    }

    func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            status = "Audio session failed: \(error.localizedDescription)"
        }
    }

    func playReference(line: PracticeLine, mediaURL: URL?) {
        stopPlayback()
        isPlayingReference = true
        if let mediaURL, let start = line.sourceStartTime {
            playSource(line: line, url: mediaURL, start: start, end: line.sourceEndTime ?? start + 4)
        } else {
            let utterance = AVSpeechUtterance(string: line.text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.45
            utterance.volume = 1.0
            tts.speak(utterance)
            status = "Playing TTS fallback"
        }
    }

    private func playSource(line: PracticeLine, url: URL, start: Double, end: Double) {
        let paddedStart = max(0, start - 0.06)
        let paddedEnd = max(end + 0.08, paddedStart + 1.0)
        let player = AVPlayer(url: url)
        sourcePlayer = player
        player.seek(to: CMTime(seconds: paddedStart, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] _ in
            Task { @MainActor in
                guard let self, let player, self.sourcePlayer === player else { return }
                player.play()
                self.status = "Playing source audio"
                let duration = UInt64(max(0.2, paddedEnd - paddedStart) * 1_000_000_000)
                self.sourceStopTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: duration)
                    await MainActor.run {
                        guard let self else { return }
                        self.sourcePlayer?.pause()
                        self.sourcePlayer = nil
                        self.isPlayingReference = false
                        self.status = "Reference finished"
                    }
                }
            }
        }
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    func startRecording() {
        configureAudioSession()
        stopPlayback()
        try? FileManager.default.removeItem(at: recordingURL)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        do {
            recorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            recorder?.delegate = self
            recorder?.prepareToRecord()
            recorder?.record()
            isRecording = true
            hasRecording = false
            recordingDuration = 0
            status = "Recording..."
            timer?.invalidate()
            timer = Timer.scheduledTimer(
                timeInterval: 0.1,
                target: self,
                selector: #selector(updateRecordingDuration),
                userInfo: nil,
                repeats: true
            )
        } catch {
            status = "Could not record: \(error.localizedDescription)"
        }
    }

    @objc private func updateRecordingDuration() {
        guard let recorder else { return }
        recordingDuration = recorder.currentTime
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        isRecording = false
        hasRecording = FileManager.default.fileExists(atPath: recordingURL.path)
        status = hasRecording ? "Recording ready" : "No recording"
    }

    func playRecording() {
        guard hasRecording else { return }
        stopPlayback()
        do {
            player = try AVAudioPlayer(contentsOf: recordingURL)
            player?.delegate = self
            player?.play()
            status = "Playing your recording"
        } catch {
            status = "Could not play recording: \(error.localizedDescription)"
        }
    }

    func stopPlayback() {
        tts.stopSpeaking(at: .immediate)
        player?.stop()
        player = nil
        sourceStopTask?.cancel()
        sourceStopTask = nil
        sourcePlayer?.pause()
        sourcePlayer = nil
        isPlayingReference = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPlayingReference = false
            self.status = "Reference finished"
        }
    }
}
