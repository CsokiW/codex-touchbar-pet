import Foundation

// Only turn status and timing fields are projected from desktop messages.
struct CodexTurnTiming: Equatable {
    var startedAt: Date?
    var duration: TimeInterval?
    var status: String

    init(_ object: [String: Any]) {
        startedAt = Self.date(object["turnStartedAtMs"])
        duration = (object["durationMs"] as? NSNumber).map { max(0, $0.doubleValue / 1000) }
        status = object["status"] as? String ?? ""
    }

    static func date(_ value: Any?) -> Date? {
        guard let milliseconds = value as? NSNumber, milliseconds.doubleValue.isFinite,
              milliseconds.doubleValue > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds.doubleValue / 1000)
    }

    mutating func set(_ field: String, value: Any?) {
        switch field {
        case "turnStartedAtMs": startedAt = Self.date(value)
        case "durationMs": duration = (value as? NSNumber).map { max(0, $0.doubleValue / 1000) }
        case "status": status = value as? String ?? ""
        default: break
        }
    }

    static func entities(_ value: Any?) -> [String: CodexTurnTiming] {
        guard let objects = value as? [String: [String: Any]] else { return [:] }
        // Each value is immediately reduced to three fields; no message contents are retained.
        let projected = objects.mapValues(CodexTurnTiming.init)
        let latest = projected.sorted { ($0.value.startedAt ?? .distantPast) > ($1.value.startedAt ?? .distantPast) }.prefix(32)
        return Dictionary(uniqueKeysWithValues: latest.map { ($0.key, $0.value) })
    }

    static func fromState(_ state: [String: Any]) -> [String: CodexTurnTiming] {
        if let history = state["turnHistory"] as? [String: Any],
           let contents = history["history"] as? [String: Any] {
            return entities(contents["entitiesByKey"])
        }
        if let turns = state["turns"] as? [[String: Any]] {
            return Dictionary(uniqueKeysWithValues: turns.suffix(32).enumerated().map { (String($0.offset), CodexTurnTiming($0.element)) })
        }
        return [:]
    }
}

struct CodexTaskCompletion: Equatable {
    let sequence: Int
    let outcome: String
    let duration: TimeInterval?
    let observedAt: Date
}

struct CodexTaskInfo: Equatable {
    var activity: CodexPetActivity = .idle
    var waitingLabel: String?
    var startedAt: Date?
    var activeCount: Int = 0
    var completionCount: Int = 0
    var completion: CodexTaskCompletion?

    static func durationText(_ duration: TimeInterval) -> String {
        let seconds = Int(max(0, duration).rounded(.down))
        if seconds >= 86400 { return "\(seconds / 86400)天\((seconds % 86400) / 3600)时" }
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func labels(now: Date) -> (elapsed: String, message: String, kind: String) {
        let recent = completion.flatMap { now.timeIntervalSince($0.observedAt) < 20 ? $0 : nil }
        let elapsed: String
        if let startedAt, activeCount > 0 { elapsed = Self.durationText(now.timeIntervalSince(startedAt)) }
        else if activeCount == 0, let duration = recent?.duration { elapsed = Self.durationText(duration) }
        else { elapsed = "" }
        if activity == .offline { return ("", "", "idle") }
        if activity == .waiting { return (elapsed, "等回应", "waiting") }
        if let recent {
            switch recent.outcome {
            case "completed": return (elapsed, completionCount > 1 ? "✓ \(completionCount)完成" : "✓ 完成", "completed")
            case "interrupted": return (elapsed, "已停止", "stopped")
            default: return (elapsed, "出错", "failed")
            }
        }
        if activity == .failed { return (elapsed, "出错", "failed") }
        if activeCount > 1 { return (elapsed, "\(activeCount)任务", "running") }
        return (elapsed, "", "idle")
    }
}

struct CodexTaskTracker {
    private var observed: [String: [Date: String]] = [:]
    private var sequence = 0
    private var completionCount = 0
    private var completion: CodexTaskCompletion?
    private var completionStart: Date?
    private var completionThread: String?

    mutating func update(_ statuses: [String: PetThreadStatus], now: Date = Date()) -> CodexTaskInfo {
        // Disappearing owners, reconnects and missing revisions cannot be completion events.
        observed = observed.filter { statuses[$0.key] != nil }
        for id in statuses.keys.sorted() {
            guard let status = statuses[id] else { continue }
            var previous = observed[id] ?? [:]
            for timing in status.timings.values.sorted(by: { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }) {
                guard let start = timing.startedAt else { continue }
                if previous[start] == "inProgress", ["completed", "interrupted", "failed"].contains(timing.status) {
                    sequence += 1
                    let nearby = completion.map { now.timeIntervalSince($0.observedAt) < 20 && $0.outcome == "completed" } ?? false
                    completionCount = timing.status == "completed" ? (nearby ? completionCount + 1 : 1) : 0
                    completionStart = start
                    completionThread = id
                    completion = CodexTaskCompletion(sequence: sequence, outcome: timing.status,
                        duration: timing.duration, observedAt: now)
                }
                if completionThread == id, completionStart == start,
                   let prior = completion, let duration = timing.duration, prior.duration != duration {
                    completion = CodexTaskCompletion(sequence: prior.sequence, outcome: prior.outcome,
                        duration: duration, observedAt: prior.observedAt)
                }
                previous[start] = timing.status
            }
            let liveStarts = Set(status.timings.values.compactMap(\.startedAt))
            observed[id] = previous.filter { liveStarts.contains($0.key) }
        }
        let active = statuses.values.filter { $0.activity == .running || $0.activity == .waiting }
        let starts = active.compactMap { status in
            status.timings.values.filter { $0.status == "inProgress" }.compactMap(\.startedAt).max()
        }
        return CodexTaskInfo(activity: PetThreadStatus.aggregate(Array(statuses.values)),
                             waitingLabel: statuses.values.contains { ($0.runtime["activeFlags"] as? [String] ?? []).contains("waitingOnApproval") } ? "待批准" :
                                (statuses.values.contains { ($0.runtime["activeFlags"] as? [String] ?? []).contains("waitingOnUserInput") } ? "待回复" : nil),
                             startedAt: starts.min(), activeCount: active.count,
                             completionCount: completionCount, completion: completion)
    }
}
