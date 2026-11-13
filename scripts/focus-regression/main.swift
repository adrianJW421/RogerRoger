// Compile the production writers against in-memory OS adapters. No real UI,
// keyboard events, application activation, or system clipboard is used.
import AppKit
import ApplicationServices

enum TargetId: String { case currentApp, codex }
enum WriteMode { case auto, axValue, clipboardReplace, clipboardPaste, clipboardInsert }
enum FocusMode { case shortcut, preserveLastFocus, accessibility, custom }
enum SendMode { case noneSyncOnly, key, customShortcut, accessibilityButton }
struct KeyShortcut {
    var modifiers: [String]; var key: String
    static let enter = KeyShortcut(modifiers: [], key: "enter")
}
struct TargetProfile {
    var bundleId = "test.target"
    var launchIfNotRunning = false
    var focusWaitMs = 100
    var focusMode = FocusMode.preserveLastFocus
    var focusShortcut: KeyShortcut? = nil
    var sendMode = SendMode.key
    var sendShortcut: KeyShortcut? = nil
    var sendButtonTitleContains: String? = nil
}
struct FakeApplication { var processIdentifier: pid_t; var bundleIdentifier: String? }
class NSWorkspace {
    static let shared = NSWorkspace()
    var frontmostApplication: FakeApplication? = FakeApplication(processIdentifier: 100, bundleIdentifier: "test.target")
}
enum ActivationResult { case activated(pid: pid_t), notRunning, launchFailed(String), timeout }
enum AppActivator {
    static var activations = 0
    static func activate(bundleId: String, launchIfNotRunning: Bool, timeoutMs: Int) -> ActivationResult {
        activations += 1
        NSWorkspace.shared.frontmostApplication = FakeApplication(processIdentifier: 100, bundleIdentifier: bundleId)
        return .activated(pid: 100)
    }
}
enum AccessibilityPermission { static let isGranted = true }
let input = AXUIElementCreateApplication(100)
let otherInput = AXUIElementCreateApplication(101)
enum AXSupport {
    static var focused: AXUIElement? = input
    static var selectionHook: (() -> Void)?
    static var text: String? = nil
    static var editable = true
    static var selection: CFRange? = CFRangeMake(0, 0)
    static var selections: [CFRange] = []
    static func focusedElement(pid: pid_t, allowFallback: Bool = true) -> AXUIElement? { focused }
    static func systemFocusedElement() -> AXUIElement? { focused }
    static func isEditableText(_ element: AXUIElement) -> Bool { editable }
    static func role(of element: AXUIElement) -> String? { "AXTextArea" }
    static func isValueSettable(_ element: AXUIElement) -> Bool { false }
    static func setValue(_ element: AXUIElement, _ text: String) -> Bool { true }
    static func setSelectionToEnd(_ element: AXUIElement, length: Int) {}
    static func value(of element: AXUIElement) -> String? { text ?? "new text" }
    static func selectedTextRange(of element: AXUIElement) -> CFRange? { selection }
    static func setSelectedTextRange(_ element: AXUIElement, range: CFRange) -> Bool {
        selection = range; selections.append(range); selectionHook?(); return true
    }
    static func pressButton(pid: pid_t, titleContains: String) -> Bool { KeyboardSynth.keys.append("button"); return true }
}
enum KeyboardSynth {
    static var keys: [String] = []
    static func press(_ shortcut: KeyShortcut) -> Bool {
        keys.append(shortcut.key)
        if let text = AXSupport.text, let selection = AXSupport.selection,
           shortcut.key == "v" || shortcut.key == "delete" {
            let replacement = shortcut.key == "delete" ? "" : String(data: NSPasteboard.general.contents[.string]!, encoding: .utf8)!
            AXSupport.text = (text as NSString).replacingCharacters(in: NSRange(location: selection.location, length: selection.length), with: replacement)
            AXSupport.selection = CFRangeMake(selection.location + (replacement as NSString).length, 0)
        }
        return true
    }
}
class NSPasteboard {
    struct PasteboardType: Hashable { let rawValue: String; static let string = PasteboardType(rawValue: "text") }
    static let general = NSPasteboard()
    var contents: [PasteboardType: Data] = [:]
    var setStringHook: (() -> Void)?
    var types: [PasteboardType]? { Array(contents.keys) }
    func data(forType type: PasteboardType) -> Data? { contents[type] }
    func clearContents() { contents.removeAll() }
    func setString(_ value: String, forType type: PasteboardType) { contents[type] = Data(value.utf8); setStringHook?() }
    func setData(_ data: Data, forType type: PasteboardType) { contents[type] = data }
}
class DiagnosticsLog { static let shared = DiagnosticsLog(); func log(_ message: String) {} }

let binding = TargetBinding(targetId: .currentApp, sessionId: "s", pid: 100, bundleId: "test.target", element: input, role: "AXTextArea")
func reset() {
    NSWorkspace.shared.frontmostApplication = FakeApplication(processIdentifier: 100, bundleIdentifier: "test.target")
    AXSupport.focused = input
    AXSupport.selectionHook = nil
    AXSupport.text = nil
    AXSupport.selection = CFRangeMake(0, 0)
    AXSupport.selections = []
    AXSupport.editable = true
    NSPasteboard.general.contents = [.string: Data("original clipboard".utf8)]
    NSPasteboard.general.setStringHook = nil
    AppActivator.activations = 0
    KeyboardSynth.keys = []
}
func leaveApp() { NSWorkspace.shared.frontmostApplication = FakeApplication(processIdentifier: 200, bundleIdentifier: "test.other") }
func assertNoActions() { precondition(AppActivator.activations == 0 && KeyboardSynth.keys.isEmpty) }

reset(); leaveApp()
if case .failed = TextWriter.writeEditor("new text", to: binding, replacing: nil) {} else { fatalError("Background editor write allowed") }
if case .failed = TextWriter.write("new text", to: binding, writeMode: .clipboardReplace) {} else { fatalError("Background replacement allowed") }
if case .failed = SendAction.perform(profile: TargetProfile(), binding: binding) {} else { fatalError("Background send allowed") }
assertNoActions()

reset(); AXSupport.focused = otherInput
if case .failed = TextWriter.writeEditor("new text", to: binding, replacing: nil) {} else { fatalError("Different input accepted") }
if case .failed = SendAction.perform(profile: TargetProfile(), binding: binding) {} else { fatalError("Different input accepted Enter") }
assertNoActions()

reset()
if case .sent = SendAction.perform(profile: TargetProfile(), binding: binding, expectedSelection: CFRangeMake(0, 0)) {}
else { fatalError("Explicit Enter rejected") }
precondition(KeyboardSynth.keys == ["enter"] && AppActivator.activations == 0)
reset()
if case .failed = SendAction.perform(profile: TargetProfile(), binding: binding, expectedSelection: CFRangeMake(5, 0)) {}
else { fatalError("Moved caret accepted Enter") }
assertNoActions()
var syncOnly = TargetProfile(); syncOnly.sendMode = .noneSyncOnly
if case .skipped = SendAction.perform(profile: syncOnly, binding: binding) {} else { fatalError("Sync-only pressed Enter") }
assertNoActions()

var sendGate = SendGate()
precondition(sendGate.decide(sessionId: "s", targetId: .currentApp, revision: 2, appliedRevision: 1, requireExactRevision: true) == .staleRevision)
precondition(sendGate.decide(sessionId: "s", targetId: .currentApp, revision: 1, appliedRevision: 2, requireExactRevision: true) == .staleRevision)
precondition(sendGate.decide(sessionId: "s", targetId: .currentApp, revision: 2, appliedRevision: 2, requireExactRevision: true) == .proceed)
sendGate.markCommitted(sessionId: "s", targetId: .currentApp, revision: 2)
precondition(sendGate.decide(sessionId: "s", targetId: .currentApp, revision: 2, appliedRevision: 2, requireExactRevision: true) == .duplicate)
precondition(sendGate.decide(sessionId: "other", targetId: .currentApp, revision: 2, appliedRevision: 2, requireExactRevision: true) == .proceed)
print("PASS: explicit Enter, sync-only, changed field/caret, exact final revision, deduplication")

reset(); AXSupport.selectionHook = leaveApp
if case .failed = TextWriter.writeEditor("new text", to: binding, replacing: nil) {} else { fatalError("Focus loss after selection ignored") }
assertNoActions()

reset(); NSPasteboard.general.setStringHook = leaveApp
if case .failed = TextWriter.writeEditor("new text", to: binding, replacing: nil) {} else { fatalError("Focus loss before paste ignored") }
assertNoActions()
precondition(NSPasteboard.general.contents[.string] == Data("original clipboard".utf8))

reset()
if case .applied = TextWriter.writeEditor("new text", to: binding, replacing: nil) {} else { fatalError("Valid foreground input rejected") }
precondition(KeyboardSynth.keys == ["v"] && AppActivator.activations == 0)

reset(); leaveApp()
if case .notFocused = FocusController.focus(targetId: .currentApp, sessionId: "s", profile: TargetProfile()) {} else { fatalError("Current app request reactivated old app") }
if case .notFocused = FocusController.focus(targetId: .codex, sessionId: "s", profile: TargetProfile(), allowActivation: false) {} else { fatalError("Passive request activated old app") }
assertNoActions()
if case .focused = FocusController.focus(targetId: .codex, sessionId: "s", profile: TargetProfile(), allowActivation: true) {} else { fatalError("Explicit selection failed") }
precondition(AppActivator.activations == 1)
print("PASS: background/input-change/paste-race guards, clipboard restore, active input, passive vs explicit selection")

reset()
precondition(FocusController.currentInput(sessionId: "automatic") != nil)
AXSupport.editable = false
precondition(FocusController.currentInput(sessionId: "button") == nil)
AXSupport.editable = true; AXSupport.selection = nil
precondition(FocusController.currentInput(sessionId: "unsupported") == nil)
assertNoActions()

reset()
NSPasteboard.general.setStringHook = { AXSupport.selection = CFRangeMake(9, 0) }
if case .failed = TextWriter.writeEditor("new text", to: binding, replacing: nil) {} else { fatalError("Caret move during paste was ignored") }
assertNoActions()
precondition(NSPasteboard.general.contents[.string] == Data("original clipboard".utf8))

reset()
let prefix = "已有前文😀"
let suffix = "保留后文"
AXSupport.text = prefix + suffix
AXSupport.selection = CFRangeMake((prefix as NSString).length, 0)
var insertion: EditorInsertionState?
var previousText = ""
for nextText in ["我试了", "我试了一下", "我试了一下。", "我试了一下。👩🏻", "我试了一下。👩🏽", "我试了一下", "我试了一下", "我试一下", "", "新的句子", "é", "e\u{301}a"] {
    AXSupport.selections = []
    guard case .applied(_, let nextState) = TextWriter.writeEditor(nextText, to: binding, replacing: insertion) else {
        fatalError("Incremental write failed: \(nextText)")
    }
    precondition(AXSupport.text == prefix + nextText + suffix, "Document changed outside dictation range")
    if nextText == previousText { precondition(AXSupport.selections.isEmpty, "Unchanged snapshot selected text") }
    else if Array(nextText.utf16).starts(with: Array(previousText.utf16)) { precondition(AXSupport.selections.allSatisfy { $0.length == 0 }, "Append selected old text") }
    precondition(AXSupport.selection?.location == (prefix + nextText as NSString).length)
    precondition(NSPasteboard.general.contents[.string] == Data("original clipboard".utf8))
    insertion = nextState
    previousText = nextText
}
print("PASS: passive input detection, caret race cancellation, incremental Chinese/emoji/trim/clear/no-op without whole-draft selection")
