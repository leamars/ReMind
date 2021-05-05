//
//  HapticsViewController.swift
//  ReMind
//
//  Created by Lea Marolt Sonnenschein on 05/05/2021.
//

import Foundation
import UIKit
import LofeltHaptics
import AVFoundation

class HapticsViewController: UIViewController {
    
    var audioPlayer: AVAudioPlayer?
    var haptics: LofeltHaptics?
    
    override func viewDidLoad() {
        haptics = try? LofeltHaptics.init()
        
        let audioData = NSDataAsset(name: "pop-audio")
        audioPlayer = try? AVAudioPlayer(data: audioData!.data)
        
        // load haptic clip
        try? haptics?.load(self.loadHapticData(fileName: "pop.haptics"))
        
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
