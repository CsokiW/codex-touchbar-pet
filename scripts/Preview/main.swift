import AppKit

// Render the actual native view with synthetic values. No data clients are started.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let previewTarget = NSObject()
let view = TouchBarRateLimitsView(voiceTarget: previewTarget, toggleVoiceAction: NSSelectorFromString("previewAction:"))
view.frame = NSRect(x: 0, y: 0, width: 624, height: 30)
view.wantsLayer = true
view.layer?.backgroundColor = NSColor.black.cgColor
view.appearance = NSAppearance(named: .darkAqua)
var state = RateLimitDisplayState.initial
let reset: Double = 1_792_324_800
state.fiveHour = LimitMeter(title: "5 小时", shortTitle: "5h",
    window: RateLimitWindow(usedPercent: 24, windowDurationMins: 300, resetsAt: reset))
state.weekly = LimitMeter(title: "周限额", shortTitle: "W",
    window: RateLimitWindow(usedPercent: 42, windowDurationMins: 10080, resetsAt: reset + 259200))
state.lastUpdated = Date(timeIntervalSince1970: reset - 3600)
view.update(with: state)
view.updateTaskInfo(CodexTaskInfo(activity: .running, activeCount: 1))
view.layoutSubtreeIfNeeded()
guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
    fatalError("Cannot allocate native view preview")
}
view.cacheDisplay(in: view.bounds, to: bitmap)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Cannot encode preview")
}
try png.write(to: URL(fileURLWithPath: "docs/touchbar-preview.png"))
print("Rendered synthetic native Touch Bar preview; no Codex data clients were started.")
