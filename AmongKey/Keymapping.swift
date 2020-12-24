//
//  Keymapping.swift
//  AmongKey
//
//  Created by Andre Savic on 30.11.20.
//

import SwiftUI

func createKeybinding() {
    NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { (event) in
        
        if (topmost == false) { return } //Only process inputs when Among Us is in focus
        
        switch (event.keyCode, gamestate) {
        case (13, "Ingame"), (13, "Lobby"), (126, "Ingame"), (126, "Lobby"):
            up = 1
            break
        case (1, "Ingame"), (1, "Lobby"), (125, "Ingame"), (125, "Lobby"):
            down = 1
            break
        case (0, "Ingame"), (0, "Lobby"), (123, "Ingame"), (123, "Lobby"):
            left = 1
            break
        case (2, "Ingame"), (2, "Lobby"), (124, "Ingame"), (124, "Lobby"):
            right = 1
            break
        default:
            break
        }
    }
    
    NSEvent.addGlobalMonitorForEvents(matching: [.keyUp]) { (event) in
        
        if (topmost == false){ return } //Only process inputs when Among Us is in focus
        
        switch (event.keyCode, gamestate) {
        case (13, "Ingame"), (13, "Lobby"), (126, "Ingame"), (126, "Lobby"):
            up = 0
            break
        case (1, "Ingame"), (1, "Lobby"), (125, "Ingame"), (125, "Lobby"):
            down = 0
            break
        case (0, "Ingame"), (0, "Lobby"), (123, "Ingame"), (123, "Lobby"):
            left = 0
            break
        case (2, "Ingame"), (2, "Lobby"), (124, "Ingame"), (124, "Lobby"):
            right = 0
            break
        case (36, "Lobbychat"): // Return to send message
            if (!isFullscreen()) {
                print("PRESS KEY")
                simulateKeypress(key: 53) //Escape to blur input field
            }
            amongusWindow()
            simulateClick(pos: CHAT1_SEND_BUTTON)
            usleep(10000)
            simulateClick(pos: (x: CHAT1_SEND_BUTTON.x - 350, y: CHAT1_SEND_BUTTON.y))
            break;
        case (36, "Meeting"): // Return to send message
            if (!isFullscreen()) {
                simulateKeypress(key: 53) //Escape to blur input field
            }
            amongusWindow()
            simulateClick(pos: CHAT2_SEND_BUTTON)
            usleep(10000)
            simulateClick(pos: (x: CHAT2_SEND_BUTTON.x - 350, y: CHAT2_SEND_BUTTON.y))
            break;
        case (49, "Ingame"), (14, "Ingame"), (49, "Lobby"), (14, "Lobby"):
            simulateClick(pos: USE_BUTTON)
            break;
        case (53, "Ingame"), (53, "Lobby"):
            simulateClick(pos: ESC_BUTTON)
            break;
        case (12, "Ingame"):  // Q - Kill
            simulateClick(pos: KILL_BUTTON)
            break;
        case (15, "Ingame"):  // R - Report
            simulateClick(pos: REPORT_BUTTON)
            break;
        case (48, "Ingame"): // Tab - Map
            simulateClick(pos: MAP_BUTTON)
            break;
        case (48, "Lobby"): // Tab to open chat and focus input field
            simulateClick(pos: CHAT1_BUTTON)
            usleep(100000)
            simulateClick(pos: (x: CHAT1_SEND_BUTTON.x - 250, y: CHAT1_SEND_BUTTON.y))
            break;
        case (48, "Meeting"): // Tab to open chat and focus input field
            simulateClick(pos: CHAT2_BUTTON)
            usleep(100000)
            simulateClick(pos: (x: CHAT2_SEND_BUTTON.x - 250, y: CHAT2_SEND_BUTTON.y))
            break;
        case (18, _): //1 - Store AI Training Data Ingame
            storeScreenshot = "Ingame"
            break;
        case (19, _): //2 - Store AI Training Data Lobby
            storeScreenshot = "Lobby"
            break;
        case (20, _): //3 - Store AI Training Data Chat
            storeScreenshot = "Lobbychat"
            break;
        case (21, _): //4 - Store AI Training Data Meeting
            storeScreenshot = "Meeting"
            break;
        case (23, _): //5 - Store AI Training Data Menu
            storeScreenshot = "Menu"
            break;
        default:
            break
        }
    }
}
