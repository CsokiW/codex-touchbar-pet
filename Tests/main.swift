import Foundation
import ImageIO

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

let art = URL(fileURLWithPath: "Resources/TouchBarPet.webp")
let data = try Data(contentsOf: art)
check(TouchBarPetView.spriteFrames(data: data)?.count == 11, "bundled original pet has valid animation rows")
print("\(checks) synthetic checks passed; no Codex account data was opened.")
