import AppKit

// MARK: - Species registry

struct MothSpecies {
    let name: String
    let prefix: String      // filename prefix of its sprite frames ("" or "comet_")
    let thumbnail: String   // bundle resource name shown in the picker
    let displaySize: CGFloat // on-screen size of the sprite canvas, in points
    var selectable = true   // false: shown as a greyscale "coming soon" tease
}

extension Notification.Name {
    static let speciesChanged = Notification.Name("speciesChanged")
}

enum SpeciesRegistry {
    static let all = [
        MothSpecies(name: "Rosy Maple", prefix: "", thumbnail: "thumb_rosy", displaySize: 138),
        MothSpecies(name: "Comet", prefix: "comet_", thumbnail: "comet_thumb", displaySize: 140),
        MothSpecies(name: "Lime Hawk", prefix: "lime_", thumbnail: "lime_thumb", displaySize: 131),
    ]

    static var selected: String {
        get { UserDefaults.standard.string(forKey: "selectedSpecies") ?? all[0].name }
        set { UserDefaults.standard.set(newValue, forKey: "selectedSpecies") }
    }

    static var current: MothSpecies {
        all.first { $0.name == selected && $0.selectable } ?? all[0]
    }
}

// MARK: - Palette

private enum PickerStyle {
    static let fill = NSColor(srgbRed: 0x12/255, green: 0x12/255, blue: 0x12/255, alpha: 1)
    static let stroke = NSColor(srgbRed: 0x33/255, green: 0x33/255, blue: 0x33/255, alpha: 1)
    static let text = NSColor(srgbRed: 0xCA/255, green: 0xCA/255, blue: 0xCA/255, alpha: 1)
    static func font(_ size: CGFloat) -> NSFont {
        NSFont(name: "PPMondwest-Regular", size: size) ?? .systemFont(ofSize: size)
    }
}

// MARK: - Species cell

final class SpeciesCell: NSView {
    let species: MothSpecies
    private var colorView: NSImageView?   // fades in over the greyscale on hover

    init(species: MothSpecies) {
        self.species = species
        super.init(frame: NSRect(x: 0, y: 0, width: 140, height: 175))

        let imageRect = NSRect(x: 25, y: 46, width: 90, height: 115)
        var image: NSImage?
        if let url = Bundle.main.url(forResource: species.thumbnail, withExtension: "png") {
            image = NSImage(contentsOf: url)
        }

        // Greyscale base with the colour version layered on top; the colour layer
        // is visible for the selected species and previews on hover for the rest.
        let imageView = NSImageView(frame: imageRect)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = image.flatMap(Self.desaturated)
        addSubview(imageView)

        let color = NSImageView(frame: imageRect)
        color.imageScaling = .scaleProportionallyUpOrDown
        color.image = image
        color.alphaValue = isSelected ? 1 : 0
        addSubview(color)
        colorView = color

        NotificationCenter.default.addObserver(forName: .speciesChanged, object: nil,
                                               queue: .main) { [weak self] _ in
            self?.setColor(visible: self?.isSelected ?? false, duration: 0.35)
        }

        let label = NSTextField(labelWithString: species.name)
        label.font = PickerStyle.font(20)
        label.textColor = PickerStyle.text
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 16, width: 140, height: 28)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var isSelected: Bool { SpeciesRegistry.selected == species.name }

    private func setColor(visible: Bool, duration: TimeInterval) {
        guard let colorView else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            colorView.animator().alphaValue = visible ? 1 : 0
        }
    }

    private static func desaturated(_ image: NSImage) -> NSImage {
        guard let tiff = image.tiffRepresentation,
              let ci = CIImage(data: tiff),
              let filter = CIFilter(name: "CIColorControls",
                                    parameters: [kCIInputImageKey: ci, kCIInputSaturationKey: 0]),
              let output = filter.outputImage else { return image }
        let rep = NSCIImageRep(ciImage: output)
        let result = NSImage(size: image.size)
        result.addRepresentation(rep)
        return result
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        setColor(visible: true, duration: 0.35)
    }

    override func mouseExited(with event: NSEvent) {
        setColor(visible: isSelected, duration: 0.45)
    }

    // First click registers even when the panel never took keyboard focus.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard species.selectable, SpeciesRegistry.selected != species.name else { return }
        SpeciesRegistry.selected = species.name
        NotificationCenter.default.post(name: .speciesChanged, object: nil)
    }
}

// MARK: - Picker panel (expands out of the notch)

/// View backed by a gradient layer so the fill tracks the grow animation.
private final class GradientView: NSView {
    override func makeBackingLayer() -> CALayer { CAGradientLayer() }
}

/// 1px edge stroke along the bottom-rounded outline that fades out toward the
/// top, so the panel's edge dissolves into the notch instead of seaming.
private final class FadingStrokeView: NSView {
    var radius: CGFloat = 20
    var color = NSColor(srgbRed: 0x33/255, green: 0x33/255, blue: 0x33/255, alpha: 1)

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r.minX, y: r.maxY + 1))           // start above the top edge
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        path.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY),
                    tangent2End: CGPoint(x: r.minX + radius, y: r.minY), radius: radius)
        path.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY),
                    tangent2End: CGPoint(x: r.maxX, y: r.minY + radius), radius: radius)
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY + 1))

        ctx.saveGState()
        ctx.addPath(path)
        ctx.setLineWidth(1)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: bounds.minY),
                                   end: CGPoint(x: 0, y: bounds.maxY), options: [])
        }
        ctx.restoreGState()
    }
}

final class PickerPanel: NSPanel {
    static let boxSize = NSSize(width: 660, height: 440)
    private let content = NSView(frame: NSRect(origin: .zero, size: PickerPanel.boxSize))
    private var closing = false

    override var canBecomeKey: Bool { true }

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.boxSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false   // the system shadow paints a hairline rim — none of that
        level = .popUpMenu          // above the menu bar, so it can hug the notch
        collectionBehavior = [.canJoinAllSpaces]

        let container = GradientView(frame: NSRect(origin: .zero, size: Self.boxSize))
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        if let gradient = container.layer as? CAGradientLayer {
            // Pure black at the top to disappear into the notch, easing into a
            // barely-there grey toward the bottom.
            gradient.colors = [
                NSColor(srgbRed: 0x14/255, green: 0x14/255, blue: 0x14/255, alpha: 1).cgColor,
                NSColor.black.cgColor,
            ]
            gradient.startPoint = CGPoint(x: 0.5, y: 0)   // bottom (AppKit coords)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)     // top
        }
        container.layer?.cornerRadius = 20
        // Top edge meets the screen edge — round only the bottom corners.
        container.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        container.layer?.masksToBounds = true

        // Fixed-size content wrapper pinned to the top and horizontally centered,
        // so nothing distorts while the window itself grows around it.
        content.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]

        let padding: CGFloat = 32
        let cellSize = NSSize(width: 140, height: 175)
        let perRow = Int((Self.boxSize.width - padding * 2) / (cellSize.width + 16))
        for (i, species) in SpeciesRegistry.all.enumerated() {
            let cell = SpeciesCell(species: species)
            let row = i / perRow, col = i % perRow
            cell.setFrameOrigin(NSPoint(
                x: padding + CGFloat(col) * (cellSize.width + 16),
                y: Self.boxSize.height - padding - cellSize.height - CGFloat(row) * (cellSize.height + 16)))
            content.addSubview(cell)
        }

        let stroke = FadingStrokeView(frame: container.bounds)
        stroke.autoresizingMask = [.width, .height]
        container.addSubview(stroke)

        container.addSubview(content)
        contentView = container
    }

    // MARK: Geometry

    private var finalFrame: NSRect {
        guard let f = NSScreen.main?.frame else { return frame }
        return NSRect(x: f.midX - Self.boxSize.width / 2, y: f.maxY - Self.boxSize.height,
                      width: Self.boxSize.width, height: Self.boxSize.height)
    }

    /// The sliver the box grows out of: the real notch on notched Macs,
    /// a notch-sized patch of menu bar elsewhere.
    var notchFrame: NSRect {
        guard let screen = NSScreen.main else { return frame }
        let f = screen.frame
        var notchW: CGFloat = 220
        let notchH: CGFloat = max(screen.safeAreaInsets.top, 34)
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchW = f.width - left.width - right.width + 8
        }
        return NSRect(x: f.midX - notchW / 2, y: f.maxY - notchH, width: notchW, height: notchH)
    }

    // MARK: Open / close animation

    func show(makeKey: Bool = true) {
        closing = false
        content.alphaValue = 0
        setFrame(notchFrame, display: false)
        // Hover-opened panels shouldn't steal keyboard focus from the user's app.
        if makeKey { makeKeyAndOrderFront(nil) } else { orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.55
            // Ease-out with a slight overshoot: pops past full size, settles back.
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.14, 0.3, 1)
            animator().setFrame(finalFrame, display: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, !self.closing else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                self.content.animator().alphaValue = 1
            }
        }
    }

    func animateClose() {
        guard isVisible, !closing else { return }
        closing = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            content.animator().alphaValue = 0
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.75, 0.35)
            animator().setFrame(notchFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.closing = false
        })
    }


    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { animateClose() } else { super.keyDown(with: event) }  // Esc
    }

    override func resignKey() {
        super.resignKey()
        animateClose()
    }
}
