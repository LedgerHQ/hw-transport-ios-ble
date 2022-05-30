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
    
    static func defaultConfig() -> BleTransportConfiguration {
        let nanoXServiceUUID = "13D63400-2C97-0004-0000-4C6564676572"
        let notifyCharacteristicUUID = "13d63400-2c97-0004-0001-4c6564676572"
        let writeWithResponseCharacteristicUUID = "13d63400-2c97-0004-0002-4c6564676572"
        let writeWithoutResponseCharacteristicUUID = "13d63400-2c97-0004-0003-4c6564676572"
        
        return BleTransportConfiguration(services: [BleService(serviceUUID: nanoXServiceUUID, notifyUUID: notifyCharacteristicUUID, writeWithResponseUUID: writeWithResponseCharacteristicUUID, writeWithoutResponseUUID: writeWithoutResponseCharacteristicUUID)])
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
