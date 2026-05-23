import ArgumentParser
import Cocoa

let pidFilePath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".fringe.pid").path

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? 0
    }
}

class BorderView: NSView {
    let color: NSColor
    let thickness: CGFloat

    init(frame: NSRect, color: NSColor, thickness: CGFloat) {
        self.color = color
        self.thickness = thickness
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        color.setStroke()
        let path = NSBezierPath(rect: bounds.insetBy(dx: thickness / 2, dy: thickness / 2))
        path.lineWidth = thickness
        path.stroke()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let borderColor: NSColor
    let borderThickness: CGFloat
    var borderWindows: [CGDirectDisplayID: NSWindow] = [:]
    var lastActiveDisplayID: CGDirectDisplayID = 0

    init(color: NSColor, thickness: CGFloat) {
        self.borderColor = color
        self.borderThickness = thickness
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        updateBorders()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateBorders()
        }
    }

    @objc func activeAppChanged(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.updateBorders()
        }
    }

    @objc func screensChanged(_ notification: Notification) {
        borderWindows.values.forEach { $0.orderOut(nil) }
        borderWindows.removeAll()
        updateBorders()
    }

    func updateBorders() {
        guard let activeScreen = NSScreen.main else { return }
        let activeID = activeScreen.displayID

        if activeID == lastActiveDisplayID { return }
        lastActiveDisplayID = activeID

        let inactiveScreens = NSScreen.screens.filter { $0.displayID != activeID }
        let activeIDs = Set(inactiveScreens.map { $0.displayID })

        for (id, window) in borderWindows where !activeIDs.contains(id) {
            window.orderOut(nil)
            borderWindows.removeValue(forKey: id)
        }

        for screen in inactiveScreens where borderWindows[screen.displayID] == nil {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.contentView = BorderView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                color: borderColor,
                thickness: borderThickness
            )
            window.orderFront(nil)
            borderWindows[screen.displayID] = window
        }
    }
}

func parseColor(_ str: String) -> NSColor? {
    switch str.lowercased() {
    case "orange": return .systemOrange
    case "red": return .systemRed
    case "blue": return .systemBlue
    case "green": return .systemGreen
    case "yellow": return .systemYellow
    case "white": return .white
    case "cyan", "teal": return .systemTeal
    case "magenta", "pink": return .systemPink
    case "purple": return .systemPurple
    default:
        var hex = str
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let val = UInt64(hex, radix: 16) else { return nil }
        return NSColor(
            red: CGFloat((val >> 16) & 0xFF) / 255,
            green: CGFloat((val >> 8) & 0xFF) / 255,
            blue: CGFloat(val & 0xFF) / 255,
            alpha: 1
        )
    }
}

func resolveExecutablePath() -> String {
    let arg0 = CommandLine.arguments[0]
    if arg0.contains("/") {
        if arg0.hasPrefix("/") { return arg0 }
        return FileManager.default.currentDirectoryPath + "/" + arg0
    }
    // Bare name — search PATH
    if let path = ProcessInfo.processInfo.environment["PATH"] {
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/\(arg0)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
    }
    return arg0
}

func readPid() -> Int32? {
    guard let str = try? String(contentsOfFile: pidFilePath, encoding: .utf8),
          let pid = Int32(str.trimmingCharacters(in: .whitespacesAndNewlines)),
          kill(pid, 0) == 0 else {
        return nil
    }
    return pid
}

var sigTermSource: DispatchSourceSignal?

func stopExisting() {
    guard let pid = readPid() else { return }
    kill(pid, SIGTERM)
    try? FileManager.default.removeItem(atPath: pidFilePath)
    // Wait up to 2s for the process to exit
    for _ in 0..<20 {
        if kill(pid, 0) != 0 { return }
        usleep(100_000)
    }
}

// MARK: - Commands

@main
struct Fringe: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Draw borders on inactive screens to highlight the active one.",
        subcommands: [Stop.self, Run.self]
    )

    @Option(name: .long, help: "Border color: orange, red, blue, green, yellow, white, cyan, pink, purple, or hex (#FF5500)")
    var color: String = "orange"

    @Option(name: .long, help: "Border thickness in points")
    var thickness: Double = 3.0

    mutating func run() throws {
        guard parseColor(color) != nil else {
            throw ValidationError("Unknown color '\(color)'. Use a named color or hex like #FF5500.")
        }

        stopExisting()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolveExecutablePath())
        process.arguments = ["_run", "--_color", color, "--_thickness", String(thickness)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        let pid = process.processIdentifier
        try String(pid).write(toFile: pidFilePath, atomically: true, encoding: .utf8)
        print("fringe started (pid \(pid))")
    }
}

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop the daemon")

    func run() throws {
        guard readPid() != nil else {
            try? FileManager.default.removeItem(atPath: pidFilePath)
            print("fringe is not running")
            throw ExitCode.failure
        }

        stopExisting()
        print("fringe stopped")
    }
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "_run",
        shouldDisplay: false
    )

    @Option(name: .customLong("_color")) var color: String = "orange"
    @Option(name: .customLong("_thickness")) var thickness: Double = 3.0

    mutating func run() throws {
        guard let borderColor = parseColor(color) else {
            throw ValidationError("Unknown color '\(color)'")
        }

        signal(SIGTERM, SIG_IGN)
        sigTermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigTermSource?.setEventHandler {
            try? FileManager.default.removeItem(atPath: pidFilePath)
            Darwin.exit(0)
        }
        sigTermSource?.resume()

        let app = NSApplication.shared
        let delegate = AppDelegate(color: borderColor, thickness: CGFloat(thickness))
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
