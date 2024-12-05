//
//  Item.swift
//  Globle
//
//  Created by R. Metehan GÖKTAŞ on 5.12.2024.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
