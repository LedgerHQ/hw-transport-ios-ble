//
//  BleTransportProtocol.swift
//  BleTransport
//
//  Created by Dante Puglisi on 5/12/22.
//

import Foundation
import Bluejay
import CoreBluetooth

public typealias DeviceInfoTuple = (device: DeviceIdentifier, rssi: Int, serviceUUID: CBUUID, canWriteWithoutResponse: Bool?)
public typealias DeviceResponse = ((DeviceIdentifier)->())
public typealias DevicesWithServicesResponse = (([DeviceInfoTuple])->())
public typealias APDUResponse = ((APDU)->())
public typealias EmptyResponse = (()->())
public typealias BleErrorResponse = ((BleTransportError)->())
public typealias OptionalBleErrorResponse = ((BleTransportError?)->())
public typealias ErrorResponse = ((Error)->())

public protocol BleTransportProtocol {
    
    static var shared: BleTransportProtocol { get }
    
    var isBluetoothAvailable: Bool { get }
    var isConnected: Bool { get }
    
    // MARK: - Scan
    
    /// Scan for reachable devices with the services provided.
    ///
    /// - Parameter callback: Called each time the peripheral list of discovered devices changes.
    func scan(duration: TimeInterval, callback: @escaping DevicesWithServicesResponse, stopped: @escaping OptionalBleErrorResponse)
    
    /// Stop scanning for reachable devices.
    ///
    func stopScanning()
    
    
    // MARK: - Connect
    
    /// Attempt to connect to a given peripheral.
    ///
    /// - Parameter peripheral: The peripheral to connect to.
    func connect(toDeviceID device: DeviceIdentifier, disconnectedCallback: EmptyResponse?, success: @escaping DeviceResponse, failure: @escaping BleErrorResponse)
    @discardableResult func connect(toDeviceID device: DeviceIdentifier, disconnectedCallback: EmptyResponse?) async throws -> DeviceIdentifier
    
    /// Convenience method to `scan` for devices and connecting to the first discovered one.
    /// - Parameters:
    ///   - success: Callback called when the connection is successful.
    ///   - failure: Callback called when the connection failed.
    func create(scanDuration: TimeInterval, disconnectedCallback: EmptyResponse?, success: @escaping DeviceResponse, failure: @escaping BleErrorResponse)
    @discardableResult func create(scanDuration: TimeInterval, disconnectedCallback: EmptyResponse?) async throws -> DeviceIdentifier
    
    
    // MARK: - Messaging
    
    /// Send an `APDU` and wait for the response from the device.
    /// - Parameters:
    ///   - apduToSend: `APDU` to send.
    ///   - callback: Callback that contains the result of the exchange.
    func exchange(apdu apduToSend: APDU, callback: @escaping (Result<String, BleTransportError>) -> Void)
    func exchange(apdu apduToSend: APDU) async throws -> String
    
    /// Send an `APDU` message.
    /// - Parameters:
    ///   - apdu: `APDU` to send.
    ///   - success: Callback called when the connection is successful.
    ///   - failure: Callback called when the connection failed.
    func send(apdu: APDU, success: @escaping EmptyResponse, failure: @escaping BleErrorResponse)
    func send(apdu: APDU) async throws
    
    
    // MARK: - Disconnect
    
    /// Disconnect from the passed device.
    /// - Parameters:
    ///   - immediate: Whether the disconnection should be queued or executed immediately. Passing `false` will wait until the current tasks have been completed.
    ///   - completion: Callback called when the device disconnection has failed with an error or disconnected successfully (`error == nil`).
    func disconnect(immediate: Bool, completion: OptionalBleErrorResponse?)
    func disconnect(immediate: Bool) async throws
    
    
    // MARK: - Notifications
    
    /// Get notified when bluetooth changes availability
    /// - Parameter completion: Callback called when bluetooth becomes available (or immediately if was already available)
    func bluetoothAvailabilityCallback(completion: @escaping ((_ availability: Bool)->()))
    
    /// Get notified once when the device disconnects
    /// - Parameter completion: Callback called when the device disconnects. This will be called only once.
    func notifyDisconnected(completion: @escaping EmptyResponse)
    
    
    // MARK: - Convenience methods
    
    func getAppAndVersion(success: @escaping ((AppInfo)->()), failure: @escaping ErrorResponse)
    func getAppAndVersion() async throws -> AppInfo
    
    func openAppIfNeeded(_ name: String, completion: @escaping (Result<Void, Error>) -> Void)
    func openAppIfNeeded(_ name: String) async throws
}

public struct AppInfo {
    let name: String
    let version: String
}
