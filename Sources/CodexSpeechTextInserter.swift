import AppKit
import ApplicationServices

protocol SpeechTextInserting {
    func insert(_ text: String, isCancelled: @escaping () -> Bool,
                completion: @escaping (Result<Void, Error>) -> Void)
}

enum SpeechInsertionError: LocalizedError {
    case accessibilityRequired, noTarget, focusChanged, cancelled, unavailable

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired: return "允许辅助功能后再点“输入”，文字已保留"
        case .noTarget: return "没有找到正在运行的 Codex"
        case .focusChanged: return "请点选 Codex 文本框后再点“输入”，文字已保留"
        case .cancelled: return "已取消输入"
        case .unavailable: return "无法输入文字，请重试"
        }
    }
}

/// Never posts global keystrokes: the validated field belongs to one host PID.
struct CodexSpeechTextInserter: SpeechTextInserting {
    func insert(_ text: String, isCancelled: @escaping () -> Bool,
                completion: @escaping (Result<Void, Error>) -> Void) {
        guard !isCancelled() else { completion(.failure(SpeechInsertionError.cancelled)); return }
        guard AXIsProcessTrusted() else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            completion(.failure(SpeechInsertionError.accessibilityRequired))
            return
        }
        let workspace = NSWorkspace.shared
        let frontmost = workspace.frontmostApplication
        let target = frontmost.flatMap { CodexLifecycleMonitor.isCodex($0) ? $0 : nil }
            ?? workspace.runningApplications.first { $0.bundleIdentifier == "com.openai.codex" }
            ?? workspace.runningApplications.first(where: CodexLifecycleMonitor.isCodex)
        guard let target else { completion(.failure(SpeechInsertionError.noTarget)); return }
        let initialPID = frontmost?.processIdentifier
        if initialPID != target.processIdentifier, !target.activate(options: [.activateAllWindows]) {
            completion(.failure(SpeechInsertionError.focusChanged))
            return
        }
        waitForFocus(text, target: target, initialPID: initialPID, deadline: Date().addingTimeInterval(1.5),
                     isCancelled: isCancelled, completion: completion)
    }

    private func waitForFocus(_ text: String, target: NSRunningApplication, initialPID: pid_t?, deadline: Date,
                              isCancelled: @escaping () -> Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !isCancelled() else { completion(.failure(SpeechInsertionError.cancelled)); return }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if frontPID == target.processIdentifier, let field = focusedField(pid: target.processIdentifier) {
            type(text, into: field, pid: target.processIdentifier, isCancelled: isCancelled, completion: completion)
        } else if target.isTerminated || Date() >= deadline || (frontPID != initialPID && frontPID != target.processIdentifier) {
            completion(.failure(SpeechInsertionError.focusChanged))
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.waitForFocus(text, target: target, initialPID: initialPID, deadline: deadline,
                                  isCancelled: isCancelled, completion: completion)
            }
        }
    }

    static func permits(role: String, subrole: String?, enabled: Bool) -> Bool {
        enabled && ["AXTextField", "AXTextArea", "AXComboBox"].contains(role) && subrole != "AXSecureTextField"
    }

    private func focusedField(pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let field = value as! AXUIElement
        var fieldPID: pid_t = 0
        guard AXUIElementGetPid(field, &fieldPID) == .success, fieldPID == pid else { return nil }
        func attribute(_ name: String) -> CFTypeRef? {
            var result: CFTypeRef?
            guard AXUIElementCopyAttributeValue(field, name as CFString, &result) == .success else { return nil }
            return result
        }
        guard Self.permits(role: attribute(kAXRoleAttribute) as? String ?? "",
                           subrole: attribute(kAXSubroleAttribute) as? String,
                           enabled: attribute(kAXEnabledAttribute) as? Bool ?? true) else { return nil }
        var selectedTextSettable = DarwinBoolean(false)
        var valueSettable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(field, kAXSelectedTextAttribute as CFString, &selectedTextSettable)
        AXUIElementIsAttributeSettable(field, kAXValueAttribute as CFString, &valueSettable)
        return selectedTextSettable.boolValue || valueSettable.boolValue ? field : nil
    }

    private func type(_ text: String, into field: AXUIElement, pid: pid_t, isCancelled: () -> Bool,
                      completion: (Result<Void, Error>) -> Void) {
        func stillFocused() -> Bool {
            guard !isCancelled(), NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  let current = focusedField(pid: pid) else { return false }
            return CFEqual(current, field)
        }
        guard stillFocused() else { completion(.failure(SpeechInsertionError.focusChanged)); return }
        // AX insertion is bound to the element, so a later focus change cannot redirect it.
        if AXUIElementSetAttributeValue(field, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
            completion(.success(()))
            return
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            completion(.failure(SpeechInsertionError.unavailable)); return
        }
        let utf16 = Array(text.utf16)
        var offset = 0
        while offset < utf16.count {
            guard stillFocused() else { completion(.failure(SpeechInsertionError.focusChanged)); return }
            var end = min(offset + 64, utf16.count)
            if end < utf16.count, (0xD800...0xDBFF).contains(utf16[end - 1]) { end -= 1 }
            var chunk = Array(utf16[offset..<end])
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                completion(.failure(SpeechInsertionError.unavailable)); return
            }
            down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            up.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            down.postToPid(pid)
            up.postToPid(pid)
            offset = end
        }
        completion(.success(()))
    }
}
