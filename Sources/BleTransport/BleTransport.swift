//
//  BleTransport.swift
//  BleTransport
//
//  Created by Dante Puglisi on 5/11/22.
//

import Foundation
import Bluejay
import CoreBluetooth

public enum BleTransportError: Error {
    case pendingActionOnDevice
    case userRefusedOnDevice
    case writeError(description: String)
    case readError(description: String)
    case lowerLeverError(description: String)
}

@objc public class BleTransport: NSObject, BleTransportProtocol {
    
    let bluejay: Bluejay
    
    /*
    /// IDs
    let nanoXService = ServiceIdentifier(uuid: "13D63400-2C97-0004-0000-4C6564676572")
    fileprivate let notifyCharacteristic = CharacteristicIdentifier(uuid: "13d63400-2c97-0004-0001-4c6564676572", service: ServiceIdentifier(uuid: "13D63400-2C97-0004-0000-4C6564676572"))
    fileprivate let writeCharacteristic = CharacteristicIdentifier(uuid: "13d63400-2c97-0004-0002-4c6564676572", service: ServiceIdentifier(uuid: "13D63400-2C97-0004-0000-4C6564676572"))
    fileprivate let writeWithoutResponseCharacteristic = CharacteristicIdentifier(uuid: "13d63400-2c97-0004-0003-4c6564676572", service: ServiceIdentifier(uuid: "13D63400-2C97-0004-0000-4C6564676572"))
    */
    
    let configuration: BleTransportConfiguration
    var disconnectedCallback: (()->())?
    
    var serviceIDsPerPeripheral = [PeripheralIdentifier: [CBUUID]]()
    var connectedPeripheral: PeripheralIdentifier?
    
    /// Exchange handling
    var exchangeCallback: ((Result<String, BleTransportError>) -> Void)?
    var isExchanging = false
    var currentResponse = ""
    var currentResponseRemainingLength = 0
    
    public var isBluetoothAvailable: Bool {
        bluejay.isBluetoothAvailable
    }
    
    // MARK: - Initialization
    
    @objc
    public required init(configuration: BleTransportConfiguration) {
        self.bluejay = Bluejay()
        self.configuration = configuration
        
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
        self.bluejay.scan(allowDuplicates: true, serviceIdentifiers: self.configuration.services.map({ $0.service }), discovery: { [weak self] discovery, discoveries in
            self?.updateServiceIDsPerPeripheral(discoveries: discoveries)
            callback(discoveries.map({ $0.peripheralIdentifier }))
            return .continue
        }, expired: { [weak self] discovery, discoveries in
            self?.updateServiceIDsPerPeripheral(discoveries: discoveries)
            callback(discoveries.map({ $0.peripheralIdentifier }))
            return .continue
        }, stopped: { [weak self] discoveries, error in
            self?.updateServiceIDsPerPeripheral(discoveries: discoveries)
            stopped()
            if let error = error {
                print("Stopped scanning with error: \(error)")
            }
        })
    }
    
    public func stopScanning() {
        self.bluejay.stopScanning()
    }
    
    /*public func open(withPeripheral peripheral: PeripheralIdentifier, success: @escaping PeripheralResponse, failure: @escaping ErrorResponse) {
        if self.bluejay.isScanning {
            self.bluejay.stopScanning()
        }
        
        self.connectToPeripheral(peripheral, success: success, failure: failure)
    }*/
    
    public func create(disconnectedCallback: @escaping (()->()), success: @escaping PeripheralResponse, failure: @escaping ErrorResponse) {
        scan { [weak self] discoveries in
            guard let firstDiscovery = discoveries.first else { failure(nil); return }
            self?.connect(toPeripheralID: firstDiscovery, disconnectedCallback: disconnectedCallback, success: { [weak self] _ in
                self?.bluejay.stopScanning()
            }, failure: failure)
        } stopped: {
            failure(nil)
        }
    }
    
    public func exchange(apdu apduToSend: APDU, callback: @escaping (Result<String, BleTransportError>) -> Void) {
        guard !isExchanging else {
            callback(.failure(.pendingActionOnDevice))
            return
        }
        
        print("Sending", "->", apduToSend.data.hexEncodedString())
        self.exchangeCallback = callback
        self.isExchanging = true
        self.writeAPDU(apduToSend)
    }
    
    /**
     * Write the next ble frame to the device,  only triggered from the exchange/send methods.
     **/
    fileprivate func writeAPDU(_ apdu: APDU, withResponse: Bool = false) {
        guard !apdu.isEmpty else { return }
        guard self.bluejay.isConnected, let connectedPeripheral = connectedPeripheral else { return }
        guard let peripheralService = configuration.services.first(where: { configService in serviceIDsPerPeripheral[connectedPeripheral]?.contains(configService.service.uuid) == true }) else { return }
        self.bluejay.write(to: withResponse ? peripheralService.writeWithResponse : peripheralService.writeWithoutResponse, value: apdu, type: withResponse ? .withResponse : .withoutResponse) { result in
            switch result {
            case .success:
                apdu.next() /// Advance to next chunck in the `APDU`
                if !apdu.isEmpty {
                    self.writeAPDU(apdu, withResponse: withResponse)
                }
            case .failure(let error):
                if let error = error as? BluejayError, case .missingCharacteristicProperty = error, !withResponse {
                    /// We try a `writeWithResponse` in case the firmware is not updated (`writeWithoutResponse` characteristic was introduced in `2.0.2`)
                    self.writeAPDU(apdu, withResponse: true)
                } else {
                    self.isExchanging = false
                    self.exchangeCallback?(.failure(.writeError(description: error.localizedDescription)))
                }
            }
        }
    }
    
    fileprivate func startListening() {
        self.listen { [weak self] apduReceived in
            guard let self = self else { return }
            /// This might be a partial response
            var offset = 6
            let hex = apduReceived.data.hexEncodedString()
            
            if self.currentResponse == "" {
                offset = 10
                
                let a = hex.index(hex.startIndex, offsetBy: 8)
                let b = hex.index(hex.startIndex, offsetBy: 10)
                let expectedLength = (Int(hex[a..<b], radix: 16) ?? 1) * 2
                self.currentResponseRemainingLength = expectedLength
                print("Expected length is: \(expectedLength)")
            }
            
            let cleanAPDU = hex.suffix(hex.count - offset)
            
            self.currentResponse += cleanAPDU
            self.currentResponseRemainingLength -= cleanAPDU.count
            
            print("Received: \(cleanAPDU)")
            
            if self.currentResponseRemainingLength <= 0 {
                /// We got the full response in `currentResponse`
                self.isExchanging = false
                self.exchangeCallback?(.success(self.currentResponse))
                self.currentResponse = ""
                self.currentResponseRemainingLength = 0
            } else {
                print("WAITING_FOR_NEXT_MESSAGE!!")
            }
        } failure: { [weak self] error in
            if let error = error {
                self?.isExchanging = false
                self?.exchangeCallback?(.failure(.readError(description: error.localizedDescription)))
            }
        }

    }
    
    fileprivate func listen(apduReceived: @escaping APDUResponse, failure: @escaping ErrorResponse) {
        guard let connectedPeripheral = connectedPeripheral else { return }
        guard let peripheralService = configuration.services.first(where: { configService in serviceIDsPerPeripheral[connectedPeripheral]?.contains(configService.service.uuid) == true }) else { return }
        self.bluejay.listen(to: peripheralService.notify, multipleListenOption: .replaceable) { (result: ReadResult<APDU>) in
            switch result {
            case .success(let apdu):
                apduReceived(apdu)
            case .failure(let error):
                failure(error)
            }
        }
    }
    
    public func send(apdu: APDU, success: @escaping (()->()), failure: @escaping ErrorResponse) {
        self.send(apdu: apdu, type: .withResponse, firstPass: true, success: success, failure: failure)
    }
    
    fileprivate func send(apdu: APDU, type: CBCharacteristicWriteType, firstPass: Bool, success: @escaping (()->()), failure: @escaping ErrorResponse) {
        guard let connectedPeripheral = connectedPeripheral else { return }
        guard let peripheralService = configuration.services.first(where: { configService in serviceIDsPerPeripheral[connectedPeripheral]?.contains(configService.service.uuid) == true }) else { return }
        self.bluejay.write(to: type == .withResponse ? peripheralService.writeWithResponse : peripheralService.writeWithoutResponse, value: apdu, type: type) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                success()
            case .failure(let error):
                if firstPass {
                    self.send(apdu: apdu, type: type == .withResponse ? .withoutResponse : .withResponse, firstPass: false, success: success, failure: failure)
                } else {
                    print(error.localizedDescription)
                    failure(error)
                }
            }
        }
    }
    
    public func disconnect(immediate: Bool, completion: @escaping ErrorResponse) {
        self.bluejay.disconnect(immediate: immediate) { [weak self] result in
            switch result {
            case .disconnected(_):
                self?.connectedPeripheral = nil
                completion(nil)
            case .failure(let error):
                completion(error)
            }
        }
    }
    
    public func connect(toPeripheralID peripheral: PeripheralIdentifier, disconnectedCallback: (()->())?, success: @escaping PeripheralResponse, failure: @escaping ErrorResponse) {
        if self.bluejay.isScanning {
            self.bluejay.stopScanning()
        }
        self.disconnectedCallback = disconnectedCallback
        self.bluejay.connect(peripheral, timeout: Timeout.seconds(15), warningOptions: nil) { [weak self] result in
            switch result {
            case .success(let peripheralIdentifier):
                self?.connectedPeripheral = peripheralIdentifier
                self?.startListening()
                success(peripheralIdentifier)
            case .failure(let error):
                failure(error)
            }
        }
    }
    
    
    // MARK: - Private methods
    
    fileprivate func updateServiceIDsPerPeripheral(discoveries: [ScanDiscovery]) {
        serviceIDsPerPeripheral.removeAll()
        for discovery in discoveries {
            let peripheral = discovery.peripheralIdentifier
            if let services = discovery.advertisementPacket["kCBAdvDataServiceUUIDs"] as? [CBUUID] {
                serviceIDsPerPeripheral[peripheral] = services
            }
        }
    }
}

extension BleTransport: ConnectionObserver {
    public func disconnected(from peripheral: PeripheralIdentifier) {
        connectedPeripheral = nil
        disconnectedCallback?()
    }
}

extension BleTransport: LogObserver {
    public func debug(_ text: String) {
        
    }
}
