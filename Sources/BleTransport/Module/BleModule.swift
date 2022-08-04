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
    
    private var connectedPeripheral: Peripheral?
    
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
        let connectOperation = Connect(peripheralIdentifier: peripheralIdentifier, manager: cbCentralManager, timeout: timeout, callback: { [weak self] result in
            guard let self = self else { callback(.failure(BleModuleError.selfIsNil)); return }
            if case .success(let cbPeripheral) = result {
                self.connectedPeripheral = Peripheral(delegate: self, cbPeripheral: cbPeripheral)
            }
            callback(result)
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
                Task() {
                    do {
                        try await peripheral.discoverService(characteristicIdentifier.service)
                        try await peripheral.discoverCharacteristic(characteristicIdentifier)
                        let writeOperation = Write(characteristicIdentifier: characteristicIdentifier, peripheral: peripheral.cbPeripheral, value: value, type: type, callback: completion)
                        self.startOperation(writeOperation)
                    } catch {
                        completion(.failure(error))
                    }
                }
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

extension BleModule: PeripheralDelegate {
    func requestStartOperation(_ operation: Operation) {
        startOperation(operation)
    }
    
    func didDiscoverServices() {
        (currentOperation as? DiscoverService)?.didDiscoverServices()
    }
    
    func didDiscoverCharacteristics() {
        (currentOperation as? DiscoverCharacteristic)?.didDiscoverCharacteristics()
    }
}
