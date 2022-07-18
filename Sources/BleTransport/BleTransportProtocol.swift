//
//  BleTransportProtocol.swift
//  BleTransport
//
//  Created by Dante Puglisi on 5/12/22.
//

import Foundation
import Bluejay
import CoreBluetooth

public typealias PeripheralInfoTuple = (peripheral: PeripheralIdentifier, rssi: Int, serviceUUID: CBUUID, canWriteWithoutResponse: Bool?)
public typealias PeripheralResponse = ((PeripheralIdentifier)->())
public typealias PeripheralsWithServicesResponse = (([PeripheralInfoTuple])->())
public typealias APDUResponse = ((APDU)->())
public typealias ErrorResponse = ((BleTransportError)->())
public typealias OptionalErrorResponse = ((BleTransportError?)->())

public protocol BleTransportProtocol {
    
    static var shared: BleTransportProtocol { get }
    
    var isBluetoothAvailable: Bool { get }
    var isConnected: Bool { get }
    
    /// Scan for reachable devices with the services provided.
    ///
    /// - Parameter callback: Called each time the peripheral list of discovered devices changes.
    func scan(callback: @escaping PeripheralsWithServicesResponse, stopped: @escaping OptionalErrorResponse)
    
    /// Stop scanning for reachable devices.
    ///
    func stopScanning()
    
    /// Attempt to connect to a given peripheral.
    ///
    /// - Parameter peripheral: The peripheral to connect to.
    func connect(toPeripheralID peripheral: PeripheralIdentifier, timeout: Timeout, disconnectedCallback: (()->())?, success: @escaping PeripheralResponse, failure: @escaping ErrorResponse)
    
    /// Convenience method to `scan` for devices and connecting to the first discovered one.
    /// - Parameters:
    ///   - success: Callback called when the connection is successful.
    ///   - failure: Callback called when the connection failed.
    func create(timeout: Timeout, disconnectedCallback: @escaping (()->()), success: @escaping PeripheralResponse, failure: @escaping OptionalErrorResponse)
    
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
    func send(apdu: APDU, success: @escaping (()->()), failure: @escaping ErrorResponse)
    func send(apdu: APDU) async throws
    
    /// Disconnect from the passed device.
    /// - Parameters:
    ///   - immediate: Whether the disconnection should be queued or executed immediately. Passing `false` will wait until the current tasks have been completed.
    ///   - completion: Callback called when the device disconnection has failed with an error or disconnected successfully (`error == nil`).
    func disconnect(immediate: Bool, completion: OptionalErrorResponse?)
    func disconnect(immediate: Bool) async throws
    
    
    /// Get notified when bluetooth changes availability
    /// - Parameter completion: Callback called when bluetooth becomes available (or immediately if was already available)
    func bluetoothAvailabilityCallback(completion: @escaping ((_ availability: Bool)->()))
}
