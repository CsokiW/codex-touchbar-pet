import Foundation
import Darwin
import SQLite3

// Only runtime status and pending-request counts are retained. Message text is discarded.
enum CodexPetActivity: String {
    case idle, running, waiting, failed, jumping, offline
    var label: String {
        switch self {
        case .idle: return "空闲"
        case .running: return "工作中"
        case .waiting: return "等你回应"
        case .failed: return "任务出错"
        case .jumping: return "已完成"
        case .offline: return "未连接"
        }
    }
}

struct PetThreadStatus {
    var revision: Int
    var runtime: [String: Any]
    var requestCount: Int
    var timings: [String: CodexTurnTiming] = [:]

    var activity: CodexPetActivity {
        let type = runtime["type"] as? String
        let flags = runtime["activeFlags"] as? [String] ?? []
        if requestCount > 0 || flags.contains("waitingOnApproval") || flags.contains("waitingOnUserInput") {
            return .waiting
        }
        if type == "systemError" { return .failed }
        if type == "active" { return .running }
        return .idle
    }

    static func snapshot(_ change: [String: Any]) -> PetThreadStatus? {
        guard let state = change["conversationState"] as? [String: Any],
              let revision = change["revision"] as? Int else { return nil }
        var result = PetThreadStatus(revision: revision,
            runtime: state["threadRuntimeStatus"] as? [String: Any] ?? [:],
            requestCount: (state["requests"] as? [Any])?.count ?? 0)
        result.timings = CodexTurnTiming.fromState(state)
        return result
    }

    mutating func apply(_ change: [String: Any]) -> Bool {
        guard change["baseRevision"] as? Int == revision,
              let next = change["revision"] as? Int,
              let patches = change["patches"] as? [[String: Any]] else { return false }
        for patch in patches {
            guard let path = patch["path"] as? [Any], let op = patch["op"] as? String else { continue }
            if path.isEmpty, let state = patch["value"] as? [String: Any] {
                runtime = state["threadRuntimeStatus"] as? [String: Any] ?? [:]
                requestCount = (state["requests"] as? [Any])?.count ?? 0
                timings = CodexTurnTiming.fromState(state)
                continue
            }
            guard let first = path.first as? String else { continue }
            if first == "turnHistory" {
                if path.count == 1 {
                    timings = CodexTurnTiming.fromState(["turnHistory": patch["value"] ?? [:]])
                } else if path.count == 2, path[1] as? String == "history" {
                    timings = CodexTurnTiming.fromState(["turnHistory": ["history": patch["value"] ?? [:]]])
                } else if path.count >= 3, path[1] as? String == "history", path[2] as? String == "entitiesByKey" {
                    if path.count == 3 { timings = CodexTurnTiming.entities(patch["value"]) }
                    else if let key = path[3] as? String {
                        if path.count == 4 {
                            if op == "remove" { timings.removeValue(forKey: key) }
                            else if let entity = patch["value"] as? [String: Any] { timings[key] = CodexTurnTiming(entity) }
                        } else if path.count == 5, let field = path[4] as? String {
                            if ["turnStartedAtMs", "durationMs", "status"].contains(field) {
                                if timings[key] == nil { timings[key] = CodexTurnTiming([:]) }
                                timings[key]?.set(field, value: op == "remove" ? nil : patch["value"])
                            }
                        }
                    }
                }
            } else if first == "threadRuntimeStatus" {
                if path.count == 1 {
                    runtime = patch["value"] as? [String: Any] ?? [:]
                } else if let key = path[1] as? String {
                    if path.count == 2 {
                        if op == "remove" { runtime.removeValue(forKey: key) }
                        else { runtime[key] = patch["value"] }
                    } else if key == "activeFlags", let index = path[2] as? Int {
                        var flags = runtime[key] as? [String] ?? []
                        if op == "remove", flags.indices.contains(index) { flags.remove(at: index) }
                        else if let value = patch["value"] as? String {
                            if op == "add", index <= flags.count { flags.insert(value, at: index) }
                            else if flags.indices.contains(index) { flags[index] = value }
                        }
                        runtime[key] = flags
                    }
                }
            } else if first == "requests" {
                if path.count == 1 { requestCount = (patch["value"] as? [Any])?.count ?? 0 }
                else if path.count == 2 {
                    if op == "add" { requestCount += 1 }
                    else if op == "remove" { requestCount = max(0, requestCount - 1) }
                }
            }
        }
        revision = next
        return true
    }

    static func aggregate(_ statuses: [PetThreadStatus]) -> CodexPetActivity {
        let activities = statuses.map(\.activity)
        if activities.contains(.waiting) { return .waiting }
        if activities.contains(.running) { return .running }
        if activities.contains(.failed) { return .failed }
        return .idle
    }
}

struct PetIPCFrames {
    private(set) var buffer = Data()
    mutating func append(_ bytes: Data) throws -> [[String: Any]] {
        buffer.append(bytes)
        var messages = [[String: Any]]()
        while buffer.count >= 4 {
            let length = buffer.prefix(4).enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
            guard length > 0, length <= 32 * 1024 * 1024 else {
                throw NSError(domain: "CodexPetIPC", code: 1)
            }
            guard buffer.count >= length + 4 else { break }
            let payload = buffer.subdata(in: 4..<(length + 4))
            buffer = Data(buffer.dropFirst(length + 4))
            if let message = try JSONSerialization.jsonObject(with: payload) as? [String: Any] {
                messages.append(message)
            }
        }
        return messages
    }

    static func encode(_ message: [String: Any]) throws -> Data {
        let payload = try JSONSerialization.data(withJSONObject: message)
        var length = UInt32(payload.count).littleEndian
        var data = Data(bytes: &length, count: 4)
        data.append(payload)
        return data
    }
}

final class CodexPetStateMonitor {
    var onActivity: ((CodexPetActivity) -> Void)?
    var onTasks: ((CodexTaskInfo) -> Void)?
    private let queue = DispatchQueue(label: "CodexBar.pet.status", qos: .utility)
    private let lock = NSLock()
    private var generation = 0
    private var descriptor: Int32 = -1
    private var running = false

    func start() {
        lock.lock()
        guard !running else { lock.unlock(); return }
        running = true
        generation += 1
        let token = generation
        lock.unlock()
        queue.async { [weak self] in self?.run(token: token) }
    }

    func stop() {
        lock.lock()
        running = false
        generation += 1
        if descriptor >= 0 { Darwin.shutdown(descriptor, SHUT_RDWR) }
        lock.unlock()
    }

    private func current(_ token: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return running && generation == token
    }

    private func publish(_ activity: CodexPetActivity, token: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.current(token) else { return }
            self.onActivity?(activity)
            if activity == .offline { self.onTasks?(CodexTaskInfo(activity: .offline)) }
        }
    }

    private func publishTasks(_ info: CodexTaskInfo, token: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.current(token) else { return }
            self.onTasks?(info)
        }
    }

    private func run(token: Int) {
        while current(token) {
            let fd = connectSocket()
            if fd < 0 {
                publish(.offline, token: token)
                Thread.sleep(forTimeInterval: 1)
                continue
            }
            lock.lock()
            if !running || generation != token {
                lock.unlock(); Darwin.close(fd); break
            }
            descriptor = fd
            lock.unlock()
            monitor(fd, token: token)
            lock.lock()
            if descriptor == fd { descriptor = -1 }
            lock.unlock()
            Darwin.close(fd)
            publish(.offline, token: token)
            if current(token) { Thread.sleep(forTimeInterval: 1) }
        }
    }

    private func connectSocket() -> Int32 {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/ipc/ipc.sock").path
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { Darwin.close(fd); return -1 }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 { Darwin.close(fd); return -1 }
        return fd
    }

    private func send(_ message: [String: Any], to fd: Int32) -> Bool {
        guard let data = try? PetIPCFrames.encode(message) else { return false }
        return data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                if count < 0 && errno == EINTR { continue }
                if count <= 0 { return false }
                offset += count
            }
            return true
        }
    }

    private func follow(_ id: String, following: Bool, client: String, fd: Int32) -> Bool {
        send(["type": "broadcast", "sourceClientId": client,
              "method": "thread-stream-following-changed", "version": 1,
              "params": ["conversationId": id, "hostId": "local", "following": following]], to: fd)
    }

    private func monitor(_ fd: Int32, token: Int) {
        let requestID = UUID().uuidString
        guard send(["type": "request", "requestId": requestID, "method": "initialize", "version": 1,
                    "params": ["clientType": "codexbar-pet"]], to: fd) else { return }
        var frames = PetIPCFrames()
        var client: String?
        var subscriptions = Set<String>()
        var statuses = [String: PetThreadStatus]()
        var owners = [String: String]()
        var nextDiscovery = Date.distantPast
        var lastActivity: CodexPetActivity?
        var tracker = CodexTaskTracker()
        var lastTaskInfo: CodexTaskInfo?
        let connectedAt = Date()
        var bytes = [UInt8](repeating: 0, count: 65536)
        while current(token) {
            if client == nil && Date().timeIntervalSince(connectedAt) > 5 { return }
            if let client, Date() >= nextDiscovery {
                // Include open and newly-created local chats without reading any chat contents.
                var ids = Set(Self.recentThreadIDs())
                ids.formUnion(statuses.filter { $0.value.activity == .running || $0.value.activity == .waiting }.keys)
                for id in ids.subtracting(subscriptions) {
                    guard follow(id, following: true, client: client, fd: fd) else { return }
                }
                for id in subscriptions.subtracting(ids) {
                    guard follow(id, following: false, client: client, fd: fd) else { return }
                    statuses.removeValue(forKey: id)
                    owners.removeValue(forKey: id)
                }
                subscriptions = ids
                nextDiscovery = Date().addingTimeInterval(3)
            }
            var event = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let polled = Darwin.poll(&event, 1, 250)
            if polled < 0 { if errno == EINTR { continue }; return }
            if event.revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 { return }
            if event.revents & Int16(POLLIN) != 0 {
                let count = Darwin.recv(fd, &bytes, bytes.count, 0)
                if count <= 0 { return }
                guard let messages = try? frames.append(Data(bytes.prefix(count))) else { return }
                for message in messages {
                    if message["type"] as? String == "client-discovery-request",
                       let request = message["requestId"] as? String, let client {
                        guard send(["type": "client-discovery-response", "requestId": request,
                                    "clientId": client, "canHandle": false], to: fd) else { return }
                    } else if message["method"] as? String == "client-status-changed",
                              let params = message["params"] as? [String: Any],
                              params["status"] as? String == "disconnected",
                              let owner = params["clientId"] as? String {
                        let lost = owners.filter { $0.value == owner }.map(\.key)
                        for id in lost {
                            statuses.removeValue(forKey: id)
                            owners.removeValue(forKey: id)
                            subscriptions.remove(id)
                        }
                        if !lost.isEmpty {
                            nextDiscovery = .distantPast
                            publish(.offline, token: token)
                            lastActivity = .offline
                        }
                    } else if message["requestId"] as? String == requestID,
                              let result = message["result"] as? [String: Any] {
                        client = result["clientId"] as? String
                    } else if message["method"] as? String == "thread-stream-state-changed",
                              let params = message["params"] as? [String: Any],
                              params["hostId"] as? String == "local",
                              let id = params["conversationId"] as? String, subscriptions.contains(id),
                              let change = params["change"] as? [String: Any] {
                        if let owner = message["sourceClientId"] as? String { owners[id] = owner }
                        if change["type"] as? String == "snapshot" {
                            statuses[id] = PetThreadStatus.snapshot(change)
                        } else if change["type"] as? String == "patches" {
                            if statuses[id]?.apply(change) != true {
                                // A missing revision must never leave a stale working animation.
                                statuses.removeValue(forKey: id)
                                if let client {
                                    guard follow(id, following: false, client: client, fd: fd),
                                          follow(id, following: true, client: client, fd: fd) else { return }
                                }
                            }
                        }
                    }
                }
            }
            let info = tracker.update(statuses)
            if info != lastTaskInfo {
                publishTasks(info, token: token)
                lastTaskInfo = info
            }
            let activity = info.activity
            if activity != lastActivity {
                publish(activity, token: token)
                lastActivity = activity
            }
        }
    }

    static func recentThreadIDs() -> [String] {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/state_5.sqlite").path
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }; return []
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 100)
        var statement: OpaquePointer?
        let sql = "SELECT id FROM threads WHERE archived = 0 ORDER BY COALESCE(updated_at_ms, updated_at * 1000) DESC LIMIT 40"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var ids = [String]()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) { ids.append(String(cString: text)) }
        }
        return ids
    }
}
