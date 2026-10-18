import Foundation
import ImageIO
import AppKit

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    precondition(condition(), name)
    checks += 1
    print("PASS: \(name)")
}

let now = Date(timeIntervalSince1970: 1_800_000_000)
let start = now.addingTimeInterval(-10)
func timing(_ status: String, duration: Double? = nil) -> CodexTurnTiming {
    var value: [String: Any] = ["turnStartedAtMs": start.timeIntervalSince1970 * 1000, "status": status]
    if let duration { value["durationMs"] = duration * 1000 }
    return CodexTurnTiming(value)
}
let running = PetThreadStatus(revision: 1, runtime: ["type": "active"], requestCount: 0,
                              timings: ["turn": timing("inProgress")])
let waiting = PetThreadStatus(revision: 1,
    runtime: ["type": "active", "activeFlags": ["waitingOnApproval"]], requestCount: 0)
check(running.activity == .running, "running task")
check(waiting.activity == .waiting, "approval wait")
check(PetThreadStatus.aggregate([running, waiting]) == .waiting, "waiting has priority")
check(PetThreadStatus(revision: 1, runtime: [:], requestCount: 1).activity == .waiting, "pending input")

var tracker = CodexTaskTracker()
let initial = tracker.update(["synthetic-task": running], now: now)
check(initial.completion == nil && initial.activeCount == 1, "initial running task is not completion")
let completed = PetThreadStatus(revision: 2, runtime: ["type": "idle"], requestCount: 0,
                                timings: ["turn": timing("completed", duration: 10)])
let done = tracker.update(["synthetic-task": completed], now: now)
check(done.completion?.outcome == "completed" && done.completion?.duration == 10, "observed completion")
check(tracker.update(["synthetic-task": completed], now: now).completion?.sequence == done.completion?.sequence,
      "repeated snapshot does not double-count completion")
var reconnected = CodexTaskTracker()
check(reconnected.update(["synthetic-task": completed], now: now).completion == nil,
      "historical completion after reconnect is ignored")
check(CodexTaskInfo.durationText(65) == "01:05", "timing format")

var patched = running
check(!patched.apply(["baseRevision": 99, "revision": 100, "patches": []]), "out-of-sequence patch rejected")
check(patched.apply(["baseRevision": 1, "revision": 2, "patches": [
    ["op": "replace", "path": ["threadRuntimeStatus"], "value": ["type": "active", "activeFlags": ["waitingOnUserInput"]]]
]]), "valid status patch accepted")
check(patched.activity == .waiting, "status patch updates waiting state")

let encoded = try PetIPCFrames.encode(["type": "test", "sequence": 7])
var framing = PetIPCFrames()
let first = try framing.append(encoded.prefix(2))
check(first.isEmpty, "partial IPC header buffered")
let second = try framing.append(encoded.dropFirst(2))
check(second.count == 1 && second[0]["sequence"] as? Int == 7, "fragmented IPC message decoded")

let art = URL(fileURLWithPath: "Resources/TouchBarPet.png")
let data = try Data(contentsOf: art)
check(TouchBarPetView.spriteFrames(data: data)?.count == 11, "bundled original pet has valid animation rows")

func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 3) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    precondition(condition(), "Asynchronous test timed out")
}

let quotaResponse = GetAccountRateLimitsResponse(rateLimits:
    RateLimitSnapshot(limitId: "codex", limitName: nil,
        primary: RateLimitWindow(usedPercent: 25, windowDurationMins: 300, resetsAt: nil), secondary: nil),
    rateLimitsByLimitId: nil, rateLimitResetCredits: nil)
final class FakeQuotaClient: CodexRateLimitClient {
    var onRateLimitsUpdated: (() -> Void)?
    var startError: Error?
    var readError: Error?
    var starts = 0
    var stops = 0
    var deferRead = false
    var pendingRead: ((Result<GetAccountRateLimitsResponse, Error>) -> Void)?
    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        starts += 1
        completion(startError.map { .failure($0) } ?? .success(()))
    }
    func stop() { stops += 1 }
    func readRateLimits(completion: @escaping (Result<GetAccountRateLimitsResponse, Error>) -> Void) {
        if deferRead { pendingRead = completion }
        else { completion(readError.map { .failure($0) } ?? .success(quotaResponse)) }
    }
}
final class QuotaObserver: RateLimitStoreDelegate {
    var state = RateLimitDisplayState.initial
    func rateLimitStore(_ store: RateLimitStore, didUpdate state: RateLimitDisplayState) { self.state = state }
}
let fakeQuota = FakeQuotaClient()
let quotaObserver = QuotaObserver()
let quotaStore = RateLimitStore(client: fakeQuota)
quotaStore.delegate = quotaObserver
fakeQuota.startError = CodexAppServerError.processUnavailable
quotaStore.start()
check(quotaObserver.state.errorMessage != nil && !quotaObserver.state.isRefreshing, "startup failure releases refresh lock")
fakeQuota.startError = nil
quotaStore.start()
check(fakeQuota.starts == 2 && quotaObserver.state.fiveHour?.remainingPercent == 75, "Refresh retries failed backend startup")
fakeQuota.readError = CodexAppServerError.processUnavailable
quotaStore.refresh()
check(quotaObserver.state.isStale && quotaObserver.state.fiveHour?.remainingPercent == 75, "failed refresh marks retained values stale")
check(quotaObserver.state.statusText.contains("旧值") && quotaObserver.state.statusText.contains("上次更新"), "stale state reports last successful update")
fakeQuota.readError = nil
quotaStore.refresh()
check(!quotaObserver.state.isStale && quotaObserver.state.errorMessage == nil, "successful retry clears stale warning")
fakeQuota.deferRead = true
quotaStore.refresh()
let obsoleteRead = fakeQuota.pendingRead
quotaStore.stop()
obsoleteRead?(.failure(CodexAppServerError.serverError("obsolete")))
quotaStore.start()
check(quotaObserver.state.isRefreshing, "new refresh is not completed by stopped session")
obsoleteRead?(.success(quotaResponse))
check(quotaObserver.state.isRefreshing, "late response from stopped session is ignored")
fakeQuota.pendingRead?(.success(quotaResponse))
check(!quotaObserver.state.isRefreshing, "current response completes new session")
quotaStore.stop()

let retryClient = FakeQuotaClient()
retryClient.startError = CodexAppServerError.processUnavailable
let retryStore = RateLimitStore(client: retryClient, refreshInterval: 0.03)
retryStore.start()
retryClient.startError = nil
waitUntil { retryClient.starts >= 2 }
check(retryClient.starts >= 2, "timer retries after startup failure")
retryStore.stop()

func fixture(_ name: String, timeout: TimeInterval = 1) -> CodexAppServerClient {
    CodexAppServerClient(codexCandidates: [URL(fileURLWithPath: ".build/synthetic-tests/\(name)-fixture")], requestTimeout: timeout)
}
let stalledClient = fixture("timeout")
let stalledObserver = QuotaObserver()
let stalledStore = RateLimitStore(client: stalledClient)
stalledStore.delegate = stalledObserver
stalledStore.start()
waitUntil { stalledObserver.state.errorMessage != nil }
check(!stalledObserver.state.isRefreshing, "real transport timeout releases store refresh lock")
stalledStore.start()
check(stalledObserver.state.isRefreshing, "refresh can retry after timeout")
waitUntil { !stalledObserver.state.isRefreshing }
check(stalledObserver.state.errorMessage != nil, "second stalled request also terminates")
stalledStore.stop()
let handshakeClient = fixture("initialize-timeout")
var handshakeFinished = false
handshakeClient.start { result in
    if case .failure = result { handshakeFinished = true }
}
waitUntil { handshakeFinished }
check(handshakeFinished, "initialization also has a bounded timeout")
handshakeClient.stop()
let healthyClient = fixture("success", timeout: 2)
var healthyReads = 0
func readHealthyFixture() {
    healthyClient.start { result in
        guard case .success = result else { preconditionFailure("Fixture initialization failed: \(result)") }
        healthyClient.readRateLimits { result in
            if case .success(let value) = result, value.rateLimits.primary?.usedPercent == 25 { healthyReads += 1 }
        }
    }
}
readHealthyFixture()
waitUntil { healthyReads == 1 }
healthyClient.stop()
readHealthyFixture()
waitUntil { healthyReads == 2 }
check(healthyReads == 2, "transport reinitializes successfully after stop")
healthyClient.stop()

var speechReply: ((Bool) -> Void)?
var microphoneRequests = 0
let cancelledSpeech = SpeechInputController(speechPermission: { speechReply = $0 }, microphonePermission: {
    microphoneRequests += 1
    $0(false) // Synthetic tests never grant capture permission.
})
cancelledSpeech.toggleRecording()
cancelledSpeech.toggleRecording()
speechReply?(true)
check(cancelledSpeech.state == .idle && microphoneRequests == 0, "cancelled speech authorization cannot request microphone")
var microphoneReply: ((Bool) -> Void)?
let cancelledMicrophone = SpeechInputController(speechPermission: { $0(true) }, microphonePermission: { microphoneReply = $0 })
cancelledMicrophone.toggleRecording()
cancelledMicrophone.toggleRecording()
microphoneReply?(false)
check(cancelledMicrophone.state == .idle, "late microphone authorization cannot change cancelled state")

final class FakeTextInserter: SpeechTextInserting {
    var reply: ((Result<Void, Error>) -> Void)?
    var cancelled: (() -> Bool)?
    var immediateError: Error?
    func insert(_ text: String, isCancelled: @escaping () -> Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        cancelled = isCancelled
        reply = completion
        if let immediateError { completion(.failure(immediateError)) }
    }
}
let permissionInserter = FakeTextInserter()
permissionInserter.immediateError = SpeechInsertionError.accessibilityRequired
let retainedSpeech = SpeechInputController(textInserter: permissionInserter, errorDisplayDuration: 0.03,
                                         initialTranscript: "合成测试文字")
retainedSpeech.toggleRecording()
waitUntil { retainedSpeech.state == .ready }
check(retainedSpeech.transcript == "合成测试文字", "accessibility warning preserves transcript after timeout")
permissionInserter.immediateError = nil
retainedSpeech.toggleRecording()
permissionInserter.reply?(.success(()))
check(retainedSpeech.transcript.isEmpty && retainedSpeech.state == .idle, "successful insertion clears transcript")
let pendingInserter = FakeTextInserter()
let pendingSpeech = SpeechInputController(speechPermission: { _ in }, textInserter: pendingInserter,
                                         initialTranscript: "合成测试文字")
pendingSpeech.toggleRecording()
pendingSpeech.clear()
check(pendingInserter.cancelled?() == true, "clear cancels pending focus activation and insertion")
pendingSpeech.toggleRecording()
pendingInserter.reply?(.success(()))
check(pendingSpeech.state == .requestingPermission, "late insertion callback cannot reset a newer operation")
pendingSpeech.clear()
check(CodexSpeechTextInserter.permits(role: "AXTextArea", subrole: nil, enabled: true), "editable text area may receive speech")
check(!CodexSpeechTextInserter.permits(role: "AXButton", subrole: nil, enabled: true), "non-text control cannot receive speech")
check(!CodexSpeechTextInserter.permits(role: "AXTextField", subrole: "AXSecureTextField", enabled: true), "secure field cannot receive speech")
check(!CodexSpeechTextInserter.permits(role: "AXTextField", subrole: nil, enabled: false), "disabled field cannot receive speech")

let quotaView = TouchBarRateLimitsView(voiceTarget: NSObject(), toggleVoiceAction: NSSelectorFromString("unused"))
var viewState = quotaObserver.state
viewState.errorMessage = "synthetic failure"
quotaView.update(with: viewState)
func labels(_ view: NSView) -> [String] {
    (view as? NSTextField).map { [$0.stringValue] } ?? view.subviews.flatMap(labels)
}
check(labels(quotaView).contains("旧 75%"), "Touch Bar explicitly labels stale quota")
check(labels(quotaView).contains(where: { $0.contains("上次更新") }), "Touch Bar stale quota includes timestamp")
viewState.errorMessage = nil
quotaView.update(with: viewState)
check(labels(quotaView).contains("剩余 75%") && !labels(quotaView).contains("旧 75%"), "successful update restores normal quota labels")
print("\(checks) synthetic checks passed; no Codex account data, recording or real keyboard input was used.")
