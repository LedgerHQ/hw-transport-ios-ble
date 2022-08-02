//
//  File.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/2/22.
//

import Foundation
import CoreBluetooth

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
    
    func scan(duration: TimeInterval,
              throttleRSSIDelta: Int = 5,
              serviceIdentifiers: [ServiceIdentifier],
              discovery: @escaping (ScanDiscovery, [ScanDiscovery]) -> ScanAction,
              expired: ((ScanDiscovery, [ScanDiscovery]) -> ScanAction)? = nil,
              stopped: @escaping ([ScanDiscovery], Error?, Bool) -> Void) {
        let scanOperation = Scan(duration: duration, throttleRSSIDelta: throttleRSSIDelta, serviceIdentifiers: serviceIdentifiers, discovery: discovery, expired: expired, stopped: stopped, manager: cbCentralManager)
        self.currentOperation = scanOperation
        scanOperation.finished = { [weak self] in
            self?.currentOperation = nil
        }
        scanOperation.start()
    }
    
    func stopScanning() {
        (currentOperation as? Scan)?.stopScanning()
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
}
