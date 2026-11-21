import AppKit

struct WindowChoice {
    let window: AXUIElement
    let title: String
    let bounds: CGRect?
    let minimized: Bool
}

private final class PreviewCard: NSButton {
    let picture = NSImageView()
    private let caption = NSTextField(labelWithString: "")
    var choose: (() -> Void)?

    init(_ item: WindowChoice, app: NSRunningApplication) {
        super.init(frame: .zero)
        isBordered = false
        title = ""
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.65).cgColor
        picture.image = app.icon
        picture.imageScaling = .scaleProportionallyDown
        picture.frame = NSRect(x: 6, y: 30, width: 168, height: 99)
        addSubview(picture)
        caption.stringValue = item.title
        caption.font = .systemFont(ofSize: 12, weight: .medium)
        caption.alignment = .center
        caption.lineBreakMode = .byTruncatingTail
        caption.frame = NSRect(x: 6, y: 7, width: 168, height: 17)
        addSubview(caption)
        toolTip = item.title
        setAccessibilityLabel(item.title)
        target = self
        action = #selector(picked)
    }

    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    @objc private func picked() { choose?() }
}

final class PreviewPanel {
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var cards: [PreviewCard] = []

    init() {
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.title = "DockSnapper window previews"
    }

    func show(app: NSRunningApplication, items: [WindowChoice], anchor: CGRect, screen: NSScreen, choose: @escaping (WindowChoice) -> Void) {
        let cardWidth: CGFloat = 180, spacing: CGFloat = 6
        let contentWidth = CGFloat(items.count) * (cardWidth + spacing) - spacing
        let panelWidth = min(contentWidth + 20, screen.visibleFrame.width - 12)
        let needsScroll = contentWidth > panelWidth - 20
        let height: CGFloat = needsScroll ? 198 : 182
        let bounds = CGRect(x: 0, y: 0, width: panelWidth, height: height)
        let background = NSVisualEffectView(frame: bounds)
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true

        let heading = NSTextField(labelWithString: app.localizedName ?? "Windows")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.frame = CGRect(x: 12, y: height - 30, width: panelWidth - 24, height: 20)
        background.addSubview(heading)
        let scroll = NSScrollView(frame: CGRect(x: 10, y: 9, width: panelWidth - 20, height: needsScroll ? 153 : 137))
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = needsScroll
        scroll.autohidesScrollers = false
        let strip = NSView(frame: CGRect(x: 0, y: 0, width: contentWidth, height: 136))
        cards = items.enumerated().map { index, item in
            let card = PreviewCard(item, app: app)
            card.frame = CGRect(x: CGFloat(index) * (cardWidth + spacing), y: 0, width: cardWidth, height: 136)
            card.choose = { choose(item) }
            strip.addSubview(card)
            return card
        }
        scroll.documentView = strip
        background.addSubview(scroll)
        panel.contentView = background
        let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
        var x = anchor.midX - panelWidth / 2, y = anchor.maxY + 3
        if orientation == "left" || orientation == "right" {
            x = orientation == "left" ? anchor.maxX + 3 : anchor.minX - panelWidth - 3
            y = anchor.midY - height / 2
        }
        let visible = screen.visibleFrame
        x = max(visible.minX, min(x, visible.maxX - panelWidth))
        y = max(visible.minY, min(y, visible.maxY - height))
        panel.setFrame(CGRect(x: x, y: y, width: panelWidth, height: height), display: true)
        panel.orderFrontRegardless()
    }

    func setImage(_ image: CGImage, at index: Int) {
        guard cards.indices.contains(index) else { return }
        cards[index].picture.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    func hide() {
        panel.orderOut(nil)
        panel.contentView = nil
        cards.removeAll()
    }
}
