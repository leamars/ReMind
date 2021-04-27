//
//  FeedbackGenerator.swift
//  ReMind
//
//  Created by Lea Marolt Sonnenschein on 21/04/2021.
//

import Foundation
import UIKit

public enum FeedbackType {
    case impact
    case selection
    case notification(Int)
    case light
    case medium
    case heavy
}

///
/// Feedback generator wrapper, will hold and prepare generators based
/// on provided
///
open class FeedbackGenerator {
    public static let shared = FeedbackGenerator()
    
    private var impact: Any?
    private var selection: Any?
    private var notification: Any?
    
    private var generators: [AnyObject] = []
    
    open func prepare(for type: FeedbackType) {
        let generator = self.generate(for: type)
        
        generator.prepare()
    }
    
    open func fire(for type: FeedbackType) {
        let generator = self.generate(for: type)
        
        if let generator = generator as? UIImpactFeedbackGenerator {
            generator.impactOccurred()
        }
        else if let generator = generator as? UISelectionFeedbackGenerator {
            generator.selectionChanged()
        }
        else if let generator = generator as? UINotificationFeedbackGenerator {
            
            switch type {
            case .notification(let type):
                let notificationType = UINotificationFeedbackGenerator.FeedbackType(rawValue: type)!
                
                generator.notificationOccurred(notificationType)
            default:
                generator.notificationOccurred(.success)
            }
            
        }
    }
    
    open func end(for type: FeedbackType) {
        let generator = self.generate(for: type)
        
        var index = 0
        
        for currentGenerator in generators {
            if currentGenerator === generator {
                break
            }
            
            index += 1
        }
        
        generators.remove(at: index)
    }
    
    open func endAll() {
        generators.removeAll()
    }
    
    private func generator<T: UIFeedbackGenerator>() -> T {
        for generator in generators {
            if let generator = generator as? T {
                return generator
            }
        }
        
        let generator = T()
        
        generators.append(generator)
        
        return generator
    }
    
    private func generate(for feedbackType: FeedbackType) -> UIFeedbackGenerator {
        
        switch feedbackType {
        case .impact:
            let generator: UIImpactFeedbackGenerator = self.generator()
            return generator
        case .selection:
            let generator: UISelectionFeedbackGenerator = self.generator()
            return generator
        case .notification:
            let generator: UINotificationFeedbackGenerator = self.generator()
            return generator
        case .light:
            let generator: UIImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
            return generator
        case .medium:
            let generator: UIImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
            return generator
        case .heavy:
            let generator: UIImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .heavy)
            return generator
        }
    }
}
