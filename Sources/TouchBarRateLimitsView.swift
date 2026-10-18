import AppKit

final class TouchBarRateLimitsView: NSView {
    private let petView = TouchBarPetView(frame: .zero)
    private let petMonitor = CodexPetStateMonitor()
    private let petAssets = CodexPetAssetLoader()
    private let activityDot = NSView()
    private let activityLabel = NSTextField(labelWithString: "未连接")
    private let taskStatusView = TouchBarTaskStatusView(frame: .zero)
    private var currentTaskInfo = CodexTaskInfo()
    private let fiveHourRow = TouchBarLimitRow(title: "5 小时")
    private let weeklyRow = TouchBarLimitRow(title: "周限额")
    private let rows = NSStackView()
    private let transcriptLabel = NSTextField(labelWithString: "点麦克风开始语音输入")
    private let microphoneButton = NSButton()

    init(
        voiceTarget: AnyObject,
        toggleVoiceAction: Selector,
        onRefresh: @escaping () -> Void = {}
    ) {
        super.init(frame: .zero)
        microphoneButton.target = voiceTarget
        microphoneButton.action = toggleVoiceAction
        taskStatusView.onRefresh = onRefresh
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with state: RateLimitDisplayState) {
        taskStatusView.updateRefreshing(state.isRefreshing)
        if let fiveHour = state.fiveHour {
            fiveHourRow.isHidden = false
            fiveHourRow.updateLimit(title: "5 小时", meter: fiveHour)
        } else if let resetCredits = state.resetCredits, resetCredits.availableCount > 0 {
            fiveHourRow.isHidden = false
            fiveHourRow.updateResetCredits(resetCredits)
        } else if state.lastUpdated != nil {
            fiveHourRow.isHidden = true
        } else {
            fiveHourRow.isHidden = false
            fiveHourRow.updatePlaceholder(title: "5 小时")
        }

        if let weekly = state.weekly {
            weeklyRow.isHidden = false
            weeklyRow.updateLimit(title: "周限额", meter: weekly)
        } else if state.lastUpdated != nil {
            weeklyRow.isHidden = true
        } else {
            weeklyRow.isHidden = false
            weeklyRow.updatePlaceholder(title: "周限额")
        }
        for row in [fiveHourRow, weeklyRow] {
            row.updateWarning(with: state)
        }
    }

    func startPet() {
        petMonitor.onActivity = { [weak self] activity in
            self?.updatePetActivity(activity)
        }
        petMonitor.onTasks = { [weak self] info in self?.updateTaskInfo(info) }
        taskStatusView.start()
        petAssets.onSprite = { [weak self] data, name in
            self?.petView.loadSprite(data: data, name: name)
        }
        petView.setAnimationEnabled(true)
        petMonitor.start()
        petAssets.start()
    }

    func updatePetActivity(_ activity: CodexPetActivity) {
        petView.update(activity: activity)
    }

    func updateTaskInfo(_ info: CodexTaskInfo) {
        let previousSequence = currentTaskInfo.completion?.sequence
        currentTaskInfo = info
        petView.update(activity: info.activity)
        taskStatusView.update(info)
        updateActivityStatus(info)
        if let completion = info.completion, completion.sequence != previousSequence,
           completion.outcome == "completed", Date().timeIntervalSince(completion.observedAt) < 20 {
            petView.celebrateCompletion()
        }
    }

    private func updateActivityStatus(_ info: CodexTaskInfo) {
        let color: NSColor
        switch info.activity {
        case .running, .jumping: color = .systemGreen
        case .waiting: color = .systemOrange
        case .failed: color = .systemRed
        case .idle, .offline: color = .systemGray
        }
        activityLabel.stringValue = info.activity == .waiting ? (info.waitingLabel ?? "待处理") : info.activity.label
        activityLabel.textColor = color
        activityDot.layer?.backgroundColor = color.cgColor
        activityLabel.toolTip = "Codex 任务状态 · " + activityLabel.stringValue
    }

    func stopPet() {
        taskStatusView.stop()
        updateTaskInfo(CodexTaskInfo(activity: .offline))
        updatePetActivity(.offline)
        petMonitor.stop()
        petAssets.stop()
        petView.setAnimationEnabled(false)
    }

    func updateVoice(state: SpeechInputController.State, transcript: String) {
        switch state {
        case .idle:
            rows.isHidden = false
            transcriptLabel.isHidden = true
            transcriptLabel.stringValue = "点麦克风开始语音输入"
            updateMicrophoneButton(
                symbolName: "waveform.circle.fill",
                color: .systemPurple,
                accessibilityLabel: "开始语音输入",
                toolTip: "开始中文语音输入；再次点击会切回 Codex，核对文本框后输入"
            )
        case .requestingPermission:
            rows.isHidden = true
            transcriptLabel.isHidden = false
            transcriptLabel.stringValue = "正在请求语音权限…"
            updateMicrophoneButton(
                symbolName: "xmark.circle.fill",
                color: .systemOrange,
                accessibilityLabel: "取消语音输入",
                toolTip: "取消权限请求"
            )
        case .recording:
            rows.isHidden = true
            transcriptLabel.isHidden = false
            transcriptLabel.stringValue = transcript.isEmpty ? "正在听，请说话…" : transcript
            updateMicrophoneButton(
                symbolName: "stop.circle.fill",
                color: .systemRed,
                accessibilityLabel: "停止并输入",
                toolTip: "停止识别并输入当前文字"
            )
        case .ready:
            rows.isHidden = true
            transcriptLabel.isHidden = false
            transcriptLabel.stringValue = transcript.isEmpty ? "没有识别到文字" : transcript
            updateMicrophoneButton(
                symbolName: transcript.isEmpty ? "waveform.circle.fill" : "arrow.up.circle.fill",
                color: transcript.isEmpty ? .systemPurple : .systemGreen,
                accessibilityLabel: transcript.isEmpty ? "重新录音" : "输入识别文字",
                toolTip: transcript.isEmpty ? "重新开始语音识别" : "输入当前识别文字"
            )
        case .error(let message):
            rows.isHidden = true
            transcriptLabel.isHidden = false
            transcriptLabel.stringValue = transcript.isEmpty ? message : "\(transcript) · \(message)"
            updateMicrophoneButton(
                symbolName: transcript.isEmpty ? "exclamationmark.circle.fill" : "arrow.up.circle.fill",
                color: .systemOrange,
                accessibilityLabel: transcript.isEmpty ? "语音识别失败" : "输入已识别文字",
                toolTip: message
            )
        }
    }

    private func updateMicrophoneButton(
        symbolName: String,
        color: NSColor,
        accessibilityLabel: String,
        toolTip: String
    ) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        microphoneButton.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityLabel
        )?.withSymbolConfiguration(configuration)
        microphoneButton.contentTintColor = color
        microphoneButton.setAccessibilityLabel(accessibilityLabel)
        microphoneButton.toolTip = toolTip
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false


        rows.setViews([fiveHourRow, weeklyRow], in: .leading)
        rows.translatesAutoresizingMaskIntoConstraints = false
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0

        transcriptLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        transcriptLabel.textColor = .labelColor
        transcriptLabel.lineBreakMode = .byTruncatingTail
        transcriptLabel.maximumNumberOfLines = 1
        transcriptLabel.isHidden = true
        transcriptLabel.translatesAutoresizingMaskIntoConstraints = false

        let voiceContent = NSView()
        voiceContent.translatesAutoresizingMaskIntoConstraints = false
        voiceContent.addSubview(rows)
        voiceContent.addSubview(transcriptLabel)

        microphoneButton.title = ""
        microphoneButton.imagePosition = .imageOnly
        microphoneButton.bezelStyle = .circular
        microphoneButton.isBordered = false
        microphoneButton.translatesAutoresizingMaskIntoConstraints = false
        updateMicrophoneButton(
            symbolName: "waveform.circle.fill",
            color: .systemPurple,
            accessibilityLabel: "开始语音输入",
            toolTip: "开始中文语音输入；再次点击会切回 Codex，核对文本框后输入"
        )

        activityDot.wantsLayer = true
        activityDot.layer?.cornerRadius = 4
        activityDot.translatesAutoresizingMaskIntoConstraints = false
        activityLabel.font = .systemFont(ofSize: 12, weight: .medium)
        activityLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let activityStatus = NSStackView(views: [activityDot, activityLabel])
        activityStatus.orientation = .horizontal
        activityStatus.alignment = .centerY
        activityStatus.spacing = 5
        activityStatus.translatesAutoresizingMaskIntoConstraints = false
        updateActivityStatus(CodexTaskInfo(activity: .offline))
        let content = NSStackView(views: [petView, activityStatus, voiceContent, taskStatusView, microphoneButton])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 6
        content.setCustomSpacing(2, after: petView)
        content.setCustomSpacing(8, after: voiceContent)

        addSubview(content)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 624),
            heightAnchor.constraint(equalToConstant: 30),
            petView.widthAnchor.constraint(equalToConstant: 44),
            petView.heightAnchor.constraint(equalToConstant: 30),
            activityStatus.widthAnchor.constraint(equalToConstant: 70),
            activityDot.widthAnchor.constraint(equalToConstant: 8),
            activityDot.heightAnchor.constraint(equalToConstant: 8),
            taskStatusView.widthAnchor.constraint(equalToConstant: 68),
            taskStatusView.heightAnchor.constraint(equalToConstant: 30),
            voiceContent.widthAnchor.constraint(equalToConstant: 364),
            voiceContent.heightAnchor.constraint(equalToConstant: 30),
            rows.leadingAnchor.constraint(equalTo: voiceContent.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: voiceContent.trailingAnchor),
            rows.centerYAnchor.constraint(equalTo: voiceContent.centerYAnchor),
            transcriptLabel.leadingAnchor.constraint(equalTo: voiceContent.leadingAnchor, constant: 6),
            transcriptLabel.trailingAnchor.constraint(equalTo: voiceContent.trailingAnchor, constant: -6),
            transcriptLabel.centerYAnchor.constraint(equalTo: voiceContent.centerYAnchor),
            fiveHourRow.widthAnchor.constraint(equalToConstant: 364),
            weeklyRow.widthAnchor.constraint(equalToConstant: 364),
            microphoneButton.widthAnchor.constraint(equalToConstant: 48),
            microphoneButton.heightAnchor.constraint(equalToConstant: 30),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            content.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }


}

private final class TouchBarLimitRow: NSView {
    private let titleLabel: NSTextField
    private let batteryBar = SegmentedBatteryBar()
    private let creditsIndicatorLabel = NSTextField(labelWithString: "")
    private let remainingLabel = NSTextField(labelWithString: "剩余 --")
    private let resetLabel = NSTextField(labelWithString: "-- 重置")

    init(title: String) {
        self.titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateLimit(title: String, meter: LimitMeter) {
        titleLabel.stringValue = title
        batteryBar.isHidden = false
        creditsIndicatorLabel.isHidden = true
        batteryBar.remainingPercent = meter.remainingPercent
        batteryBar.isDimmed = false
        remainingLabel.stringValue = "剩余 \(meter.remainingText)"
        resetLabel.stringValue = meter.resetText
    }

    func updateResetCredits(_ resetCredits: ResetCreditSummary) {
        titleLabel.stringValue = "重置券"
        batteryBar.isHidden = true
        creditsIndicatorLabel.isHidden = false
        creditsIndicatorLabel.stringValue = Self.creditIndicator(count: resetCredits.availableCount)
        remainingLabel.stringValue = resetCredits.availableText
        resetLabel.stringValue = resetCredits.expirationText
    }

    func updatePlaceholder(title: String) {
        titleLabel.stringValue = title
        batteryBar.isHidden = false
        creditsIndicatorLabel.isHidden = true
        batteryBar.remainingPercent = 0
        batteryBar.isDimmed = true
        remainingLabel.stringValue = "剩余 --"
        resetLabel.stringValue = "-- 重置"
    }

    func updateWarning(with state: RateLimitDisplayState) {
        toolTip = state.statusText
        remainingLabel.textColor = state.errorMessage == nil ? .labelColor : .systemOrange
        resetLabel.textColor = state.errorMessage == nil ? .labelColor : .systemOrange
        guard state.errorMessage != nil else { return }
        batteryBar.isDimmed = true
        if state.isStale {
            remainingLabel.stringValue = "旧 " + remainingLabel.stringValue.replacingOccurrences(of: "剩余 ", with: "")
            resetLabel.stringValue = state.lastUpdatedText
        } else {
            resetLabel.stringValue = "读取失败，请刷新"
        }
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .left

        creditsIndicatorLabel.font = .systemFont(ofSize: 11, weight: .bold)
        creditsIndicatorLabel.textColor = .systemTeal
        creditsIndicatorLabel.alignment = .left
        creditsIndicatorLabel.lineBreakMode = .byClipping
        creditsIndicatorLabel.isHidden = true

        remainingLabel.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        remainingLabel.textColor = .labelColor
        remainingLabel.lineBreakMode = .byTruncatingTail

        resetLabel.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        resetLabel.textColor = .labelColor
        resetLabel.lineBreakMode = .byTruncatingTail

        let statusContainer = NSView()
        statusContainer.translatesAutoresizingMaskIntoConstraints = false
        batteryBar.translatesAutoresizingMaskIntoConstraints = false
        creditsIndicatorLabel.translatesAutoresizingMaskIntoConstraints = false
        statusContainer.addSubview(batteryBar)
        statusContainer.addSubview(creditsIndicatorLabel)

        let row = NSStackView(views: [
            titleLabel,
            statusContainer,
            remainingLabel,
            resetLabel
        ])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 4
        row.setCustomSpacing(4, after: titleLabel)
        row.setCustomSpacing(0, after: remainingLabel)

        addSubview(row)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 15),
            titleLabel.widthAnchor.constraint(equalToConstant: 44),
            statusContainer.widthAnchor.constraint(equalToConstant: 110),
            statusContainer.heightAnchor.constraint(equalToConstant: 12),
            batteryBar.widthAnchor.constraint(equalToConstant: 110),
            batteryBar.heightAnchor.constraint(equalToConstant: 12),
            batteryBar.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor),
            batteryBar.topAnchor.constraint(equalTo: statusContainer.topAnchor),
            creditsIndicatorLabel.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor, constant: 5),
            creditsIndicatorLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusContainer.trailingAnchor),
            creditsIndicatorLabel.centerYAnchor.constraint(equalTo: statusContainer.centerYAnchor),
            remainingLabel.widthAnchor.constraint(equalToConstant: 66),
            resetLabel.widthAnchor.constraint(equalToConstant: 133),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private static func creditIndicator(count: Int) -> String {
        if count <= 5 {
            return Array(repeating: "●", count: max(0, count)).joined(separator: "  ")
        }
        return "●  × \(count)"
    }
}
