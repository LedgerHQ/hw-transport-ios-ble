//
//  Connect.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/2/22.
//

import Foundation
import CoreBluetooth

/// Types of connection time outs. Can specify a time out in seconds, or no time out.
public enum Timeout {
    /// Specify a timeout with a duration in seconds.
    case seconds(TimeInterval)
    /// Specify there is no timeout.
    case none
}

public enum ConnectionError: LocalizedError {
    case timedOut
    case unexpectedDisconnect
    
    public var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Connection timed out."
        case .unexpectedDisconnect:
            return "Unexpected disconnect while connecting."
        }
    }
}

public class Connect: Operation {
    
    var finished: EmptyResponse?
    
    /// The peripheral this operation is for.
    var peripheral: CBPeripheral! = nil
    
    /// The manager responsible for this operation.
    let manager: CBCentralManager
    
    /// Callback for the connection attempt.
    var callback: ((ConnectionResult) -> Void)?
    
    private var connectionTimer: Timer?
    private let timeout: Timeout?
    
    deinit {
        //print("Deinited Connect")
    }
    
    init(peripheralIdentifier: PeripheralIdentifier, manager: CBCentralManager, timeout: Timeout, callback: @escaping (ConnectionResult) -> Void) {
        
        self.manager = manager
        self.timeout = timeout
        self.callback = callback
        
        guard let cbPeripheral = manager.retrievePeripherals(withIdentifiers: [peripheralIdentifier.uuid]).first else { complete(.failure(ConnectionError.unexpectedDisconnect)); return }
        self.peripheral = cbPeripheral
    }
    
    func start() {
        manager.connect(peripheral)
        
        cancelTimer()
        
        if let timeOut = timeout, case let .seconds(timeoutInterval) = timeOut {
            connectionTimer = Timer.scheduledTimer(withTimeInterval: timeoutInterval, repeats: false) { [weak self] _ in
                guard let weakSelf = self else {
                    return
                }
                
                weakSelf.timedOut()
            }
        }
    }
    
    func complete(_ result: ConnectionResult) {
        callback?(result)
        callback = nil
        finished?()
    }
    
    func didConnectPeripheral() {
        complete(.success(peripheral))
    }
    
    func didDisconnectPeripheral() {
        complete(.failure(ConnectionError.unexpectedDisconnect))
    }
    
    private func cancelTimer() {
        connectionTimer?.invalidate()
        connectionTimer = nil
    }
    
    @objc private func timedOut() {
        complete(.failure(ConnectionError.timedOut))
    }
}
