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

protocol Operation: AnyObject {
    var finished: EmptyResponse? { get set }
    
    func start()
}

public class BleModule: NSObject {
    private var cbCentralManager: CBCentralManager!
    
    private var delegate: BleModuleDelegate!
    
    private var operationsQueue = Queue()
    
    private var connectedPeripheral: Peripheral?
    
    private var listeners: [CharacteristicIdentifier: (ReadResult<Data?>) -> Void?] = [:]
    
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
    
    /*private func startOperation(_ operation: Operation) {
        self.currentOperation = operation
        /*self.currentOperation?.finished = { [weak self] in
            self?.currentOperation = nil
        }*/
        self.currentOperation?.start()
    }*/
    private func addOperation(_ operation: Operation) {
        operation.finished = { [weak self] in
            if let first = self?.operationsQueue.first, first === operation {
                operation.finished = nil
                self?.operationsQueue.next()
            }
        }
        operationsQueue.add(operation)
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
        addOperation(scanOperation)
    }
    
    func stopScanning() {
        operationsQueue.operationsOfType(Scan.self).first?.stopScanning()
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
        addOperation(connectOperation)
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
                        try await peripheral.prepareForCharacteristic(characteristicIdentifier)
                        let writeOperation = Write(characteristicIdentifier: characteristicIdentifier, peripheral: peripheral.cbPeripheral, value: value, writeType: type, callback: completion)
                        self.addOperation(writeOperation)
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

// MARK: - Listen
extension BleModule {
    public func listen<R: Receivable>(
        to characteristicIdentifier: CharacteristicIdentifier,
        completion: @escaping (ReadResult<R>) -> Void) {
            /*if let peripheral = connectedPeripheral {
                peripheral.listen(to: characteristicIdentifier, multipleListenOption: option, completion: completion)
            } else {
                print("Cannot request listen on \(characteristicIdentifier.description): \(BleModuleError.notConnected.localizedDescription)")
                completion(.failure(BleModuleError.notConnected))
            }*/
            
            if let peripheral = connectedPeripheral {
                print("Requesting listen on \(characteristicIdentifier.description)...")
                
                Task() {
                    do {
                        try await peripheral.prepareForCharacteristic(characteristicIdentifier)
                        
                        let listenOperation = Listen(characteristicIdentifier: characteristicIdentifier, peripheral: peripheral.cbPeripheral, value: true) { [weak self] result in
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
                        addOperation(listenOperation)
                    }
                }
            } else {
                print("Cannot request listen on \(characteristicIdentifier.description): \(BleModuleError.notConnected.localizedDescription)")
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
        /*if let scan = currentOperation as? Scan {
            scan.discoveredPeripheral(cbPeripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)
        }*/
        operationsQueue.operationsOfType(Scan.self).first?.discoveredPeripheral(cbPeripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        operationsQueue.operationsOfType(Connect.self).first?.didConnectPeripheral()
        //(currentOperation as? Connect)?.didConnectPeripheral()
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        operationsQueue.operationsOfType(Connect.self).first?.didDisconnectPeripheral()
        //(currentOperation as? Connect)?.didDisconnectPeripheral()
        clearAfterDisconnect()
    }
    
    /**
     This mostly happens when either the Bluetooth device or the Core Bluetooth stack somehow only partially completes the negotiation of a connection. For simplicity we treat this as a disconnection event, so we can perform all the same clean up logic.
     */
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        operationsQueue.operationsOfType(Connect.self).first?.didDisconnectPeripheral()
        //(currentOperation as? Connect)?.didDisconnectPeripheral()
        clearAfterDisconnect()
    }
}

extension BleModule: PeripheralDelegate {
    func requestStartOperation(_ operation: Operation) {
        addOperation(operation)
    }
    
    func didDiscoverServices() {
        print("didDiscoverServices")
        operationsQueue.operationsOfType(DiscoverService.self).first?.didDiscoverServices()
        //(currentOperation as? DiscoverService)?.didDiscoverServices()
    }
    
    func didDiscoverCharacteristics() {
        operationsQueue.operationsOfType(DiscoverCharacteristic.self).first?.didDiscoverCharacteristics()
        //(currentOperation as? DiscoverCharacteristic)?.didDiscoverCharacteristics()
    }
    
    func didUpdateCharacteristicNotificationState() {
        operationsQueue.operationsOfType(Listen.self).forEach({
            $0.didUpdateCharacteristicNotificationState()
        })
        //(currentOperation as? Listen)?.didUpdateCharacteristicNotificationState()
    }
    
    func didUpdateValueFor(characteristic: CBCharacteristic, error: Error?) {
        guard let characteristicIdentifier = CharacteristicIdentifier(characteristic) else {
            print("Received value update for characteristic (\(characteristic.uuid.uuidString) without a valid service. Update will be ignored")
            return
        }
        
        guard let listenCallback = listeners[characteristicIdentifier] else { return }
        if let error = error {
            listenCallback(.failure(error))
        } else {
            listenCallback(.success(characteristic.value))
        }
    }
}
