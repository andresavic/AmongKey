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
   
    var body: some View {
        VStack {
            Image("UI")
               .resizable()
               .frame(width: 400, height: 520)
         
            Text((self.state.scene != "" ? self.state.scene : "Nothing") + " - Confidence: " + String(self.state.score) + "%")
               .foregroundColor(Color.white)
               .frame(maxWidth: .infinity, alignment: .leading)
               .padding(.leading, 25).padding(.bottom, 25)
               .background(Color.black)
        
               Button("Update available"){
                  openURL(URL(string: self.state.download)!)
               }
                  .isHidden(self.state.download == "", remove: true)
                  .padding(.bottom, 25)

        }.frame(minWidth: 400, maxWidth: 400, alignment: .topLeading).background(Color.black)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

//Source: https://stackoverflow.com/a/59228385
extension View {
    @ViewBuilder func isHidden(_ hidden: Bool, remove: Bool = false) -> some View {
        if hidden {
            if !remove {
                self.hidden()
            }
        } else {
            self
        }
    }
}
