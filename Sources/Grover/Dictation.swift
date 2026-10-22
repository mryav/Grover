import AVFoundation
import Speech

/// Live speech-to-text for the search field.
@MainActor
final class Dictation {
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private(set) var isRunning = false

    /// Starts listening. `onText` receives the running transcript and `onEnd`
    /// fires once when listening stops for any reason.
    func start(onText: @escaping (String) -> Void, onEnd: @escaping () -> Void) {
        guard !isRunning else { return }
        Task {
            guard await Self.authorize(), let recognizer, recognizer.isAvailable else {
                onEnd()
                return
            }
            do {
                try begin(recognizer: recognizer, onText: onText, onEnd: onEnd)
            } catch {
                stop()
                onEnd()
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.finish()
        task = nil
    }

    private func begin(
        recognizer: SFSpeechRecognizer,
        onText: @escaping (String) -> Void,
        onEnd: @escaping () -> Void
    ) throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()
        isRunning = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let finished = error != nil || (result?.isFinal ?? false)
            DispatchQueue.main.async {
                if let text { onText(text) }
                if finished {
                    self?.stop()
                    onEnd()
                }
            }
        }
    }

    private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}
