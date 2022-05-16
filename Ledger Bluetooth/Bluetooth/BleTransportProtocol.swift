//
//  BleTransportProtocol.swift
//  Ledger Bluetooth
//
//  Created by Dante Puglisi on 5/12/22.
//

import Foundation
import Bluejay

public typealias PeripheralResponse = ((PeripheralIdentifier)->())
public typealias PeripheralsResponse = (([PeripheralIdentifier])->())
public typealias APDUResponse = ((APDU)->())
public typealias ErrorResponse = ((Error?)->())

protocol BleTransportProtocol {
    
    var isBluetoothAvailable: Bool { get }
    
    /// Scan for reachable devices with the services provided.
    ///
    /// - Parameter callback: Called each time the peripheral list of discovered devices changes.
    func scan(callback: @escaping PeripheralsResponse, stopped: @escaping (()->()))
    
    /// Attempt to connect to a given peripheral.
    ///
    /// - Parameter peripheral: The peripheral to connect to.
    func open(withPeripheral peripheral: PeripheralIdentifier, success: @escaping PeripheralResponse, failure: @escaping ErrorResponse)
    
    /// Convenience method to `scan` for devices and connecting to the first discovered one.
    /// - Parameters:
    ///   - success: Callback called when the connection is successful.
    ///   - failure: Callback called when the connection failed.
    func create(success: @escaping PeripheralResponse, failure: @escaping ErrorResponse)
    
    /// Continuously listen to messages sent by the passed characteristic
    /// - Parameters:
    ///   - to: Characteristic to listen.
    ///   - apduReceived: Callback called when an APDU is received from the device, will be called every time an APDU is received.
    ///   - failure: Callback called when the connection failed.
    func listen(to: CharacteristicIdentifier, apduReceived: @escaping APDUResponse, failure: @escaping ErrorResponse)
    
    /// Send an `APDU` message to the specified characteristic.
    /// - Parameters:
    ///   - apdu: `APDU` to send.
    ///   - to: Characteristic to send the message to.
    ///   - success: Callback called when the connection is successful.
    ///   - failure: Callback called when the connection failed.
    func send(apdu: APDU, to: CharacteristicIdentifier, success: @escaping (()->()), failure: @escaping ErrorResponse)
    
    /// Disconnect from the passed device.
    /// - Parameters:
    ///   - immediate: Whether the disconnection should be queued or executed immediately. Passing `false` will wait until the current tasks have been completed.
    ///   - completion: Callback called when the device disconnection has failed with an error or disconnected successfully (`error == nil`).
    func disconnect(immediate: Bool, completion: @escaping ErrorResponse)
}
