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

var mouseIsDown: Bool = false;
var mouseIsClicking: Bool = false;

let JOYSTICK = (x: 64.05, y: 555.3)
let USE_BUTTON = (x: 720, y: 535);
let ESC_BUTTON = (x: 50, y: 135);
let KILL_BUTTON = (x: 580, y: 535);
let MAP_BUTTON = (x: 750, y: 150);
let REPORT_BUTTON = (x: 720, y: 430);
let CHAT1_BUTTON = (x: 680, y: 60);
let CHAT2_BUTTON = (x: 680, y: 110);
let CHAT1_SEND_BUTTON = (x: 593, y: 474);
let CHAT2_SEND_BUTTON = (x: 593, y: 544);


var X: Int = 0 //X Position of the Among Us Window
var Y: Int = 0 //Y Position of the Among Us Window

var Height: Int = 0 //Height of the Among Us Window
var Width: Int = 0 //Width of the Among Us Window

var topmost: Bool = false // Is Among Us in focus

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
   
   //Run movment all 25ms
   Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { _ in
      movement()
   }

   //Caputre Among Us window all 250ms
   Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
      amongusWindow()
   }
}

func movement() {
    if (X == 0 && Y == 0) { rescueMouse(); return }

    if (mouseIsClicking == true){ return }

    if (topmost == false) { rescueMouse(); return }

    if (gamestate != "Ingame" && gamestate != "Lobby") { rescueMouse(); return }

    if ((up + down + left + right) == 0) { rescueMouse(); return }

    var joystickY: Double = JOYSTICK.y
    var joystickX: Double = JOYSTICK.x

    if (mouseIsDown == false) {
      //Set cursor in the center of the Joystick
      mouseDown(pos: CGPoint(x: Double(X) + JOYSTICK.x, y: Double(Y) + JOYSTICK.y));
    }
    
    //Set the cursor to the movemment direction
    joystickY = joystickY - (30 * Double(up));
    joystickY = joystickY + (30 * Double(down));
    joystickX = joystickX - (30 * Double(left));
    joystickX = joystickX + (30 * Double(right));

    lastX = Double(X) + joystickX
    lastY = Double(Y) + joystickY

    mouseDown(pos: CGPoint(x: lastX, y: lastY));
    mouseIsDown = true
}

func amongusWindow() {
   let options = CGWindowListOption(arrayLiteral: CGWindowListOption.optionAll)
   let cgWindowListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
   let cgWindowListInfo2 = cgWindowListInfo as NSArray? as? [[String: AnyObject]]
   let frontMostAppId = NSWorkspace.shared.frontmostApplication!.processIdentifier

   for windowDic in cgWindowListInfo2! {
        //Determine the Among Us window
        if (windowDic["kCGWindowOwnerName"] as! String == "Among Us" && windowDic["kCGWindowStoreType"] as! Int == 1) {
            let ownerProcessID = windowDic["kCGWindowOwnerPID"] as! Int
            let bounds = windowDic["kCGWindowBounds"] as! [String: Int]
            
            if (bounds["X"]! == 0 && bounds["Width"]! == 0) { continue } //Fix for Macs with Touchbar
            
            X = bounds["X"]!
            Y = bounds["Y"]!
            Height = bounds["Height"]!
            Width = bounds["Width"]!
            topmost = (frontMostAppId == ownerProcessID)
            
            if (topmost == false) { return } //Only capture Among Us window when it is in focus
            
            //Create capture of Window
            guard let windowImage: CGImage =
             CGWindowListCreateImage(.null, .optionIncludingWindow, (windowDic["kCGWindowNumber"] as! NSNumber).uint32Value,
                                     [.boundsIgnoreFraming, .nominalResolution]) else { return }
           
            
            //Push the capture into the Image Classifier model
            //Source: https://developer.apple.com/documentation/createml/creating_an_image_classifier_model
            do {
                let model = try VNCoreMLModel(for: AmongUsClassifier(configuration: MLModelConfiguration()).model)
                let request = VNCoreMLRequest(model: model, completionHandler: AmongUsClassifierResult)
                let handler = VNImageRequestHandler(cgImage: windowImage)
                try handler.perform([request])
            } catch {
              print(error)
            }
            
            //Write capture to disk as image for training data purposes
            if (storeScreenshot != "") {
                let picturesDirectory = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]

                let imageUrl = picturesDirectory.appendingPathComponent("/Training Data/" + storeScreenshot + "/among" + UUID().uuidString + ".png", isDirectory: false)
                try? windowImage.png!.write(to: imageUrl)
                
                storeScreenshot = ""
            }
      }
   }
}

func AmongUsClassifierResult(request: VNRequest, error: Error?) {
    guard let results = request.results as? [VNClassificationObservation] else { fatalError("Error") }
    
    //Ignore results with a confidence smaller than 25%
    if results[0].confidence < 0.25 { return }
    
    globaleState.shared.score = Int(results[0].confidence * 100)
    globaleState.shared.scene = results[0].identifier
    
    gamestate = results[0].identifier
}

func rescueMouse() {
   if (mouseIsDown == true) {
      mouseUp(pos: CGPoint(x: lastX, y: lastY));
      mouseIsDown = false;
   }
}

func simulateClick(pos: (x: Int, y: Int)) {
    if (X == 0 && Y == 0) {
        return;
    }
    mouseIsClicking = true
    rescueMouse()
    usleep(50000)
    let pos = CGPoint(x: X + pos.x, y: Y + pos.y)
    mouseDown(pos: pos)
    usleep(50000)
    mouseUp(pos: pos)
    mouseIsClicking = false
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
