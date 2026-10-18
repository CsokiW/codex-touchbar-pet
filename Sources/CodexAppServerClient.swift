import Foundation

enum CodexAppServerError: LocalizedError {
    case processUnavailable
    case malformedResponse
    case serverError(String)
    case missingResult
    case requestTimedOut

    var errorDescription: String? {
        switch self {
        case .processUnavailable:
            return "Codex app-server is not running."
        case .malformedResponse:
            return "Codex app-server returned an unexpected response."
        case .serverError(let message):
            return message
        case .missingResult:
            return "Codex app-server response did not include a result."
        case .requestTimedOut:
            return "额度读取超时，请重试。"
        }
    }
}

protocol CodexRateLimitClient: AnyObject {
    var onRateLimitsUpdated: (() -> Void)? { get set }
    func start(completion: @escaping (Result<Void, Error>) -> Void)
    func stop()
    func readRateLimits(completion: @escaping (Result<GetAccountRateLimitsResponse, Error>) -> Void)
}

final class CodexAppServerClient: CodexRateLimitClient {
    typealias JSONDictionary = [String: Any]

    private static let defaultCandidates = [
        "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
        "/Applications/ChatGPT.app/Contents/Resources/codex",
        "/Applications/Codex.app/Contents/Resources/codex",
        "/Applications/GPT.app/Contents/Resources/codex"
    ].map(URL.init(fileURLWithPath:))
    private let codexCandidates: [URL]
    private let requestTimeout: TimeInterval
    private let queue = DispatchQueue(label: "CodexTouchBarPet.CodexAppServerClient")

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var outputBuffer = Data()
    private var nextRequestId = 1
    private var pendingResponses: [Int: (Result<Any, Error>) -> Void] = [:]
    private var pendingTimeouts: [Int: DispatchWorkItem] = [:]
    private var isInitialized = false
    private var connectionGeneration = UUID()

    init(codexCandidates: [URL]? = nil, requestTimeout: TimeInterval = 20) {
        self.codexCandidates = codexCandidates ?? Self.defaultCandidates
        self.requestTimeout = requestTimeout
    }

    var onRateLimitsUpdated: (() -> Void)?

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            if self.process?.isRunning == true, self.isInitialized {
                DispatchQueue.main.async {
                    completion(.success(()))
                }
                return
            }

            do {
                self.stopProcess(error: CodexAppServerError.processUnavailable)
                try self.launchProcess()
                self.initialize(completion: completion)
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func stop() {
        queue.async {
            self.stopProcess(error: CodexAppServerError.processUnavailable)
        }
    }

    private func stopProcess(error: Error) {
        connectionGeneration = UUID()
        isInitialized = false
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        inputPipe?.fileHandleForWriting.closeFile()
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        outputBuffer.removeAll()
        failPendingResponses(error)
    }

    func readRateLimits(completion: @escaping (Result<GetAccountRateLimitsResponse, Error>) -> Void) {
        request(method: "account/rateLimits/read", params: nil) { result in
            switch result {
            case .success(let value):
                do {
                    guard JSONSerialization.isValidJSONObject(value) else {
                        throw CodexAppServerError.malformedResponse
                    }
                    let data = try JSONSerialization.data(withJSONObject: value)
                    let response = try JSONDecoder().decode(GetAccountRateLimitsResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func launchProcess() throws {
        guard let codexURL = codexCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw CodexAppServerError.processUnavailable
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let generation = connectionGeneration

        process.executableURL = codexURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            self?.queue.async {
                guard self?.connectionGeneration == generation else { return }
                self?.consumeOutput(data)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        process.terminationHandler = { [weak self] _ in
            self?.queue.async {
                guard self?.connectionGeneration == generation else { return }
                self?.stopProcess(error: CodexAppServerError.processUnavailable)
            }
        }

        try process.run()

        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
    }

    private func initialize(completion: @escaping (Result<Void, Error>) -> Void) {
        let generation = connectionGeneration
        let capabilities: JSONDictionary = [
            "experimentalApi": true,
            "requestAttestation": false,
            "optOutNotificationMethods": [String]()
        ]

        let params: JSONDictionary = [
            "clientInfo": [
                "name": "codex-touchbar-pet",
                "title": "Codex Touch Bar Pet",
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.2"
            ],
            "capabilities": capabilities
        ]

        request(method: "initialize", params: params) { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard self.connectionGeneration == generation else {
                    DispatchQueue.main.async {
                        if case .failure(let error) = result { completion(.failure(error)) }
                        else { completion(.failure(CodexAppServerError.processUnavailable)) }
                    }
                    return
                }
                switch result {
                case .success:
                    self.isInitialized = true
                    DispatchQueue.main.async { completion(.success(())) }
                case .failure(let error):
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
    }

    private func request(method: String, params: Any?, completion: @escaping (Result<Any, Error>) -> Void) {
        queue.async {
            guard let writer = self.inputPipe?.fileHandleForWriting, self.process?.isRunning == true else {
                DispatchQueue.main.async {
                    completion(.failure(CodexAppServerError.processUnavailable))
                }
                return
            }

            let requestId = self.nextRequestId
            self.nextRequestId += 1
            self.pendingResponses[requestId] = { result in
                DispatchQueue.main.async {
                    completion(result)
                }
            }
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.pendingResponses[requestId] != nil else { return }
                self.stopProcess(error: CodexAppServerError.requestTimedOut)
            }
            self.pendingTimeouts[requestId] = timeout
            self.queue.asyncAfter(deadline: .now() + self.requestTimeout, execute: timeout)

            var payload: JSONDictionary = [
                "id": requestId,
                "method": method
            ]
            if let params {
                payload["params"] = params
            }

            do {
                let data = try JSONSerialization.data(withJSONObject: payload)
                var framed = data
                framed.append(0x0A)
                try writer.write(contentsOf: framed)
            } catch {
                self.pendingResponses.removeValue(forKey: requestId)
                self.pendingTimeouts.removeValue(forKey: requestId)?.cancel()
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private func consumeOutput(_ data: Data) {
        outputBuffer.append(data)

        while let newlineRange = outputBuffer.firstRange(of: Data([0x0A])) {
            let line = outputBuffer.subdata(in: outputBuffer.startIndex..<newlineRange.lowerBound)
            outputBuffer.removeSubrange(outputBuffer.startIndex..<newlineRange.upperBound)

            guard !line.isEmpty else {
                continue
            }
            consumeLine(line)
        }
    }

    private func consumeLine(_ data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let message = object as? JSONDictionary
        else {
            return
        }

        if let method = message["method"] as? String {
            if method == "account/rateLimits/updated" {
                DispatchQueue.main.async {
                    self.onRateLimitsUpdated?()
                }
            }
            return
        }

        guard let id = intRequestId(from: message["id"]) else {
            return
        }

        guard let completion = pendingResponses.removeValue(forKey: id) else {
            return
        }
        pendingTimeouts.removeValue(forKey: id)?.cancel()

        if let error = message["error"] as? JSONDictionary {
            let message = error["message"] as? String ?? "Codex app-server returned an error."
            completion(.failure(CodexAppServerError.serverError(message)))
            return
        }

        guard let result = message["result"] else {
            completion(.failure(CodexAppServerError.missingResult))
            return
        }

        completion(.success(result))
    }

    private func intRequestId(from value: Any?) -> Int? {
        if let id = value as? Int {
            return id
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    private func failPendingResponses(_ error: Error) {
        let completions = Array(pendingResponses.values)
        pendingResponses.removeAll()
        pendingTimeouts.values.forEach { $0.cancel() }
        pendingTimeouts.removeAll()

        completions.forEach { completion in
            completion(.failure(error))
        }
    }
}
