//
//  ContentView.swift
//  AmongKey
//
//  Created by Andre Savic on 24.11.20.
//
import SwiftUI

class globaleState: ObservableObject {
   static let shared = globaleState()
   private init() {}
   @Published var score: Int = 0
   @Published var scene: String = ""
   @Published var download: String = ""
}

struct ContentView: View {
   @Environment(\.openURL) var openURL
   @ObservedObject var state = globaleState.shared
   // Remembered between launches. Default on: the first run needs it to confirm the game is recognised.
   @AppStorage("showLiveStatus") private var showLiveStatus = true

    // Same window as before (artwork on top, status, setup checkbox, update button), only tidied up:
    // one left edge for everything below the artwork, two text sizes (13 pt for what you read, 11 pt for the
    // hint), one vertical rhythm, and the hint wraps instead of being cut off.
    var body: some View {
        VStack(spacing: 0) {
            Image("UI")
               .resizable()
               .frame(width: 400, height: 520)

            VStack(alignment: .leading, spacing: 14) {
                if showLiveStatus {
                    Text((self.state.scene != "" ? self.state.scene : "Nothing") + " - Confidence: " + String(self.state.score) + "%")
                       .font(.system(size: 13))
                       .foregroundColor(Color.white)
                }

                // The checkbox and its explanation belong together, so they sit closer than the rows around them
                VStack(alignment: .leading, spacing: 5) {
                    Toggle(isOn: $showLiveStatus) {
                        Text("Show live detection (setup mode)")
                           .font(.system(size: 13))
                           .foregroundColor(Color.white)
                    }
                       .toggleStyle(.checkbox)
                       .onChange(of: showLiveStatus) { on in setLiveStatus(on) }

                    Text("Useful the first time, to check that AmongKey recognises the game. Turn it off afterwards: it uses a little less CPU.")
                       .font(.system(size: 11))
                       .foregroundColor(Color.gray)
                       .lineSpacing(3)
                       .fixedSize(horizontal: false, vertical: true) // wrap, never truncate
                }

                // The old force-unwrapped URL(string:)! could crash on a malformed update.json; only offer https links
                if let url = URL(string: self.state.download), url.scheme == "https" {
                   Button("Update available"){
                      openURL(url)
                   }
                }
            }
               .frame(maxWidth: .infinity, alignment: .leading)
               .padding(.horizontal, 25).padding(.top, 18).padding(.bottom, 24)

        }.frame(minWidth: 400, maxWidth: 400, alignment: .topLeading).background(Color.black)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
