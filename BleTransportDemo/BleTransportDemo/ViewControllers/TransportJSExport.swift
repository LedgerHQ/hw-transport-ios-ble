//
//  TransportJSExport.swift
//  BleTransportDemo
//
//  Created by Dante Puglisi on 6/4/22.
//

import Foundation
import JavaScriptCore
import BleTransport

@objc protocol TransportJSExport: JSExport {
    static func create() -> TransportJS
    
    func send(_ completion: @escaping (()->()))
}

@objc public class TransportJS : NSObject, TransportJSExport {
    
    let transport: BleTransport
    
    required override init() {
        self.transport = BleTransport(configuration: nil, debugMode: false)
    }
    
    /*func send(apduString: String) -> String {
        transport.exchange(apdu: APDU(raw: apduString)) { result in
            result
        }
    }*/
    
    func send(_ completion: @escaping (()->())) {
        //DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            completion()
        //}
    }
    
    class func create() -> TransportJS {
        return TransportJS()
    }
    
    func getNumberAfterWaiting() -> Int {
        let asd = (1...100_000).map { _ in Double.random(in: -10...30) }
        print(asd)
        return 8
    }
}
