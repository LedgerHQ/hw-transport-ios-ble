//
//  AppInstaller.swift
//  Ledger Bluetooth
//
//  Created by Dante Puglisi on 5/12/22.
//

import Foundation
import Starscream
import Bluejay

protocol InstallingProtocol {
    func progressUpdated(percentageCompleted: Float, finished: Bool)
}

class AppInstaller {
    
    fileprivate let transport: BleTransportProtocol
    fileprivate let installingProtocol: InstallingProtocol
    fileprivate var websocket: WebSocket?
    
    fileprivate var lastBLEResponse: String = ""
    fileprivate var APDUQueue = [APDU]()
    fileprivate var bulkAPDUcount = 0
    fileprivate var installing = false
    fileprivate var HSMNonce: Int = 0
    
    fileprivate let notifyCharacteristic = CharacteristicIdentifier(uuid: "13d63400-2c97-0004-0001-4c6564676572", service: ServiceIdentifier(uuid: "13D63400-2C97-0004-0000-4C6564676572"))
    //fileprivate let writeCharacteristic = CharacteristicIdentifier(uuid: "13d63400-2c97-0004-0002-4c6564676572", service: ServiceIdentifier(uuid: "13D63400-2C97-0004-0000-4C6564676572"))
    fileprivate let writeCharacteristic = CharacteristicIdentifier(uuid: "13d63400-2c97-0004-0003-4c6564676572", service: ServiceIdentifier(uuid: "13D63400-2C97-0004-0000-4C6564676572"))
    
    init(transport: BleTransportProtocol, installingProtocol: InstallingProtocol) {
        self.installingProtocol = installingProtocol
        self.transport = transport
    }
    
    func installBTC() {
        let installWSUrl = "wss://scriptrunner.api.live.ledger.com/update/install?targetId=855638020&perso=perso_11&deleteKey=nanox%2F2.0.2-2%2Fbitcoin%2Fapp_2.0.4_del_key&firmware=nanox%2F2.0.2-2%2Fbitcoin%2Fapp_2.0.4&firmwareKey=nanox%2F2.0.2-2%2Fbitcoin%2Fapp_2.0.4_key&hash=8bf06e39e785ba5a8cf27bfa95036ccab02d756f8b8f44c3c3137fd035d5cb0c&livecommonversion=22.0.0"
        var request = URLRequest(url: URL(string: installWSUrl)!)
        request.timeoutInterval = 50
        self.websocket = WebSocket(request: request)
        self.websocket?.delegate = self
        
        self.prepareToListen()
        self.websocket?.connect()
    }
    
    fileprivate func prepareToListen() {
        self.transport.listen(to: notifyCharacteristic) { [weak self] apdu in
            self?.handleDeviceResponse(apdu)
        } failure: { error in
            if let error = error {
                print("Failed to listen with error: \(error.localizedDescription)")
            }
        }
    }
    
    fileprivate func handleDeviceResponse(_ apdu: APDU) {
        let hex = apdu.data.hexEncodedString()
        print("NANO -> \(hex)")
        
        let offset = self.lastBLEResponse == "" ? 10 : 6
        let cleanAPDU = String(hex[hex.index(hex.startIndex, offsetBy: offset)...])
        self.lastBLEResponse += cleanAPDU
        
        // TODO: Include error cases
        if self.lastBLEResponse.hasSuffix("9000") {
            if self.installing {
                /// Continue writing from our queue.
                self.nextFrame()
            } else {
                // Respond back to the HSM
                let responseWithoutStatus = self.lastBLEResponse.dropLast(4)
                let response = "{\"nonce\":\(self.HSMNonce),\"response\":\"success\",\"data\":\"\(responseWithoutStatus)\"}"
                print("HSM  -> \(response)")
                self.websocket?.write(string: response)
            }
            // Consider the response complete
            self.lastBLEResponse = ""
        }
    }
    
    fileprivate func nextFrame() {
        guard let currentAPDU = self.APDUQueue.first else { self.APDUQueue.removeAll(); return }
        print("NANO <- \(currentAPDU.toBluetoothData().hexEncodedString())")
        self.transport.send(apdu: currentAPDU, to: writeCharacteristic) { [weak self] in
            guard let self = self else { return }
            currentAPDU.next()
            if currentAPDU.isEmpty {
                self.APDUQueue.removeFirst()
                let completedAPDUcount = self.bulkAPDUcount - self.APDUQueue.count
                self.installingProtocol.progressUpdated(percentageCompleted: Float(completedAPDUcount) / Float(self.bulkAPDUcount), finished: self.APDUQueue.count == 0 && self.installing)
            } else {
                /// Only continue if it's a frame from same apdu
                self.nextFrame()
            }
        } failure: { [weak self] error in
            self?.APDUQueue.removeAll()
            if let error = error {
                print("Error when writing: \(error)")
            }
        }
    }
    
}

extension AppInstaller: WebSocketDelegate {
    internal func didReceive(event: WebSocketEvent, client: WebSocket) {
        if case .text(let stringReceived) = event {
            let data = Data(stringReceived.utf8)
            do {
                print("HSM  <- \(stringReceived)")
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    let query = json["query"] as? String
                    if query == "bulk" {
                        print("STARTED: \(Date())")
                        let rawAPDUs = json["data"] as? [String] ?? []
                        self.APDUQueue = []
                        
                        for rawAPDU in rawAPDUs {
                            self.APDUQueue.append(APDU(raw: rawAPDU))
                        }
                        self.bulkAPDUcount = APDUQueue.count
                        print("WILL INSTALL: \(Date())")
                        self.installing = true
                        self.nextFrame()
                    } else {
                        self.APDUQueue = [APDU(raw: json["data"] as? String ?? "")]
                        self.HSMNonce = json["nonce"] as? Int ?? 0
                        self.nextFrame()
                    }
                }
            } catch {
                print("Failed to serialize: \(error)")
            }
        }
    }
}
