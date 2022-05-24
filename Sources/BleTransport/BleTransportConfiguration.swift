//
//  BleTransportConfiguration.swift
//  BleTransport
//
//  Created by Dante Puglisi on 5/10/22.
//

import Foundation
import Bluejay

@objc
public class BleTransportConfiguration: NSObject {
    let services: [BleService]
    
    var connectedService: BleService?
    
    public init(services: [BleService]) {
        self.services = services
    }
}

@objc
public class BleService: NSObject {
    let service: ServiceIdentifier
    
    let notify: CharacteristicIdentifier
    let writeWithResponse: CharacteristicIdentifier
    let writeWithoutResponse: CharacteristicIdentifier
    
    public init(serviceUUID: String, notifyUUID: String, writeWithResponseUUID: String, writeWithoutResponseUUID: String) {
        let service = ServiceIdentifier(uuid: serviceUUID)
        self.notify = CharacteristicIdentifier(uuid: notifyUUID, service: service)
        self.writeWithResponse = CharacteristicIdentifier(uuid: writeWithResponseUUID, service: service)
        self.writeWithoutResponse = CharacteristicIdentifier(uuid: writeWithoutResponseUUID, service: service)
        self.service = service
    }
    
    static func == (lhs: BleService, rhs: BleService) -> Bool {
        return lhs.service.uuid == rhs.service.uuid
    }
}
