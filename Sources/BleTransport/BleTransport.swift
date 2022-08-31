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
    case connectError(description: String)
    case writeError(description: String)
    case readError(description: String)
    case listenError(description: String)
    case scanError(description: String)
    case pairingError(description: String)
    case lowerLevelError(description: String)
    
    public func description() -> String {
        switch self {
        case .pendingActionOnDevice:
            return "Pending action on device"
        case .userRefusedOnDevice:
            return "User refused on device"
        case .connectError(let description):
            return "Connect error: \(description)"
        case .writeError(let description):
            return "Write error: \(description)"
        case .readError(let description):
            return "Read error: \(description)"
        case .listenError(let description):
            return "Listen error: \(description)"
        case .scanError(let description):
            return "Scan error: \(description)"
        case .pairingError(let description):
            return "Pairing error: \(description)"
        case .lowerLevelError(let description):
            return "Lower level error: \(description)"
        }
    }
}

@objc public class BleTransport: NSObject, BleTransportProtocol {
    
    public static var shared: BleTransportProtocol = BleTransport(configuration: nil, debugMode: false)
    
    private let bluejay: Bluejay
    
    private let configuration: BleTransportConfiguration
    private var disconnectedCallback: (()->())?
    private var connectFailure: ((BleTransportError)->())?
    
    private var peripheralsServicesTuple = [PeripheralInfoTuple]()
    private var connectedPeripheral: PeripheralIdentifier?
    private var bluetoothAvailabilityCompletion: ((Bool)->())?
    private var notifyDisconnectedCompletion: EmptyResponse?
    
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
    
    @objc
    public var isConnected: Bool {
        connectedPeripheral != nil
    }
    
    // MARK: - Initialization
    
    private init(configuration: BleTransportConfiguration?, debugMode: Bool) {
        self.bluejay = Bluejay()
        self.configuration = configuration ?? BleTransportConfiguration.defaultConfig()
        
        super.init()

        self.bleInit(debugMode: debugMode)
    }
    
    fileprivate func bleInit(debugMode: Bool) {
        if !debugMode {
            self.bluejay.register(logObserver: self)
        }
        self.bluejay.register(connectionObserver: self)
        self.bluejay.registerDisconnectHandler(handler: self)
        self.bluejay.start()
    }
    
    // MARK: - Public Methods
    
    public func scan(callback: @escaping PeripheralsWithServicesResponse, stopped: @escaping OptionalErrorResponse) {
        DispatchQueue.main.async {
            if self.bluejay.isScanning {
                self.bluejay.stopScanning()
            }
            
            if self.bluejay.isConnected {
                self.bluejay.disconnect()
            }
            
            self.peripheralsServicesTuple = [] /// We clean `peripheralsServicesTuple` at the start of each scan so the changes can be properly propagated and not before because it has info needed for connecting and writing to devices
            
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
                self.updatePeripheralsServicesTuple(discoveries: discoveries)
                if let error = error {
                    print("Stopped scanning with error: \(error)")
                    stopped(.scanError(description: error.localizedDescription))
                } else {
                    stopped(nil)
                }
            })
        }
    }
    
    @objc
    public func stopScanning() {
        DispatchQueue.main.async {
            self.bluejay.stopScanning()
        }
    }
    
    public func create(timeout: Timeout, disconnectedCallback: @escaping (()->()), success: @escaping PeripheralResponse, failure: @escaping ErrorResponse) {
        DispatchQueue.main.async {
            self.scan { [weak self] discoveries in
                guard let firstDiscovery = discoveries.first else { return }
                self?.connect(toPeripheralID: firstDiscovery.peripheral, timeout: timeout, disconnectedCallback: disconnectedCallback, success: { [weak self] connectedPeripheral in
                    if self?.bluejay.isScanning == true {
                        self?.bluejay.stopScanning()
                    }
                    success(connectedPeripheral)
                }, failure: failure)
            } stopped: { error in
                if let error = error {
                    failure(error)
                }
            }
        }
    }
    
    public func exchange(apdu apduToSend: APDU, callback: @escaping (Result<String, BleTransportError>) -> Void) {
        DispatchQueue.main.async {
            guard !self.isExchanging else {
                callback(.failure(.pendingActionOnDevice))
                return
            }
            
            print("Sending", "->", apduToSend.data.hexEncodedString())
            self.exchangeCallback = callback
            self.isExchanging = true
            self.writeAPDU(apduToSend)
        }
    }
    
    public func exchange(apdu apduToSend: APDU) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            exchange(apdu: apduToSend) { result in
                switch result {
                case .success(let response):
                    continuation.resume(returning: response)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func send(apdu: APDU, success: @escaping (()->()), failure: @escaping ErrorResponse) {
        DispatchQueue.main.async {
            self.send(value: apdu, success: success, failure: failure)
        }
    }
    
    public func send(apdu: APDU) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            send(apdu: apdu) {
                continuation.resume()
            } failure: { error in
                continuation.resume(throwing: error)
            }

        }
    }
    
    /// The inner implementation of `send`
    /// - Parameters:
    ///   - value: APDU to send
    ///   - retryWithResponse: Used internally in the function if `writeWithoutResponse` fails the first time
    ///   - success: The success callback
    ///   - failure: The failue callback
    fileprivate func send<S: Sendable>(value: S, retryWithResponse: Bool = false, success: @escaping (()->()), failure: @escaping ErrorResponse) {
        guard self.bluejay.isConnected, let connectedPeripheral = connectedPeripheral else { failure(.writeError(description: "Not connected")); return }
        guard let connectedPeripheralTuple = peripheralsServicesTuple.first(where: { $0.peripheral.uuid == connectedPeripheral.uuid }) else { self.exchangeCallback?(.failure(.writeError(description: "peripheralsServiceTuple doesn't contain conencted peripheral UUID"))); return }
        guard let peripheralService = configuration.services.first(where: { configService in connectedPeripheralTuple.serviceUUID == configService.service.uuid }) else { failure(.writeError(description: "No matching peripheralService")); return }
        let writeCharacteristic: CharacteristicIdentifier
        let type: CBCharacteristicWriteType
        if let canWriteWithoutCharacteristic = connectedPeripheralTuple.canWriteWithoutResponse {
            writeCharacteristic = peripheralService.writeCharacteristic(canWriteWithoutResponse: canWriteWithoutCharacteristic)
            type = canWriteWithoutCharacteristic ? .withoutResponse : .withResponse
        } else {
            writeCharacteristic = retryWithResponse ? peripheralService.writeWithResponse : peripheralService.writeWithoutResponse
            type = retryWithResponse ? .withResponse : .withoutResponse
        }
        self.bluejay.write(to: writeCharacteristic, value: value, type: type) { [weak self] result in
            guard let self = self else { failure(.writeError(description: "Self got deallocated")); return }
            switch result {
            case .success:
                if connectedPeripheralTuple.canWriteWithoutResponse == nil {
                    if let tupleIndex = self.peripheralsServicesTuple.firstIndex(where: { $0.peripheral.uuid == connectedPeripheral.uuid }) {
                        self.peripheralsServicesTuple[tupleIndex].canWriteWithoutResponse = type == .withoutResponse
                    }
                }
                success()
            case .failure(let error):
                if connectedPeripheralTuple.canWriteWithoutResponse == nil {
                    self.send(value: value, retryWithResponse: true, success: success, failure: failure)
                } else {
                    print(error.localizedDescription)
                    failure(.writeError(description: error.localizedDescription))
                }
            }
        }
    }
    
    public func disconnect(immediate: Bool, completion: OptionalErrorResponse?) {
        self.bluejay.disconnect(immediate: immediate) { [weak self] result in
            switch result {
            case .disconnected(_):
                self?.connectedPeripheral = nil
                completion?(nil)
            case .failure(let error):
                completion?(.lowerLevelError(description: error.localizedDescription))
            }
        }
    }
    
    public func disconnect(immediate: Bool) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            disconnect(immediate: immediate) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    public func connect(toPeripheralID peripheral: PeripheralIdentifier, timeout: Timeout, disconnectedCallback: (()->())?, success: @escaping PeripheralResponse, failure: @escaping ErrorResponse) {
        if self.bluejay.isScanning {
            self.bluejay.stopScanning()
        }
        self.disconnectedCallback = disconnectedCallback
        
        let connect = {
            self.bluejay.connect(peripheral, timeout: Timeout.seconds(5), warningOptions: nil) { [weak self] result in
                switch result {
                case .success(let peripheralIdentifier):
                    self?.connectedPeripheral = peripheralIdentifier
                    self?.connectFailure = failure
                    self?.startListening()
                    self?.mtuWaitingForCallback = success
                    self?.inferMTU()
                case .failure(let error):
                    failure(.connectError(description: error.localizedDescription))
                }
            }
        }
        
        if !peripheralsServicesTuple.contains(where: { $0.peripheral == peripheral }) {
            scanAndDiscoverBeforeConnecting(lookingFor: peripheral, connectFunction: connect, failure: failure)
        } else {
            connect()
        }
    }
    
    public func bluetoothAvailabilityCallback(completion: @escaping ((Bool)->())) {
        completion(isBluetoothAvailable)
        bluetoothAvailabilityCompletion = completion
    }
    
    public func notifyDisconnected(completion: @escaping EmptyResponse) {
        if !isConnected {
            completion()
        } else {
            notifyDisconnectedCompletion = completion
        }
    }
    
    // MARK: - Private methods
    
    /// Updates the current list of peripherals matching them with their service.
    ///
    /// - Parameter discoveries: All the current devices.
    /// - Returns: A boolean indicating whether the last changed since the last update.
    @discardableResult
    fileprivate func updatePeripheralsServicesTuple(discoveries: [ScanDiscovery]) -> Bool {
        var auxPeripherals = [PeripheralInfoTuple]()
        for discovery in discoveries {
            let peripheral = discovery.peripheralIdentifier
            if let services = discovery.advertisementPacket["kCBAdvDataServiceUUIDs"] as? [CBUUID], let firstService = services.first {
                auxPeripherals.append((peripheral: peripheral, rssi: discovery.rssi, serviceUUID: firstService, canWriteWithoutResponse: nil))
            }
        }
        
        let somethingChanged = auxPeripherals.map({ $0.peripheral }) != peripheralsServicesTuple.map({ $0.peripheral })
        
        peripheralsServicesTuple = auxPeripherals
        
        return somethingChanged
    }
    
    fileprivate func scanAndDiscoverBeforeConnecting(lookingFor: PeripheralIdentifier, connectFunction: @escaping ()->(), failure: @escaping ErrorResponse) {
        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            self.stopScanning()
            failure(.connectError(description: "Couldn't find peripheral when scanning, timed out"))
        }
        
        scan { [weak self] discoveries in
            if discoveries.contains(where: { $0.peripheral == lookingFor }) {
                timer.invalidate()
                connectFunction()
                self?.stopScanning()
            }
        } stopped: { error in
            if let error = error {
                failure(.connectError(description: "Couldn't find peripheral when scanning because of error: \(error.description())"))
            }
        }

    }
    
    /**
     * Write the next ble frame to the device,  only triggered from the exchange/send methods.
     **/
    fileprivate func writeAPDU(_ apdu: APDU, withResponse: Bool = false) {
        guard !apdu.isEmpty else { self.exchangeCallback?(.failure(.writeError(description: "APDU is empty"))); return }
        send(apdu: apdu) {
            apdu.next()
            if !apdu.isEmpty {
                self.writeAPDU(apdu)
            }
        } failure: { error in
            self.isExchanging = false
            self.exchangeCallback?(.failure(.writeError(description: error.description())))
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
                
                let a = hex.index(hex.startIndex, offsetBy: 6)
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
            if case .pairingError = error {
                self?.connectFailure?(error)
                self?.disconnect(immediate: false, completion: nil)
            } else {
                self?.exchangeCallback?(.failure(error))
            }
            self?.isExchanging = false
        }
    }
    
    fileprivate func listen(apduReceived: @escaping APDUResponse, failure: @escaping ErrorResponse) {
        guard let connectedPeripheral = connectedPeripheral else { failure(.listenError(description: "Not connected")); return }
        guard let peripheralService = configuration.services.first(where: { configService in peripheralsServicesTuple.first(where: { $0.peripheral.uuid == connectedPeripheral.uuid })?.serviceUUID == configService.service.uuid }) else { failure(.listenError(description: "No matching peripheralService")); return }
        self.bluejay.listen(to: peripheralService.notify, multipleListenOption: .replaceable) { (result: ReadResult<APDU>) in
            switch result {
            case .success(let apdu):
                apduReceived(apdu)
            case .failure(let error):
                if (error as NSError).code == CBATTError.insufficientEncryption.rawValue {
                    failure(.pairingError(description: error.localizedDescription))
                } else {
                    failure(.listenError(description: error.localizedDescription))
                }
            }
        }
    }
    
    fileprivate func inferMTU() {
        send(value: Data([0x08,0x00,0x00,0x00,0x00])) {
            
        } failure: { error in
            print("Error infering MTU: \(error.description())")
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
    
    fileprivate func clearConnection() {
        connectedPeripheral = nil
        isExchanging = false
        notifyDisconnectedCompletion?()
        notifyDisconnectedCompletion = nil /// We call `notifyDisconnectedCompletion` only once since it's used to be notified about the next disconnection not all of them
        disconnectedCallback?()
    }
}

extension BleTransport: ConnectionObserver {
    public func disconnected(from peripheral: PeripheralIdentifier) {
        clearConnection()
    }
    
    public func bluetoothAvailable(_ available: Bool) {
        bluetoothAvailabilityCompletion?(available)
        if !available {
            clearConnection()
        }
    }
}

extension BleTransport: DisconnectHandler {
    public func didDisconnect(from peripheral: PeripheralIdentifier, with error: Error?, willReconnect autoReconnect: Bool) -> AutoReconnectMode {
        return .change(shouldAutoReconnect: false)
    }
}

extension BleTransport: LogObserver {
    public func debug(_ text: String) {
        
    }
}

func print(_ object: Any) {
    #if DEBUG
    Swift.print("BleTransport", object)
    #endif
}
