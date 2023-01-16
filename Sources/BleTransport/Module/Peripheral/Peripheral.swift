//
//  Peripheral.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/4/22.
//

import Foundation
import CoreBluetooth

public class Peripheral: NSObject {
    
    private(set) weak var delegate: PeripheralDelegate!
    let cbPeripheral: CBPeripheral
    
    private var listeners: [CharacteristicIdentifier: (ReadResult<Data?>) -> Void?] = [:]
    
    init(delegate: PeripheralDelegate, cbPeripheral: CBPeripheral) {
        self.delegate = delegate
        self.cbPeripheral = cbPeripheral
        
        super.init()
        
        self.cbPeripheral.delegate = self
    }
    
    public var identifier: PeripheralIdentifier {
        return PeripheralIdentifier(uuid: cbPeripheral.identifier, name: cbPeripheral.name)
    }
    
    public func prepareForCharacteristic(_ characteristicIdentifier: CharacteristicIdentifier) async throws {
        try await discoverService(characteristicIdentifier.service)
        try await discoverCharacteristic(characteristicIdentifier)
    }
    
    private func discoverService(_ serviceIdentifier: ServiceIdentifier) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            discoverService(serviceIdentifier) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func discoverCharacteristic(_ characteristicIdentifier: CharacteristicIdentifier) async throws {
        let lock = NSLock()
        return try await withCheckedThrowingContinuation { continuation in
            var nillableContinuation: CheckedContinuation<Void, Error>? = continuation

            discoverCharacteristic(characteristicIdentifier) { result in
                lock.lock()
                defer { lock.unlock() }
                
                switch result {
                case .success:
                    nillableContinuation?.resume()
                    nillableContinuation = nil
                case .failure(let error):
                    nillableContinuation?.resume(throwing: error)
                    nillableContinuation = nil                }
            }
        }
    }
    
    private func discoverService(_ serviceIdentifier: ServiceIdentifier, callback: @escaping (DiscoveryResult) -> Void) {
        let discoverService = DiscoverService(serviceIdentifier: serviceIdentifier, peripheral: cbPeripheral) { result in
            switch result {
            case .success:
                callback(.success)
            case .failure(let error):
                callback(.failure(error))
                return
            }
        }
        
        delegate.requestStartOperation(discoverService)
    }
    
    private func discoverCharacteristic(_ characteristicIdentifier: CharacteristicIdentifier, callback: @escaping (DiscoveryResult) -> Void) {
        let discoverCharacteristic = DiscoverCharacteristic(characteristicIdentifier: characteristicIdentifier, peripheral: cbPeripheral) { result in
            switch result {
            case .success:
                callback(.success)
            case .failure(let error):
                callback(.failure(error))
                return
            }
        }
        self.delegate.requestStartOperation(discoverCharacteristic)
    }
    
    public func isListening(to characteristicIdentifier: CharacteristicIdentifier) -> Bool {
        return listeners.keys.contains(characteristicIdentifier)
    }
    
    public func listen<R: Receivable>(
        to characteristicIdentifier: CharacteristicIdentifier,
        completion: @escaping (ReadResult<R>) -> Void) {
            
            //print("Requesting listen on \(characteristicIdentifier.description)...")
            
            Task() {
                do {
                    try await prepareForCharacteristic(characteristicIdentifier)
                    
                    let listenOperation = Listen(characteristicIdentifier: characteristicIdentifier, peripheral: cbPeripheral, value: true) { [weak self] result in
                        guard let self = self else { completion(.failure(BleModuleError.selfIsNil)); return }
                        
                        switch result {
                        case .success:
                            self.listeners[characteristicIdentifier] = ({ dataResult in
                                completion(ReadResult<R>(dataResult: dataResult))
                            })
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                    delegate.requestStartOperation(listenOperation)
                }
            }
        }
}

extension Peripheral: CBPeripheralDelegate {
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        delegate.didDiscoverServices()
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        delegate.didDiscoverCharacteristics()
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        delegate.didUpdateCharacteristicNotificationState(error: error)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        delegate.didUpdateValueFor(characteristic: characteristic, error: error)
    }
}
