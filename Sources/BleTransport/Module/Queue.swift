//
//  Queue.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/5/22.
//

import Foundation
import CoreBluetooth

class Queue {
    var queue = [TaskOperation]()
    
    var isEmpty: Bool {
        queue.isEmpty
    }
    
    var first: TaskOperation? {
        queue.first
    }
    
    func add(_ operation: TaskOperation, finished: EmptyResponse? = nil) {
        DispatchQueue.main.async {
            self.queue.append(operation)
            if self.queue.count == 1 {
                self.queue.first?.start()
            }
            finished?()
        }
    }
    
    func next(finished: EmptyResponse? = nil) {
        DispatchQueue.main.async {
            if !self.isEmpty {
                self.queue.removeFirst()
            }
            self.queue.first?.start()
            finished?()
        }
    }
    
    func operationsOfType<T: TaskOperation>(_ operationType: T.Type) -> [T] {
        queue.filter({ type(of: $0) == operationType }) as! [T]
    }
    
    func removeAll(finished: EmptyResponse? = nil) {
        DispatchQueue.main.async {
            self.queue.forEach({ $0.finished = nil })
            self.queue.removeAll()
            finished?()
        }
    }
    
    func removeAllUpToScanOrConnect(finished: EmptyResponse? = nil) {
        DispatchQueue.main.async {
            guard let currentOperation = self.queue.first else { return }
            if let firstOperationOfTypeIndex = self.queue.firstIndex(where: { type(of: $0) == Connect.self || type(of: $0) == Scan.self }) {
                var newQueue = [TaskOperation]()
                for (index, operation) in self.queue.enumerated() {
                    if index < firstOperationOfTypeIndex {
                        operation.finished = nil
                    } else {
                        newQueue.append(operation)
                    }
                }
                self.queue = newQueue
                if let newCurrentOperation = self.queue.first, newCurrentOperation !== currentOperation {
                    newCurrentOperation.start()
                }
                finished?()
            } else {
                self.removeAll {
                    finished?()
                }
            }
        }
    }
}
