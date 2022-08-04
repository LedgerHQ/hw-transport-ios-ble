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
    
    public func discoverService(_ serviceIdentifier: ServiceIdentifier) async throws {
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
    
    public func discoverCharacteristic(_ characteristicIdentifier: CharacteristicIdentifier) async throws {
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
}
