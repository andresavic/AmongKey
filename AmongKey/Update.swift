//
//  Update.swift
//  AmongKey
//
//  Created by Andre Savic on 30.11.20.
//

import Foundation

class Update {
    static let url = URL(string: "https://andresavic.at/amongkey/update.json")
    
    struct UpdateJson: Codable {
      let version: Double
      let download: String
    }
    
    static func checkForUpdate(completion:  @escaping (String)->()) {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return;
        }
        
        URLSession.shared.dataTask(with: self.url!) { data, response, error in
          if let data = data {
             do {
                let res = try JSONDecoder().decode(UpdateJson.self, from: data)
                if (res.version > Double(currentVersion)!) {
                    completion(res.download)
                }
             } catch let error {
                print(error)
             }
          }
        }.resume()
        
        
    }
}
