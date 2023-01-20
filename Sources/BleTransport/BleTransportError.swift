//
//  BleTransportError.swift
//  
//
//  Created by Harrison on 1/13/23.
//

import Foundation

/// Errors thrown when scanning/sending/receiving/connecting
public enum BleTransportError: LocalizedError {
    case pendingActionOnDevice
    case userRefusedOnDevice
    case scanningTimedOut
    case bluetoothNotAvailable
    case connectError(description: String)
    case currentConnectedError(description: String)
    case writeError(description: String)
    case readError(description: String)
    case listenError(description: String)
    case scanError(description: String)
    case pairingError(description: String)
    case lowerLevelError(description: String)
    
    public var errorDescription: String? {
        switch self {
        case .pendingActionOnDevice:
            return "Pending action on device"
        case .userRefusedOnDevice:
            return "User refused on device"
        case .scanningTimedOut:
            /// https://github.com/LedgerHQ/ledger-live/blob/acdd59af6dcfcda1d136ccbfc8fdf49311485a32/libs/ledgerjs/packages/hw-transport/src/Transport.ts#L261
            return "No Ledger device found (timeout)"
        case .bluetoothNotAvailable:
            return "Bluetooth is not available"
        case .connectError(let description):
            return "Connect error: \(description)"
        case .currentConnectedError(let description):
            return "Current connected error: \(description)"
        case .writeError(let description):
            return "Write error: \(description)"
        case .readError(let description):
            return "Read error: \(description)"
        case .listenError(let description):
            return "Listen error: \(description)"
        case .scanError(let description):
            return "Scan error: \(description)"
        case .pairingError(let description):
            return "Pairing error: \(description)"
        case .lowerLevelError(let description):
            return "Lower level error: \(description)"
        }
    }
    
    /// `id` is defined by what the JS bindings are returning and using for error handling
    public var id: String? {
        switch self {
        case .pendingActionOnDevice:
            return "TransportRaceCondition"
        case .userRefusedOnDevice:
            return nil
        case .scanningTimedOut:
            /// https://github.com/LedgerHQ/ledger-live/blob/acdd59af6dcfcda1d136ccbfc8fdf49311485a32/libs/ledgerjs/packages/hw-transport/src/Transport.ts#L261
            return "ListenTimeout"
        case .bluetoothNotAvailable:
            return nil
        case .connectError(_):
            return nil
        case .currentConnectedError(_):
            return nil
        case .writeError(_):
            return nil
        case .readError(_):
            return nil
        case .listenError(_):
            return nil
        case .scanError(_):
            return nil
        case .pairingError(_):
            return nil
        case .lowerLevelError(_):
            return nil
        }
    }
}

extension BleTransportError: Equatable {
    public static func == (lhs: BleTransportError, rhs: BleTransportError) -> Bool {
        switch (lhs, rhs) {
        case (.pendingActionOnDevice, .pendingActionOnDevice):
            return true
        case (.userRefusedOnDevice, .userRefusedOnDevice):
            return true
        case (.scanningTimedOut, .scanningTimedOut):
            return true
        case (.bluetoothNotAvailable, .bluetoothNotAvailable):
            return true
        case (.connectError(let lhsDescription), .connectError(let rhsDescription)):
            return lhsDescription == rhsDescription
        case (.currentConnectedError(let lhsDescription), .currentConnectedError(let rhsDescription)):
            return lhsDescription == rhsDescription
        case (.writeError(let lhsDescription), .writeError(let rhsDescription)):
            return lhsDescription == rhsDescription
        case (.readError(let lhsDescription), .readError(let rhsDescription)):
            return lhsDescription == rhsDescription
        case (.listenError(let lhsDescription), .listenError(let rhsDescription)):
            return lhsDescription == rhsDescription
        case (.scanError(let lhsDescription), .scanError(let rhsDescription)):
            return lhsDescription == rhsDescription
        case (.pairingError(let lhsDescription), .pairingError(let rhsDescription)):
            return lhsDescription == rhsDescription
        case (.lowerLevelError(let lhsDescription), .lowerLevelError(let rhsDescription)):
            return lhsDescription == rhsDescription
        default:
            return false
        }
    }
}

