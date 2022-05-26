//
//  BleTransportProtocol.swift
//  BleTransport
//
//  Created by Dante Puglisi on 5/12/22.
//

import Foundation
import Bluejay
import CoreBluetooth

public typealias DeviceResponse = ((DeviceIdentifier)->())
public typealias DevicesWithServicesResponse = (([DeviceWithService])->())
public typealias APDUResponse = ((APDU)->())
public typealias ErrorResponse = ((Error?)->())

public protocol BleTransportProtocol {
    
    var isBluetoothAvailable: Bool { get }
    
    init(configuration: BleTransportConfiguration)
    
    /// Scan for reachable devices with the services provided.
    ///
    /// - Parameter callback: Called each time the peripheral list of discovered devices changes.
    func scan(callback: @escaping DevicesWithServicesResponse, stopped: @escaping (()->()))
    
    /// Stop scanning for reachable devices.
    ///
    func stopScanning()
    
    /// Attempt to connect to a given peripheral.
    ///
    /// - Parameter peripheral: The peripheral to connect to.
    func connect(toDeviceID device: DeviceIdentifier, disconnectedCallback: (()->())?, success: @escaping DeviceResponse, failure: @escaping ErrorResponse)
    
    /// Convenience method to `scan` for devices and connecting to the first discovered one.
    /// - Parameters:
    ///   - success: Callback called when the connection is successful.
    ///   - failure: Callback called when the connection failed.
    func create(disconnectedCallback: @escaping (()->()), success: @escaping DeviceResponse, failure: @escaping ErrorResponse)
    
    /// Send an `APDU` and wait for the response from the device.
    /// - Parameters:
    ///   - apduToSend: `APDU` to send.
    ///   - success: Callback called when the exchange is successful with the response from the device.
    ///   - failure: Callback called when the exchange failed.
    func exchange(apdu apduToSend: APDU, success: @escaping ((String)->()), failure: @escaping ((NSError)->()))
    
    /// Send an `APDU` message.
    /// - Parameters:
    ///   - apdu: `APDU` to send.
    ///   - success: Callback called when the connection is successful.
    ///   - failure: Callback called when the connection failed.
    func send(apdu: APDU, success: @escaping (()->()), failure: @escaping ErrorResponse)
    
    /// Disconnect from the passed device.
    /// - Parameters:
    ///   - immediate: Whether the disconnection should be queued or executed immediately. Passing `false` will wait until the current tasks have been completed.
    ///   - completion: Callback called when the device disconnection has failed with an error or disconnected successfully (`error == nil`).
    func disconnect(immediate: Bool, completion: @escaping ErrorResponse)
}
