//
//  ContentView.swift
//  AmongKey
//
//  Created by Andre Savic on 24.11.20.
//
import Cocoa
import SwiftUI

var up: Int = 0
var down: Int = 0
var left: Int = 0
var right: Int = 0


var mouseIsDown: Bool = false;


let JOYSTICK = (x: 64.05, y: 555.3)

let USE_BUTTON = (x: 720, y: 535);
let ESC_BUTTON = (x: 50, y: 160);

let KILL_BUTTON = (x: 580, y: 535);

let MAP_BUTTON = (x: 750, y: 150);

let REPORT_BUTTON = (x: 720, y: 430);

let CHAT1_BUTTON = (x: 593, y: 474);
let CHAT2_BUTTON = (x: 593, y: 544);

var X: Int = 0
var Y: Int = 0
var Height: Int = 0
var Width: Int = 0
var windowID: UInt32 = 0
var topmost: Bool = false
var gamestate: String = "menu"

struct ContentView: View {
    var body: some View {
        VStack {
         Image("Frame 2-3").resizable().frame(width: 400, height: 400)
        }.onAppear(perform: {
            setup()
        })
    }
}


func setup() {
    NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { (event) in
        print(event.keyCode)
        if (topmost == false){
            return
        }
        switch (event.keyCode, gamestate) {
        case (13, "ingame"), (13, "lobby"):
            up = 1
            break
        case (1, "ingame"), (1, "lobby"):
            down = 1
            break
        case (0, "ingame"), (0, "lobby"):
            left = 1
            break
        case (2, "ingame"), (2, "lobby"):
            right = 1
            break
        default:
            break
        }
    }
    
    NSEvent.addGlobalMonitorForEvents(matching: [.keyUp]) { (event) in
        if (topmost == false){
           return
        }
        switch (event.keyCode, gamestate) {
        case (13, "ingame"), (13, "lobby"):
            up = 0
            break
        case (1, "ingame"), (1, "lobby"):
            down = 0
            break
        case (0, "ingame"), (0, "lobby"):
            left = 0
            break
        case (2, "ingame"), (2, "lobby"):
            right = 0
            break
        case (36, "chat1"):
            simulateClick(pos: CHAT1_BUTTON)
            let textfield = (x: CHAT1_BUTTON.x - 250, y: CHAT1_BUTTON.y)
            simulateClick(pos: textfield)
            break;
        case (36, "chat2"):
            simulateClick(pos: CHAT2_BUTTON)
            let textfield = (x: CHAT2_BUTTON.x - 250, y: CHAT2_BUTTON.y)
            simulateClick(pos: textfield)
            break;
        case (49, "ingame"), (14, "ingame"), (49, "lobby"), (14, "lobby"):
            simulateClick(pos: USE_BUTTON)
            break;
        case (53, "ingame"), (53, "lobby"):
            simulateClick(pos: ESC_BUTTON)
            break;
        case (12, "ingame"):  // Q - Kill
            simulateClick(pos: KILL_BUTTON)
            break;
        case (15, "ingame"):  // R - Report
            simulateClick(pos: REPORT_BUTTON)
            break;
        case (48, "ingame"): // Tab - Map
            simulateClick(pos: MAP_BUTTON)
            break;
        default:
            break
        }
    }
    
   Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
      if (X == 0 && Y == 0) {
         rescueMouse()
         return;
      }

      if (topmost == false) {
         rescueMouse()
         return;
      }

      if (gamestate != "ingame" && gamestate != "lobby") {
         rescueMouse()
         return;
      }

      let running =  up + down + left + right;

      var joystickY: Double = JOYSTICK.y
      var joystickX: Double = JOYSTICK.x

      if (running == 0) {
         rescueMouse()
         return;
      }
      if (mouseIsDown == false) {
         print("center in joystick")
         mouseDown(pos: CGPoint(x: Double(X) + JOYSTICK.x, y: Double(Y) + JOYSTICK.y));
      }
      joystickY = joystickY - (40 * Double(up));
      joystickY = joystickY + (40 * Double(down));
      joystickX = joystickX - (40 * Double(left));
      joystickX = joystickX + (40 * Double(right));
      mouseDown(pos: CGPoint(x: Double(X) + joystickX, y: Double(Y) + joystickY));
      mouseIsDown = true
    }

   Timer.scheduledTimer(withTimeInterval: 0.250, repeats: true) { timer in
      amongusWindow()
      print(gamestate)
   }
}

func rescueMouse() {
   if (mouseIsDown == true) {
       mouseUp(pos: CGPoint(x: Double(X) + JOYSTICK.x, y: Double(Y) + JOYSTICK.y));
       mouseIsDown = false;
   }
}

func simulateClick(pos: (x: Int, y: Int)) {
    if (X == 0 && Y == 0) {
        return;
    }
    let pos = CGPoint(x: X + pos.x, y: Y + pos.y);
    mouseDown(pos: pos);
    usleep(10000)
    mouseUp(pos: pos);
}

func mouseDown(pos: CGPoint) {
    let source = CGEventSource.init(stateID: .hidSystemState)
    let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
    mouseCursorPosition: pos, mouseButton: .left)
    print("Down");
    mouseDown?.post(tap: .cghidEventTap)
}

func mouseUp(pos: CGPoint) {
    let source = CGEventSource.init(stateID: .hidSystemState)
    let mouseEventUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
    mouseCursorPosition: pos, mouseButton: .left)
    print("Up");
    mouseEventUp?.post(tap: .cghidEventTap)
}

func amongusWindow() {
   let options = CGWindowListOption(arrayLiteral: CGWindowListOption.optionAll)
   let cgWindowListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
   let cgWindowListInfo2 = cgWindowListInfo as NSArray? as? [[String: AnyObject]]
   let frontMostAppIDfrontMostAppID = NSWorkspace.shared.frontmostApplication!.processIdentifier

   for windowDic in cgWindowListInfo2!
   {
       if (windowDic["kCGWindowOwnerName"] as! String == "Among Us" && windowDic["kCGWindowStoreType"] as! Int == 1) {
         let ownerProcessID = windowDic["kCGWindowOwnerPID"] as! Int
         let bounds = windowDic["kCGWindowBounds"] as AnyObject
         X = bounds["X"] as! Int;
         Y = bounds["Y"] as! Int;
         Height = bounds["Height"] as! Int;
         Width = bounds["Width"] as! Int;
         windowID = (windowDic["kCGWindowNumber"] as! NSNumber).uint32Value
         topmost = (frontMostAppIDfrontMostAppID == ownerProcessID)
         
         if (topmost == false) {
            return
         }
       
         let windowImage: CGImage? =
             CGWindowListCreateImage(.null, .optionIncludingWindow, windowID,
                                     [.boundsIgnoreFraming, .nominalResolution])
         
         if (windowImage == nil){
            return
         }
        
         
         let picturesDirectory = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
         let imageUrl = picturesDirectory.appendingPathComponent("public.png", isDirectory: false)
         try?  windowImage!.png!.write(to: imageUrl)
         
         let px = PixelExtractor(img: windowImage!)
         
         let sendButtonPx1 = px.colorAt(x: 595, y: 472)
         let sendButtonPx2 = px.colorAt(x: 573, y: 469)
         if (sendButtonPx1 == (CGFloat(0), CGFloat(114), CGFloat(229)) && sendButtonPx2 == (CGFloat(255), CGFloat(255), CGFloat(255))) {
            gamestate = "chat1"
            return
         }
  
         let mapButtonPx1 = px.colorAt(x: 750, y: 126)
         let mapButtonPx2 = px.colorAt(x: 753, y: 142)
         if (mapButtonPx1 == (CGFloat(238), CGFloat(238), CGFloat(238)) && mapButtonPx2 == (CGFloat(85), CGFloat(102), CGFloat(102))) {
            gamestate = "ingame"
            return
         }
         
         let sendButton2Px1 = px.colorAt(x: 595, y: 539)
         let sendButton2Px2 = px.colorAt(x: 573, y: 539)
         if (sendButton2Px1 == (CGFloat(0), CGFloat(114), CGFloat(229)) && sendButton2Px2 == (CGFloat(255), CGFloat(255), CGFloat(255))) {
            gamestate = "chat2"
            return
         }

         let chatButtonPx1 = px.colorAt(x: 669, y: 47)
         let chatButtonPx2 = px.colorAt(x: 649, y: 58)
         if (chatButtonPx1 == (CGFloat(255), CGFloat(255), CGFloat(255)) && chatButtonPx2 == (CGFloat(0), CGFloat(0), CGFloat(0))) {
            gamestate = "lobby"
            return
         }
         
         gamestate = "menu"
       }
   }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}


class PixelExtractor: NSObject {

    let image: CGImage
    let context: CGContext?

    var width: Int {
        get {
            return image.width
        }
    }

    var height: Int {
        get {
            return image.height
        }
    }

    init(img: CGImage) {
        image = img
        context = PixelExtractor.createBitmapContext(img: img)
    }

    class func createBitmapContext(img: CGImage) -> CGContext {

        // Get image width, height
        let pixelsWide = img.width
        let pixelsHigh = img.height
      
        print(pixelsWide)
        print(pixelsHigh)

        let bitmapBytesPerRow = pixelsWide * 4
        let bitmapByteCount = bitmapBytesPerRow * Int(pixelsHigh)

        // Use the generic RGB color space.
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // Allocate memory for image data. This is the destination in memory
        // where any drawing to the bitmap context will be rendered.
        let bitmapData = malloc(bitmapByteCount)
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        // create bitmap
        let context = CGContext(data: bitmapData,
                                width: pixelsWide,
                                height: pixelsHigh,
                                bitsPerComponent: 8,
                                bytesPerRow: bitmapBytesPerRow,
                                space: colorSpace,
                                bitmapInfo: bitmapInfo.rawValue)

        // draw the image onto the context
        let rect = CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh)

        context?.draw(img, in: rect)
      
        free(bitmapData)

        return context!
    }

    func colorAt(x: Int, y: Int)->(CGFloat, CGFloat, CGFloat) {

        assert(0<=x && x<width)
        assert(0<=y && y<height)

        guard let pixelBuffer = context?.data else { return (CGFloat(255), CGFloat(255), CGFloat(255)) }
        let data = pixelBuffer.bindMemory(to: UInt8.self, capacity: width * height)

        let offset = 4 * (y * width + x)

        let red: CGFloat = CGFloat(data[offset+1])
        let green: CGFloat = CGFloat(data[offset+2])
        let blue: CGFloat = CGFloat(data[offset+3])

        return (red,  green, blue);
    }
}

extension CGImage {
    var png: Data? {
        guard let mutableData = CFDataCreateMutable(nil, 0),
            let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, self, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}
