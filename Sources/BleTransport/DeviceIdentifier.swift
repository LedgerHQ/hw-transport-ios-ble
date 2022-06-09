//
//  DeviceIdentifier.swift
//  BleTransport
//
//  Created by Dante Puglisi on 5/26/22.
//

import Foundation
import Bluejay

@objc
class DeviceIdentifier: NSObject {
    let uuid: UUID
    let name: String
    
    init(uuid: UUID, name: String?) {
        self.uuid = uuid
        self.name = name ?? "No Name"
    }
    
    init(peripheralIdentifier: PeripheralIdentifier) {
        self.uuid = peripheralIdentifier.uuid
        self.name = peripheralIdentifier.name
    }
}
