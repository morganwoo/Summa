import Foundation
import AVFoundation
import Speech

/// Live dictation with Apple's Speech framework. Audio is streamed to the
/// recognizer and never written to disk; only the editable transcript is kept.
@MainActor
final class SpeechDictation: ObservableObject {
    enum Access: Equatable { case undetermined, granted, denied, unavailable }

    @Published private(set) var access: Access = .undetermined
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""

    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var configurationObserver: NSObjectProtocol?
    private var restarts = 0

    /// Requests speech and microphone access. Called only after the person chooses voice.
    func requestAccess() async {
        guard recognizer != nil else {
            access = .unavailable
            return
        }
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            access = .denied
            return
        }
        let microphone: Bool = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        access = microphone ? .granted : .denied
    }

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    func start() {
        guard access == .granted, let recognizer, recognizer.isAvailable else {
            if access == .granted { access = .unavailable }
            return
        }
        stop()
        transcript = ""
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                access = .unavailable
                return
            }
            Self.installTap(on: input, format: format, request: request)
            engine.prepare()
            try engine.start()

            // The audio route can change just after recording begins (a headset, a call ending, or the
            // Simulator settling its audio device). The engine stops itself when that happens, so it
            // is restarted with the new format instead of leaving a recording that hears nothing.
            restarts = 0
            configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resumeAfterRouteChange() }
            }

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let finished = error != nil || (result?.isFinal ?? false)
                Task { @MainActor in
                    guard let self else { return }
                    if let text { self.transcript = text }
                    if finished { self.stop() }
                }
            }
            isRecording = true
        } catch {
            stop()
            access = .unavailable
        }
    }

    /// Installed from a nonisolated context because the tap runs on the audio thread.
    nonisolated private static func installTap(on input: AVAudioInputNode, format: AVAudioFormat,
                                               request: SFSpeechAudioBufferRecognitionRequest) {
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    private func resumeAfterRouteChange() {
        guard isRecording, let request, restarts < 3 else { return }
        restarts += 1
        engine.stop()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            stop()
            access = .unavailable
            return
        }
        Self.installTap(on: input, format: format, request: request)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            access = .unavailable
        }
    }

    func stop() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        guard isRecording || task != nil else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Reads Summa's questions aloud on the voice path.
@MainActor
final class PromptSpeaker: ObservableObject {
    @Published var isEnabled = true {
        didSet { if !isEnabled { synthesizer.stopSpeaking(at: .immediate) } }
    }
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        guard isEnabled, !AppEnvironment.isUITesting else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        synthesizer.speak(utterance)
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}
