//
//  BleStatusError.swift
//  
//
//  Created by Harrison on 1/13/23.
//

import Foundation

/// Errors received as `status` sent in a message from a device
public enum BleStatusError: LocalizedError, Hashable {
    case userRejected(status: String)
    case appNotAvailableInDevice(status: String)
    case formatNotSupported(status: String)
    case couldNotParseResponseData(status: String)
    case unknown(status: String)
    case noStatus
    
    public var errorDescription: String? {
        switch self {
        case .userRejected(_):
            return "User rejected action"
        case .appNotAvailableInDevice(_):
            return "App is not available in device"
        case .formatNotSupported(_):
            return "Format is not supported"
        case .couldNotParseResponseData(_):
            return "Could not parse response data"
        case .unknown(let status):
            return "Unknown error. Status received: \(status)"
        case .noStatus:
            return "No status received from device"
        }
    }
    
    public var status: String? {
        switch self {
        case .userRejected(let status):
            return status
        case .appNotAvailableInDevice(let status):
            return status
        case .formatNotSupported(let status):
            return status
        case .couldNotParseResponseData(let status):
            return status
        case .unknown(let status):
            return status
        case .noStatus:
            return nil
        }
    }
}
