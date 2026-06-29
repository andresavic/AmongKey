//
//  AmongKeyApp.swift
//  AmongKey
//
//  Created by Andre Savic on 24.11.20.
//

import SwiftUI
import CoreML
import Vision
import ImageIO
import ScreenCaptureKit

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
var mouseIsClicking: Bool = false
var mouseClickLock = NSLock()


func calculateUIPosition(ui_position: (ui_x: Int, ui_y: Int)) -> (x: Double, y: Double) {
    let bottom_right_button = (x: 2536.0, y: 1873.0)
    let vertical_spacing = 400.0;
    let horizontal_spacing = 350.0;
    return (x: bottom_right_button.x - horizontal_spacing * Double(ui_position.ui_x),
            y: bottom_right_button.y - vertical_spacing * Double(ui_position.ui_y))
}


let JOYSTICK = (x: 227.589, y: 1873.375)
let USE_BUTTON = calculateUIPosition(ui_position: (ui_x: 0, ui_y: 0))
let KILL_BUTTON = calculateUIPosition(ui_position: (ui_x: 0, ui_y: 1))
let REPORT_BUTTON = calculateUIPosition(ui_position: (ui_x: 1, ui_y: 0))
let SABOTAGE_BUTTON = calculateUIPosition(ui_position: (ui_x: 1, ui_y: 1))
let VENT_BUTTON = calculateUIPosition(ui_position: (ui_x: 2, ui_y: 1))
let ROLE_BUTTON = calculateUIPosition(ui_position: (ui_x: 2, ui_y: 0))

let ESC_BUTTON = (x: 120.0, y: 420.0)
let MAP_BUTTON = (x: 2665.0, y: 421.0)
let LOBBY_CHAT_BUTTON = (x: 2395.0, y: 110.0)
let MEETING_CHAT_BUTTON = (x: 2411.0, y: 301.0)
let LOBBY_CHAT_SEND_BUTTON = (x: 2105.0, y: 1585.0)
let MEETING_CHAT_SEND_BUTTON = (x: 1850.0, y: 1650.0)

var originalPosition = (x: 0.0, y: 0.0)
var originalSize = (height: 0.0, width: 0.0)

var X: Double = -1.0 //X Position of the Among Us Window
var Y: Double = -1.0 //Y Position of the Among Us Window

var Height: Double = -1 //Height of the Among Us Window
var Width: Double = -1 //Width of the Among Us Window

var topmost: Bool = false // Is Among Us in focus

var captureInProgress: Bool = false // Guard so overlapping async captures don't pile up

var gamestate: String = "Menu" //Curent game state

var storeScreenshot: String = ""

var lastX: Double = 0.0 //Last down X position of cursor
var lastY: Double = 0.0 //Last down Y position of cursor

func setup() {
   Update.checkForUpdate(completion: { download in
      DispatchQueue.main.async {
         globaleState.shared.download = download
      }
   })
   
   let permission = AXIsProcessTrustedWithOptions(
               [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
   
    if (permission) {
        createKeybinding()
    }
   //Run movement all 25ms
   Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { _ in
      movement()
   }

   //Caputre Among Us window all 250ms
   Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
      amongusWindow()
   }
}


func movement() {
    if (X == -1 && Y == -1) { rescueMouse(); return }
    
    if (topmost == false) { rescueMouse(); return }

    if (gamestate != "Ingame" && gamestate != "Lobby") { rescueMouse(); return }

    if ((up + down + left + right) == 0) { rescueMouse(); return }
    
    let lockSuccess = mouseClickLock.try()
    if (!lockSuccess){ return }
    var joystickY: Double = calcPos(pos: JOYSTICK).y
    var joystickX: Double = calcPos(pos: JOYSTICK).x

    if (mouseIsDown == false) {
        //Set cursor in the center of the Joystick
        mouseDown(pos: CGPoint(x: X + calcPos(pos: JOYSTICK).x, y: Y + calcPos(pos: JOYSTICK).y));
    }
    
    //Set the cursor to the movemment direction
    joystickY = joystickY - (joysticDistance() * Double(up));
    joystickY = joystickY + (joysticDistance() * Double(down));
    joystickX = joystickX - (joysticDistance() * Double(left));
    joystickX = joystickX + (joysticDistance() * Double(right));

    lastX = X + joystickX
    lastY = Y + joystickY

    mouseDown(pos: CGPoint(x: lastX, y: lastY));
    mouseIsDown = true
    mouseClickLock.unlock()
}

func calcPos(pos: (x: Double, y: Double)) -> (x: Double, y: Double) {
    return (x: pos.x / (2800.0 / Width), y: pos.y / (2100 / Height))
}

func joysticDistance() -> Double {
    return 120 / (2800.0 / Width)
}

func amongusWindow() {
   let options = CGWindowListOption(arrayLiteral: CGWindowListOption.optionAll)
   let cgWindowListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
   let cgWindowListInfo2 = cgWindowListInfo as NSArray? as? [[String: AnyObject]]
   let frontMostAppId = NSWorkspace.shared.frontmostApplication!.processIdentifier
   for windowDic in cgWindowListInfo2! {
        //Determine the Among Us window.
        //The iPad-on-Mac build reports its window name as "AmongUs" (no space) instead of
        //"Among Us", so normalise (lowercase + strip spaces) before comparing.
        let ownerName = (windowDic["kCGWindowOwnerName"] as? String) ?? ""
        if (ownerName.lowercased().replacingOccurrences(of: " ", with: "") == "amongus") {
            let ownerProcessID = windowDic["kCGWindowOwnerPID"] as! Int
            let bounds = windowDic["kCGWindowBounds"] as! [String: Double]

            if (bounds["Height"]! <= 500 || bounds["Width"]! <= 500) { continue } //Skip tiny helper windows
        
            originalPosition = (x: bounds["X"]!, y: bounds["Y"]!)
            originalSize = (height: bounds["Height"]!, width: bounds["Width"]!)
            
            X = originalPosition.x
            Y = originalPosition.y
            Height = originalSize.height
            Width = originalSize.width
            
            if (isFullscreen()) {
                let f = 2800.0 / 2100.0
                X = (Width - (Height * f)) / 2.0
                Y = 0.167 //I dont know why but there are wered
                Width = (Height * f)
            }else{
                Y = Y + 29 // Window Topbar
                Height = Height - 29 // Window Topbar
            }
        
            topmost = (frontMostAppId == ownerProcessID)
            
            if (topmost == false) { return } //Only capture Among Us window when it is in focus

            //Capture the Among Us window and push it into the Image Classifier model.
            //We only ever need a single still frame every 250ms, so a one-shot capture is enough.
            let windowID = (windowDic["kCGWindowNumber"] as! NSNumber).uint32Value
            captureWindow(windowID: windowID) { captured in
                guard let captured = captured else { return }
                processCapturedImage(captured)
            }
      }
   }
}

//Capture a single window image.
//macOS 14 (Sonoma) deprecated CGWindowListCreateImage in favour of ScreenCaptureKit,
//so we use SCScreenshotManager on 14+ and fall back to the old API on older systems.
//Both paths require the user to grant "Screen Recording" permission in System Settings.
func captureWindow(windowID: CGWindowID, completion: @escaping (CGImage?) -> Void) {
   if (captureInProgress) { return } //Skip if a previous capture is still running
   captureInProgress = true

   if #available(macOS 14.0, *) {
      let scale = NSScreen.main?.backingScaleFactor ?? 2.0
      Task {
         defer { captureInProgress = false }
         do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
               completion(nil); return
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)
            config.showsCursor = false //Don't capture our injected cursor
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            completion(image)
         } catch {
            print("ScreenCaptureKit capture failed: \(error)")
            completion(nil)
         }
      }
   } else {
      //Legacy fallback for macOS 11-13
      let image = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID,
                                          [.boundsIgnoreFraming, .nominalResolution])
      captureInProgress = false
      completion(image)
   }
}

//Run the captured frame through the CoreML image classifier (and optionally save it as training data).
//Source: https://developer.apple.com/documentation/createml/creating_an_image_classifier_model
func processCapturedImage(_ windowImage: CGImage) {
   var image = windowImage

   if (isFullscreen()) {
      //Among Us renders 4:3 (2800x2100) and letterboxes the sides in fullscreen.
      //Crop those black bars off so the classifier sees the same framing it was trained on.
      let w = Double(windowImage.width)
      let h = Double(windowImage.height)
      let expectedW = h * (2800.0 / 2100.0)
      if (w > expectedW + 1) {
         let inset = (w - expectedW) / 2.0
         if let cropped = windowImage.cropping(to: CGRect(x: inset, y: 0, width: expectedW, height: h)) {
            image = cropped
         }
      }
   }

   do {
      let model = try VNCoreMLModel(for: AmongUsClassifier(configuration: MLModelConfiguration()).model)
      let request = VNCoreMLRequest(model: model, completionHandler: AmongUsClassifierResult)
      let handler = VNImageRequestHandler(cgImage: image)
      try handler.perform([request])
   } catch {
      print(error)
   }

   //Write capture to disk as image for training data purposes
   if (storeScreenshot != "") {
      let picturesDirectory = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
      let imageUrl = picturesDirectory.appendingPathComponent("/Training Data/" + storeScreenshot + "/among" + UUID().uuidString + ".png", isDirectory: false)
      try? image.png!.write(to: imageUrl)
      storeScreenshot = ""
   }
}

func isFullscreen() -> Bool {
    print("------")
    print(originalPosition)
    print(originalSize)
    return (originalSize.height > 619 && originalPosition.x == 0.0 && originalPosition.y == 0.0)
}

func AmongUsClassifierResult(request: VNRequest, error: Error?) {
    guard let results = request.results as? [VNClassificationObservation] else { fatalError("Error") }
    
    //Ignore results with a confidence smaller than 25%
    if results[0].confidence < 0.25 { return }

    gamestate = results[0].identifier

    //@Published properties must be updated on the main thread (capture now runs on a background Task)
    let score = Int(results[0].confidence * 100)
    let scene = results[0].identifier
    DispatchQueue.main.async {
        globaleState.shared.score = score
        globaleState.shared.scene = scene
    }
}

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
   print("Keypress: " + String(key))
   let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)
   keyDownEvent?.flags = CGEventFlags.maskCommand
   keyDownEvent?.post(tap: CGEventTapLocation.cghidEventTap)
   
   usleep(10000)
   let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
   keyUpEvent?.flags = CGEventFlags.maskCommand
   keyUpEvent?.post(tap: CGEventTapLocation.cghidEventTap)
}

func mouseDown(pos: CGPoint) {
    let mouseDown = CGEvent(mouseEventSource: CGEventSource.init(stateID: .hidSystemState), mouseType: .leftMouseDown,
    mouseCursorPosition: pos, mouseButton: .left)
    
    mouseDown?.post(tap: .cghidEventTap)
}

func mouseUp(pos: CGPoint) {
    let mouseEventUp = CGEvent(mouseEventSource: CGEventSource.init(stateID: .hidSystemState), mouseType: .leftMouseUp,
    mouseCursorPosition: pos, mouseButton: .left)
    
    mouseEventUp?.post(tap: .cghidEventTap)
}


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
