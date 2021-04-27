//
//  PassthroughView.swift
//  ReMind
//
//  Created by Lea Marolt Sonnenschein on 26/04/2021.
//

import Foundation
import UIKit

class PassthroughImageView: UIImageView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return false
    }
}
