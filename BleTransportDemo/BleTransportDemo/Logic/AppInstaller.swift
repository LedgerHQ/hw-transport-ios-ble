//
//  AppInstaller.swift
//  Ledger Bluetooth
//
//  Created by Dante Puglisi on 5/12/22.
//

import Foundation
import Starscream
import Bluejay
import BleTransport

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
        
        self.websocket?.connect()
    }
    
    fileprivate func handleDeviceResponse(_ hex: String) {
        print("NANO -> \(hex)")
        
        if hex.hasSuffix("9000") {
            if self.installing {
                /// Continue writing from our queue.
                self.nextFrame()
            } else {
                // Respond back to the HSM
                let responseWithoutStatus = hex.dropLast(4)
                let response = "{\"nonce\":\(self.HSMNonce),\"response\":\"success\",\"data\":\"\(responseWithoutStatus)\"}"
                print("HSM  -> \(response)")
                self.websocket?.write(string: response)
            }
        } else {
            print("Got an exchange response with an error, response: \(hex)")
        }
    }
    
    fileprivate func nextFrame() {
        guard let currentAPDU = self.APDUQueue.first else { self.APDUQueue.removeAll(); return }
        print("NANO <- \(currentAPDU.toBluetoothData().hexEncodedString())")
        /*self.transport.exchange(apdu: currentAPDU) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let hexResponse):
                self.APDUQueue.removeFirst()
                
                let completedAPDUcount = self.bulkAPDUcount - self.APDUQueue.count
                self.installingProtocol.progressUpdated(percentageCompleted: Float(completedAPDUcount) / Float(self.bulkAPDUcount), finished: self.APDUQueue.count == 0 && self.installing)
                
                self.handleDeviceResponse(hexResponse)
            case .failure(let error):
                self.APDUQueue.removeAll()
                switch error {
                case .readError(let description):
                    print(description)
                case .writeError(let description):
                    print(description)
                case .pendingActionOnDevice:
                    print("PENDING DEVICE ACTION!")
                default:
                    print("Another error thrown!")
                }
            }
        }*/
        Task() {
            do {
                let hexResponse = try await self.transport.exchange(apdu: currentAPDU)
                self.APDUQueue.removeFirst()
                
                let completedAPDUcount = self.bulkAPDUcount - self.APDUQueue.count
                await MainActor.run {
                    self.installingProtocol.progressUpdated(percentageCompleted: Float(completedAPDUcount) / Float(self.bulkAPDUcount), finished: self.APDUQueue.count == 0 && self.installing)
                }
                
                self.handleDeviceResponse(hexResponse)
            } catch {
                guard let error = error as? BleTransportError else { return }
                self.APDUQueue.removeAll()
                switch error {
                case .readError(let description):
                    print(description)
                case .writeError(let description):
                    print(description)
                case .pendingActionOnDevice:
                    print("PENDING DEVICE ACTION!")
                default:
                    print("Another error thrown!")
                }
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
