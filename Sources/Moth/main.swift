import AppKit
import SpriteKit

// MARK: - Sprite sets (one per species, loaded by filename prefix)

struct SpriteSet {
    let rest: SKTexture
    let shiver: SKTexture
    let takeoff: SKTexture
    let landing: SKTexture
    let glide: SKTexture
    /// Full wingbeat as a ping-pong loop: downstroke → flat → up → peak → back down.
    let flight: [SKTexture]
    /// Square canvas size of the frames, for scaling to an on-screen size.
    let canvas: CGFloat
    let displaySize: CGFloat

    private static var cache: [String: SpriteSet] = [:]

    static func load(_ species: MothSpecies) -> SpriteSet {
        if let cached = cache[species.name] { return cached }
        func texture(_ name: String) -> SKTexture {
            let file = species.prefix + name
            guard let url = Bundle.main.url(forResource: file, withExtension: "png"),
                  let image = NSImage(contentsOf: url) else {
                fatalError("missing sprite: \(file).png")
            }
            return SKTexture(image: image)
        }
        let rest = texture("rest_01")
        let set = SpriteSet(
            rest: rest,
            shiver: texture("rest_02"),
            takeoff: texture("takeoff_01"),
            landing: texture("landing_01"),
            glide: texture("flight_flat"),
            flight: ["flight_down", "flight_flat", "flight_up30", "flight_up60",
                     "flight_up90", "flight_up60", "flight_up30", "flight_flat"].map(texture),
            canvas: rest.size().width,
            displaySize: species.displaySize)
        cache[species.name] = set
        return set
    }
}

// MARK: - Scene

final class MothScene: SKScene {
    /// Container node steered every frame during flight; the visual sits inside it,
    /// pre-rotated so "up" on the artwork aligns with the heading's +x direction.
    let moth = SKNode()
    private var sprites = SpriteSet.load(SpeciesRegistry.current)
    private var pendingSpecies: MothSpecies?
    private lazy var visual = SKSpriteNode(texture: sprites.rest)
    private lazy var shadow = SKSpriteNode(texture: sprites.rest)
    private let sheenCrop = SKCropNode()
    private lazy var sheenMask = SKSpriteNode(texture: sprites.rest)
    private let sheen = SKSpriteNode(texture: MothScene.makeSheenTexture())
    private var isHovering = false
    private(set) var isFlying = false

    override func didMove(to view: SKView) {
        backgroundColor = .clear

        shadow.color = .black
        shadow.colorBlendFactor = 1.0
        shadow.alpha = 0.30
        shadow.position = CGPoint(x: 3, y: -4)
        shadow.zRotation = -.pi / 2
        moth.addChild(shadow)

        visual.zRotation = -.pi / 2
        moth.addChild(visual)

        // Holographic sheen: an iridescent band clipped to the moth's silhouette,
        // swept diagonally across it on hover. Added above the visual.
        sheenCrop.maskNode = sheenMask
        sheen.blendMode = .add
        sheen.size = CGSize(width: 190, height: 380)
        sheen.zRotation = .pi / 4      // band lies on the TL–BR diagonal
        sheen.alpha = 0
        sheenCrop.addChild(sheen)
        sheenCrop.alpha = 0
        moth.addChild(sheenCrop)

        applyScale()
        moth.position = randomLandingPoint()
        moth.zRotation = .random(in: 0 ..< 2 * .pi)
        addChild(moth)
        scheduleIdleShiver()

        NotificationCenter.default.addObserver(forName: .speciesChanged, object: nil,
                                               queue: .main) { [weak self] _ in
            self?.setSpecies(SpeciesRegistry.current)
        }
    }

    // MARK: Species switching

    private func applyScale() {
        let scale = sprites.displaySize / sprites.canvas
        visual.setScale(scale)
        shadow.setScale(scale)
        sheenMask.setScale(scale)
    }

    func setSpecies(_ species: MothSpecies) {
        guard isFlying == false else { pendingSpecies = species; return }
        pendingSpecies = nil
        sprites = SpriteSet.load(species)
        applyScale()
        // Quick blink-swap: shrink, change skin, pop back.
        moth.removeAction(forKey: "idle")
        let scale = sprites.displaySize / sprites.canvas
        visual.run(.sequence([
            .scale(to: scale * 0.85, duration: 0.1),
            .run { [self] in setTexture(sprites.rest) },
            .scale(to: scale, duration: 0.15),
        ]))
        scheduleIdleShiver()
    }

    // MARK: Interaction

    func mothHit(atWindowPoint windowPoint: CGPoint, in view: SKView) -> Bool {
        let scenePoint = view.convert(windowPoint, to: self)
        return moth.calculateAccumulatedFrame().insetBy(dx: -10, dy: -10).contains(scenePoint)
    }

    override func mouseDown(with event: NSEvent) {
        guard !isFlying else { return }
        fly(to: randomLandingPoint())
    }

    /// Home perch: top-right corner, moth's bounds inset 48px from the top and right edges.
    var basePoint: CGPoint {
        CGPoint(x: size.width - 48 - sprites.displaySize / 2,
                y: size.height - 48 - sprites.displaySize / 2)
    }

    func flyToBase() {
        guard !isFlying else { return }
        let alreadyHome = hypot(moth.position.x - basePoint.x,
                                moth.position.y - basePoint.y) < 20
        guard !alreadyHome else { return }
        fly(to: basePoint)
    }

    // MARK: Route generation

    private func randomLandingPoint() -> CGPoint {
        let margin: CGFloat = 90
        return CGPoint(x: .random(in: margin ... max(margin + 1, size.width - margin)),
                       y: .random(in: margin ... max(margin + 1, size.height - margin)))
    }

    private func clampToScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 40), size.width - 40),
                y: min(max(p.y, 40), size.height - 40))
    }

    /// Densely sampled route: wandering legs (smooth curves mixed with sharp darts)
    /// to an overshoot point past the target, then a decaying spiral onto it.
    private func routePoints(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        var pts: [CGPoint] = [start]

        func sampleQuad(_ a: CGPoint, _ control: CGPoint, _ b: CGPoint) {
            for s in 1...16 {
                let t = CGFloat(s) / 16
                let u = 1 - t
                pts.append(clampToScreen(CGPoint(
                    x: u*u*a.x + 2*u*t*control.x + t*t*b.x,
                    y: u*u*a.y + 2*u*t*control.y + t*t*b.y)))
            }
        }

        let d = hypot(end.x - start.x, end.y - start.y)
        let dir = CGPoint(x: (end.x - start.x) / max(d, 1), y: (end.y - start.y) / max(d, 1))
        let overshoot = clampToScreen(CGPoint(x: end.x + dir.x * .random(in: 70...140),
                                              y: end.y + dir.y * .random(in: 70...140)))

        let hops = Int.random(in: 3...5)
        var previous = start
        for i in 1...hops {
            let t = CGFloat(i) / CGFloat(hops)
            let base = CGPoint(x: start.x + (overshoot.x - start.x) * t,
                               y: start.y + (overshoot.y - start.y) * t)
            let target = i == hops ? overshoot
                : clampToScreen(CGPoint(x: base.x + .random(in: -140...140),
                                        y: base.y + .random(in: -140...140)))
            if i != hops, CGFloat.random(in: 0...1) < 0.35 {
                pts.append(target)   // straight dart: sharp mid-flight correction
            } else {
                let mid = CGPoint(x: (previous.x + target.x) / 2 + .random(in: -100...100),
                                  y: (previous.y + target.y) / 2 + .random(in: -100...100))
                sampleQuad(previous, mid, target)
            }
            previous = target
        }

        // Circle the landing spot, spiraling in from the overshoot radius.
        let radius0 = max(hypot(previous.x - end.x, previous.y - end.y), 50)
        let angle0 = atan2(previous.y - end.y, previous.x - end.x)
        let sweep = CGFloat.random(in: 3.6...5.2) * (Bool.random() ? 1 : -1)
        let steps = 26
        for s in 1...steps {
            let t = CGFloat(s) / CGFloat(steps)
            let a = angle0 + sweep * t
            let r = radius0 * (1 - t) + 10 * t
            pts.append(clampToScreen(CGPoint(x: end.x + cos(a) * r, y: end.y + sin(a) * r)))
        }
        pts.append(end)
        return pts
    }

    // MARK: Flight state (driven per-frame in update)

    private struct Flight {
        var points: [CGPoint]
        var cumulative: [CGFloat]
        var total: CGFloat
        var distance: CGFloat = 0
        var destination: CGPoint
        // Speed pulsing: two unsynced sines → bursts and stalls, never uniform.
        var pulseA: CGFloat = .random(in: 0 ..< 2 * .pi)
        var pulseB: CGFloat = .random(in: 0 ..< 2 * .pi)
        let freqA: CGFloat = .random(in: 4.5...6.5)
        let freqB: CGFloat = .random(in: 1.6...2.6)
        // High-frequency wobble perpendicular to the heading.
        var wobblePhase: CGFloat = 0
        let wobbleFreq: CGFloat = .random(in: 24...32)
        let wobbleAmp: CGFloat = .random(in: 2.0...3.5)
    }

    private var flight: Flight?
    private var lastTime: TimeInterval = 0
    private let baseSpeed: CGFloat = 430

    private func fly(to destination: CGPoint) {
        isFlying = true
        moth.removeAllActions()
        setTexture(sprites.takeoff)
        visual.run(.repeatForever(.animate(with: sprites.flight,
                                           timePerFrame: .random(in: 0.038...0.05))),
                   withKey: "flap")
        shadow.run(.group([
            .fadeAlpha(to: 0.15, duration: 0.2),
            .move(to: CGPoint(x: 10, y: -14), duration: 0.2),
        ]))

        let points = routePoints(from: moth.position, to: destination)
        var cumulative: [CGFloat] = [0]
        for i in 1 ..< points.count {
            cumulative.append(cumulative[i - 1] + hypot(points[i].x - points[i - 1].x,
                                                        points[i].y - points[i - 1].y))
        }
        // Brief takeoff pose before the route starts.
        moth.run(.wait(forDuration: 0.09)) { [weak self] in
            self?.flight = Flight(points: points, cumulative: cumulative,
                                  total: cumulative.last ?? 0, destination: destination)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : CGFloat(min(currentTime - lastTime, 1.0 / 30))
        lastTime = currentTime
        updateHover()
        guard var f = flight, dt > 0 else { return }

        f.pulseA += f.freqA * dt
        f.pulseB += f.freqB * dt
        f.wobblePhase += f.wobbleFreq * dt

        // Burst-and-stall speed profile, easing off on final approach.
        var factor = 0.62 + 0.24 * sin(f.pulseA) + 0.18 * sin(f.pulseB)
        let remaining = f.total - f.distance
        factor *= min(max(remaining / 160, 0.4), 1.0)
        f.distance = min(f.distance + baseSpeed * max(factor, 0.25) * dt, f.total)

        // Locate position and heading along the polyline.
        var i = f.cumulative.count - 1
        for k in 1 ..< f.cumulative.count where f.cumulative[k] >= f.distance {
            i = k
            break
        }
        let segLen = max(f.cumulative[i] - f.cumulative[i - 1], 0.001)
        let t = (f.distance - f.cumulative[i - 1]) / segLen
        let a = f.points[i - 1], b = f.points[i]
        let pos = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        let heading = atan2(b.y - a.y, b.x - a.x)

        // High-frequency flutter wobble, perpendicular to travel.
        let wobble = f.wobbleAmp * sin(f.wobblePhase)
        moth.position = CGPoint(x: pos.x + cos(heading + .pi / 2) * wobble,
                                y: pos.y + sin(heading + .pi / 2) * wobble)

        // Smoothly chase the heading — fast enough to snap on darts.
        var delta = heading - moth.zRotation
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        moth.zRotation += delta * min(12 * dt, 1)

        if f.distance >= f.total {
            flight = nil
            moth.position = f.destination
            touchDown()
        } else {
            flight = f
        }
    }

    private func touchDown() {
        visual.removeAction(forKey: "flap")
        setTexture(sprites.glide)
        shadow.run(.group([
            .fadeAlpha(to: 0.30, duration: 0.15),
            .move(to: CGPoint(x: 3, y: -4), duration: 0.15),
        ]))
        // Keep the landing heading; just a small two-step shuffle-turn as it settles.
        let shuffleAngle = CGFloat.random(in: 0.15...0.6) * (Bool.random() ? 1 : -1)
        moth.run(.sequence([
            .wait(forDuration: 0.1),
            .run { [self] in setTexture(sprites.landing) },
            .wait(forDuration: 0.16),
            .run { [self] in setTexture(sprites.rest) },
            .wait(forDuration: .random(in: 0.2...0.5)),
            .rotate(byAngle: shuffleAngle * 0.7, duration: 0.12),
            .wait(forDuration: 0.1),
            .rotate(byAngle: shuffleAngle * 0.3, duration: 0.08),
        ])) { [weak self] in
            guard let self else { return }
            self.isFlying = false
            if let pending = self.pendingSpecies {
                self.setSpecies(pending)
            } else {
                self.scheduleIdleShiver()
            }
        }
    }

    private func setTexture(_ texture: SKTexture) {
        visual.texture = texture
        shadow.texture = texture
        sheenMask.texture = texture
    }

    // MARK: Holographic sheen

    /// Iridescent gradient band drawn in code: gold → white core → pink, soft edges.
    private static func makeSheenTexture() -> SKTexture {
        let size = CGSize(width: 512, height: 8)
        let image = NSImage(size: size, flipped: false) { rect in
            let gradient = NSGradient(colorsAndLocations:
                (NSColor(red: 1, green: 0.85, blue: 0.4, alpha: 0.0), 0.0),
                (NSColor(red: 1, green: 0.85, blue: 0.4, alpha: 0.45), 0.28),
                (NSColor(red: 1, green: 1, blue: 1, alpha: 0.9), 0.5),
                (NSColor(red: 1, green: 0.5, blue: 0.8, alpha: 0.45), 0.72),
                (NSColor(red: 1, green: 0.5, blue: 0.8, alpha: 0.0), 1.0))
            gradient?.draw(in: rect, angle: 0)
            return true
        }
        return SKTexture(image: image)
    }

    private func updateHover() {
        // Scene coords match global screen coords: full-screen window at origin.
        let mouse = NSEvent.mouseLocation
        let over = !isFlying && moth.calculateAccumulatedFrame()
            .insetBy(dx: -6, dy: -6).contains(mouse)
        guard over != isHovering else { return }
        isHovering = over
        // Only accept clicks while over the moth; otherwise the whole window is
        // transparent to the mouse so desktop icons stay clickable.
        view?.window?.ignoresMouseEvents = !over
        sheen.removeAllActions()
        sheenCrop.removeAllActions()
        if over {
            // Counter-rotate the crop so the sweep runs top-right → bottom-left in
            // screen space regardless of the moth's resting angle; re-align the
            // mask so it still matches the visual.
            sheenCrop.zRotation = -moth.zRotation
            sheenMask.zRotation = moth.zRotation - .pi / 2
            sheenCrop.run(.fadeAlpha(to: 1, duration: 0.12))
            let sweep = SKAction.sequence([
                .run { [self] in sheen.position = CGPoint(x: 120, y: 120) },
                .fadeAlpha(to: 1, duration: 0.1),
                .group([
                    .move(to: CGPoint(x: -120, y: -120), duration: 0.75),
                    .sequence([.wait(forDuration: 0.5), .fadeAlpha(to: 0, duration: 0.25)]),
                ]),
                .wait(forDuration: 1.1),
            ])
            sweep.timingMode = .easeInEaseOut
            sheen.run(.repeatForever(sweep))
        } else {
            sheenCrop.run(.fadeAlpha(to: 0, duration: 0.2))
        }
    }

    // MARK: Idle life

    private func scheduleIdleShiver() {
        let wait = SKAction.wait(forDuration: .random(in: 18...50))
        let shiver = SKAction.sequence([
            .run { [self] in setTexture(sprites.shiver) },
            .wait(forDuration: 0.09),
            .run { [self] in setTexture(sprites.rest) },
            .wait(forDuration: 0.12),
            .run { [self] in setTexture(sprites.shiver) },
            .wait(forDuration: 0.07),
            .run { [self] in setTexture(sprites.rest) },
        ])
        moth.run(.sequence([wait, shiver, .run { [weak self] in
            self?.scheduleIdleShiver()
        }]), withKey: "idle")
    }
}

// MARK: - Click-through view

/// Passes mouse events through to whatever is behind the window unless the
/// cursor is over the moth itself.
final class PassthroughSKView: SKView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let scene = scene as? MothScene, !scene.isFlying else { return nil }
        return scene.mothHit(atWindowPoint: point, in: self) ? self : nil
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var mothScene: MothScene!
    private var picker: PickerPanel?
    private var notchHoverTimer: Timer?
    private var wasInNotch = false
    private var pickerHoverOpened = false

    @objc private func flyToBase() {
        mothScene.flyToBase()
    }

    @objc private func selectMoths() {
        if picker == nil { picker = PickerPanel() }
        guard let picker else { return }
        if picker.isVisible {
            picker.animateClose()
        } else {
            pickerHoverOpened = false   // menu-opened panels are sticky
            picker.show()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func pollNotchHover() {
        if picker == nil { picker = PickerPanel() }
        guard let picker else { return }
        let mouse = NSEvent.mouseLocation
        let notch = picker.notchFrame.insetBy(dx: -6, dy: 0)
        let inNotch = mouse.x >= notch.minX && mouse.x <= notch.maxX && mouse.y >= notch.minY
        if !picker.isVisible {
            if inNotch && !wasInNotch {
                pickerHoverOpened = true
                picker.show(makeKey: false)
            }
        } else if pickerHoverOpened,
                  !inNotch, !picker.frame.insetBy(dx: -30, dy: -30).contains(mouse) {
            pickerHoverOpened = false
            picker.animateClose()
        }
        wasInNotch = inNotch
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }

        window = NSWindow(contentRect: screen.frame,
                          styleMask: .borderless,
                          backing: .buffered,
                          defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true   // toggled off only while hovering the moth
        // Just above desktop icons, below every normal app window.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let skView = PassthroughSKView(frame: screen.frame)
        skView.allowsTransparency = true
        let scene = MothScene(size: screen.frame.size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
        mothScene = scene
        window.contentView = skView
        window.orderFrontRegardless()

        notchHoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.pollNotchHover()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🦋"
        let menu = NSMenu()
        let select = NSMenuItem(title: "Select Moths…", action: #selector(selectMoths), keyEquivalent: "m")
        select.target = self
        menu.addItem(select)
        let home = NSMenuItem(title: "Fly to Base", action: #selector(flyToBase), keyEquivalent: "b")
        home.target = self
        menu.addItem(home)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Moth", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
