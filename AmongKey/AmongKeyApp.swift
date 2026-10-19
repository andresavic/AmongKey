//
//  AmongKeyApp.swift
//  AmongKey
//
//  Created by Andre Savic on 24.11.20.
//
//  ARCHITECTURE
//  ------------
//  AmongKey turns keyboard input into mouse events inside the Among Us window (the iPad build running on Apple
//  Silicon has no keyboard support). To know *which* buttons exist right now (joystick + Use/Report while playing,
//  a chat box in a meeting, ...) it screenshots the game window and classifies the scene with a Core ML model.
//
//      focus events ──► [tick, 4 Hz, only while the game is in front]
//                          ├─ pollGameWindow()  cheap "did the window move / resize?" check, recalibrates coordinates
//                          └─ startClassify()   background capture + Core ML, only when due (see requestClassify)
//      key events   ──► Keymapping.swift ──► simulateClick() / movement() ──► synthetic mouse events
//
//  POWER MODEL (this is the part worth reading before changing anything)
//  ---------------------------------------------------------------------
//  The expensive operations are (1) capturing the window, which makes WindowServer re-composite the game's Metal
//  layer, and (2) running the classifier. Everything else is noise. So:
//   - nothing runs while Among Us is not the front app (focus is event driven, not polled)
//   - window geometry is a metadata query for ONE window (~0.3 ms, no pixels)
//   - captures happen only when something changed (window moved, key that can change the scene, game regained
//     focus) and back off to ~1/s once the scene has been stable for a few readings
//   - the classifier runs on the Neural Engine so it does not compete with the game for the GPU
//   - the 40 Hz movement timer only exists while a movement key is held
//  Everything that is not essential for playing (logging, tuning, training-data capture) is off unless developer
//  mode is enabled, see "Developer mode" below.
//
//  THREADING
//  ---------
//  All game state (gamestate, X/Y/Width/Height, stableCount, ...) is read and written on the MAIN thread only.
//  The only thing that leaves the main thread is capture + Core ML (classifyQueue), and its result is posted back
//  with DispatchQueue.main.async. This is deliberate: the original code classified on the main thread, which also
//  serves key events and the movement timer, so every classification froze input for its duration.
//

import SwiftUI
import CoreML
import Vision
import ImageIO

@main
struct AmongKeyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().onAppear(perform: {
                setup()
            })
        }
    }
}

var up: Int = 0
var down: Int = 0
var left: Int = 0
var right: Int = 0

var mouseIsDown: Bool = false
var mouseClickLock = NSLock()


// MARK: - Layout (where the buttons are)
//
// All positions are FRACTIONS of the GAME AREA: x = 0...1 across, y = 0...1 down. Not pixels, not window points.
//
// Why fractions of the game area: the game renders at a fixed shape (width / height = 1.4317) and letterboxes
// itself inside whatever window it gets, both windowed and fullscreen. Measured on macOS 27 / M1:
//     fullscreen  1440x900 pt screen  -> game area 1288.5 x 900 pt, centred (76 pt bars left and right)
//     windowed    919 x 674 pt window -> 32 pt title bar + game area 919 x 642 pt
// 1288.5 / 900 = 919 / 642 = 1.4317, so one set of fractions is valid for every window size. The previous
// constants assumed a 4:3 reference (2800 x 2100), which put every button a few points off and the joystick
// centre ~5 pt too far right (the player drifted "up" on left/right and "right" on up/down).
//
// How these numbers were obtained (re-do this when the game's HUD changes): take fullscreen screenshots
// (Cmd+Shift+3) per scene, find the black pillar bars to get the game area, then take the centre of each
// button's light inner square, e.g.  map button centre (2599.5, 143.5) px in a 2880x1800 shot:
//     x = (2599.5 - 152) / 2577 = 0.9497      y = 143.5 / 1800 = 0.0797
// Verified on a windowed screenshot afterwards: predicted joystick and map centres were within 1 pt.
let ASPECT = 1.4317

// Bottom-right button grid, USE is the anchor. Row 0 = Use / Report, row 1 = Kill / Sabotage / Vent.
// USE and REPORT are measured. The vertical pitch is the old layout's value (400 of 2100) and the horizontal pitch
// follows from the measured REPORT position. KILL / SABOTAGE / VENT / ROLE only exist for impostors and have NOT
// been re-measured on the current HUD.
func calculateUIPosition(ui_position: (ui_x: Int, ui_y: Int)) -> (x: Double, y: Double) {
    let use_button = (x: 0.9064, y: 0.8867)
    let horizontal_spacing = 0.1160
    let vertical_spacing = 0.1905
    return (x: use_button.x - horizontal_spacing * Double(ui_position.ui_x),
            y: use_button.y - vertical_spacing * Double(ui_position.ui_y))
}

// Joystick geometry (tunable in developer mode, see below)
var JOYSTICK = (x: 0.0755, y: 0.8911) // centre of the (fixed) joystick
var JOY_DIST: Double = 0.055 // push distance as a fraction of the game area height; slightly beyond the ring radius (~0.051) so the stick is fully deflected
var TITLEBAR: Double = 32.0 // macOS 27 window title bar; applyBounds() re-derives it from the window shape when it can
var MOVE_MODE: Int = 1 // 1 = drag events (default), 0 = the original repeated mouse-down events
let USE_BUTTON = calculateUIPosition(ui_position: (ui_x: 0, ui_y: 0))
let KILL_BUTTON = calculateUIPosition(ui_position: (ui_x: 0, ui_y: 1))
let REPORT_BUTTON = calculateUIPosition(ui_position: (ui_x: 1, ui_y: 0))
let SABOTAGE_BUTTON = calculateUIPosition(ui_position: (ui_x: 1, ui_y: 1))
let VENT_BUTTON = calculateUIPosition(ui_position: (ui_x: 2, ui_y: 1))
let ROLE_BUTTON = calculateUIPosition(ui_position: (ui_x: 2, ui_y: 0))

let ESC_BUTTON = (x: 0.0171, y: 0.2060)          // the "Tasks" tab on the left edge (measured)
let MAP_BUTTON = (x: 0.9497, y: 0.0797)          // measured
let MEETING_CHAT_BUTTON = (x: 0.7827, y: 0.0792) // measured
let LOBBY_CHAT_BUTTON = (x: 0.7827, y: 0.0792)   // NOT measured yet, assumed to be in the same slot as in meetings
// Send button of the chat panel, measured in a meeting (the white input box is directly to its left, u 0.21...0.64).
// The old values pointed far below the panel, so "Return to send" clicked outside the chat and closed it.
// The lobby chat is the same panel but its position has NOT been measured there.
let LOBBY_CHAT_SEND_BUTTON = (x: 0.688, y: 0.625)
let MEETING_CHAT_SEND_BUTTON = (x: 0.688, y: 0.625)

var originalPosition = (x: 0.0, y: 0.0)
var originalSize = (height: 0.0, width: 0.0)

// The GAME AREA in global screen points (top-left origin, like CGEvent coordinates). Everything is derived from
// the window bounds in applyBounds(). -1 means "game window not found".
var X: Double = -1.0 //X Position of the game area
var Y: Double = -1.0 //Y Position of the game area

var Height: Double = -1 //Height of the game area
var Width: Double = -1 //Width of the game area

var topmost: Bool = false // Is Among Us in focus

var gamestate: String = "Menu" //Curent game state

var storeScreenshot: String = ""

var lastX: Double = 0.0 //Last down X position of cursor
var lastY: Double = 0.0 //Last down Y position of cursor

// MARK: - Developer mode
//
// Developer mode is on only if the file ~/.amongkey_tune exists when the app starts. When it does not exist
// there is no logging, no file polling and no training-data capture, so end users pay nothing for these features.
// Why a file and not a build flag / menu item: coordinates can be re-tuned on a running app without a rebuild,
// which matters because every rebuilt (re-signed) copy has to be granted Accessibility + Screen Recording again.
//
// File format, whitespace or comma separated, all optional from the right:
//     joyX joyY joyDist titlebar moveMode fastCheckSeconds slowCheckSeconds runBenchmark
//     0.0755 0.8911 0.055 32 1 0.5 1.0 0
// The log goes to ~/Library/Logs/AmongKey-debug.log and only records scene changes, window geometry and key codes
// while Among Us is in front.
let tunePath = NSHomeDirectory() + "/.amongkey_tune"
let logPath = NSHomeDirectory() + "/Library/Logs/AmongKey-debug.log"
let devMode: Bool = FileManager.default.fileExists(atPath: tunePath)
let logQueue = DispatchQueue(label: "amongkey.log")
var lastLog = ""

// @autoclosure so the (sometimes expensive) message string is not even built when developer mode is off.
// Identical consecutive messages are dropped, otherwise key repeat floods the log.
func dlog(_ message: @autoclosure () -> String) {
    guard devMode else { return }
    let msg = message()
    logQueue.async {
        if msg == lastLog { return }
        lastLog = msg
        let line = ISO8601DateFormatter().string(from: Date()) + " " + msg + "\n"
        if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
        else { try? line.write(toFile: logPath, atomically: true, encoding: .utf8) }
    }
}

// Scene check cadence (seconds), see requestClassify() / startClassify()
var FAST_CHECK: Double = 0.35 // right after something changed, and the whole time a meeting / chat is on screen
var SLOW_CHECK: Double = 0.75 // once the scene has been stable for a while
var RUN_BENCH: Int = 0

func loadTune() {
    guard devMode, let t = try? String(contentsOfFile: tunePath) else { return }
    let v = t.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "," }).compactMap { Double($0) }
    if v.count >= 3 { JOYSTICK = (x: v[0], y: v[1]); JOY_DIST = v[2] }
    if v.count >= 4 { TITLEBAR = v[3] }
    if v.count >= 5 { MOVE_MODE = Int(v[4]) }
    if v.count >= 6 { FAST_CHECK = max(0.2, v[5]) } // clamped: a typo must not turn the classifier into a busy loop
    if v.count >= 7 { SLOW_CHECK = max(0.2, v[6]) }
    if v.count >= 8 { RUN_BENCH = Int(v[7]) }
}

// MARK: - Setup

var didSetup = false

func setup() {
    // onAppear fires again whenever the window is re-opened from the Dock. Without this guard every re-open
    // registered a second set of global key monitors and timers, i.e. every key press was handled twice.
    if didSetup { return }
    didSetup = true

    UserDefaults.standard.register(defaults: ["showLiveStatus": true])
    liveStatus = UserDefaults.standard.bool(forKey: "showLiveStatus")
    loadTune()

    // One request per app start (not recurring)
    Update.checkForUpdate(completion: { download in
        DispatchQueue.main.async {
            globaleState.shared.download = download
        }
    })

    let permission = AXIsProcessTrustedWithOptions(
        [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)

    dlog("setup accessibilityTrusted=\(permission) screenCapture=\(CGPreflightScreenCaptureAccess()) dev=true")
    if (permission) {
        createKeybinding()
    }

    classifyQueue.async { _ = visionRequest } // load the model once, off the main thread
    setupFocusTracking()
}

// MARK: - Focus tracking (event driven, no polling while another app is in front)
//
// The old code polled the full window list 4x per second forever, including while you were in another app.
// NSWorkspace tells us when the front app changes, so the poll timer only exists while the game is in front.

var pollTimer: Timer?
var tickCount = 0

// The CGWindow owner / app name is "AmongUs" (no space) on macOS 27; the original code matched "Among Us" with a
// space and therefore never found the window. Normalise so either spelling works.
func isGameName(_ name: String?) -> Bool {
    guard let n = name else { return false }
    return n.replacingOccurrences(of: " ", with: "").lowercased() == "amongus"
}

func isGameApp(_ app: NSRunningApplication?) -> Bool {
    guard let app = app else { return false }
    if gamePID != 0 && app.processIdentifier == gamePID { return true }
    return isGameName(app.localizedName) || isGameName(app.bundleURL?.deletingPathExtension().lastPathComponent)
}

func setupFocusTracking() {
    let nc = NSWorkspace.shared.notificationCenter
    nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { n in
        focusChanged(to: n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
    }
    nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { n in
        if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.processIdentifier == gamePID {
            gameWindowID = 0; gamePID = 0; X = -1; Y = -1
            focusChanged(to: nil)
        }
    }
    focusChanged(to: NSWorkspace.shared.frontmostApplication)
}

func focusChanged(to app: NSRunningApplication?) {
    if isGameApp(app), let app = app {
        gamePID = app.processIdentifier
        topmost = true
        locateGameWindow()
        requestClassify(after: 0) // we may have been away for a while, look right now
        if pollTimer == nil {
            let t = Timer(timeInterval: 0.25, repeats: true) { _ in tick() }
            t.tolerance = 0.05 // lets the OS coalesce our wake-ups with other timers
            RunLoop.main.add(t, forMode: .common) // .common: keep ticking while a menu / drag is tracking
            pollTimer = t
        }
    } else {
        topmost = false
        pollTimer?.invalidate(); pollTimer = nil
        // We stop seeing key-up events for the game while another app is in front, so never leave a
        // movement key (or the synthetic mouse button) latched.
        up = 0; down = 0; left = 0; right = 0
        stopMovementTimer()
        rescueMouse()
    }
}

// Runs 4x per second, ONLY while Among Us is the front app
func tick() {
    tickCount += 1
    if tickCount % 8 == 0 { loadTune() }
    pollGameWindow()
    let now = ProcessInfo.processInfo.systemUptime
    if (now >= nextClassifyAt && !classifyBusy && gameWindowID != 0) { startClassify(now) }
}

// MARK: - Window geometry

var gamePID: pid_t = 0
var gameWindowID: CGWindowID = 0
var lastBounds = CGRect.zero

// Find the game's main window: the biggest on-screen window that belongs to it. "Biggest" instead of "first/last
// match" because the app also owns tiny helper windows (menu bar strip, 500x500 overlay) whose order in the
// window list is not stable.
@discardableResult
func locateGameWindow() -> Bool {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], CGWindowID(0)) as? [[String: Any]] else { return false }
    var best: (id: CGWindowID, rect: CGRect)? = nil
    for w in list {
        // Every field is optional-checked: the old code force-unwrapped them, which can crash on a window that
        // lacks one of these keys.
        guard isGameName(w[kCGWindowOwnerName as String] as? String),
              (w[kCGWindowStoreType as String] as? Int) == 1,
              (w[kCGWindowAlpha as String] as? Double ?? 0) >= 1,
              let id = w[kCGWindowNumber as String] as? Int,
              let b = w[kCGWindowBounds as String] as? [String: Double],
              let rect = CGRect(dictionaryRepresentation: b as CFDictionary) else { continue }
        if (rect.height <= 500 || rect.width <= 500) { continue } //Fix for Macs with Touchbar
        if best == nil || rect.width * rect.height > best!.rect.width * best!.rect.height { best = (CGWindowID(id), rect) }
    }
    guard let found = best else { gameWindowID = 0; X = -1; Y = -1; return false }
    gameWindowID = found.id
    applyBounds(found.rect)
    return true
}

// The "has the window moved or been resized?" check.
//
// Why a metadata query and not "sample a few pixels": reading a pixel needs a screen capture, which is exactly
// the expensive operation we are trying to avoid. WindowServer already knows the exact rectangle; asking for ONE
// window costs ~0.3 ms (measured) and involves no pixels at all; the all-windows query used before grows with the
// number of windows open on the machine.
// If the rectangle changed we recalibrate immediately and re-check the scene once the window has settled.
func pollGameWindow() {
    if gameWindowID == 0 {
        if locateGameWindow() { requestClassify(after: 0) }
        return
    }
    guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], gameWindowID) as? [[String: Any]])?.first,
          (info[kCGWindowIsOnscreen as String] as? Bool) ?? false,
          let b = info[kCGWindowBounds as String] as? [String: Double],
          let rect = CGRect(dictionaryRepresentation: b as CFDictionary) else {
        gameWindowID = 0; X = -1; Y = -1 // closed / minimised: look for it again on the next tick
        return
    }
    if rect != lastBounds {
        applyBounds(rect)
        // Coordinates are updated instantly (so input keeps lining up while you drag), but the expensive scene
        // check is debounced: while the window is being dragged this keeps pushing the check back instead of
        // capturing the window at the fast cadence the whole time.
        stableCount = 0
        nextClassifyAt = ProcessInfo.processInfo.systemUptime + 0.6
    }
}

// Window rectangle -> game area (X, Y, Width, Height). See "Layout" above for why the game area is not the window.
func applyBounds(_ r: CGRect) {
    lastBounds = r
    originalPosition = (x: Double(r.minX), y: Double(r.minY))
    originalSize = (height: Double(r.height), width: Double(r.width))

    // The game is drawn below the title bar, as large as its fixed shape allows, centred in what is left.
    var titleBar = isFullscreen() ? 0.0 : TITLEBAR
    if (!isFullscreen()) {
        // A window that has the game's own shape tells us its title bar exactly (height - width / aspect). This
        // keeps working on macOS versions whose title bar is not 32 pt without hard-coding a table of them.
        let exact = originalSize.height - originalSize.width / ASPECT
        if abs(exact - TITLEBAR) < 6 { titleBar = exact }
    }
    let contentW = originalSize.width, contentH = originalSize.height - titleBar
    var gw = contentW, gh = contentW / ASPECT
    if (gh > contentH) { gh = contentH; gw = gh * ASPECT } // window is wider than the game: bars left and right
    X = originalPosition.x + (contentW - gw) / 2
    Y = originalPosition.y + titleBar + (contentH - gh) / 2
    Width = gw
    Height = gh
    dlog("window X=\(X) Y=\(Y) W=\(Width) H=\(Height) fullscreen=\(isFullscreen()) joy=\(JOYSTICK) dist=\(JOY_DIST) tb=\(TITLEBAR) mode=\(MOVE_MODE) fast=\(FAST_CHECK) slow=\(SLOW_CHECK)")
}

// Fullscreen = the window sits at the origin of the screen and is tall. A title bar is never present then.
func isFullscreen() -> Bool {
    return (originalSize.height > 619 && originalPosition.x == 0.0 && originalPosition.y == 0.0)
}

// Fractions of the game area -> screen points
func calcPos(pos: (x: Double, y: Double)) -> (x: Double, y: Double) {
    return (x: pos.x * Width, y: pos.y * Height)
}

func joysticDistance() -> Double {
    return JOY_DIST * Height
}

// MARK: - Movement (timer only exists while a movement key is held)

var movementTimer: Timer?
var lastTarget = CGPoint(x: -1, y: -1)
var moveTick = 0

// The old code ran this 40x per second forever, even with no key held. Now the timer is created on the first
// movement key down and torn down by movement() itself once every key is released.
func ensureMovementTimer() {
    guard movementTimer == nil else { return }
    let t = Timer(timeInterval: 0.025, repeats: true) { _ in movement() }
    t.tolerance = 0.005
    RunLoop.main.add(t, forMode: .common)
    movementTimer = t
}

func stopMovementTimer() {
    movementTimer?.invalidate()
    movementTimer = nil
}

func movement() {
    if ((up + down + left + right) == 0 || topmost == false) { rescueMouse(); stopMovementTimer(); return }

    if (X == -1 && Y == -1) { rescueMouse(); return }

    if (gamestate != "Ingame" && gamestate != "Lobby") { rescueMouse(); return }

    // A synthetic click (Use, Report, ...) is in flight: do not interleave events with it
    let lockSuccess = mouseClickLock.try()
    if (!lockSuccess){ return }
    defer { mouseClickLock.unlock() }

    // The joystick is a "touch" that starts on its centre and is then dragged in the wanted direction.
    // The game reads direction = touch position - joystick centre, so the centre has to be exact (see Layout).
    let center = calcPos(pos: JOYSTICK)
    let dist = joysticDistance()
    let target = CGPoint(x: X + center.x + dist * Double(right - left),
                         y: Y + center.y + dist * Double(down - up))

    if (mouseIsDown == false) {
        //Put the cursor on the center of the joystick once, then push it in the direction
        mouseDown(pos: CGPoint(x: X + center.x, y: Y + center.y))
        mouseIsDown = true
        lastTarget = CGPoint(x: -1, y: -1)
    }

    // Only send an event when the direction changed, plus a slow keep-alive (every 8th tick = 200 ms) so the
    // game never decides the touch was lost. The old code posted a full mouse-down every 25 ms regardless.
    moveTick += 1
    if (target != lastTarget || moveTick % 8 == 0) {
        if (MOVE_MODE == 0) { mouseDown(pos: target) } else { mouseDrag(pos: target) }
        lastTarget = target
    }

    lastX = target.x
    lastY = target.y
}

// MARK: - Scene detection

// The model is loaded ONCE (it used to be rebuilt from disk on every classification, 4x per second) and is
// restricted to CPU + Neural Engine so it never competes with the game for the GPU. On macOS < 13 the
// computeUnits API does not exist and the default is used. The class AmongUsClassifier is generated by Xcode from
// AmongUsClassifier.mlmodel.
let visionRequest: VNCoreMLRequest? = {
    do {
        let cfg = MLModelConfiguration()
        if #available(macOS 13.0, *) { cfg.computeUnits = .cpuAndNeuralEngine }
        let model = try VNCoreMLModel(for: AmongUsClassifier(configuration: cfg).model)
        return VNCoreMLRequest(model: model)
    } catch {
        dlog("model load failed: \(error)")
        return nil
    }
}()

let classifyQueue = DispatchQueue(label: "amongkey.classify", qos: .userInitiated)
var classifyBusy = false          // main thread: at most one capture + inference in flight
var nextClassifyAt: TimeInterval = 0 // main thread, ProcessInfo.systemUptime based
var stableCount = 0               // main thread: consecutive identical, confident results
var benchDone = false

// "Something happened, look at the screen soon" (a key that can change the scene, the window moved, the game
// came back to the front). Also resets the stability counter so the fast cadence is used until the scene has
// settled again. min(): never postpone a check that is already due sooner.
func requestClassify(after delay: TimeInterval) {
    stableCount = 0
    nextClassifyAt = min(nextClassifyAt, ProcessInfo.processInfo.systemUptime + delay)
}

// Cadence: FAST_CHECK until the same scene was read confidently 3 times in a row, then SLOW_CHECK.
// A meeting that starts while stable is noticed within SLOW_CHECK; most transitions are announced by a key press
// and re-checked after ~0.4 s anyway.
func startClassify(_ now: TimeInterval) {
    classifyBusy = true
    // Meetings and the chat change constantly (votes, panel opening, typing), so they keep the fast cadence
    nextClassifyAt = now + ((stableCount >= 3 && gamestate != "Meeting" && !chatOpen) ? SLOW_CHECK : FAST_CHECK)
    let id = gameWindowID
    // The classifier input is deliberately identical to what the model was trained on: the whole window, or in
    // fullscreen a centred 4:3 crop. Do NOT replace this with the (more correct) game area crop used for
    // clicking, it would change what the model sees and silently lower its confidence.
    let wb = lastBounds
    let crop: CGRect? = isFullscreen() ? CGRect(x: (wb.width - wb.height * 4.0 / 3.0) / 2, y: 0, width: wb.height * 4.0 / 3.0, height: wb.height) : nil
    let shot = storeScreenshot
    storeScreenshot = ""
    let bounds = lastBounds
    // Game area relative to the window's own top-left corner: what the overlay detectors look at
    let gameRect = CGRect(x: X - bounds.minX, y: Y - bounds.minY, width: Width, height: Height)
    if (devMode && RUN_BENCH == 1 && !benchDone) {
        benchDone = true
        classifyQueue.async { if #available(macOS 13.0, *) { runBench(windowID: id, rect: bounds) } }
    }
    classifyQueue.async { classify(windowID: id, crop: crop, gameRect: gameRect, windowSize: bounds.size, store: shot) }
}

// Only touched from classifyQueue
var lastSignature = [UInt8]()
var skippedInARow = 0
var lastOverlay = Overlay()

// Tiny 16x12 grey thumbnail. Cheap (<< 1 ms) way to tell "the picture is practically the same as when we last
// ran the network" without running it. In menus, lobby and chat the picture is almost static, which is where it pays off.
func signature(of image: CGImage) -> [UInt8] {
    let w = 16, h = 12
    var px = [UInt8](repeating: 0, count: w * h)
    px.withUnsafeMutableBytes { buf in
        guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return px
}

// Mean absolute difference per cell, 0...255
func signatureDistance(_ a: [UInt8], _ b: [UInt8]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return 255 }
    var sum = 0
    for i in 0..<a.count { sum += abs(Int(a[i]) - Int(b[i])) }
    return Double(sum) / Double(a.count)
}

// Runs on classifyQueue (background)
func classify(windowID: CGWindowID, crop: CGRect?, gameRect: CGRect, windowSize: CGSize, store: String) {
    defer { DispatchQueue.main.async { classifyBusy = false } }
    guard let request = visionRequest,
          let windowImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .nominalResolution])
    else { return }

    var image = windowImage
    if let crop = crop, let cropped = windowImage.cropping(to: crop) { image = cropped }

    // Deterministic screen checks on the same capture (see "Overlay detectors"): is the chat panel open, is this the
    // voting / discussion screen? The model was trained on an older look of these screens and is unreliable on them.
    // They run BEFORE the shortcut below on purpose: typing a few letters changes the picture too little to trigger a
    // new classification, but it must still be noticed within one check.
    let overlay = detectOverlays(windowImage, gameRect, windowSize)
    let overlayChanged = (overlay != lastOverlay)
    lastOverlay = overlay

    // Screen practically identical to the last time we ran the network? Then the answer is the same: skip it.
    // Compared against the last *classified* frame (not the previous frame), so a slow drift cannot creep past the
    // threshold unnoticed, and capped at 4 skips in a row so a real classification still happens regularly.
    // A training-data capture (store != "") and any change in the overlay checks always go through.
    let sig = signature(of: image)
    if (store == "" && !overlayChanged && skippedInARow < 4 && signatureDistance(sig, lastSignature) < 2.0) {
        skippedInARow += 1
        DispatchQueue.main.async { stableCount += 1 } // an unchanged picture counts as evidence the scene is stable
        return
    }
    lastSignature = sig
    skippedInARow = 0

    //Push the capture into the Image Classifier model
    //Source: https://developer.apple.com/documentation/createml/creating_an_image_classifier_model
    do { try VNImageRequestHandler(cgImage: image).perform([request]) } catch { dlog("vision error \(error)"); return }
    var id = "", conf = 0
    if let best = (request.results as? [VNClassificationObservation])?.first, best.confidence >= 0.25 { //Ignore results below 25%
        id = best.identifier; conf = Int(best.confidence * 100)
    }
    // A weak model reading is dropped as before, unless a detector has something to say (or just changed)
    if (id != "" || overlayChanged || overlay.chat || overlay.meetingHUD) {
        DispatchQueue.main.async { applyResult(id, conf, overlay) }
    }

    //Write capture to disk as image for training data purposes (developer mode only)
    if (devMode && store != "") {
        let picturesDirectory = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        let imageUrl = picturesDirectory.appendingPathComponent("/Training Data/" + store + "/among" + UUID().uuidString + ".png", isDirectory: false)
        try? image.png!.write(to: imageUrl)
    }
}

var lastConfidence = 0

// Look at the screen RIGHT NOW (used when Tab / Return is pressed). The cached result can be up to a scheduled check
// old, which is exactly how a keypress used to be judged against a chat that was already closed or open. One capture
// on the main thread costs a few ms, only once per key press. Falls back to the cached values if the capture fails.
func freshOverlay() -> Overlay {
    guard gameWindowID != 0,
          let img = CGWindowListCreateImage(.null, .optionIncludingWindow, gameWindowID, [.boundsIgnoreFraming, .nominalResolution])
    else { return Overlay(chat: chatOpen, chatSend: chatSendEnabled, meetingHUD: false) }
    let rect = CGRect(x: X - lastBounds.minX, y: Y - lastBounds.minY, width: Width, height: Height)
    let o = detectOverlays(img, rect, lastBounds.size)
    chatOpen = o.chat
    chatSendEnabled = o.chatSend
    return o
}

// Open the chat and put the cursor into the input box. The panel slides in, so instead of a fixed delay (a click
// before it has arrived lands on the vote screen and closes it again) we poll for the panel and click the input
// box only once it is really there. If it never shows up we do nothing rather than click blindly.
func openChatThenFocusInput() {
    guard gameWindowID != 0 else { return }
    simulateClick(pos: MEETING_CHAT_BUTTON)
    let id = gameWindowID
    let rect = CGRect(x: X - lastBounds.minX, y: Y - lastBounds.minY, width: Width, height: Height)
    let size = lastBounds.size
    DispatchQueue.global(qos: .userInteractive).async {
        for _ in 0..<12 { // up to ~0.7 s
            usleep(60_000)
            if let img = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .nominalResolution]),
               detectOverlays(img, rect, size).chat {
                DispatchQueue.main.async {
                    chatOpen = true
                    requestClassify(after: 0.25)
                    simulateClick(pos: (x: MEETING_CHAT_SEND_BUTTON.x - 0.0893, y: MEETING_CHAT_SEND_BUTTON.y))
                }
                return
            }
        }
    }
}

// MARK: - Overlay detectors
//
// Two exact, cheap pixel checks on the game area of the capture we already have (no extra capture, ~0.2 ms):
//  - chat panel open: the chat button in the top-right row turns TEAL while the panel is open (measured: 60 % teal
//    in every screenshot with the chat open, with or without typed text, 0 % when closed). The Send button is NOT
//    usable for this: it is grey while the input is empty, and a grey card on the vote screen looks the same.
//    The Send button is only used to tell "there is something to send" (it turns teal once text is typed).
//  - voting / discussion screen: its top-right button row is [notes][chat][settings][map] with an EMPTY gap at
//    u = 0.74; during play that spot is the notes button (row is [notes][settings][map]), so the gap tells them apart.
//    (While the chat is open its panel covers the notes button, which is why the chat check exists separately.)
// All positions are fractions of the game area (see Layout), measured on macOS 27 screenshots of a meeting with and
// without the chat open. Thresholds are deliberately loose: the checks look at boxes of pixels, not single pixels.

struct Overlay: Equatable {
    var chat = false        // chat panel open (input empty or not)
    var chatSend = false    // ...and there is text to send
    var meetingHUD = false  // voting / discussion screen
}

private let thumbW = 200, thumbH = 140 // aspect of the game area; a button is ~12 px wide here, plenty for box checks

private func isNeutralLight(_ r: Int, _ g: Int, _ b: Int) -> Bool { abs(r - g) <= 8 && abs(g - b) <= 10 && r >= 150 && r <= 250 }
private func isTeal(_ r: Int, _ g: Int, _ b: Int) -> Bool { g > r + 30 && b > r + 30 && g >= 90 }
private func isWhite(_ r: Int, _ g: Int, _ b: Int) -> Bool { r >= 235 && g >= 235 && b >= 235 }

// Share of pixels in a box (centre u,v, half size du,dv, all as fractions of the game area) that satisfy a colour test
private func share(_ px: [UInt8], _ u: Double, _ v: Double, _ du: Double, _ dv: Double, _ test: (Int, Int, Int) -> Bool) -> Double {
    let x0 = max(0, Int((u - du) * Double(thumbW))), x1 = min(thumbW - 1, max(x0, Int((u + du) * Double(thumbW))))
    let y0 = max(0, Int((v - dv) * Double(thumbH))), y1 = min(thumbH - 1, max(y0, Int((v + dv) * Double(thumbH))))
    var hit = 0, n = 0
    for y in y0...y1 { for x in x0...x1 {
        let o = (y * thumbW + x) * 4
        n += 1
        if test(Int(px[o]), Int(px[o + 1]), Int(px[o + 2])) { hit += 1 }
    } }
    return Double(hit) / Double(max(n, 1))
}

func detectOverlays(_ window: CGImage, _ gameRect: CGRect, _ windowSize: CGSize) -> Overlay {
    // gameRect is in points relative to the window; the capture may be at another pixel scale
    let sx = CGFloat(window.width) / max(windowSize.width, 1), sy = CGFloat(window.height) / max(windowSize.height, 1)
    let r = CGRect(x: gameRect.minX * sx, y: gameRect.minY * sy, width: gameRect.width * sx, height: gameRect.height * sy)
        .integral.intersection(CGRect(x: 0, y: 0, width: window.width, height: window.height))
    guard r.width > 50, r.height > 50, let game = window.cropping(to: r) else { return Overlay() }

    var px = [UInt8](repeating: 0, count: thumbW * thumbH * 4)
    let drawn: Bool = px.withUnsafeMutableBytes { buf in
        guard let ctx = CGContext(data: buf.baseAddress, width: thumbW, height: thumbH, bitsPerComponent: 8, bytesPerRow: thumbW * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.interpolationQuality = .medium
        ctx.draw(game, in: CGRect(x: 0, y: 0, width: thumbW, height: thumbH))
        return true
    }
    if !drawn { return Overlay() }

    var o = Overlay()
    // Send button teal (text typed) with the white input box to its left (typed text only covers part of it)
    o.chatSend = share(px, 0.688, 0.625, 0.025, 0.02, isTeal) >= 0.45 && share(px, 0.42, 0.625, 0.12, 0.012, isWhite) >= 0.5
    // Chat button highlighted teal = panel open. The Send check is the fallback for a layout where the button is elsewhere (lobby).
    o.chat = share(px, 0.783, 0.079, 0.015, 0.03, isTeal) >= 0.30 || o.chatSend
    // Voting / discussion screen: buttons at u 0.69, 0.85, 0.95 and the empty gap at 0.74
    o.meetingHUD = share(px, 0.69, 0.079, 0.012, 0.03, isNeutralLight) >= 0.30
        && share(px, 0.74, 0.079, 0.012, 0.03, isNeutralLight) <= 0.10
        && share(px, 0.85, 0.079, 0.012, 0.03, isNeutralLight) >= 0.20
        && share(px, 0.95, 0.079, 0.012, 0.03, isNeutralLight) >= 0.35
    return o
}

// Main thread
var chatOpen = false        // is the chat panel open right now (from the overlay detector)
var chatSendEnabled = false // ...and is there text to send (the Send button is only teal then)

func applyResult(_ modelID: String, _ modelConf: Int, _ overlay: Overlay) {
    var id = modelID.isEmpty ? gamestate : modelID
    var conf = modelConf
    chatOpen = overlay.chat
    chatSendEnabled = overlay.chatSend
    dlog("overlay chat=\(overlay.chat) send=\(overlay.chatSend) votingHUD=\(overlay.meetingHUD) model=\(modelID.isEmpty ? "-" : modelID) \(modelConf)%")

    // Why the override: on the current meeting screens the model answers "Ingame" at 38-52 %. Ingame means WASD,
    // Space, Q, R ... are turned into clicks on the joystick / Use button, which land on the chat or the vote
    // screen and close the chat while you are typing. The detectors are exact for these two screens, so they win.
    if overlay.chat {
        id = "Meeting" // one consistent chat path, whatever the model thinks (it often says Lobbychat / Ingame)
        conf = max(conf, 90)
    } else if (overlay.meetingHUD && !((id == "Ingame" || id == "Lobby") && conf >= 90)) {
        // ...but a confident Ingame / Lobby reading is trusted, so a detector false positive cannot take away
        // the controls in a real match.
        id = "Meeting"
        conf = max(conf, 90)
    }

    // "Stable" needs a confident reading: a scene flapping at 40-60 % must keep the fast cadence
    if (id == gamestate && conf >= 80) { stableCount += 1 } else { stableCount = 0 }
    if (stableCount == 0) { nextClassifyAt = min(nextClassifyAt, ProcessInfo.processInfo.systemUptime + FAST_CHECK) }
    if (id != gamestate) { dlog("scene \(gamestate) -> \(id) conf=\(conf)") }
    gamestate = id
    lastConfidence = conf
    publishStatus()
}

// MARK: - Live status in the AmongKey window
//
// Handy while setting up ("does it recognise the game?"), pointless afterwards, so it can be switched off in the
// window (ContentView). When off we do not even publish to SwiftUI, which would otherwise re-render on every reading.

var liveStatus = true
var shownScene = ""
var shownScore = -100

func publishStatus() {
    guard liveStatus else { return }
    // Only touch the UI when something visible changed (the confidence jitters by a point or two constantly)
    if (gamestate != shownScene || abs(lastConfidence - shownScore) >= 3) {
        shownScene = gamestate
        shownScore = lastConfidence
        globaleState.shared.scene = gamestate
        globaleState.shared.score = lastConfidence
    }
}

func setLiveStatus(_ on: Bool) {
    liveStatus = on
    if on { shownScene = ""; publishStatus() }
}

// MARK: - Input

func rescueMouse() {
   if (mouseIsDown == true) {
      mouseUp(pos: CGPoint(x: lastX, y: lastY));
      mouseIsDown = false;
   }
}

func simulateClick(pos: (x: Double, y: Double)) {
    if (X == -1 && Y == -1) {
        return;
    }
    let clickEventWaitTime : useconds_t = 10000;
    DispatchQueue.global(qos:.background).async {
        let pos = CGPoint(x: X + calcPos(pos: pos).x, y: Y + calcPos(pos: pos).y)
        mouseClickLock.lock()
        rescueMouse()
        usleep(clickEventWaitTime)
        mouseDown(pos: pos)
        usleep(clickEventWaitTime)
        mouseUp(pos: pos)
        usleep(clickEventWaitTime)
        mouseClickLock.unlock()
    }
}

func simulateKeypress(key: UInt16) {
   let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)
   keyDownEvent?.flags = CGEventFlags.maskCommand
   keyDownEvent?.post(tap: CGEventTapLocation.cghidEventTap)

   usleep(10000)
   let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
   keyUpEvent?.flags = CGEventFlags.maskCommand
   keyUpEvent?.post(tap: CGEventTapLocation.cghidEventTap)
}

// Events are posted at the HID level, which moves the visible cursor. Posting straight to the game process
// (CGEvent.postToPid) would keep the cursor still, but the game ignores events delivered that way (tested), so
// the system-wide path is the only one that works.
let mouseSource = CGEventSource(stateID: .hidSystemState)

func postMouse(_ type: CGEventType, _ pos: CGPoint) {
    CGEvent(mouseEventSource: mouseSource, mouseType: type, mouseCursorPosition: pos, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func mouseDown(pos: CGPoint) { postMouse(.leftMouseDown, pos) }
func mouseDrag(pos: CGPoint) { postMouse(.leftMouseDragged, pos) }
func mouseUp(pos: CGPoint) { postMouse(.leftMouseUp, pos) }


//Source: https://stackoverflow.com/a/48312429
extension CGImage {
    var png: Data? {
        guard let mutableData = CFDataCreateMutable(nil, 0),
            let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, self, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}

// MARK: - One-off benchmark (developer mode, last value of ~/.amongkey_tune = 1)
//
// Logs how much each building block costs on the current machine (ms per call, wall and this-app CPU), which is
// how the decisions in the power model above were made: window metadata for one window vs. all windows, a one-pixel
// capture vs. a full capture, and the classifier on Neural Engine vs. GPU vs. CPU. Re-run it before changing the
// scheduling.

@available(macOS 13.0, *)
func runBench(windowID: CGWindowID, rect: CGRect) {
    func cpuTime() -> Double { var ts = timespec(); clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts); return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9 }
    func f(_ x: Double) -> String { String(format: "%.3f", x) }
    func measure(_ name: String, _ n: Int, _ body: () -> Void) {
        body() // warm-up
        let c0 = cpuTime(), w0 = ProcessInfo.processInfo.systemUptime
        for _ in 0..<n { body() }
        let c1 = cpuTime(), w1 = ProcessInfo.processInfo.systemUptime
        dlog("BENCH \(name): wall \(f((w1 - w0) / Double(n) * 1000)) ms/call, this-app-cpu \(f((c1 - c0) / Double(n) * 1000)) ms/call")
    }
    let opts: CGWindowImageOption = [.boundsIgnoreFraming, .nominalResolution]
    measure("A metadata, this window only", 200) { _ = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) }
    measure("B metadata, all on-screen windows", 200) { _ = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], CGWindowID(0)) }
    let px = CGRect(x: rect.minX + 4, y: rect.minY + 40, width: 1, height: 1)
    measure("C capture ONE pixel (the corner idea)", 100) { _ = CGWindowListCreateImage(px, .optionIncludingWindow, windowID, .nominalResolution) }
    measure("D capture whole window", 60) { _ = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, opts) }
    guard let img = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, opts) else { dlog("BENCH no image (screen recording?)"); return }
    measure("E 16x12 thumbnail signature of a capture", 200) { _ = signature(of: img) }
    let units: [(String, MLComputeUnits)] = [("Neural Engine+CPU", .cpuAndNeuralEngine), ("GPU+CPU", .cpuAndGPU), ("CPU only", .cpuOnly)]
    for (name, u) in units {
        let cfg = MLModelConfiguration(); cfg.computeUnits = u
        guard let m = try? VNCoreMLModel(for: AmongUsClassifier(configuration: cfg).model) else { continue }
        let r = VNCoreMLRequest(model: m)
        measure("F classify on \(name)", 40) { try? VNImageRequestHandler(cgImage: img).perform([r]) }
    }
    dlog("BENCH done")
}
