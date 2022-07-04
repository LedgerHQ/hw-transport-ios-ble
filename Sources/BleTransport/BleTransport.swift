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
    
    public func description() -> String {
        switch self {
        case .pendingActionOnDevice:
            return "Pending action on device"
        case .userRefusedOnDevice:
            return "User refused on device"
        case .writeError(let description):
            return "Write error: \(description)"
        case .readError(let description):
            return "Read error: \(description)"
        case .lowerLeverError(let description):
            return "Lower level error: \(description)"
        }
    }
}

@objc public class BleTransport: NSObject, BleTransportProtocol {
    
    public static var shared: BleTransportProtocol = BleTransport(configuration: nil, debugMode: false)
    
    private let bluejay: Bluejay
    
    private let configuration: BleTransportConfiguration
    private var disconnectedCallback: (()->())?
    
    private var peripheralsServicesTuple = [(peripheral: PeripheralIdentifier, serviceUUID: CBUUID)]()
    private var connectedPeripheral: PeripheralIdentifier?
    
    /// Exchange handling
    private var exchangeCallback: ((Result<String, BleTransportError>) -> Void)?
    private var isExchanging = false
    private var currentResponse = ""
    private var currentResponseRemainingLength = 0
    
    /// Infer MTU
    private var mtuWaitingForCallback: PeripheralResponse?
    
    @objc
    public var isBluetoothAvailable: Bool {
        bluejay.isBluetoothAvailable
    }
    
    // MARK: - Initialization
    
    @objc
    public required init(configuration: BleTransportConfiguration?, debugMode: Bool) {
        self.bluejay = Bluejay()
        self.configuration = configuration ?? BleTransportConfiguration.defaultConfig()
        
        super.init()
        
        self.bleInit(debugMode: debugMode)
    }
    
    fileprivate func bleInit(debugMode: Bool) {
        if !debugMode {
            self.bluejay.register(logObserver: self)
        }
        self.bluejay.start()
    }
    
    // MARK: - Public Methods
    
    public func scan(callback: @escaping PeripheralsWithServicesResponse, stopped: @escaping (()->())) {
        guard !self.bluejay.isScanning else { return }
        self.bluejay.scan(allowDuplicates: true, serviceIdentifiers: self.configuration.services.map({ $0.service }), discovery: { [weak self] discovery, discoveries in
            guard let self = self else { return .continue }
            if self.updatePeripheralsServicesTuple(discoveries: discoveries) {
                callback(self.peripheralsServicesTuple)
            }
            return .continue
        }, expired: { [weak self] discovery, discoveries in
            guard let self = self else { return .continue }
            if self.updatePeripheralsServicesTuple(discoveries: discoveries) {
                callback(self.peripheralsServicesTuple)
            }
            return .continue
        }, stopped: { [weak self] discoveries, error in
            guard let self = self else { return }
            if self.updatePeripheralsServicesTuple(discoveries: discoveries) {
                stopped()
            }
            if let error = error {
                print("Stopped scanning with error: \(error)")
            }
        })
    }
    
    @objc
    public func stopScanning() {
        self.bluejay.stopScanning()
    }
    
    public func create(disconnectedCallback: @escaping (()->()), success: @escaping PeripheralResponse, failure: @escaping ErrorResponse) {
        scan { [weak self] discoveries in
            guard let firstDiscovery = discoveries.first else { failure(nil); return }
            self?.connect(toPeripheralID: firstDiscovery.peripheral, disconnectedCallback: disconnectedCallback, success: { [weak self] _ in
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
        guard let peripheralService = configuration.services.first(where: { configService in peripheralsServicesTuple.first(where: { $0.peripheral.uuid == connectedPeripheral.uuid })?.serviceUUID == configService.service.uuid }) else { return }
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
            if self.mtuWaitingForCallback != nil {
                self.parseMTUresponse(apduReceived: apduReceived)
                self.mtuWaitingForCallback = nil
                return
            }
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
                self?.exchangeCallback?(.failure(.readError(description: error.localizedDescription)))
            }
            self?.isExchanging = false
        }
    }
    
    fileprivate func listen(apduReceived: @escaping APDUResponse, failure: @escaping ErrorResponse) {
        guard let connectedPeripheral = connectedPeripheral else { return }
        guard let peripheralService = configuration.services.first(where: { configService in peripheralsServicesTuple.first(where: { $0.peripheral.uuid == connectedPeripheral.uuid })?.serviceUUID == configService.service.uuid }) else { return }
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
        self.send(value: apdu, type: .withoutResponse, firstPass: true, success: success, failure: failure)
    }
    
    fileprivate func send<S: Sendable>(value: S, type: CBCharacteristicWriteType, firstPass: Bool, success: @escaping (()->()), failure: @escaping ErrorResponse) {
        guard let connectedPeripheral = connectedPeripheral else { return }
        guard let peripheralService = configuration.services.first(where: { configService in peripheralsServicesTuple.first(where: { $0.peripheral.uuid == connectedPeripheral.uuid })?.serviceUUID == configService.service.uuid }) else { return }
        self.bluejay.write(to: type == .withResponse ? peripheralService.writeWithResponse : peripheralService.writeWithoutResponse, value: value, type: type) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                success()
            case .failure(let error):
                if firstPass {
                    self.send(value: value, type: type == .withResponse ? .withoutResponse : .withResponse, firstPass: false, success: success, failure: failure)
                } else {
                    print(error.localizedDescription)
                    failure(error)
                }
            }
        }
    }
    
    @objc
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
                self?.mtuWaitingForCallback = success
                self?.inferMTU()
                //self?.inferMTU(peripheral: peripheralIdentifier)
                //success(peripheralIdentifier)
            case .failure(let error):
                failure(error)
            }
        }
    }
    
    
    // MARK: - Private methods
    
    /// Updates the current list of peripherals matching them with their service.
    ///
    /// - Parameter discoveries: All the current devices.
    /// - Returns: A boolean indicating whether the last changed since the last update.
    fileprivate func updatePeripheralsServicesTuple(discoveries: [ScanDiscovery]) -> Bool {
        //peripheralsServicesTuple.removeAll()
        var auxPeripherals = [(peripheral: PeripheralIdentifier, serviceUUID: CBUUID)]()
        for discovery in discoveries {
            let peripheral = discovery.peripheralIdentifier
            if let services = discovery.advertisementPacket["kCBAdvDataServiceUUIDs"] as? [CBUUID], let firstService = services.first {
                auxPeripherals.append((peripheral: peripheral, serviceUUID: firstService))
            }
        }
        
        let somethingChanged = auxPeripherals.map({ $0.peripheral }) == peripheralsServicesTuple.map({ $0.peripheral })
        
        peripheralsServicesTuple = auxPeripherals
        
        return somethingChanged
    }
    
    fileprivate func inferMTU() {
        send(value: Data([0x08,0x00,0x00,0x00,0x00]), type: .withoutResponse, firstPass: true) {
            
        } failure: { error in
            print("Error infering MTU: \(error?.localizedDescription ?? "no error")")
        }

    }
    
    fileprivate func parseMTUresponse(apduReceived: APDU) {
        if apduReceived.data.first == 0x08 {
            if let fifthByte = apduReceived.data.advanced(by: 5).first {
                APDU.mtuSize = Int(fifthByte)
            }
        }
        if let connectedPeripheral = connectedPeripheral {
            mtuWaitingForCallback?(connectedPeripheral)
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
