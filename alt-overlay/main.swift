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
    let app: String
    let title: String
    let role: String?
    let frame: YabaiFrame
    let isVisible: Bool
    let isMinimized: Bool
    let isHidden: Bool

    enum CodingKeys: String, CodingKey {
        case id, app, title, role, frame
        case isVisible = "is-visible"
        case isMinimized = "is-minimized"
        case isHidden = "is-hidden"
    }
}

let keyLabels = ["G", "H", "J", "K", "L"]
let targetKeyCodes: [Int64: Int] = [
    5: 0,   // 'g'
    4: 1,   // 'h'
    38: 2,  // 'j'
    40: 3,  // 'k'
    37: 4   // 'l'
]

class OverlayManager {
    static let shared = OverlayManager()
    
    private var darkWindows: [NSWindow] = []
    private var badgeWindows: [NSWindow] = []
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
                        self.focusWindow(id: win.id)
                    }
                    self.hideOverlay()
                }
                // Suppress key press so it doesn't type into the active window
                return nil
            }
        }

        return Unmanaged.passRetained(event)
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

    private func focusWindow(id: Int) {
        let task = Process()
        task.launchPath = "/opt/homebrew/bin/yabai"
        task.arguments = ["-m", "window", "--focus", "\(id)"]
        try? task.run()
    }

    private func showOverlay() {
        guard !isOverlayActive else { return }
        isOverlayActive = true
        activeWindows = fetchWindows()

        // 1. Create dimming overlay for each screen
        for screen in NSScreen.screens {
            let dimWin = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            dimWin.isOpaque = false
            dimWin.backgroundColor = NSColor.black.withAlphaComponent(0.40)
            dimWin.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
            dimWin.ignoresMouseEvents = true
            dimWin.orderFrontRegardless()
            darkWindows.append(dimWin)
        }

        // 2. Create key badges on each visible window
        guard let primaryScreen = NSScreen.screens.first else { return }
        let primaryHeight = primaryScreen.frame.height

        for (idx, win) in activeWindows.prefix(5).enumerated() {
            let keyChar = keyLabels[idx]
            let numStr = "\(idx + 1)"
            
            // Convert yabai coordinate (top-left based) to macOS Cocoa coordinate (bottom-left based)
            let winX = win.frame.x
            let winY = primaryHeight - (win.frame.y + win.frame.h)
            let winW = win.frame.w
            let winH = win.frame.h

            // Position badge in center of window
            let badgeW: CGFloat = 140
            let badgeH: CGFloat = 100
            let badgeX = winX + (winW - badgeW) / 2
            let badgeY = winY + (winH - badgeH) / 2

            let badgeRect = NSRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)
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

            let badgeView = BadgeView(frame: NSRect(x: 0, y: 0, width: badgeW, height: badgeH), key: keyChar, number: numStr)
            badgeWin.contentView = badgeView
            badgeWin.orderFrontRegardless()
            badgeWindows.append(badgeWin)
        }
    }

    private func hideOverlay() {
        guard isOverlayActive else { return }
        isOverlayActive = false

        for win in darkWindows {
            win.orderOut(nil)
        }
        darkWindows.removeAll()

        for win in badgeWindows {
            win.orderOut(nil)
        }
        badgeWindows.removeAll()
        activeWindows.removeAll()
    }
}

class BadgeView: NSView {
    let key: String
    let number: String

    init(frame: NSRect, key: String, number: String) {
        self.key = key
        self.number = number
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw rounded pill container
        let bgPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 18, yRadius: 18)
        NSColor(white: 0.12, alpha: 0.92).setFill()
        bgPath.fill()

        NSColor(calibratedRed: 0.35, green: 0.65, blue: 1.0, alpha: 0.9).setStroke()
        bgPath.lineWidth = 2.5
        bgPath.stroke()

        // Key label (e.g. "G", "H", "J")
        let keyText = "\(key)"
        let keyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 42, weight: .heavy),
            .foregroundColor: NSColor.white
        ]
        let keySize = keyText.size(withAttributes: keyAttrs)
        let keyPoint = NSPoint(
            x: (bounds.width - keySize.width) / 2,
            y: (bounds.height / 2) - 2
        )
        keyText.draw(at: keyPoint, withAttributes: keyAttrs)

        // Number subtitle (e.g. "[1]")
        let subText = "Window \(number)"
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.7, green: 0.85, blue: 1.0, alpha: 0.95)
        ]
        let subSize = subText.size(withAttributes: subAttrs)
        let subPoint = NSPoint(
            x: (bounds.width - subSize.width) / 2,
            y: keyPoint.y - subSize.height - 4
        )
        subText.draw(at: subPoint, withAttributes: subAttrs)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
OverlayManager.shared.start()
app.run()
