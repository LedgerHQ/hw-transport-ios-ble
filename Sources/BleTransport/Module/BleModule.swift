//
//  File.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/2/22.
//

import Foundation
import CoreBluetooth

enum BleModuleError: LocalizedError {
    case selfIsNil
    case notConnected
    
    var errorDescription: String? {
        switch self {
        case .selfIsNil:
            return "Self is nil."
        case .notConnected:
            return "Attempted to perform an action when there's no device connected."
        }
    }
}

protocol BleModuleDelegate {
    func bluetoothAvailable(_ available: Bool)
}

protocol Operation {
    var finished: EmptyResponse? { get set }
    
    func start()
}

public class BleModule: NSObject {
    private var cbCentralManager: CBCentralManager!
    
    private var delegate: BleModuleDelegate!
    
    private var currentOperation: Operation?
    
    private var connectedPeripheral: CBPeripheral?
    
    //private var nextOperationsQueue = [Operation]()
    
    public var isBluetoothAvailable: Bool {
        if cbCentralManager == nil {
            return false
        } else {
            return cbCentralManager.state == .poweredOn
        }
    }
    
    func start(delegate: BleModuleDelegate) {
        self.delegate = delegate
        self.cbCentralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    private func startOperation(_ operation: Operation) {
        self.currentOperation = operation
        self.currentOperation?.finished = { [weak self] in
            self?.currentOperation = nil
        }
        self.currentOperation?.start()
    }
    
    private func clearAfterDisconnect() {
        self.connectedPeripheral = nil
    }
}

// MARK: - Scan
extension BleModule {
    public func scan(duration: TimeInterval,
              throttleRSSIDelta: Int = 5,
              serviceIdentifiers: [ServiceIdentifier],
              discovery: @escaping (ScanDiscovery, [ScanDiscovery]) -> ScanAction,
              expired: ((ScanDiscovery, [ScanDiscovery]) -> ScanAction)? = nil,
              stopped: @escaping ([ScanDiscovery], Error?, Bool) -> Void) {
        let scanOperation = Scan(duration: duration, throttleRSSIDelta: throttleRSSIDelta, serviceIdentifiers: serviceIdentifiers, discovery: discovery, expired: expired, stopped: stopped, manager: cbCentralManager)
        startOperation(scanOperation)
    }
    
    func stopScanning() {
        (currentOperation as? Scan)?.stopScanning()
    }
}

// MARK: - Connect
extension BleModule {
    public func connect(peripheralIdentifier: PeripheralIdentifier, timeout: Timeout, callback: @escaping (ConnectionResult) -> Void) {
        let connectOperation = Connect(peripheralIdentifier: peripheralIdentifier, manager: cbCentralManager, timeout: timeout, callback: { result in
            if case .success(let peripheral) = result {
                self.connectedPeripheral = peripheral
                callback(result)
            }
        })
        startOperation(connectOperation)
    }
}

// MARK: - Write
extension BleModule {
    public func write<S: Sendable>(
        to characteristicIdentifier: CharacteristicIdentifier,
        value: S,
        type: CBCharacteristicWriteType = .withResponse,
        completion: @escaping (WriteResult) -> Void) {
            if let peripheral = connectedPeripheral {
                
                let writeOperation = Write(characteristicIdentifier: characteristicIdentifier, peripheral: peripheral, value: value, type: type, callback: completion)
                
                let discoverService = DiscoverService(serviceIdentifier: characteristicIdentifier.service, peripheral: peripheral) { [weak self] result in
                    guard let self = self else { completion(.failure(BleModuleError.selfIsNil)); return }
                    switch result {
                    case .success:
                        let discoverCharacteristic = DiscoverCharacteristic(characteristicIdentifier: characteristicIdentifier, peripheral: peripheral) { result in
                            switch result {
                            case .success:
                                self.startOperation(writeOperation)
                            case .failure(let error):
                                completion(.failure(error))
                                return
                            }
                        }
                        self.startOperation(discoverCharacteristic)
                    case .failure(let error):
                        completion(.failure(error))
                        return
                    }
                }
                startOperation(discoverService)
            } else {
                print("Cannot request write on \(characteristicIdentifier.description): \(BleModuleError.notConnected.localizedDescription)")
                completion(.failure(BleModuleError.notConnected))
            }
        }
}

extension BleModule: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        delegate.bluetoothAvailable(central.state == .poweredOn)
        switch central.state {
        case .poweredOn:
            print("Bluetooth is on")
        case .poweredOff:
            print("Bluetooth is off")
        case .unauthorized:
            print("App is unauthorized")
        default:
            print("Bluetooth is unsupported")
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if let scan = currentOperation as? Scan {
            scan.discoveredPeripheral(cbPeripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        (currentOperation as? Connect)?.didConnectPeripheral()
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        (currentOperation as? Connect)?.didDisconnectPeripheral()
        clearAfterDisconnect()
    }
    
    /**
     This mostly happens when either the Bluetooth device or the Core Bluetooth stack somehow only partially completes the negotiation of a connection. For simplicity we treat this as a disconnection event, so we can perform all the same clean up logic.
     */
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        (currentOperation as? Connect)?.didDisconnectPeripheral()
        clearAfterDisconnect()
    }
    
    
}
