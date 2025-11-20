//
//  Item.swift
//  Memory
//
//  Created by Jessica Young on 11/19/25.
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
