// 目标聚焦与绑定校验。PRD 9.2 / 9.3 / 16.2 / 16.3。
// 安全核心：成功聚焦后记录绑定；后续写入/发送前必须校验绑定仍有效，
// 否则暂停同步、报「目标失焦」，绝不向任意焦点盲写（PRD 3.4 / 10.3）。

import ApplicationServices
import AppKit

/// 一次成功聚焦后记录的目标绑定。
struct TargetBinding {
    let id = UUID()
    let targetId: TargetId
    let sessionId: String
    let pid: pid_t
    let bundleId: String
    let element: AXUIElement
    let role: String?
}

enum FocusOutcome {
    case focused(TargetBinding)
    case appNotRunning
    case appLaunchFailed(String)
    case noPermission
    case notFocused(String)
}

enum FocusController {

    /// Observe only the actual foreground input; no activation, shortcuts or
    /// editable-descendant fallback. A fresh session separates dictation ranges.
    static func currentInput(sessionId: String) -> TargetBinding? {
        guard AccessibilityPermission.isGranted,
              let app = NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier,
              let element = AXSupport.focusedElement(pid: app.processIdentifier, allowFallback: false),
              AXSupport.isEditableText(element),
              AXSupport.selectedTextRange(of: element) != nil else { return nil }
        let binding = TargetBinding(targetId: .currentApp, sessionId: sessionId,
                                    pid: app.processIdentifier, bundleId: bundleId,
                                    element: element, role: AXSupport.role(of: element))
        return validate(binding) ? binding : nil
    }

    /// 激活并聚焦目标，返回绑定或失败原因。应在后台队列调用（含同步等待）。
    static func focus(targetId: TargetId, sessionId: String, profile: TargetProfile,
                      allowActivation: Bool = true) -> FocusOutcome {
        guard AccessibilityPermission.isGranted else { return .noPermission }

        let pid: pid_t
        if targetId == .currentApp || !allowActivation {
            // Current App follows the user's foreground choice; a queued focus
            // request must never reactivate an app the user has already left.
            guard let front = NSWorkspace.shared.frontmostApplication,
                  front.bundleIdentifier == profile.bundleId else {
                return .notFocused("当前应用已改变，请在手机上重新聚焦")
            }
            pid = front.processIdentifier
        } else {
            // Only an explicit target selection may activate a named app.
            let act = AppActivator.activate(bundleId: profile.bundleId,
                                            launchIfNotRunning: profile.launchIfNotRunning,
                                            timeoutMs: profile.focusWaitMs * 4)
            switch act {
            case .activated(let p): pid = p
            case .notRunning: return .appNotRunning
            case .launchFailed(let m): return .appLaunchFailed(m)
            case .timeout: return .notFocused("应用激活超时")
            }
        }

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            return .notFocused("前台应用已改变，请重新聚焦")
        }

        // 2) 执行聚焦策略
        switch profile.focusMode {
        case .shortcut:
            if let sc = profile.focusShortcut {
                _ = KeyboardSynth.press(sc)
                Thread.sleep(forTimeInterval: Double(profile.focusWaitMs) / 1000.0)
            }
        case .preserveLastFocus:
            // 直接使用应用当前焦点，不额外操作。
            break
        case .accessibility, .custom:
            // M3-2 / 二期实现；此处先回退为 preserveLastFocus 行为。
            break
        }

        // 3) 读取当前聚焦元素并校验。
        // Electron(如 Notion)激活后 AX 焦点可能略有延迟，重试几次拿可编辑元素，
        // 解决"光标看着在输入框但首次查询 AXFocusedUIElement 为空"导致的偶发失败。
        var element: AXUIElement?
        for attempt in 0..<5 {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                return .notFocused("前台应用已改变，请重新聚焦")
            }
            if let el = AXSupport.focusedElement(pid: pid), AXSupport.isEditableText(el) {
                element = el
                break
            }
            if attempt < 4 { Thread.sleep(forTimeInterval: 0.08) }
        }
        guard let element else {
            return .notFocused("未取得可编辑的聚焦控件（请确认目标输入框处于编辑状态）")
        }
        let role = AXSupport.role(of: element)
        let binding = TargetBinding(targetId: targetId, sessionId: sessionId,
                                    pid: pid, bundleId: profile.bundleId,
                                    element: element, role: role)
        return .focused(binding)
    }

    /// Check the real foreground input. Never activate an app or choose an
    /// arbitrary editable field while validating an existing binding.
    static func validate(_ binding: TargetBinding) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == binding.pid else {
            return false
        }
        guard let current = AXSupport.systemFocusedElement()
                ?? AXSupport.focusedElement(pid: binding.pid, allowFallback: false),
              CFEqual(current, binding.element) else { return false }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == binding.pid
    }
}
