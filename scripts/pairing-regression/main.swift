import AppKit
import Vision

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let samples = [
    "http://192.0.2.10:8797/?token=demo-only_0123456789abcdefghijklm",
    "http://198.51.100.25:65535/?token=demo-only_abcdefghijklmnopqrstuvwxyz0123456789"
]
for value in samples {
    guard let image = PairingQRCode.image(for: value),
          let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("QR generation failed") }
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]
    try VNImageRequestHandler(cgImage: bitmap).perform([request])
    precondition(request.results?.first?.payloadStringValue == value, "QR did not round-trip its complete pairing URL")
}
let window = PairingWindowController(openSettings: {}, openAccessibility: {})
let activeBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
let ready = PairingWindowState(url: samples[0], serviceRunning: true, accessibilityGranted: false, connectedPhones: 0)
precondition(ready.address == "192.0.2.10:8797")
window.update(ready)
precondition(window.window?.isVisible == false, "Status refresh unexpectedly opened the window")
precondition(NSWorkspace.shared.frontmostApplication?.processIdentifier == activeBefore, "Status refresh activated the app")
func visit(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(visit) }
let views = visit(window.window!.contentView!)
let qr = views.compactMap { $0 as? NSImageView }.first!
let copy = views.compactMap { $0 as? NSButton }.first { $0.title == MacI18n.t("pairingCopyLink") }!
precondition(qr.image != nil && copy.isEnabled)
window.update(PairingWindowState(url: samples[0], serviceRunning: false, accessibilityGranted: false, connectedPhones: 0))
precondition(qr.image == nil && !copy.isEnabled, "Stopped service kept a usable-looking QR or copy button")
window.update(PairingWindowState(url: nil, serviceRunning: true, accessibilityGranted: true, connectedPhones: 0))
precondition(qr.image == nil && !copy.isEnabled)
window.update(ready)
window.window!.contentView!.layoutSubtreeIfNeeded()
if CommandLine.arguments.count > 1 {
    let view = window.window!.contentView!
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Cannot render window") }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
window.close()
window.update(PairingWindowState(url: samples[1], serviceRunning: true, accessibilityGranted: true, connectedPhones: 1))
precondition(window.window?.isVisible == false, "Background update reopened a closed pairing window")
precondition(qr.image != nil && copy.isEnabled)
print("PASS: QR URL round trips, no stale QR for unavailable service/network, passive refresh and closed-window behavior")
