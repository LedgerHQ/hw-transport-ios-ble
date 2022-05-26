//
//  DeviceIdentifier.swift
//  BleTransport
//
//  Created by Dante Puglisi on 5/26/22.
//

import Foundation
import Bluejay

@objc
public class DeviceIdentifier: NSObject {
    public let uuid: UUID
    public let name: String
    
    init(uuid: UUID, name: String?) {
        self.uuid = uuid
        self.name = name ?? "No Name"
    }
    
    init(peripheralIdentifier: PeripheralIdentifier) {
        self.uuid = peripheralIdentifier.uuid
        self.name = peripheralIdentifier.name
    }
    
    func peripheralIdentifier() -> PeripheralIdentifier {
        return PeripheralIdentifier(uuid: self.uuid, name: self.name)
    }
}

/*
/// Uniquely identifies a peripheral to the current iOS device. The UUID changes and is different on different iOS devices.
public struct PeripheralIdentifier {
    /// The UUID of the peripheral.
    public let uuid: UUID
    
    /// The name of the peripheral.
    public let name: String
    
    /// Returns both the name and uuid of the peripheral.
    public var description: String {
        return "Peripheral: \(name), UUID: \(uuid)"
    }
    
    /// Create a PeripheralIdentifier using a UUID.
    public init(uuid: UUID, name: String?) {
        self.uuid = uuid
        self.name = name ?? "No Name"
    }
}

extension PeripheralIdentifier: Hashable {
    public static func == (lhs: PeripheralIdentifier, rhs: PeripheralIdentifier) -> Bool {
        return lhs.uuid == rhs.uuid
    }
}*/
