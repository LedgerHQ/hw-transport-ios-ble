//
//  Errors.swift
//  BleTransport
//
//  Created by Dante Puglisi on 5/26/22.
//

import Foundation

@objc
public enum BleTransportError: Int {
    case pendingActionOnDevice
    case userRefusedOnDevice
    case writeError
    case readError
    case lowerLeverError
}

@objc
public class Errors: NSObject {
    static func createError(type: BleTransportError, description: String? = nil) -> NSError {
        var domain = ""
        var code = 0
        switch type {
        case .pendingActionOnDevice:
            domain = "Pending action on Device."
            code = 01
        case .userRefusedOnDevice:
            domain = "User refused on Device."
            code = 02
        case .writeError:
            domain = "Write error."
            code = 03
        case .readError:
            domain = "Read error."
            code = 04
        case .lowerLeverError:
            domain = "Lower level error."
            code = 05
        }
        
        if let description = description {
            domain += " Description: \(description)"
        }
        
        return NSError(domain: domain, code: code)
    }
}
