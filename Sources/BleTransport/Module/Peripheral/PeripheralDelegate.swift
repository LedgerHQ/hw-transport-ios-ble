//
//  PeripheralDelegate.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/4/22.
//

import Foundation
import CoreBluetooth

protocol PeripheralDelegate: AnyObject {
    func requestStartOperation(_ operation: Operation)
    func didDiscoverServices()
    func didDiscoverCharacteristics()
    func didUpdateCharacteristicNotificationState()
    func didUpdateValueFor(characteristic: CBCharacteristic, error: Error?)
}
