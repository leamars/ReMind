//
//  HapticGenerator.swift
//  ReMind
//
//  Created by Lea Marolt Sonnenschein on 21/04/2021.
//

import Foundation
import CoreHaptics
import os.log

open class HapticGenerator {
    public static let shared = HapticGenerator()
    
    @available(iOS 13.0, *)
    private(set) lazy var engine: CHHapticEngine? = nil
    
    @available(iOS 13.0, *)
    private(set) lazy var engineNeedsStart = true
    
    @available(iOS 13.0, *)
    private var supportsHaptics: Bool {
        let hapticCapability = CHHapticEngine.capabilitiesForHardware()
        return hapticCapability.supportsHaptics
    }
    
    /// - Tag: CreateAndStartEngine
    public func start() {
        
        if #available(iOS 13.0, *) {
            // Create and configure a haptic engine.
            do {
                engine = try CHHapticEngine()
            } catch let error {
                os_log("Engine Creation Error: %@", error.localizedDescription)
            }
            
            // Mute audio to reduce latency for collision haptics.
            engine?.playsHapticsOnly = true
            
            // The stopped handler alerts you of engine stoppage.
            engine?.stoppedHandler = { reason in
                
                os_log("Stop Handler: The engine stopped for reason: %@", String(reason.rawValue))
                switch reason {
                case .audioSessionInterrupt: os_log("Audio session interrupt")
                case .applicationSuspended: os_log("Application suspended")
                case .idleTimeout: os_log("Idle timeout")
                case .systemError: os_log("System error")
                case .notifyWhenFinished: os_log("Playback finished")
                @unknown default:
                    os_log("Unknown error: %@", String(reason.rawValue))
                }
            }
            
            // The reset handler provides an opportunity to restart the engine.
            engine?.resetHandler = { [weak self] in
                
                guard let self = self else { return }
                os_log("Reset Handler: Restarting the engine.")
                
                do {
                    // Try restarting the engine.
                    try self.engine?.start()
                    
                    // Indicate that the next time the app requires a haptic, the app doesn't need to call engine.start().
                    self.engineNeedsStart = false
                    
                } catch {
                    os_log("Failed to start the engine")
                }
            }
            
            // Start the haptic engine for the first time.
            do {
                try self.engine?.start()
            } catch {
                os_log("Failed to start the engine: %@", error.localizedDescription)
            }
        }
    }
    
    public func stop() {
        if #available(iOS 13.0, *) {
            engine?.stop(completionHandler: nil)
        }
    }
    
    public func fire(sharpness: Float = 1.0, intensity: Float = 1.0, duration: Double = 0.2) {
        if #available(iOS 13.0, *) {
            guard supportsHaptics else { return }
            
            // Create an event (static) parameter to represent the haptic's intensity.
            let intensityParameter = CHHapticEventParameter(parameterID: .hapticIntensity,
                                                            value: sharpness)
            
            // Create an event (static) parameter to represent the haptic's sharpness.
            let sharpnessParameter = CHHapticEventParameter(parameterID: .hapticSharpness,
                                                            value: intensity)
            
            // Create an event to represent the haptic pattern.
            let event = CHHapticEvent(eventType: .hapticContinuous,
                                      parameters: [intensityParameter, sharpnessParameter],
                                      relativeTime: 0,
                                      duration: duration)
            
            // Create a pattern from the haptic event.
            do {
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                
                // Create a player to play the haptic pattern.
                if engineNeedsStart {
                    start()
                }
                let player = try engine?.makePlayer(with: pattern)
                try player?.start(atTime: CHHapticTimeImmediate) // Play now.
            } catch let error {
                os_log("Error creating a haptic transient pattern: %@", error.localizedDescription)
            }
        } else {
            FeedbackGenerator.shared.fire(for: .impact)
        }
    }
}
