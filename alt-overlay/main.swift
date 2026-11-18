import Cocoa
import Foundation

// Models for decoding yabai JSON output
struct YabaiFrame: Decodable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double
}

struct YabaiWindow: Decodable {
    let id: Int
    let pid: Int
    let app: String
    let title: String
    let role: String?
    let frame: YabaiFrame
    let isVisible: Bool
    let isMinimized: Bool
    let isHidden: Bool
    let hasFocus: Bool?

    enum CodingKeys: String, CodingKey {
        case id, pid, app, title, role, frame
        case isVisible = "is-visible"
        case isMinimized = "is-minimized"
        case isHidden = "is-hidden"
        case hasFocus = "has-focus"
    }
}

let keyLabels = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
let targetKeyCodes: [Int64: Int] = [
    18: 0,  // '1'
    19: 1,  // '2'
    20: 2,  // '3'
    21: 3,  // '4'
    23: 4,  // '5'
    22: 5,  // '6'
    26: 6,  // '7'
    28: 7,  // '8'
    25: 8   // '9'
]

class OverlayManager {
    static let shared = OverlayManager()
    
    private var darkWindows: [NSWindow] = []
    private var badgeWindows: [NSWindow] = []
    private var glowWindows: [NSWindow] = []
    private var bottomHudWindow: NSWindow?
    private var activeWindows: [YabaiWindow] = []
    private var isOverlayActive = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<OverlayManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            fputs("Error: Could not create event tap. Make sure Antigravity / Terminal has Accessibility permissions in System Settings.\n", stderr)
            exit(1)
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags
        let isAltPressed = flags.contains(.maskAlternate)

        if type == .flagsChanged {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if isAltPressed && !self.isOverlayActive {
                    self.showOverlay()
                } else if !isAltPressed && self.isOverlayActive {
                    self.hideOverlay()
                }
            }
            return Unmanaged.passRetained(event)
        }

        if type == .keyDown && isOverlayActive {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if let targetIdx = targetKeyCodes[keyCode] {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if targetIdx < self.activeWindows.count {
                        let win = self.activeWindows[targetIdx]
                        self.focusWindow(win: win)
                        // Refresh overlay immediately so glow and cutouts update to newly focused window
                        self.hideOverlay()
                        self.showOverlay()
                    }
                }
                // Suppress key press so it doesn't type into the active window
                return nil
            }
            // Spacebar keycode is 49: trigger toggle-layout.sh and refresh overlay
            if keyCode == 49 {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.toggleLayout()
                }
                return nil
            }
        }

        return Unmanaged.passRetained(event)
    }

    private func fetchSpaceType() -> String {
        let task = Process()
        task.launchPath = "/opt/homebrew/bin/yabai"
        task.arguments = ["-m", "query", "--spaces", "--space"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = json["type"] as? String {
                return type
            }
        } catch {}
        return "float"
    }

    private func toggleLayout() {
        let toggleScript = "\(NSHomeDirectory())/.config/yabai/toggle-layout.sh"
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = [toggleScript]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {}
        
        // Refresh overlays with new window positions and updated bottom HUD mode
        hideOverlay()
        showOverlay()
    }

    private func fetchWindows() -> [YabaiWindow] {
        let task = Process()
        task.launchPath = "/opt/homebrew/bin/yabai"
        task.arguments = ["-m", "query", "--windows", "--space"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let windows = try JSONDecoder().decode([YabaiWindow].self, from: data)
            return windows
                .filter { $0.isVisible && !$0.isMinimized && !$0.isHidden && $0.role == "AXWindow" }
                .sorted {
                    let row1 = floor($0.frame.y / 60)
                    let row2 = floor($1.frame.y / 60)
                    if row1 != row2 { return row1 < row2 }
                    if $0.frame.x != $1.frame.x { return $0.frame.x < $1.frame.x }
                    return $0.id < $1.id
                }
        } catch {
            return []
        }
    }

    private func focusWindow(win: YabaiWindow) {
        let task = Process()
        task.launchPath = "/opt/homebrew/bin/yabai"
        task.arguments = ["-m", "window", "--focus", "\(win.id)"]
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                if let app = NSRunningApplication(processIdentifier: pid_t(win.pid)) {
                    app.activate()
                }
            }
        } catch {
            if let app = NSRunningApplication(processIdentifier: pid_t(win.pid)) {
                app.activate()
            }
        }
    }

    private func showOverlay() {
        guard !isOverlayActive else { return }
        isOverlayActive = true
        activeWindows = fetchWindows()
        let currentSpaceType = fetchSpaceType()

        guard let primaryScreen = NSScreen.screens.first else { return }
        let primaryHeight = primaryScreen.frame.height

        // 1. Create dimming overlay for each screen with cutout for focused window
        let focusedWindow = activeWindows.first(where: { $0.hasFocus == true })
        for screen in NSScreen.screens {
            let dimWin = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            dimWin.isOpaque = false
            dimWin.backgroundColor = .clear
            dimWin.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
            dimWin.ignoresMouseEvents = true

            // Cut out focused window so it stays full light
            var cutoutInScreenCoords: NSRect? = nil
            if let fw = focusedWindow {
                // yabai frame: origin top-left of main display
                // screen frame: origin bottom-left of respective display
                let winX = fw.frame.x
                let winY = primaryHeight - (fw.frame.y + fw.frame.h)
                let winRectGlobal = NSRect(x: winX, y: winY, width: fw.frame.w, height: fw.frame.h)
                if screen.frame.intersects(winRectGlobal) {
                    cutoutInScreenCoords = NSRect(
                        x: winRectGlobal.origin.x - screen.frame.origin.x,
                        y: winRectGlobal.origin.y - screen.frame.origin.y,
                        width: winRectGlobal.size.width,
                        height: winRectGlobal.size.height
                    )
                }
            }

            let dimView = DimMaskView(frame: NSRect(origin: .zero, size: screen.frame.size), cutoutRect: cutoutInScreenCoords)
            dimWin.contentView = dimView
            dimWin.orderFrontRegardless()
            darkWindows.append(dimWin)
        }

        // 2. Create glowing outline overlay on focused window
        if let fw = focusedWindow {
            let winX = fw.frame.x
            let winY = primaryHeight - (fw.frame.y + fw.frame.h)
            let glowPadding: CGFloat = 20.0
            let glowRect = NSRect(
                x: winX - glowPadding,
                y: winY - glowPadding,
                width: fw.frame.w + (glowPadding * 2),
                height: fw.frame.h + (glowPadding * 2)
            )

            let glowWin = NSWindow(
                contentRect: glowRect,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            glowWin.isOpaque = false
            glowWin.backgroundColor = .clear
            glowWin.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)) + 1)
            glowWin.ignoresMouseEvents = true

            let glowView = GlowingOutlineView(
                frame: NSRect(origin: .zero, size: glowRect.size),
                innerWindowRect: NSRect(x: glowPadding, y: glowPadding, width: fw.frame.w, height: fw.frame.h)
            )
            glowWin.contentView = glowView
            glowWin.orderFrontRegardless()
            glowWindows.append(glowWin)
        }

        // 3. Create key badges on each visible window

        for (idx, win) in activeWindows.prefix(9).enumerated() {
            let keyChar = keyLabels[idx]
            
            // Convert yabai coordinate (top-left based) to macOS Cocoa coordinate (bottom-left based)
            let winX = win.frame.x
            let winY = primaryHeight - (win.frame.y + win.frame.h)
            let winH = win.frame.h

            // Position keycap badge flush with top-left of each window
            let badgeWidth: CGFloat = 36
            let badgeHeight: CGFloat = 34
            let badgeX = winX
            let badgeY = winY + winH - badgeHeight

            let badgeRect = NSRect(x: badgeX, y: badgeY, width: badgeWidth, height: badgeHeight)
            let badgeWin = NSWindow(
                contentRect: badgeRect,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            badgeWin.isOpaque = false
            badgeWin.backgroundColor = .clear
            badgeWin.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)) + 1)
            badgeWin.ignoresMouseEvents = true

            let badgeView = BadgeView(frame: NSRect(x: 0, y: 0, width: badgeWidth, height: badgeHeight), key: keyChar)
            badgeWin.contentView = badgeView
            badgeWin.orderFrontRegardless()
            badgeWindows.append(badgeWin)
        }

        // 3. Bottom HUD indicator: Spacebar keycap with "switch to bsp" / "switch to float" inside
        let targetMode = (currentSpaceType == "bsp") ? "float" : "bsp"
        let hudWidth: CGFloat = 200
        let hudHeight: CGFloat = 38
        let hudX = (primaryScreen.frame.width - hudWidth) / 2.0
        let hudY: CGFloat = 28 // 28px from bottom of screen

        let hudRect = NSRect(x: hudX, y: hudY, width: hudWidth, height: hudHeight)
        let hudWin = NSWindow(
            contentRect: hudRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hudWin.isOpaque = false
        hudWin.backgroundColor = .clear
        hudWin.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)) + 1)
        hudWin.ignoresMouseEvents = true

        let hudView = BottomHudView(frame: NSRect(x: 0, y: 0, width: hudWidth, height: hudHeight), targetMode: targetMode)
        hudWin.contentView = hudView
        hudWin.orderFrontRegardless()
        bottomHudWindow = hudWin
    }

    private func hideOverlay() {
        guard isOverlayActive else { return }
        isOverlayActive = false

        for win in darkWindows {
            win.orderOut(nil)
        }
        darkWindows.removeAll()

        for win in glowWindows {
            win.orderOut(nil)
        }
        glowWindows.removeAll()

        for win in badgeWindows {
            win.orderOut(nil)
        }
        badgeWindows.removeAll()

        bottomHudWindow?.orderOut(nil)
        bottomHudWindow = nil

        activeWindows.removeAll()
    }
}

class BottomHudView: NSView {
    let targetMode: String

    init(frame: NSRect, targetMode: String) {
        self.targetMode = targetMode
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let cornerRadius: CGFloat = 6.0
        
        // 1. Drop shadow / 3D bottom bevel
        let shadowRect = NSRect(x: 4, y: 2, width: bounds.width - 8, height: bounds.height - 5)
        let shadowPath = NSBezierPath(roundedRect: shadowRect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor(white: 0.08, alpha: 0.95).setFill()
        shadowPath.fill()

        // 2. Main mechanical spacebar body
        let keyRect = NSRect(x: 4, y: 5, width: bounds.width - 8, height: bounds.height - 7)
        let keyPath = NSBezierPath(roundedRect: keyRect, xRadius: cornerRadius, yRadius: cornerRadius)

        let gradient = NSGradient(
            starting: NSColor(white: 0.24, alpha: 0.98),
            ending: NSColor(white: 0.14, alpha: 0.98)
        )
        gradient?.draw(in: keyPath, angle: -90)

        // 3. Top highlight inner stroke
        let highlightPath = NSBezierPath(roundedRect: keyRect.insetBy(dx: 1, dy: 1), xRadius: cornerRadius - 1, yRadius: cornerRadius - 1)
        NSColor(white: 0.35, alpha: 0.6).setStroke()
        highlightPath.lineWidth = 1.0
        highlightPath.stroke()

        // 4. Outer border (grayscale)
        NSColor(white: 0.45, alpha: 0.85).setStroke()
        keyPath.lineWidth = 1.2
        keyPath.stroke()

        // 5. Centered action text inside the spacebar
        let font = NSFont(name: "Press Start 2P", size: 10) ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        let labelText = "switch to \(targetMode)"
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(white: 0.96, alpha: 1.0),
            .paragraphStyle: paragraphStyle
        ]
        
        let textSize = labelText.size(withAttributes: textAttrs)
        let textY = keyRect.origin.y + (keyRect.height - textSize.height) / 2.0 - 0.5
        let textRect = NSRect(
            x: keyRect.origin.x,
            y: textY,
            width: keyRect.width,
            height: textSize.height
        )

        // Subtle dark engraved shadow
        let shadowAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(white: 0.05, alpha: 0.8),
            .paragraphStyle: paragraphStyle
        ]
        let textShadowRect = NSRect(x: textRect.origin.x, y: textRect.origin.y - 1.0, width: textRect.width, height: textRect.height)
        labelText.draw(in: textShadowRect, withAttributes: shadowAttrs)

        labelText.draw(in: textRect, withAttributes: textAttrs)
    }
}

class BadgeView: NSView {
    let key: String

    init(frame: NSRect, key: String) {
        self.key = key
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let cornerRadius: CGFloat = 6.0
        
        // 1. Drop shadow / bottom 3D bevel (dark bevel underneath)
        let bottomShadowRect = NSRect(x: 3, y: 2, width: bounds.width - 6, height: bounds.height - 5)
        let bottomShadowPath = NSBezierPath(roundedRect: bottomShadowRect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor(white: 0.08, alpha: 0.95).setFill()
        bottomShadowPath.fill()

        // 2. Main keycap body (raised slightly for mechanical key look)
        let keyRect = NSRect(x: 3, y: 5, width: bounds.width - 6, height: bounds.height - 7)
        let keyPath = NSBezierPath(roundedRect: keyRect, xRadius: cornerRadius, yRadius: cornerRadius)
        
        // Grayscale subtle gradient top-to-bottom
        let gradient = NSGradient(
            starting: NSColor(white: 0.24, alpha: 0.98),
            ending: NSColor(white: 0.14, alpha: 0.98)
        )
        gradient?.draw(in: keyPath, angle: -90)

        // 3. Subtle top highlight inner stroke
        let highlightPath = NSBezierPath(roundedRect: keyRect.insetBy(dx: 1, dy: 1), xRadius: cornerRadius - 1, yRadius: cornerRadius - 1)
        NSColor(white: 0.35, alpha: 0.6).setStroke()
        highlightPath.lineWidth = 1.0
        highlightPath.stroke()

        // 4. Subtle outer border (grayscale)
        NSColor(white: 0.45, alpha: 0.85).setStroke()
        keyPath.lineWidth = 1.2
        keyPath.stroke()

        // 5. Centered key label with pixel/monospace font
        let keyFont = NSFont(name: "Press Start 2P", size: 14) ?? NSFont.monospacedSystemFont(ofSize: 15, weight: .black)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let keyAttrs: [NSAttributedString.Key: Any] = [
            .font: keyFont,
            .foregroundColor: NSColor(white: 0.96, alpha: 1.0),
            .paragraphStyle: paragraphStyle
        ]
        
        let keyText = "\(key)"
        let keySize = keyText.size(withAttributes: keyAttrs)
        let textY = keyRect.origin.y + (keyRect.height - keySize.height) / 2.0 - 0.5
        let textRect = NSRect(
            x: keyRect.origin.x,
            y: textY,
            width: keyRect.width,
            height: keySize.height
        )
        
        // Subtle dark text shadow for 3D engraved look
        let shadowAttrs: [NSAttributedString.Key: Any] = [
            .font: keyFont,
            .foregroundColor: NSColor(white: 0.05, alpha: 0.8),
            .paragraphStyle: paragraphStyle
        ]
        let shadowRect = NSRect(x: textRect.origin.x, y: textRect.origin.y - 1.0, width: textRect.width, height: textRect.height)
        keyText.draw(in: shadowRect, withAttributes: shadowAttrs)

        keyText.draw(in: textRect, withAttributes: keyAttrs)
    }
}

class DimMaskView: NSView {
    let cutoutRect: NSRect?

    init(frame: NSRect, cutoutRect: NSRect?) {
        self.cutoutRect = cutoutRect
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(rect: bounds)
        if let cutout = cutoutRect {
            let cornerRadius: CGFloat = 8.0
            let cutoutPath = NSBezierPath(roundedRect: cutout, xRadius: cornerRadius, yRadius: cornerRadius)
            path.append(cutoutPath)
            path.windingRule = .evenOdd
        }

        NSColor.black.withAlphaComponent(0.40).setFill()
        path.fill()
    }
}

class GlowingOutlineView: NSView {
    let innerWindowRect: NSRect

    init(frame: NSRect, innerWindowRect: NSRect) {
        self.innerWindowRect = innerWindowRect
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let cornerRadius: CGFloat = 8.0
        let pureWhite = NSColor.white

        // Multiple concentric strokes for clean white halo glow effect
        let glowLevels: [(inset: CGFloat, alpha: CGFloat, width: CGFloat)] = [
            (-8.0, 0.05, 8.0),
            (-5.0, 0.12, 6.0),
            (-3.0, 0.25, 4.0),
            (-1.0, 0.50, 3.0),
            ( 0.0, 0.95, 2.0)
        ]

        for level in glowLevels {
            let rect = innerWindowRect.insetBy(dx: level.inset, dy: level.inset)
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius - level.inset / 2.0, yRadius: cornerRadius - level.inset / 2.0)
            pureWhite.withAlphaComponent(level.alpha).setStroke()
            path.lineWidth = level.width
            path.stroke()
        }

        // Inner crisp white highlight rim
        let innerHighlightRect = innerWindowRect.insetBy(dx: 1.0, dy: 1.0)
        let innerHighlightPath = NSBezierPath(roundedRect: innerHighlightRect, xRadius: cornerRadius - 1.0, yRadius: cornerRadius - 1.0)
        NSColor.white.withAlphaComponent(0.90).setStroke()
        innerHighlightPath.lineWidth = 1.0
        innerHighlightPath.stroke()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
OverlayManager.shared.start()
app.run()
