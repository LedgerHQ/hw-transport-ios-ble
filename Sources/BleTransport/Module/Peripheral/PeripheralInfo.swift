//
//  PeripheralInfo.swift
//  
//
//  Created by Harrison on 1/19/23.
//

import CoreBluetooth

public struct PeripheralInfo: Hashable {
    public let peripheral: PeripheralIdentifier
    public let rssi: Int
    public let serviceUUID: CBUUID
    public var canWriteWithoutResponse: Bool?
}
