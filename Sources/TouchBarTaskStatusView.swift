import AppKit

// One stable touch target: refresh in Codex, return to Codex in other apps.
final class TouchBarTaskStatusView: NSView {
    enum Action: Equatable { case refresh, returnToCodex }
    var onRefresh: (() -> Void)?
    var onReturn: (() -> Void)?
    var codexFrontmostProvider: (() -> Bool)?
    private let button = NSButton()
    private var observing = false
    private var codexIsFrontmost = false
    private var refreshing = false
    private var needsAttention = false

    var currentAction: Action { codexIsFrontmost ? .refresh : .returnToCodex }

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = #selector(performContextAction)
        button.bezelStyle = .rounded
        button.isBordered = true
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 12.5, weight: .semibold)
        button.setButtonType(.momentaryPushIn)
        addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        refreshFrontmostApplication()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func start() {
        guard !observing else { return }
        observing = true
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(frontmostChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        refreshFrontmostApplication()
    }

    func stop() {
        observing = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func update(_ info: CodexTaskInfo, now: Date = Date()) {
        needsAttention = info.activity == .waiting || info.activity == .failed
        render()
    }

    func updateRefreshing(_ value: Bool) {
        refreshing = value
        render()
    }

    // Separate context input also lets verification exercise both modes without switching the user's apps.
    func setCodexFrontmost(_ value: Bool) {
        codexIsFrontmost = value
        render()
    }

    @objc private func frontmostChanged(_ notification: Notification) {
        refreshFrontmostApplication()
    }

    private func refreshFrontmostApplication() {
        if let provider = codexFrontmostProvider { setCodexFrontmost(provider()); return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        // A menu belonging to this accessory app should preserve the previous working context.
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        setCodexFrontmost(CodexLifecycleMonitor.isCodex(app))
    }

    @objc func performContextAction() {
        refreshFrontmostApplication()
        switch currentAction {
        case .refresh:
            guard !refreshing else { return }
            onRefresh?()
        case .returnToCodex:
            if let onReturn { onReturn() }
            else {
                NSWorkspace.shared.runningApplications.first(where: CodexLifecycleMonitor.isCodex)?
                    .activate(options: [.activateAllWindows])
            }
        }
    }

    private func render() {
        let symbol: String
        switch currentAction {
        case .refresh:
            button.title = refreshing ? "刷新中" : "刷新"
            symbol = "arrow.clockwise"
            button.toolTip = needsAttention ? "Codex 有待处理事项；点此刷新额度" : "刷新 Codex 额度"
            button.isEnabled = !refreshing
        case .returnToCodex:
            button.title = needsAttention ? "待处理" : "返回"
            symbol = needsAttention ? "exclamationmark.circle.fill" : "arrow.uturn.backward"
            button.toolTip = needsAttention ? "有任务等待回应或需要查看错误；点此切回 Codex" : "切回 Codex"
            button.isEnabled = true
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        button.bezelColor = needsAttention ? .systemOrange : nil
        button.contentTintColor = needsAttention ? .black : .labelColor
        button.setAccessibilityLabel(button.toolTip)
        toolTip = button.toolTip
    }

    deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }
}
