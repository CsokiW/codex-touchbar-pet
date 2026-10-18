import AppKit
import ImageIO

final class TouchBarPetView: NSView {
    private var frames: [[NSImage]] = []
    private var activity: CodexPetActivity = .idle
    private var row = 0
    private var column = 0
    private var timer: Timer?
    private var animationEnabled = false
    private var temporaryUntil = Date.distantPast
    private var petName = "王臭吉"
    private var tapAnimation = false
    private var previousActivity: CodexPetActivity = .idle

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        if let url = Bundle.main.url(forResource: "TouchBarPet", withExtension: "webp") {
            loadSprite(at: url, name: petName)
        }
        refreshDescription()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func spriteFrames(data: Data) -> [[NSImage]]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil),
              sheet.width == 1536, [1872, 2288].contains(sheet.height) else { return nil }
        let counts = [6, 8, 8, 4, 5, 8, 6, 6, 6, 8, 8]
        var result = [[NSImage]]()
        for row in 0..<(sheet.height / 208) {
            var images = [NSImage]()
            for column in 0..<counts[row] {
                guard let crop = sheet.cropping(to: CGRect(x: column * 192, y: row * 208, width: 192, height: 208)) else { return nil }
                images.append(NSImage(cgImage: crop, size: NSSize(width: 192, height: 208)))
            }
            result.append(images)
        }
        return result
    }

    @discardableResult
    func loadSprite(at url: URL, name: String) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return loadSprite(data: data, name: name)
    }

    @discardableResult
    func loadSprite(data: Data, name: String) -> Bool {
        guard let frames = Self.spriteFrames(data: data) else { return false }
        self.frames = frames
        petName = name
        column = 0
        needsDisplay = true
        refreshDescription()
        return true
    }

    func setAnimationEnabled(_ enabled: Bool) {
        animationEnabled = enabled
        timer?.invalidate()
        timer = nil
        if enabled { scheduleFrame() }
    }

    func update(activity newActivity: CodexPetActivity) {
        guard activity != newActivity else { return }
        previousActivity = activity
        activity = newActivity
        tapAnimation = false
        temporaryUntil = .distantPast
        row = rowForActivity(newActivity)
        column = 0
        refreshDescription()
        needsDisplay = true
        timer?.invalidate()
        if animationEnabled { scheduleFrame() }
    }

    func celebrateCompletion() {
        temporaryUntil = Date().addingTimeInterval(2.2)
        row = 4
        column = 0
        needsDisplay = true
        timer?.invalidate()
        if animationEnabled { scheduleFrame() }
    }

    private func rowForActivity(_ activity: CodexPetActivity) -> Int {
        switch activity {
        case .idle, .offline: return 0
        case .running: return 7
        case .waiting: return 6
        case .failed: return 5
        case .jumping: return 4
        }
    }

    private func refreshDescription() {
        let label = "\(petName) · \(activity.label)"
        toolTip = label + "；点一下打招呼"
        setAccessibilityLabel(label)
    }

    override func mouseDown(with event: NSEvent) {
        tapAnimation = true
        temporaryUntil = Date().addingTimeInterval(1.8)
        row = 3
        column = 0
        timer?.invalidate()
        needsDisplay = true
        if animationEnabled { scheduleFrame() }
    }

    private func scheduleFrame() {
        guard animationEnabled, frames.indices.contains(row), !frames[row].isEmpty else { return }
        let idleDurations: [Double] = [1.68, 0.66, 0.66, 0.84, 0.84, 1.92]
        let normal: Double = row == 7 ? 0.12 : (row == 6 || row == 8 ? 0.15 : 0.14)
        let last: Double = row == 7 ? 0.22 : (row == 6 ? 0.26 : (row == 5 ? 0.24 : 0.28))
        let interval = row == 0 ? idleDurations[column % 6] : (column == frames[row].count - 1 ? last : normal)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.temporaryUntil != .distantPast && Date() >= self.temporaryUntil {
                self.row = self.rowForActivity(self.activity)
                self.column = 0
                self.temporaryUntil = .distantPast
                self.tapAnimation = false
            } else {
                self.column = (self.column + 1) % self.frames[self.row].count
            }
            self.needsDisplay = true
            self.scheduleFrame()
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard frames.indices.contains(row), frames[row].indices.contains(column) else { return }
        let height = min(30, bounds.height)
        let width = height * 192 / 208
        let rect = NSRect(x: (bounds.width - width) / 2 - 3, y: (bounds.height - height) / 2,
                          width: width, height: height)
        NSGraphicsContext.current?.imageInterpolation = .high
        frames[row][column].draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)

    }

    deinit { timer?.invalidate() }
}

// Follow custom desktop pets; never redistribute Codex's built-in artwork.
final class CodexPetAssetLoader {
    var onSprite: ((Data, String) -> Void)?
    private var timer: Timer?
    private var loadedKey = ""
    private var pendingKey: String?
    private var nextAttempt = Date.distantPast
    private var active = false
    private var task: URLSessionDataTask?

    func start() {
        guard !active else { return }
        active = true
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() {
        active = false
        timer?.invalidate(); timer = nil
        task?.cancel(); task = nil; pendingKey = nil
    }

    private func refresh() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/.codex-global-state.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let atoms = root["electron-persisted-atom-state"] as? [String: Any],
              let cache = atoms["cloud-pet-artwork-cache"] as? [String: Any],
              let account = cache["accountId"] as? String, let user = cache["userId"] as? String,
              let selection = atoms["last-observed-cloud-pet-selection-v1"] as? [String: Any],
              let accountJSON = try? JSONSerialization.data(withJSONObject: [account, user], options: .fragmentsAllowed),
              let accountKey = String(data: accountJSON, encoding: .utf8),
              let id = selection[accountKey] as? String else { return }
        let builtinIDs: Set<String> = ["codex", "bsod", "seedy", "hoots", "null-signal", "stacky", "dewey", "fireball", "rocky"]
        if builtinIDs.contains(id) {
            let key = "bundled-fallback:" + id
            if loadedKey != key, let bundled = Bundle.main.url(forResource: "TouchBarPet", withExtension: "webp"),
               let bytes = try? Data(contentsOf: bundled) {
                task?.cancel(); task = nil; pendingKey = nil
                loadedKey = key
                onSprite?(bytes, "王臭吉")
            }
            return
        }
        guard let pets = cache["pets"] as? [[String: Any]],
              let pet = pets.first(where: { $0["id"] as? String == id }) else { return }
        let fingerprint = String(describing: pet["spritesheetFingerprint"] ?? "")
        let key = id + ":" + fingerprint
        guard loadedKey != key, pendingKey == nil, Date() >= nextAttempt,
              let address = pet["spritesheetUrl"] as? String, let assetURL = URL(string: address),
              assetURL.scheme == "https" else { return }
        pendingKey = key
        var request = URLRequest(url: assetURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        task = URLSession.shared.dataTask(with: request) { [weak self] bytes, response, _ in
            DispatchQueue.main.async {
                guard let self, self.active, self.pendingKey == key else { return }
                self.pendingKey = nil; self.task = nil
                self.nextAttempt = Date().addingTimeInterval(30)
                guard let bytes, bytes.count < 16 * 1024 * 1024,
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      TouchBarPetView.spriteFrames(data: bytes) != nil else { return }
                self.loadedKey = key
                self.onSprite?(bytes, pet["name"] as? String ?? "Codex 宠物")
            }
        }
        task?.resume()
    }
}
