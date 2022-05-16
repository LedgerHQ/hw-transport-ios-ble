//
//  BleTransport.swift
//  Ledger Bluetooth
//
//  Created by Dante Puglisi on 5/11/22.
//

import Foundation
import Bluejay

@objc public class BleTransport: NSObject, BleTransportProtocol {
    
    let bluejay: Bluejay
    
    let nanoXService = ServiceIdentifier(uuid: "13D63400-2C97-0004-0000-4C6564676572")
    
    var isBluetoothAvailable: Bool {
        bluejay.isBluetoothAvailable
    }
    
    // MARK: - Initialization
    
    @objc public override init() {
        self.bluejay = Bluejay()
        
        super.init()
        
        self.bleInit()
    }
    
    fileprivate func bleInit() {
        self.bluejay.register(logObserver: self)
        self.bluejay.start()
    }
    
    // MARK: - Public Methods
    
    public func scan(callback: @escaping PeripheralsResponse, stopped: @escaping (()->())) {
        guard !self.bluejay.isScanning else { return }
        self.bluejay.scan(allowDuplicates: true, serviceIdentifiers: [self.nanoXService], discovery: {  discovery, discoveries in
            callback(discoveries.map({ $0.peripheralIdentifier }))
            return .continue
        }, expired: { discovery, discoveries in
            callback(discoveries.map({ $0.peripheralIdentifier }))
            return .continue
        }, stopped: { discoveries, error in
            stopped()
            if let error = error {
                print("Stopped scanning with error: \(error)")
            }
        })
    }
    
    public func open(withPeripheral peripheral: PeripheralIdentifier, success: @escaping PeripheralResponse, failure: @escaping ErrorResponse) {
        if self.bluejay.isScanning {
            self.bluejay.stopScanning()
        }
        
        self.connectToPeripheral(peripheral, success: success, failure: failure)
    }
    
    public func create(success: @escaping PeripheralResponse, failure: @escaping ErrorResponse) {
        scan { [weak self] discoveries in
            guard let firstDiscovery = discoveries.first else { failure(nil); return }
            self?.open(withPeripheral: firstDiscovery, success: { [weak self] _ in
                self?.bluejay.stopScanning()
            }, failure: failure)
        } stopped: {
            failure(nil)
        }
    }
    
    public func listen(to: CharacteristicIdentifier, apduReceived: @escaping APDUResponse, failure: @escaping ErrorResponse) {
        self.bluejay.listen(to: to, multipleListenOption: .replaceable) { (result: ReadResult<APDU>) in
            switch result {
            case .success(let apdu):
                apduReceived(apdu)
            case .failure(let error):
                failure(error)
            }
        }
    }
    
    public func send(apdu: APDU, to: CharacteristicIdentifier, success: @escaping (()->()), failure: @escaping ErrorResponse) {
        self.bluejay.write(to: to, value: apdu, type: .withoutResponse) { result in
            switch result {
            case .success:
                success()
            case .failure(let error):
                failure(error)
            }
        }
    }
    
    public func disconnect(immediate: Bool, completion: @escaping ErrorResponse) {
        self.bluejay.disconnect(immediate: immediate) { result in
            switch result {
            case .disconnected(_):
                completion(nil)
            case .failure(let error):
                completion(error)
            }
        }
    }
    
    
    // MARK: - Private methods
    
    fileprivate func connectToPeripheral(_ peripheral: PeripheralIdentifier, success: @escaping PeripheralResponse, failure: @escaping ErrorResponse) {
        self.bluejay.connect(peripheral, timeout: Timeout.seconds(15), warningOptions: nil) { result in
            switch result {
            case .success(let peripheralIdentifier):
                success(peripheralIdentifier)
            case .failure(let error):
                failure(error)
            }
        }
    }
}

extension BleTransport: LogObserver {
    public func debug(_ text: String) {
        
    }
}
