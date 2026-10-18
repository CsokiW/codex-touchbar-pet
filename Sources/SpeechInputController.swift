import AppKit
import ApplicationServices
import AVFoundation
import Speech

protocol SpeechInputControllerDelegate: AnyObject {
    func speechInputController(_ controller: SpeechInputController, didChange state: SpeechInputController.State)
    func speechInputController(_ controller: SpeechInputController, didUpdateTranscript transcript: String)
}

final class SpeechInputController {
    enum State: Equatable {
        case idle
        case requestingPermission
        case recording
        case ready
        case error(String)
    }

    weak var delegate: SpeechInputControllerDelegate?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInstalledAudioTap = false
    private var errorResetWorkItem: DispatchWorkItem?
    private var generation = 0
    private let speechPermission: (@escaping (Bool) -> Void) -> Void
    private let microphonePermission: (@escaping (Bool) -> Void) -> Void
    private let textInserter: SpeechTextInserting
    private let errorDisplayDuration: TimeInterval

    init(
        speechPermission: @escaping (@escaping (Bool) -> Void) -> Void = SpeechInputController.requestSpeechPermission,
        microphonePermission: @escaping (@escaping (Bool) -> Void) -> Void = SpeechInputController.requestMicrophonePermission,
        textInserter: SpeechTextInserting = CodexSpeechTextInserter(),
        errorDisplayDuration: TimeInterval = 2.5,
        initialTranscript: String = ""
    ) {
        self.speechPermission = speechPermission
        self.microphonePermission = microphonePermission
        self.textInserter = textInserter
        self.errorDisplayDuration = errorDisplayDuration
        self.transcript = initialTranscript
        if !initialTranscript.isEmpty { self.state = .ready }
    }

    private(set) var state: State = .idle {
        didSet {
            guard state != oldValue else { return }
            delegate?.speechInputController(self, didChange: state)
        }
    }

    private(set) var transcript = "" {
        didSet {
            guard transcript != oldValue else { return }
            delegate?.speechInputController(self, didUpdateTranscript: transcript)
        }
    }

    var isRecording: Bool {
        state == .recording || state == .requestingPermission
    }

    func toggleRecording() {
        if state == .requestingPermission {
            clear()
        } else if state == .recording {
            stopAndInsertTranscript()
        } else if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            insertTranscript()
        } else {
            requestPermissionsAndStart()
        }
    }

    func stopRecording() {
        generation += 1
        finishAudioCapture(cancelTask: false)
        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state = .idle
        } else {
            state = .ready
        }
    }

    func clear() {
        generation += 1
        errorResetWorkItem?.cancel()
        errorResetWorkItem = nil
        finishAudioCapture(cancelTask: true)
        transcript = ""
        state = .idle
    }

    private func stopAndInsertTranscript() {
        stopRecording()
        insertTranscript()
    }

    private func insertTranscript() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            showTemporaryError("没有识别到文字")
            return
        }

        generation += 1
        let operation = generation
        errorResetWorkItem?.cancel()
        state = .ready
        textInserter.insert(text, isCancelled: { [weak self] in
            self?.generation != operation
        }) { [weak self] result in
            guard let self, self.generation == operation else { return }
            switch result {
            case .success:
                self.transcript = ""
                self.state = .idle
            case .failure(let error):
                self.showTemporaryError(error.localizedDescription)
            }
        }
    }

    private func requestPermissionsAndStart() {
        generation += 1
        let operation = generation
        errorResetWorkItem?.cancel()
        state = .requestingPermission

        speechPermission { [weak self] speechAllowed in
            guard let self, self.generation == operation, self.state == .requestingPermission else { return }
            guard speechAllowed else {
                self.showTemporaryError("请允许语音识别权限")
                return
            }

            self.microphonePermission { [weak self] microphoneAllowed in
                guard let self, self.generation == operation, self.state == .requestingPermission else { return }
                guard microphoneAllowed else {
                    self.showTemporaryError("请允许麦克风权限")
                    return
                }
                self.startRecording(operation: operation)
            }
        }
    }

    private static func requestSpeechPermission(completion: @escaping (Bool) -> Void) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            completion(true)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    completion(status == .authorized)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    private static func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                DispatchQueue.main.async {
                    completion(allowed)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    private func startRecording(operation: Int) {
        guard generation == operation, state == .requestingPermission else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            showTemporaryError("语音识别服务暂不可用")
            return
        }

        finishAudioCapture(cancelTask: true)
        transcript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            recognitionRequest = nil
            showTemporaryError("没有可用的麦克风输入")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        hasInstalledAudioTap = true

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.generation == operation else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.stopRecording()
                    }
                }

                if let error, !self.isCancellationError(error) {
                    self.finishAudioCapture(cancelTask: true)
                    if self.transcript.isEmpty {
                        self.showTemporaryError("识别失败，请重试")
                    } else {
                        self.state = .ready
                    }
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            state = .recording
        } catch {
            finishAudioCapture(cancelTask: true)
            showTemporaryError("无法启动麦克风")
        }
    }

    private func showTemporaryError(_ message: String) {
        errorResetWorkItem?.cancel()
        state = .error(message)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, case .error = self.state else {
                return
            }
            self.errorResetWorkItem = nil
            self.state = self.transcript.isEmpty ? .idle : .ready
        }
        errorResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + errorDisplayDuration, execute: workItem)
    }

    private func finishAudioCapture(cancelTask: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        if hasInstalledAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledAudioTap = false
        }

        recognitionRequest?.endAudio()
        if cancelTask {
            recognitionTask?.cancel()
        }
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func isCancellationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216
    }
}
