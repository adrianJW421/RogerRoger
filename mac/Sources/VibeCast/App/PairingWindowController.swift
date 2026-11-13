import AppKit

private final class PairingContentView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

struct PairingWindowState: Equatable {
    var url: String?
    var serviceRunning: Bool
    var accessibilityGranted: Bool
    var connectedPhones: Int

    var usableURL: String? { serviceRunning ? url : nil }
    var address: String? {
        guard let value = usableURL, let components = URLComponents(string: value),
              let host = components.host, let port = components.port else { return nil }
        return "\(host):\(port)"
    }
}

/// Refreshes content without ordering the window or activating the application.
/// Only explicit launch, reopen, and menu actions call present().
final class PairingWindowController: NSWindowController {
    private let qr = NSImageView()
    private let placeholder = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let address = NSTextField(labelWithString: "")
    private let permission = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private let permissionButton = NSButton()
    private var currentURL: String?
    private var state: PairingWindowState?
    private let openSettings: () -> Void
    private let openAccessibility: () -> Void

    init(openSettings: @escaping () -> Void, openAccessibility: @escaping () -> Void) {
        self.openSettings = openSettings
        self.openAccessibility = openAccessibility
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = MacI18n.t("pairingWindowTitle")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentView = makeContentView()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func update(_ value: PairingWindowState) {
        guard state != value else { return }
        state = value
        let url = value.usableURL
        if currentURL != url {
            currentURL = url
            qr.image = url.flatMap(PairingQRCode.image)
            copyButton.title = MacI18n.t("pairingCopyLink")
        }
        qr.isHidden = qr.image == nil
        placeholder.isHidden = qr.image != nil
        placeholder.stringValue = !value.serviceRunning ? MacI18n.t("pairingServiceUnavailable")
            : url == nil ? MacI18n.t("pairingNoNetwork") : MacI18n.t("pairingQRUnavailable")
        copyButton.isEnabled = url != nil
        address.stringValue = value.address ?? ""
        if !value.serviceRunning || url == nil {
            status.stringValue = MacI18n.t("pairingNotReady")
            status.textColor = .secondaryLabelColor
        } else if value.connectedPhones > 0 {
            status.stringValue = MacI18n.f("connectedPhones", value.connectedPhones)
            status.textColor = .systemGreen
        } else {
            status.stringValue = MacI18n.t("pairingWaiting")
            status.textColor = .secondaryLabelColor
        }
        permission.stringValue = MacI18n.t(value.accessibilityGranted ? "pairingPermissionReady" : "pairingPermissionNeeded")
        permission.textColor = value.accessibilityGranted ? .systemGreen : .secondaryLabelColor
        permissionButton.isHidden = value.accessibilityGranted
    }

    private func makeContentView() -> NSView {
        let root = PairingContentView(frame: NSRect(x: 0, y: 0, width: 540, height: 680))
        let title = text("RogerRoger", size: 26, weight: .semibold)
        let subtitle = text(MacI18n.t("pairingSubtitle"), size: 14)
        subtitle.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 13, weight: .medium)
        status.alignment = .center
        address.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        address.alignment = .center
        address.isSelectable = true

        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 14
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        qr.translatesAutoresizingMaskIntoConstraints = false
        qr.imageScaling = .scaleNone
        qr.setAccessibilityLabel(MacI18n.t("pairingQRCodeLabel"))
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.alignment = .center
        placeholder.font = .systemFont(ofSize: 14)
        placeholder.textColor = .darkGray
        card.addSubview(qr)
        card.addSubview(placeholder)
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 260), card.heightAnchor.constraint(equalToConstant: 260),
            qr.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            qr.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            qr.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            qr.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            placeholder.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            placeholder.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            placeholder.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])

        let instructions = text(MacI18n.t("pairingInstructions"), size: 14)
        copyButton.title = MacI18n.t("pairingCopyLink")
        copyButton.bezelStyle = .rounded
        copyButton.controlSize = .large
        copyButton.target = self
        copyButton.action = #selector(copyLink)
        copyButton.isEnabled = false
        let network = NSButton(title: MacI18n.t("pairingNetworkSettings"), target: self, action: #selector(networkSettings))
        network.bezelStyle = .rounded
        network.controlSize = .large
        let actions = NSStackView(views: [copyButton, network])
        actions.orientation = .horizontal
        actions.spacing = 12
        permission.font = .systemFont(ofSize: 12)
        permissionButton.title = MacI18n.t("pairingGrantPermission")
        permissionButton.bezelStyle = .rounded
        permissionButton.target = self
        permissionButton.action = #selector(accessibilitySettings)
        let permissions = NSStackView(views: [permission, permissionButton])
        permissions.orientation = .horizontal
        permissions.spacing = 8
        let footer = text(MacI18n.t("pairingFooter"), size: 12)
        footer.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, subtitle, status, card, address, instructions, actions, permissions, footer])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 26),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -26),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -18),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            instructions.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return root
    }

    private func text(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: string)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.alignment = .center
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    @objc private func copyLink() {
        guard let url = currentURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        copyButton.title = MacI18n.t("pairingLinkCopied")
    }
    @objc private func networkSettings() { openSettings() }
    @objc private func accessibilitySettings() { openAccessibility() }
}
