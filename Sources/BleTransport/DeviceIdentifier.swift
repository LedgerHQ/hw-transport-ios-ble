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
    
    public init(uuid: UUID, name: String?) {
        self.uuid = uuid
        self.name = name ?? "No Name"
    }
    
    public init(peripheralIdentifier: PeripheralIdentifier) {
        self.uuid = peripheralIdentifier.uuid
        self.name = peripheralIdentifier.name
    }
    
    func toPeripheralIdentifier() -> PeripheralIdentifier {
        return PeripheralIdentifier(uuid: self.uuid, name: self.name)
    }
}

extension DeviceIdentifier {
    static func ==(lhs: DeviceIdentifier, rhs: DeviceIdentifier) -> Bool {
        return lhs.uuid == rhs.uuid
    }
}
