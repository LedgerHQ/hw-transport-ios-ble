//
//  TransportJSExport.swift
//  BleTransportDemo
//
//  Created by Dante Puglisi on 6/4/22.
//

import Foundation
import BleTransport
import JavaScriptCore

@objc protocol TransportJSExport: JSExport {
    static func create() -> TransportJS
    
    func exchange(_ buffer: [UInt8]) -> (@convention(block) (JSValue) -> Void)
    func send(_ cla: UInt8, _ ins: UInt8, _ p1: UInt8, _ p2: UInt8, _ data: [UInt8]) -> (@convention(block) (JSValue) -> Void)
}

@objc public class TransportJS : NSObject, TransportJSExport {
    
    let transport: BleTransportProtocol = BleTransport.shared
    
    class func create() -> TransportJS {
        return TransportJS()
    }
    
    func exchange(_ buffer: [UInt8]) -> (@convention(block) (JSValue) -> Void) {
        let block: @convention(block) (JSValue) -> Void = { callback in
            self.transport.exchange(apdu: APDU(data: buffer)) { result in
                switch result {
                case .success(let response):
                    callback.call(withArguments: [response, ""])
                case .failure(let error):
                    callback.call(withArguments: ["", "ERROR: \(error.description())"])
                }
            }
        }
        
        return block
    }
    
    func send(_ cla: UInt8, _ ins: UInt8, _ p1: UInt8, _ p2: UInt8, _ data: [UInt8]) -> (@convention(block) (JSValue) -> Void) {
        var apdu = [cla, ins, p1, p2, UInt8(data.count)]
        apdu.append(contentsOf: data)
        let block: @convention(block) (JSValue) -> Void = { callback in
            self.transport.exchange(apdu: APDU(data: apdu)) { result in
                switch result {
                case .success(let response):
                    callback.call(withArguments: [response.UInt8Array(), ""])
                case .failure(let error):
                    callback.call(withArguments: ["", "ERROR: \(error.description())"])
                }
            }
        }
        
        return block
    }
}

