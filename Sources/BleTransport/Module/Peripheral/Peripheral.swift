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
    private(set) var cbPeripheral: CBPeripheral!
    
    private var listeners: [CharacteristicIdentifier: (ReadResult<Data?>) -> Void?] = [:]
    
    init(delegate: PeripheralDelegate, cbPeripheral: CBPeripheral) {
        self.delegate = delegate
        self.cbPeripheral = cbPeripheral
        
        super.init()
        
        guard self.delegate != nil else {
            fatalError("Peripheral initialized without a PeripheralDelegate association.")
        }
        
        guard self.cbPeripheral != nil else {
            fatalError("Peripheral initialized without a CBPeripheral association.")
        }
        
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
        return try await withCheckedThrowingContinuation { continuation in
            discoverCharacteristic(characteristicIdentifier) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
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
    
    /// Captures CoreBluetooth's did discover services event and pass it to Bluejay's queue for processing.
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        //handle(event: .didDiscoverServices, error: error as NSError?)
        delegate.didDiscoverServices()
    }
    
    /// Captures CoreBluetooth's did discover characteristics event and pass it to Bluejay's queue for processing.
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        //handle(event: .didDiscoverCharacteristics, error: error as NSError?)
        delegate.didDiscoverCharacteristics()
    }
    
    /// Captures CoreBluetooth's did write to charactersitic event and pass it to Bluejay's queue for processing.
    /*public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        handle(event: .didWriteCharacteristic(characteristic), error: error as NSError?)
    }*/
    
    /// Captures CoreBluetooth's did turn on or off notification/listening on a characteristic event and pass it to Bluejay's queue for processing.
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        //handle(event: .didUpdateCharacteristicNotificationState(characteristic), error: error as NSError?)
        delegate.didUpdateCharacteristicNotificationState(error: error)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        //print("LISTENERS: \(listeners)")
        delegate.didUpdateValueFor(characteristic: characteristic, error: error)
    }
}
