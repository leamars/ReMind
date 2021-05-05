//
//  HapticGenerator.swift
//  ReMind
//
//  Created by Lea Marolt Sonnenschein on 21/04/2021.
//

import Foundation
import CoreHaptics
import UIKit
import os.log


class HapticGenerator {
    
    private(set) var engine: CHHapticEngine
    
    private(set) lazy var engineNeedsStart = true
    
    private var supportsHaptics: Bool {
        let hapticCapability = CHHapticEngine.capabilitiesForHardware()
        return hapticCapability.supportsHaptics
    }
    
    private var continuousPlayer: CHHapticAdvancedPatternPlayer!
    private let initialIntensity: Float = 1.0
    private let initialSharpness: Float = 0.5
    
    // Tokens to track whether app is in the foreground or the background:
    private var foregroundToken: NSObjectProtocol?
    private var backgroundToken: NSObjectProtocol?
    
    init?() {
        let hapticCapability = CHHapticEngine.capabilitiesForHardware()
        guard hapticCapability.supportsHaptics else { return nil }
        
        // Create and configure a haptic engine.
        do {
            engine = try CHHapticEngine()
            setup()
        } catch let error {
            os_log("Engine Creation Error: %@", error.localizedDescription)
            return nil
        }
        
    }
    
    /// - Tag: Setup Haptic engine handlers
    public func setup() {
        
        // Mute audio to reduce latency for collision haptics.
        engine.playsHapticsOnly = true
        
        // The stopped handler alerts you of engine stoppage.
        engine.stoppedHandler = { reason in
            
            os_log("Stop Handler: The engine stopped for reason: %@", String(reason.rawValue))
            switch reason {
            case .audioSessionInterrupt: os_log("Audio session interrupt")
            case .applicationSuspended: os_log("Application suspended")
            case .idleTimeout: os_log("Idle timeout")
            case .systemError: os_log("System error")
            case .notifyWhenFinished: os_log("Playback finished")
            case .engineDestroyed: os_log("Engine destroyed")
            case .gameControllerDisconnect: os_log("Game controller disconnect")
            @unknown default:
                os_log("Unknown error: %@", String(reason.rawValue))
            }
        }
        
        // The reset handler provides an opportunity to restart the engine.
        engine.resetHandler = { [weak self] in
            
            guard let self = self else { return }
            os_log("Reset Handler: Restarting the engine.")
            
            do {
                // Try restarting the engine.
                try self.engine.start()
                
                // Indicate that the next time the app requires a haptic, the app doesn't need to call engine.start().
                self.engineNeedsStart = false
                
            } catch {
                os_log("Failed to start the engine")
            }
        }
        
        // Start the haptic engine for the first time.
        do {
            try self.engine.start()
        } catch {
            os_log("Failed to start the engine: %@", error.localizedDescription)
        }
    }
    
    private func addObservers() {
        backgroundToken = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                                 object: nil,
                                                                 queue: nil)
        { _ in
            guard self.supportsHaptics else {
                return
            }
            // Stop the haptic engine.
            self.engine.stop(completionHandler: { error in
                if let error = error {
                    print("Haptic Engine Shutdown Error: \(error)")
                    return
                }
                self.engineNeedsStart = true
            })
        }
        foregroundToken = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                                                 object: nil,
                                                                 queue: nil)
        { _ in
            guard self.supportsHaptics else {
                return
            }
            // Restart the haptic engine.
            self.engine.start(completionHandler: { error in
                if let error = error {
                    print("Haptic Engine Startup Error: \(error)")
                    return
                }
                self.engineNeedsStart = false
            })
        }
    }
    
    public func stop() {
        engine.stop(completionHandler: nil)
    }
    
    public func fire(sharpness: Float = 1.0, intensity: Float = 1.0, duration: Double = 0.2) {
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
//            if engineNeedsStart {
//                start()
//            }
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate) // Play now.
        } catch let error {
            os_log("Error creating a haptic transient pattern: %@", error.localizedDescription)
        }
    }
    
    /// - Tag: CreateContinuousPattern
    func createContinuousHapticPlayer() {
        // Create an intensity parameter:
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity,
                                               value: initialIntensity)
        
        // Create a sharpness parameter:
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness,
                                               value: initialSharpness)
        
        // Create a continuous event with a long duration from the parameters.
        let continuousEvent = CHHapticEvent(eventType: .hapticContinuous,
                                            parameters: [intensity, sharpness],
                                            relativeTime: 0,
                                            duration: 100)
        
        do {
            // Create a pattern from the continuous haptic event.
            let pattern = try CHHapticPattern(events: [continuousEvent], parameters: [])
            
            // Create a player from the continuous haptic pattern.
//            if engineNeedsStart {
//                start()
//            }
            continuousPlayer = try engine.makeAdvancedPlayer(with: pattern)
            
        } catch let error {
            print("Pattern Player Creation Error: \(error)")
        }
        
        continuousPlayer.completionHandler = { _ in
            DispatchQueue.main.async {
                // Restore original color.
                print("Completed...")
            }
        }
    }
    
    func fireSwipePattern() {
        // create a dull, strong haptic
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0)
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1)

        // create a curve that fades from 1 to 0 over one second
        let start = CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 1)
        let end = CHHapticParameterCurve.ControlPoint(relativeTime: 1, value: 0)

        // use that curve to control the haptic strength
        let parameter = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [start, end], relativeTime: 0)

        // create a continuous haptic event starting immediately and lasting one second
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [sharpness, intensity], relativeTime: 0, duration: 1)

        // now attempt to play the haptic, with our fading parameter
        do {
            let pattern = try CHHapticPattern(events: [event], parameterCurves: [parameter])

            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            // add your own meaningful error handling here!
            print(error.localizedDescription)
        }
    }
    
    func fireAnotherFunky() {
        var events = [CHHapticEvent]()
        var curves = [CHHapticParameterCurve]()

        do {
            // create one continuous buzz that fades out
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0)
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1)

            let start = CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 1)
            let end = CHHapticParameterCurve.ControlPoint(relativeTime: 1.5, value: 0)

            let parameter = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [start, end], relativeTime: 0)
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [sharpness, intensity], relativeTime: 0, duration: 1.5)
            events.append(event)
            curves.append(parameter)
        }

        for _ in 1...16 {
            // make some sparkles
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1)
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1)
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [sharpness, intensity], relativeTime: TimeInterval.random(in: 0.1...1))
            events.append(event)
        }

        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)

            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print(error.localizedDescription)
        }
    }
    
    func fireContinuous() {
//        if engineNeedsStart {
//            start()
//        }
        
        print("Engine is running? \(engineNeedsStart)")
        
        if continuousPlayer == nil {
            createContinuousHapticPlayer()
        }
        
        if supportsHaptics {
            // Create dynamic parameters for the updated intensity & sharpness.
            let intensityParameter = CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                                              value: 1,
                                                              relativeTime: 0)
            
            let sharpnessParameter = CHHapticDynamicParameter(parameterID: .hapticSharpnessControl,
                                                              value: 1,
                                                              relativeTime: 0)
            
            // Send dynamic parameters to the haptic player.
            do {
                try continuousPlayer.sendParameters([intensityParameter, sharpnessParameter],
                                                    atTime: 0)
            } catch let error {
                if let hapticError = error as? CHHapticError {
                    print("Error \(hapticError)")
                }
                print("Dynamic Parameter Error: \(error)")
            }
            
            // Warm engine.
            do {
                // Begin playing continuous pattern.
                try continuousPlayer.start(atTime: CHHapticTimeImmediate)
            } catch let error {
                print("Error starting the continuous haptic player: \(error)")
            }
        }
    }
    
    func stopContinuous() {
        if supportsHaptics {
            // Stop playing the haptic pattern.
            do {
                try continuousPlayer.stop(atTime: CHHapticTimeImmediate)
            } catch let error {
                print("Error stopping the continuous haptic player: \(error)")
            }
            
            // The background color returns to normal in the player's completion handler.
        }
    }
}
