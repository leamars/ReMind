//
//  RoundedButton.swift
//  ReMind
//
//  Created by Lea Marolt Sonnenschein on 05/05/2021.
//

import Foundation
import UIKit

class RoundedButton: UIButton {
    override func draw(_ rect: CGRect) {
        self.layer.cornerRadius = 15.0
        self.layer.borderWidth = 5.0
        self.layer.borderColor = UIColor.clear.cgColor
        self.layer.masksToBounds = true
    }
}
