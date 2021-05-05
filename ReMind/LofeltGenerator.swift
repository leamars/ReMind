//
//  LofeltGenerator.swift
//  ReMind
//
//  Created by Lea Marolt Sonnenschein on 05/05/2021.
//

import Foundation
import LofeltHaptics
import UIKit
import os.log

enum Pattern {
    case pop
}

class LofeltGenerator {
    var audioPlayer: AVAudioPlayer?
    var haptics: LofeltHaptics?
    
    func playPattern() {
        haptics = try? LofeltHaptics.init()
        
        let audioData = NSDataAsset(name: "Achievement_1-audio")
        audioPlayer = try? AVAudioPlayer(data: audioData!.data)
        
        // load haptic clip
        try? haptics?.load(self.loadHapticData(fileName: "Achievement_1.haptic"))
        
        // play audio and haptic clip
        audioPlayer?.play()
        try? haptics?.play()
    }
    
    func loadHapticData(fileName: String) -> String {
        let hapticData = NSDataAsset(name: fileName)
        let dataString = NSString(data: hapticData!.data , encoding: String.Encoding.utf8.rawValue)
        return dataString! as String
    }
    
}
