//
//  BleTransport.swift
//  BleTransport
//
//  Created by Dante Puglisi on 5/11/22.
//

import Foundation
import Bluejay
import CoreBluetooth

/// Errors thrown when scanning/sending/receiving/connecting
public enum BleTransportError: LocalizedError {
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

/// Errors received as `status` sent in a message from a device
public enum BleStatusError: LocalizedError {
    case userRejected
    case appNotAvailableInDevice
    case noStatus
    case formatNotSupported
    case couldNotParseResponseData
    case unknown
}

@objc public class BleTransport: NSObject, BleTransportProtocol {
    
    public static var shared: BleTransportProtocol = BleTransport(configuration: nil, debugMode: false)
    
    private let bluejay: Bluejay
    
    private let configuration: BleTransportConfiguration
    private var disconnectedCallback: EmptyResponse? /// Once `disconnectCallback` is set it never becomes `nil` again so we can reuse it in methods where we reconnect to the device blindly like `openApp/closeApp`
    private var connectFailure: ((BleTransportError)->())?
    
    private var scanDuration: TimeInterval = 5.0 /// `scanDuration` will be overriden every time a value gets passed to `scan/create`
    
    private var devicesServicesTuple = [DeviceInfoTuple]()
    private var connectedDevice: DeviceIdentifier?
    private var bluetoothAvailabilityCompletion: ((Bool)->())?
    private var notifyDisconnectedCompletion: EmptyResponse?
    
    /// Exchange handling
    private var exchangeCallback: ((Result<String, BleTransportError>) -> Void)?
    private var isExchanging = false
    private var currentResponse = ""
    private var currentResponseRemainingLength = 0
    
    /// Infer MTU
    private var mtuWaitingForCallback: DeviceResponse?
    
    @objc
    public var isBluetoothAvailable: Bool {
        bluejay.isBluetoothAvailable
    }
    
    @objc
    public var isConnected: Bool {
        connectedDevice != nil
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
    
    public func scan(duration: TimeInterval, callback: @escaping DevicesWithServicesResponse, stopped: @escaping OptionalBleErrorResponse) {
        DispatchQueue.main.async {
            if self.bluejay.isScanning {
                self.bluejay.stopScanning()
            }
            
            if self.bluejay.isConnected {
                self.bluejay.disconnect()
            }
            
            self.devicesServicesTuple = [] /// We clean `devicesServicesTuple` at the start of each scan so the changes can be properly propagated and not before because it has info needed for connecting and writing to devices
            
            self.bluejay.scan(duration: duration, allowDuplicates: true, serviceIdentifiers: self.configuration.services.map({ $0.service }), discovery: { [weak self] discovery, discoveries in
                guard let self = self else { return .continue }
                if self.updateDevicesServicesTuple(discoveries: discoveries) {
                    callback(self.devicesServicesTuple)
                }
                return .continue
            }, expired: { [weak self] discovery, discoveries in
                guard let self = self else { return .continue }
                if self.updateDevicesServicesTuple(discoveries: discoveries) {
                    callback(self.devicesServicesTuple)
                }
                return .continue
            }, stopped: { [weak self] discoveries, error in
                guard let self = self else { return }
                self.updateDevicesServicesTuple(discoveries: discoveries)
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
    
    public func create(scanDuration: TimeInterval, disconnectedCallback: @escaping EmptyResponse, success: @escaping DeviceResponse, failure: @escaping BleErrorResponse) {
        self.scanDuration = scanDuration
        
        var connecting = false
        
        func attemptConnecting(deviceInfo: DeviceInfoTuple) {
            connect(toDeviceID: deviceInfo.device, disconnectedCallback: disconnectedCallback, success: { connectedDevice in
                success(connectedDevice)
            }, failure: failure)
        }
        
        self.scan(duration: scanDuration) { discoveries in
            guard let firstDiscovery = discoveries.first else { return }
            if !connecting {
                connecting = true
                attemptConnecting(deviceInfo: firstDiscovery)
            }
        } stopped: { error in
            if let error = error {
                failure(error)
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
    
    public func send(apdu: APDU, success: @escaping EmptyResponse, failure: @escaping BleErrorResponse) {
        DispatchQueue.main.async {
            self.send(value: apdu, success: success, failure: failure)
        }
    }
    
    /// The inner implementation of `send`
    /// - Parameters:
    ///   - value: APDU to send
    ///   - retryWithResponse: Used internally in the function if `writeWithoutResponse` fails the first time
    ///   - success: The success callback
    ///   - failure: The failue callback
    fileprivate func send<S: Sendable>(value: S, retryWithResponse: Bool = false, success: @escaping EmptyResponse, failure: @escaping BleErrorResponse) {
        guard self.bluejay.isConnected, let connectedDevice = connectedDevice else { failure(.writeError(description: "Not connected")); return }
        guard let connectedDeviceTuple = devicesServicesTuple.first(where: { $0.device.uuid == connectedDevice.uuid }) else { self.exchangeCallback?(.failure(.writeError(description: "devicesServiceTuple doesn't contain conencted device UUID"))); return }
        guard let deviceService = configuration.services.first(where: { configService in connectedDeviceTuple.serviceUUID == configService.service.uuid }) else { failure(.writeError(description: "No matching deviceService")); return }
        let writeCharacteristic: CharacteristicIdentifier
        let type: CBCharacteristicWriteType
        if let canWriteWithoutCharacteristic = connectedDeviceTuple.canWriteWithoutResponse {
            writeCharacteristic = deviceService.writeCharacteristic(canWriteWithoutResponse: canWriteWithoutCharacteristic)
            type = canWriteWithoutCharacteristic ? .withoutResponse : .withResponse
        } else {
            writeCharacteristic = retryWithResponse ? deviceService.writeWithResponse : deviceService.writeWithoutResponse
            type = retryWithResponse ? .withResponse : .withoutResponse
        }
        self.bluejay.write(to: writeCharacteristic, value: value, type: type) { [weak self] result in
            guard let self = self else { failure(.writeError(description: "Self got deallocated")); return }
            switch result {
            case .success:
                if connectedDeviceTuple.canWriteWithoutResponse == nil {
                    if let tupleIndex = self.devicesServicesTuple.firstIndex(where: { $0.device.uuid == connectedDevice.uuid }) {
                        self.devicesServicesTuple[tupleIndex].canWriteWithoutResponse = type == .withoutResponse
                    }
                }
                success()
            case .failure(let error):
                if connectedDeviceTuple.canWriteWithoutResponse == nil {
                    self.send(value: value, retryWithResponse: true, success: success, failure: failure)
                } else {
                    print(error.localizedDescription)
                    failure(.writeError(description: error.localizedDescription))
                }
            }
        }
    }
    
    public func disconnect(immediate: Bool, completion: OptionalBleErrorResponse?) {
        self.bluejay.disconnect(immediate: immediate) { [weak self] result in
            switch result {
            case .disconnected(_):
                self?.connectedDevice = nil
                completion?(nil)
            case .failure(let error):
                completion?(.lowerLevelError(description: error.localizedDescription))
            }
        }
    }
    
    public func connect(toDeviceID device: DeviceIdentifier, disconnectedCallback: EmptyResponse?, success: @escaping DeviceResponse, failure: @escaping BleErrorResponse) {
        if self.bluejay.isScanning {
            self.bluejay.stopScanning()
        }
        self.disconnectedCallback = disconnectedCallback
        
        let connect = {
            self.bluejay.connect(device.toPeripheralIdentifier(), timeout: .seconds(5), warningOptions: nil) { [weak self] result in
                switch result {
                case .success(let peripheralIdentifier):
                    self?.connectedDevice = DeviceIdentifier(peripheralIdentifier: peripheralIdentifier)
                    self?.connectFailure = failure
                    self?.startListening()
                    self?.mtuWaitingForCallback = success
                    self?.inferMTU()
                case .failure(let error):
                    failure(.connectError(description: error.localizedDescription))
                }
            }
        }
        
        if !devicesServicesTuple.contains(where: { $0.device == device }) {
            scanAndDiscoverBeforeConnecting(lookingFor: device, connectFunction: connect, failure: failure)
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
    
    public func getAppAndVersion(success: @escaping ((AppInfo)->()), failure: @escaping ErrorResponse) {
        let apdu = APDU(data: [0xb0, 0x01, 0x00, 0x00])
        exchange(apdu: apdu) { result in
            switch result {
            case .success(let string):
                let data = string.UInt8Array()
                var i = 0
                let format = data[i]
                if format != 1 {
                    failure(BleStatusError.formatNotSupported)
                    return
                }
                i += 1
                let nameLength = Int(data[i])
                i += 1
                let nameData = data[i..<i+Int(nameLength)]
                i += nameLength
                let versionLength = Int(data[i])
                i += 1
                let versionData = data[i..<i+Int(versionLength)]
                i += versionLength
                guard let name = String(data: Data(nameData), encoding: .ascii) else { failure(BleStatusError.couldNotParseResponseData); return }
                guard let version = String(data: Data(versionData), encoding: .ascii) else { failure(BleStatusError.couldNotParseResponseData); return }
                success(AppInfo(name: name, version: version))
            case .failure(let error):
                failure(error)
            }
        }
    }
    
    public func openAppIfNeeded(_ name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Task() {
            do {
                let currentAppInfo = try await getAppAndVersion()
                if currentAppInfo.name != name {
                    if currentAppInfo.name == "BOLOS" {
                        try await openApp(name)
                        completion(.success(()))
                    } else {
                        try await closeApp()
                        try await openApp(name)
                        completion(.success(()))
                    }
                } else {
                    completion(.success(()))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    
    // MARK: - Private methods
    
    /// Updates the current list of devices matching them with their service.
    ///
    /// - Parameter discoveries: All the current devices.
    /// - Returns: A boolean indicating whether the last changed since the last update.
    @discardableResult
    fileprivate func updateDevicesServicesTuple(discoveries: [ScanDiscovery]) -> Bool {
        var auxDevices = [DeviceInfoTuple]()
        for discovery in discoveries {
            let device = DeviceIdentifier(peripheralIdentifier: discovery.peripheralIdentifier)
            if let services = discovery.advertisementPacket["kCBAdvDataServiceUUIDs"] as? [CBUUID], let firstService = services.first {
                auxDevices.append((device: device, rssi: discovery.rssi, serviceUUID: firstService, canWriteWithoutResponse: nil))
            }
        }
        
        let somethingChanged = auxDevices.map({ $0.device }) != devicesServicesTuple.map({ $0.device })
        
        devicesServicesTuple = auxDevices
        
        return somethingChanged
    }
    
    fileprivate func scanAndDiscoverBeforeConnecting(lookingFor: DeviceIdentifier, connectFunction: @escaping ()->(), failure: @escaping BleErrorResponse) {
        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            self.stopScanning()
            failure(.connectError(description: "Couldn't find device when scanning, timed out"))
        }
        
        scan(duration: scanDuration) { [weak self] discoveries in
            if discoveries.contains(where: { $0.device == lookingFor }) {
                timer.invalidate()
                connectFunction()
                self?.stopScanning()
            }
        } stopped: { error in
            if let error = error {
                failure(.connectError(description: "Couldn't find device when scanning because of error: \(error.description())"))
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
    
    fileprivate func listen(apduReceived: @escaping APDUResponse, failure: @escaping BleErrorResponse) {
        guard let connectedDevice = connectedDevice else { failure(.listenError(description: "Not connected")); return }
        guard let deviceService = configuration.services.first(where: { configService in devicesServicesTuple.first(where: { $0.device.uuid == connectedDevice.uuid })?.serviceUUID == configService.service.uuid }) else { failure(.listenError(description: "No matching deviceService")); return }
        self.bluejay.listen(to: deviceService.notify, multipleListenOption: .replaceable) { (result: ReadResult<APDU>) in
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
        if let connectedDevice = connectedDevice {
            mtuWaitingForCallback?(connectedDevice)
        }
    }
    
    fileprivate func clearConnection() {
        connectedDevice = nil
        isExchanging = false
        notifyDisconnectedCompletion?()
        notifyDisconnectedCompletion = nil /// We call `notifyDisconnectedCompletion` only once since it's used to be notified about the next disconnection not all of them
        disconnectedCallback?()
    }
    
    fileprivate func openApp(_ name: String, success: @escaping EmptyResponse, failure: @escaping ErrorResponse) {
        let errorCodes: [BleStatusError: [String]] = [.userRejected: ["6985", "5501"], .appNotAvailableInDevice: ["6984", "6807"]]
        let nameData = Data(name.utf8)
        var data: [UInt8] = [0xe0, 0xd8, 0x00, 0x00]
        data.append(UInt8(nameData.count))
        data.append(contentsOf: nameData)
        let apdu = APDU(data: data)
        BleTransport.shared.exchange(apdu: apdu) { [weak self] result in
            guard let self = self else { failure(BleTransportError.lowerLevelError(description: "closeApp -> self is nil")); return }
            guard let disconnectedCallback = self.disconnectedCallback else { failure(BleTransportError.lowerLevelError(description: "closeApp -> disconnectedCallback is nil")); return }
            
            switch result {
            case .success(let response):
                if let error = self.parseStatus(response: response, errorCodes: errorCodes) {
                    failure(error)
                } else {
                    self.notifyDisconnected {
                        self.create(scanDuration: self.scanDuration, disconnectedCallback: disconnectedCallback) { _ in
                            success()
                        } failure: { error in
                            failure(error)
                        }
                    }
                }
            case .failure(let error):
                failure(error)
            }
        }
    }
    
    /// Never call this method directly since some apps (like Bitcoin) will hang the execution if `getAppAndVersion` is not called right before
    fileprivate func closeApp(success: @escaping EmptyResponse, failure: @escaping ErrorResponse) {
        let apdu = APDU(data: [0xb0, 0xa7, 0x00, 0x00])
        BleTransport.shared.exchange(apdu: apdu) { [weak self] result in
            guard let self = self else { failure(BleTransportError.lowerLevelError(description: "closeApp -> self is nil")); return }
            guard let disconnectedCallback = self.disconnectedCallback else { failure(BleTransportError.lowerLevelError(description: "closeApp -> disconnectedCallback is nil")); return }
            
            switch result {
            case .success(_):
                self.notifyDisconnected {
                    self.create(scanDuration: self.scanDuration, disconnectedCallback: disconnectedCallback) { _ in
                        success()
                    } failure: { error in
                        failure(error)
                    }
                }
            case .failure(let error):
                failure(error)
            }
        }
    }
    
    fileprivate func parseStatus(response: String, errorCodes: [BleStatusError: [String]]) -> BleStatusError? {
        let status = response.suffix(4)
        if status.count == 4 {
            if status == "9000" {
                return nil
            } else {
                if let error = errorCodes.first(where: { $0.value.contains(String(status)) })?.key {
                    return error
                } else {
                    return .unknown
                }
            }
        } else {
            return .noStatus
        }
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

/// Async implementations
extension BleTransport {
    @discardableResult
    public func create(scanDuration: TimeInterval, disconnectedCallback: @escaping EmptyResponse) async throws -> DeviceIdentifier {
        return try await withCheckedThrowingContinuation { continuation in
            create(scanDuration: scanDuration, disconnectedCallback: disconnectedCallback) { response in
                continuation.resume(returning: response)
            } failure: { error in
                continuation.resume(throwing: error)
            }

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
    public func send(apdu: APDU) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            send(apdu: apdu) {
                continuation.resume()
            } failure: { error in
                continuation.resume(throwing: error)
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
    public func getAppAndVersion() async throws -> AppInfo {
        return try await withCheckedThrowingContinuation { continuation in
            self.getAppAndVersion { response in
                continuation.resume(returning: response)
            } failure: { error in
                continuation.resume(throwing: error)
            }
        }
    }
    public func openAppIfNeeded(_ name: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            openAppIfNeeded(name) { result in
                switch result {
                case .success(_):
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    fileprivate func openApp(_ name: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            openApp(name) {
                continuation.resume()
            } failure: { error in
                continuation.resume(throwing: error)
            }
        }
    }
    fileprivate func closeApp() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            closeApp() {
                continuation.resume()
            } failure: { error in
                continuation.resume(throwing: error)
            }
        }
    }
}

func print(_ object: Any) {
    #if DEBUG
    Swift.print("BleTransport", object)
    #endif
}
