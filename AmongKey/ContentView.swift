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

    var body: some View {
        VStack(spacing: 0) {
            Image("UI")
               .resizable()
               .frame(width: 400, height: 520)

            if showLiveStatus {
                Text((self.state.scene != "" ? self.state.scene : "Nothing") + " - Confidence: " + String(self.state.score) + "%")
                   .foregroundColor(Color.white)
                   .frame(maxWidth: .infinity, alignment: .leading)
                   .padding(.leading, 25).padding(.top, 10)
            }

            Toggle(isOn: $showLiveStatus) {
                Text("Show live detection (setup mode)").foregroundColor(Color.white)
            }
               .toggleStyle(.checkbox)
               .frame(maxWidth: .infinity, alignment: .leading)
               .padding(.leading, 25).padding(.top, 10)
               .onChange(of: showLiveStatus) { on in setLiveStatus(on) }

            Text("Useful the first time, to check that AmongKey recognises the game. Turn it off afterwards: it uses a little less CPU.")
               .font(.caption)
               .foregroundColor(Color.gray)
               .frame(maxWidth: .infinity, alignment: .leading)
               .padding(.horizontal, 25).padding(.top, 2).padding(.bottom, 20)

            // The old force-unwrapped URL(string:)! could crash on a malformed update.json; only offer https links
            if let url = URL(string: self.state.download), url.scheme == "https" {
               Button("Update available"){
                  openURL(url)
               }
                  .padding(.bottom, 25)
            }

        }.frame(minWidth: 400, maxWidth: 400, alignment: .topLeading).background(Color.black)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
