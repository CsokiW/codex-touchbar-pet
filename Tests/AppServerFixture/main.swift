import Foundation

// A local JSON-lines fixture, never a real Codex process or account.
let mode = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
while let line = readLine(), let data = line.data(using: .utf8),
      let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let id = request["id"] {
    let method = request["method"] as? String
    if mode == "initialize-timeout-fixture" || (mode == "timeout-fixture" && method != "initialize") { continue }
    let result: [String: Any] = method == "initialize" ? [:] : [
        "rateLimits": ["limitId": "codex", "primary": ["usedPercent": 25, "windowDurationMins": 300]]
    ]
    var response = try JSONSerialization.data(withJSONObject: ["id": id, "result": result])
    response.append(0x0A)
    try FileHandle.standardOutput.write(contentsOf: response)
}
