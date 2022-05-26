//
//  DeviceWithService.swift
//  BleTransport
//
//  Created by Dante Puglisi on 5/26/22.
//

import Foundation
import CoreBluetooth

@objc
public class DeviceWithService: NSObject {
    public let device: DeviceIdentifier
    public let serviceUUID: CBUUID
    
    init(device: DeviceIdentifier, serviceUUID: CBUUID) {
        self.device = device
        self.serviceUUID = serviceUUID
    }
}
