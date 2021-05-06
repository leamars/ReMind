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

enum Pattern: String {
    case pop
    case whoosh
    case smallWhoosh
    case tab1
    case tab2
    case tab3
    case collapse
    case expand
    case success3
    //case aces
    case airPop // used for skipping back or forward for 3 seconds, gives that bit of "interrupt" feeling whe music stops and "rewinds"
    //case alert1
    //case alert5 - this is double
    case approval // Pretty strong
    case arise // Cancel or go back?
    case transitionLeft
    case transitionRight
    case unlock
    case clear
    case loop
    case loop2
    case pong
    case popped
    case trippleClick
    case snap
    case lock
    case shutter
    
    var fileName: String {
        return self.rawValue
    }
    
    var audioFileName: String {
        return "\(fileName).audio"
    }
    
    var hapticFileName: String {
        return "\(fileName).haptic"
    }
}

class LofeltGenerator {
    var audioPlayer: AVAudioPlayer?
    var haptics: LofeltHaptics?
    
    func play(pattern: Pattern, withAudio: Bool = false) {
        playPattern(audioFileName: pattern.audioFileName, hapticFileName: pattern.hapticFileName, withAudio: withAudio)
    }
    
    func play(audioOnlyPattern: Pattern) {
        let audioData = NSDataAsset(name: audioOnlyPattern.audioFileName)
        audioPlayer = try? AVAudioPlayer(data: audioData!.data)
        
        audioPlayer?.play()
    }
    
    private func playPattern(audioFileName: String, hapticFileName: String, withAudio: Bool = false) {
        haptics = try? LofeltHaptics.init()
        
        let audioData = NSDataAsset(name: audioFileName)
        audioPlayer = try? AVAudioPlayer(data: audioData!.data)
        
        // load haptic clip
        try? haptics?.load(self.loadHapticData(fileName: hapticFileName))
        
        // play audio and haptic clip
        if withAudio {
            audioPlayer?.play()
        }
        try? haptics?.play()
    }
    
    private func loadHapticData(fileName: String) -> String {
        let hapticData = NSDataAsset(name: fileName)
        let dataString = NSString(data: hapticData!.data , encoding: String.Encoding.utf8.rawValue)
        return dataString! as String
    }
    
}
