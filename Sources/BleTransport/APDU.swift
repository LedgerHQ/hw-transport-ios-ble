//
//  APDU.swift
//  BleTransport
//
//  Created by Dante Puglisi on 5/10/22.
//

import Foundation
import Bluejay

public class APDU: Sendable, Receivable {
    
    public let data: Data                   /// The APDU data to send or receive.
    public var chunks: [Data] = []          /// The APDU data split into frames smaller than `mtuSize`
    
    static var mtuSize: Int = 153           /// The maximum number of bytes (including the tag and frame index) we can send. This should be updated every time we connect to a new device.
    
    public var isEmpty: Bool {
        chunks.isEmpty
    }
    
    public init(data: [UInt8]) {
        let dataReceived = Data(data)
        self.data = dataReceived
        self.chunks = self.chunkAPDU(data: dataReceived)
    }
    
    // Overload to allow passing a String instead of UInt8 since that's what we get from live-common anyway
    public init(raw: String) {
        guard raw.isHexDigit else { print("STRING PASSED IS NOT HEX"); fatalError() }
        let dataReceived = Data(raw.UInt8Array())
        self.data = dataReceived
        self.chunks = self.chunkAPDU(data: dataReceived)
    }
    
    required public init(bluetoothData: Data) throws {
        self.data = bluetoothData
        self.chunks = self.chunkAPDU(data: bluetoothData)
    }
    
    // When called by the Bluejay library it will return the current frame to send
    public func toBluetoothData() -> Data {
        return self.chunks[0]
    }
    
    // Increase index to point to the next frame
    func next() -> Void {
        self.chunks.removeFirst()
    }
    
    private func chunkAPDU(data: Data) -> [Data] {
        let apdu: [UInt8] = Array(data)
        var chunks = Array<Data>()
        let size = UInt8(apdu.count)
        
        let head: [UInt8] = [0x05]     // Tag/Head we need to send for the nano x
        var hi = 0                     // Our current index inside the data
        var ind = UInt8(0)             // Frame counter
        
        while(hi < size) {
            let maxDataForFrame = ind == 0 ? (APDU.mtuSize - 5) : (APDU.mtuSize - 3)
            var messageData = Data()
            messageData.append(Data(head))
            messageData.append(ind == 0 ? Data([0x00,0x00,0x00]) : Data([0x00]))
            messageData.append(ind == 0 ? size.bigEndian : ind.bigEndian)
            messageData.append(Data(apdu[hi..<min(hi+maxDataForFrame, apdu.count)]))
            
            // Move forward in the data
            hi += maxDataForFrame
            ind += 1
            
            // Append the newly created frame to the array representing the apdu.
            chunks.append(messageData)
        }
        return chunks
    }
}

class APDUs: NSObject {
    public static let openBitcoin: [APDU] = [APDU(raw: "e0d8000007426974636f696e")]
}

public extension String {
    func UInt8Array() -> [UInt8] {
        var lo = 0
        let chars = Array(self)
        var out = Array<UInt8>()
        while (lo < self.count) {
            let pair = String(chars[lo])+String(chars[lo+1])
            out.append(UInt8(pair, radix: 16)!)
            lo += 2
        }
        return out
    }
    
    var isHexDigit: Bool {
        filter(\.isHexDigit).count == count
    }
}

extension Array where Element == UInt8 {
    func bytesToHex(spacing: String) -> String {
        var hexString: String = ""
        var count = self.count
        for byte in self
        {
            hexString.append(String(format:"%02X", byte))
            count = count - 1
            if count > 0
            {
                hexString.append(spacing)
            }
        }
        return hexString
    }
}

extension Data {
    public func hexEncodedString(uppercase: Bool = false) -> String {
        let format = uppercase ? "%02hhX" : "%02hhx"
        return self.map { String(format: format, $0) }.joined()
    }
}
