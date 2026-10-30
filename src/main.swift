// hdr-always-on keeps HDR switched on for external displays on macOS.
//
// It reacts to wake, unlock, and display changes, checks every 15 minutes as a backup,
// only asks for HDR when macOS reports that the display can use it, and confirms the result.

import AppKit
import CoreGraphics
import Darwin

let appVersion = "2.0.0"
let backupCheckInterval: TimeInterval = 15 * 60
let retryDelayAfterFailure: TimeInterval = 15 * 60
let confirmDelay: TimeInterval = 3

setlinebuf(stdout)
setlinebuf(stderr)

// MARK: - Private HDR controls

/// Private functions that back the "High Dynamic Range" switch in System Settings.
struct HDRControl {
    typealias Query = @convention(c) (CGDirectDisplayID) -> Bool
    typealias Setter = @convention(c) (CGDirectDisplayID, Bool) -> Int32

    let isAvailable: Query
    let isEnabled: Query
    let setEnabled: Setter

    /// Looks the functions up at runtime so a future macOS change produces a clear message instead of a crash.
    static func load() -> HDRControl? {
        let candidates: [(path: String, symbols: [String])] = [
            ("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
             ["CoreDisplay_Display_SupportsHDRMode", "CoreDisplay_Display_IsHDRModeEnabled", "CoreDisplay_Display_SetHDRModeEnabled"]),
            ("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
             ["SLSDisplaySupportsHDRMode", "SLSDisplayIsHDRModeEnabled", "SLSDisplaySetHDRModeEnabled"]),
        ]
        for candidate in candidates {
            guard let handle = dlopen(candidate.path, RTLD_LAZY) else { continue }
            let found = candidate.symbols.compactMap { dlsym(handle, $0) }
            guard found.count == candidate.symbols.count else { continue }
            return HDRControl(
                isAvailable: unsafeBitCast(found[0], to: Query.self),
                isEnabled: unsafeBitCast(found[1], to: Query.self),
                setEnabled: unsafeBitCast(found[2], to: Setter.self))
        }
        return nil
    }
}

// MARK: - Displays

struct ExternalDisplay {
    let id: CGDirectDisplayID
    let name: String
    /// Vendor, model, and serial number in hex. Unlike the display ID, this stays the same across reconnects.
    let identifier: String

    var shortIdentifier: String { identifier.split(separator: ":").prefix(2).joined(separator: ":") }
    var label: String { "\(name) [\(identifier)]" }
}

func externalDisplays() -> [ExternalDisplay] {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }

    let names = screenNames()
    return ids.prefix(Int(count))
        .filter { CGDisplayIsBuiltin($0) == 0 }
        .map { id in
            let identifier = String(format: "%04x:%04x:%08x",
                                    CGDisplayVendorNumber(id), CGDisplayModelNumber(id), CGDisplaySerialNumber(id))
            return ExternalDisplay(id: id, name: names[id] ?? "Display \(id)", identifier: identifier)
        }
}

func screenNames() -> [CGDirectDisplayID: String] {
    var names: [CGDirectDisplayID: String] = [:]
    for screen in NSScreen.screens {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            names[number.uint32Value] = screen.localizedName
        }
    }
    return names
}

// MARK: - Exclusions

enum Exclusions {
    static var directory: String {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return home + "/.config/hdr-always-on"
    }

    static var file: String { directory + "/exclude.txt" }

    static func load() -> [String] {
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    static func save(_ entries: [String]) throws {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let header = """
            # Displays that hdr-always-on leaves alone, one per line.
            # Use a display name or an identifier shown by `hdr-always-on list`.

            """
        try (header + entries.map { $0 + "\n" }.joined()).write(toFile: file, atomically: true, encoding: .utf8)
    }

    static func matches(_ display: ExternalDisplay, entries: [String]) -> Bool {
        let names = [display.name, display.identifier, display.shortIdentifier].map { $0.lowercased() }
        return entries.contains { names.contains($0.lowercased()) }
    }
}

// MARK: - Keeping HDR on

let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}()

func log(_ message: String) {
    print("[\(timestampFormatter.string(from: Date()))] \(message)")
}

final class HDRKeeper {
    private let hdr: HDRControl
    private var lastStatus: [String: String] = [:]
    private var nextAttempt: [String: Date] = [:]
    private var connected: Set<String> = []
    private var checking = false
    private var checkAgainWhenDone = false
    private var pendingCheck: DispatchWorkItem?

    init(hdr: HDRControl) {
        self.hdr = hdr
    }

    /// Coalesces bursts of display events into one check once the displays have settled.
    func schedule(after delay: TimeInterval, retryFailedDisplays: Bool = false) {
        if retryFailedDisplays { nextAttempt.removeAll() }
        pendingCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.check() }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func check(completion: (() -> Void)? = nil) {
        if checking {
            checkAgainWhenDone = true
            return
        }
        checking = true

        let displays = externalDisplays()
        let exclusions = Exclusions.load()
        let now = Date()
        let confirmations = DispatchGroup()

        // A display that reconnects gets a fresh attempt and logs its state again.
        let present = Set(displays.map(\.identifier))
        for identifier in connected.subtracting(present) {
            lastStatus[identifier] = nil
            nextAttempt[identifier] = nil
        }
        connected = present

        if displays.isEmpty {
            report(key: "*", "No external displays connected")
        } else {
            lastStatus["*"] = nil
        }

        for display in displays {
            let key = display.identifier
            if Exclusions.matches(display, entries: exclusions) {
                report(display, "excluded, so HDR is left as it is")
                continue
            }
            guard hdr.isAvailable(display.id) else {
                report(display, "macOS isn't offering HDR for this display in its current mode")
                continue
            }
            if hdr.isEnabled(display.id) {
                nextAttempt[key] = nil
                report(display, "HDR is on")
                continue
            }
            if let next = nextAttempt[key], next > now { continue }

            // Block repeat attempts right away, so the display change caused by this attempt can't trigger another one.
            nextAttempt[key] = now.addingTimeInterval(retryDelayAfterFailure)
            let code = hdr.setEnabled(display.id, true)
            confirmations.enter()
            DispatchQueue.main.asyncAfter(deadline: .now() + confirmDelay) { [self] in
                defer { confirmations.leave() }
                if hdr.isEnabled(display.id) {
                    nextAttempt[key] = nil
                    log("\(display.label): HDR was off, turned it back on")
                    lastStatus[key] = "HDR is on"
                } else {
                    report(display, "HDR is off and macOS didn't turn it on (code \(code)). Trying again after the next wake or reconnect, or in 15 minutes")
                }
            }
        }

        confirmations.notify(queue: .main) { [self] in
            checking = false
            completion?()
            if checkAgainWhenDone {
                checkAgainWhenDone = false
                schedule(after: 1)
            }
        }
    }

    private func report(_ display: ExternalDisplay, _ status: String) {
        report(key: display.identifier, status, label: display.label)
    }

    /// Logs only when a display's state changes, so the log stays short.
    private func report(key: String, _ status: String, label: String? = nil) {
        guard lastStatus[key] != status else { return }
        lastStatus[key] = status
        log(label.map { "\($0): \(status)" } ?? status)
    }
}

// MARK: - Commands

func loadControlsOrExit(exitCode: Int32) -> HDRControl {
    if let hdr = HDRControl.load() { return hdr }
    log("This version of macOS doesn't provide the HDR controls hdr-always-on uses. Nothing to do.")
    exit(exitCode)
}

func runAgent() -> Never {
    // A successful exit keeps launchd from restarting the agent over and over on an unsupported macOS.
    let hdr = loadControlsOrExit(exitCode: 0)
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)

    let keeper = HDRKeeper(hdr: hdr)
    log("hdr-always-on \(appVersion) started")

    CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
        guard !flags.contains(.beginConfigurationFlag), let userInfo = userInfo else { return }
        Unmanaged<HDRKeeper>.fromOpaque(userInfo).takeUnretainedValue().schedule(after: 3)
    }, Unmanaged.passUnretained(keeper).toOpaque())

    NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { _ in keeper.schedule(after: 3) }

    let workspace = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                 NSWorkspace.sessionDidBecomeActiveNotification] {
        workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
            keeper.schedule(after: 5, retryFailedDisplays: true)
        }
    }

    let backupTimer = Timer(timeInterval: backupCheckInterval, repeats: true) { _ in keeper.schedule(after: 0) }
    backupTimer.tolerance = 60
    RunLoop.main.add(backupTimer, forMode: .common)

    keeper.schedule(after: 2)
    app.run()
    exit(0)
}

func runOnce() -> Never {
    let keeper = HDRKeeper(hdr: loadControlsOrExit(exitCode: 1))
    keeper.check { exit(0) }
    RunLoop.main.run()
    exit(0)
}

func listDisplays() {
    let hdr = loadControlsOrExit(exitCode: 1)
    let displays = externalDisplays()
    if displays.isEmpty {
        print("No external displays connected.")
    }
    let exclusions = Exclusions.load()
    for display in displays {
        print(display.name)
        print("  Identifier:     \(display.identifier)")
        print("  HDR available:  \(hdr.isAvailable(display.id) ? "yes" : "no")")
        print("  HDR on:         \(hdr.isEnabled(display.id) ? "yes" : "no")")
        print("  Excluded:       \(Exclusions.matches(display, entries: exclusions) ? "yes" : "no")")
    }
    print("\nExclusions file: \(Exclusions.file)")
}

func updateExclusions(adding: Bool, entry rawEntry: String) {
    let entry = rawEntry.trimmingCharacters(in: .whitespaces)
    guard !entry.isEmpty else {
        printUsage(to: stderr)
        exit(64)
    }
    var entries = Exclusions.load()
    let alreadyListed = entries.contains { $0.caseInsensitiveCompare(entry) == .orderedSame }
    if adding {
        guard !alreadyListed else {
            print("\(entry) is already excluded.")
            return
        }
        entries.append(entry)
    } else {
        guard alreadyListed else {
            print("\(entry) isn't in the exclusions list.")
            return
        }
        entries.removeAll { $0.caseInsensitiveCompare(entry) == .orderedSame }
    }
    do {
        try Exclusions.save(entries)
    } catch {
        fputs("Couldn't update \(Exclusions.file): \(error.localizedDescription)\n", stderr)
        exit(1)
    }
    if adding {
        print("hdr-always-on will leave \(entry) alone from its next check.")
    } else {
        print("hdr-always-on will manage \(entry) again. Run `hdr-always-on once` to turn HDR on now.")
    }
}

func printUsage(to stream: UnsafeMutablePointer<FILE> = stdout) {
    fputs("""
        hdr-always-on \(appVersion): keeps HDR switched on for external displays.

        Usage:
          hdr-always-on list               Show external displays and their HDR state
          hdr-always-on once               Check now and turn HDR on where it's off
          hdr-always-on exclude DISPLAY    Leave a display alone (name or identifier from `list`)
          hdr-always-on include DISPLAY    Manage a previously excluded display again
          hdr-always-on run                Keep HDR on in the background (used by the LaunchAgent)
          hdr-always-on --version          Print the version

        """, stream)
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "run":
    runAgent()
case "once":
    runOnce()
case "list":
    listDisplays()
case "exclude":
    updateExclusions(adding: true, entry: arguments.dropFirst().joined(separator: " "))
case "include":
    updateExclusions(adding: false, entry: arguments.dropFirst().joined(separator: " "))
case "--version", "version":
    print(appVersion)
case nil, "help", "-h", "--help":
    printUsage()
default:
    printUsage(to: stderr)
    exit(64)
}
