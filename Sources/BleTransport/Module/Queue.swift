//
//  File.swift
//  
//
//  Created by Dante Puglisi on 8/5/22.
//

import Foundation
import CoreBluetooth

class Queue {
    var queue = [Operation]()
    
    var isEmpty: Bool {
        queue.isEmpty
    }
    
    var first: Operation? {
        queue.first
    }
    
    func add(_ operation: Operation) {
        DispatchQueue.main.async {
            self.queue.append(operation)
            if self.queue.count == 1 {
                self.queue.first?.start()
            }
        }
    }
    
    func next() {
        DispatchQueue.main.async {
            if !self.isEmpty {
                self.queue.removeFirst()
            }
            
            self.queue.first?.start()
        }
    }
    
    func operationsOfType<T: Operation>(_ operationType: T.Type) -> [T] {
        queue.filter({ type(of: $0) == operationType }) as! [T]
    }
}
