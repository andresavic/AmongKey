//
//  Keymapping.swift
//  AmongKey
//
//  Created by Andre Savic on 30.11.20.
//

import SwiftUI

// Global key handling. Positions passed to simulateClick() are fractions of the game area (see AmongKeyApp.swift).
//
// Both monitors are global (they see every key press in every app), so each one decides what to do in the
// cheapest possible order: release logic first where it must always run, then bail out unless the game is in front.

// Keys that can change what is on screen (chat, menus, report, ...). After one of them the scene is re-checked
// ~0.25 s later (instead of waiting for the next scheduled check), so the key mapping follows the UI quickly even
// though the scheduled checks have been made much rarer.
let sceneKeys: Set<UInt16> = [36, 48, 53, 49, 14, 15]

func createKeybinding() {
    NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { (event) in

        if (topmost == false) { return } //Only process inputs when Among Us is in focus
        // Logged only after the focus check (and only in developer mode): keystrokes typed into other apps
        // must never end up in a log file.
        dlog("keyDown code=\(event.keyCode) gamestate=\(gamestate)")

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

        // Key repeat sends many key-downs; ensureMovementTimer() is a no-op after the first one
        if ((up + down + left + right) != 0) { ensureMovementTimer() }
    }

    NSEvent.addGlobalMonitorForEvents(matching: [.keyUp]) { (event) in

        // Always release movement keys, even if the game lost focus while the key was held. The key-up used to be
        // ignored when another app was in front, which could leave the direction latched until the next key press.
        switch event.keyCode {
        case 13, 126: up = 0
        case 1, 125: down = 0
        case 0, 123: left = 0
        case 2, 124: right = 0
        default: break
        }

        if (topmost == false){ return } //Only process inputs when Among Us is in focus

        switch (event.keyCode, gamestate) {
        case (36, "Lobbychat"): // Return to send message
            if (!isFullscreen()) {
                simulateKeypress(key: 53) //Escape to blur input field
            }
            pollGameWindow() // refresh the coordinates right before clicking, the window may have been moved
            simulateClick(pos: LOBBY_CHAT_SEND_BUTTON)
            usleep(10000)
            simulateClick(pos: (x: LOBBY_CHAT_SEND_BUTTON.x - 0.125, y: LOBBY_CHAT_SEND_BUTTON.y))
            break;
        case (36, "Meeting"): // Return sends the typed message, but only while the chat panel is open with text in it
            // Judged on the screen as it is right now, not on a result that may be a check old. Without text (Send is
            // grey) there is nothing to send, and outside the chat this click would land on the vote screen.
            // No Esc first (the lobby path does that): clicking Send already takes the focus off the text field, and
            // Esc could close the panel instead.
            if (freshOverlay().chatSend) {
                pollGameWindow() // refresh the coordinates right before clicking, the window may have been moved
                simulateClick(pos: MEETING_CHAT_SEND_BUTTON)
                usleep(10000)
                // ...then put the cursor back into the input box so you can keep typing the next message
                simulateClick(pos: (x: MEETING_CHAT_SEND_BUTTON.x - 0.125, y: MEETING_CHAT_SEND_BUTTON.y))
            }
            break;
        case (49, "Ingame"), (14, "Ingame"), (49, "Lobby"), (14, "Lobby"): // Space button
            simulateClick(pos: USE_BUTTON)
            break;
        case (53, "Ingame"), (53, "Lobby"):
            simulateClick(pos: ESC_BUTTON)
            break;
        case (12, "Ingame"):  // Q - Kill
            simulateClick(pos: KILL_BUTTON)
            break;
        case (9, "Ingame"):  // V - Vent
            simulateClick(pos: VENT_BUTTON)
            break;
        case (3, "Ingame"): // F - Role Ability
            simulateClick(pos: ROLE_BUTTON)
            break;
        case (15, "Ingame"):  // R - Report
            simulateClick(pos: REPORT_BUTTON)
            break;
        case (48, "Ingame"): // Tab - Map
            simulateClick(pos: MAP_BUTTON)
            break;
        case (48, "Lobby"): // Tab to open chat and focus input field
            simulateClick(pos: LOBBY_CHAT_BUTTON)
            usleep(100000)
            simulateClick(pos: (x: LOBBY_CHAT_SEND_BUTTON.x - 0.0893, y: LOBBY_CHAT_SEND_BUTTON.y))
            break;
        case (48, "Meeting"): // Tab toggles the chat: open + focus the input field, or close it again
            if (freshOverlay().chat) {
                simulateClick(pos: MEETING_CHAT_BUTTON) // already open: close it, nothing else to click
                chatOpen = false
            } else {
                openChatThenFocusInput()
            }
            break;
        // Keys 1-5 save training screenshots. Developer mode only: it used to trigger while typing digits in chat,
        // and every trigger PNG-encodes a full window capture.
        case (18, _) where devMode: //1 - Store AI Training Data Ingame
            storeScreenshot = "Ingame"
            break;
        case (19, _) where devMode: //2 - Store AI Training Data Lobby
            storeScreenshot = "Lobby"
            break;
        case (20, _) where devMode: //3 - Store AI Training Data Chat
            storeScreenshot = "Lobbychat"
            break;
        case (21, _) where devMode: //4 - Store AI Training Data Meeting
            storeScreenshot = "Meeting"
            break;
        case (23, _) where devMode: //5 - Store AI Training Data Menu
            storeScreenshot = "Menu"
            break;
        default:
            break
        }

        if (sceneKeys.contains(event.keyCode)) { requestClassify(after: 0.25) }
    }
}
