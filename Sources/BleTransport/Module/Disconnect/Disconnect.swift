//
//  Disconnect.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/9/22.
//

import CoreBluetooth
import Foundation

/// A disconnection operation.
class Disconnect: Operation {
    
    var finished: EmptyResponse?
    
    /// The peripheral this operation is for.
    let peripheral: CBPeripheral
    
    /// The manager responsible for this operation.
    let manager: CBCentralManager
    
    /// Callback for the disconnection attempt.
    var callback: ((DisconnectionResult) -> Void)?
    
    deinit {
        //print("Deinited Disconnect")
    }
    
    init(peripheral: CBPeripheral, manager: CBCentralManager, callback: ((DisconnectionResult) -> Void)?) {
        self.peripheral = peripheral
        self.manager = manager
        
        self.callback = callback
    }
    
    func start() {
        manager.cancelPeripheralConnection(peripheral)
        
        //print("Started disconnecting from \(peripheral.name ?? peripheral.identifier.uuidString).")
    }
    
    func didDisconnectPeripheral(peripheral: PeripheralIdentifier) {
        complete(.disconnected(peripheral))
    }
    
    func complete(_ result: DisconnectionResult) {
        callback?(result)
        callback = nil
        
        /// We don't call `finished?()` on `Disconnect` because we don't want the queue to advance to the next operation, as soon as the delegate received `didDisconnect` it clears the queue
        //finished?()
    }
    
    func fail(_ error: Error) {
        //print("Failed disconnecting from: \(peripheral.name ?? peripheral.identifier.uuidString) with error: \(error.localizedDescription)")
        
        complete(.failure(error))
    }
}
