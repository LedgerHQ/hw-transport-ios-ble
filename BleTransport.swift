//
//  BLE.swift
//  BackgroundInstallPOC
//  See if this can be implemented without the Bluejay library, I think it's introducing some overhead
//  in logs, and the main queue bullshit.
//
//  Created by Juan on 23/11/21.
//

import Foundation
import Bluejay

// Temptative at error representation
enum BleTransportError: Error {
  case pendingActionOnDevice
  case deviceDisconnected
  case userRefusedOnDevice
  case transportError(statusCode: Int)
}

@objc public class BleTransport: NSObject, ConnectionObserver, LogObserver {
  public func debug(_ text: String) {
    print("BLE FRAMES", text)
  }
  
  public static var shared = BleTransport("SwiftLedgerBLETransport")
  public static var tag = "SwiftLedgerBLETransport"
  var nonce = 0
  
  var bluejay: Bluejay?
  var connected: Bool = false
  var canConnect: Bool = false
  var wantToScan: Bool = false
  
  // Callbacks, if we move to ios13, we could async/await
  var scanCallback: ((PeripheralIdentifier)->Void)?
  var exchangeCallback: ((String)->Void)?
  var connectCallback: (()->Void)?
  var disconnectCallback: (()->Void)?
  
  var apdu: APDU?
  var currentAPDUResponse: String = ""
  var expectedLength: Int = 0
  
  // IDs
  var nanoXService: ServiceIdentifier;
  var writeCharacteristic: CharacteristicIdentifier;
  var notifyCharacteristic: CharacteristicIdentifier;
  
  func ping() {
    //print("NativeBridge", "pong")
  }
  
  private init(_: String) {
    // Declare services and characteristics, this should allow for more than one service/characteristics set
    self.nanoXService = ServiceIdentifier(uuid: "13D63400-2C97-0004-0000-4C6564676572");
    self.notifyCharacteristic = CharacteristicIdentifier(uuid: "13d63400-2c97-0004-0001-4c6564676572", service: nanoXService);
    self.writeCharacteristic = CharacteristicIdentifier(uuid: "13d63400-2c97-0004-0002-4c6564676572", service: nanoXService);
    
    super.init();
    self.bluejay = Bluejay(logObserver: self)
    self.bluejay!.start()
    self.bluejay!.register(connectionObserver: self)
  }
  /**
   * Scan for bluetooth Ledger devices
   */
  func listen (callback: @escaping (PeripheralIdentifier)->Void) {
    self.scanCallback = callback
    
    // Prevent duplicates
    if self.bluejay!.isConnected || self.bluejay!.isScanning || !self.bluejay!.isBluetoothAvailable { // Already doing it
      self.wantToScan = (self.bluejay == nil) || !self.bluejay!.isBluetoothAvailable
      return
    }
    print(BleTransport.tag, "start scanning")
    
    // Start the scan
    
    self.bluejay!.scan(
      serviceIdentifiers: [self.nanoXService],
      discovery: { (discovery, discoveries) -> ScanAction in
        callback(discovery.peripheralIdentifier)
        return .stop // FIXME in the real world we will want to know about more than one.
      },
      stopped: { (discoveries, error) in })
    
  }
  
  /**
   * Stop scanning for bluetooth Ledger devices
   */
  func stop () -> Void {
    if self.bluejay!.isScanning {
      print(BleTransport.tag, "stop scanning")
      self.bluejay!.stopScanning()
    }
  }
  
  /**
   * Connect to a BLE device by its ID
   */
  func connect (id : PeripheralIdentifier, connectCallback: @escaping ()->Void, disconnectCallback: (()->Void)? = nil) -> Void {
    if self.bluejay!.isConnected || self.bluejay!.isConnecting {
      // We are already connected (?)
    } else {
      if self.bluejay!.isScanning {
        DispatchQueue.main.async {
          self.bluejay!.stopScanning()
        }
      }
      self.connectCallback = connectCallback
      self.disconnectCallback = disconnectCallback
      
      // Attempt to connect to the device
      self.bluejay!.connect(id, timeout: .seconds(10)) { result in
        switch result {
        case .success(_):
          // FIXME this gets called inconsistently due to //Dispatch.dispatchPrecondition(condition: .onQueue(.main))
          // Seems to be a result of the _attempt to connect_ but not consistently connected at this point
          print(BleTransport.tag, "Connection attempt succeeded, trigger callback from delegate BleTransport.disconnected(from:)")
        case .failure(let error):
          disconnectCallback!() // TODO Not really a disconnect, never connected but hey  ¯\_(ツ)_/¯
          print(BleTransport.tag, "Failed to listen with error: \(error.localizedDescription)")
        }
      }
    }
  }
  
  /**
   * Disconnect from a BLE device by its ID
   */
  func disconnect (id : PeripheralIdentifier, immediate : Bool = false) -> Void {
    if self.bluejay!.isConnected {
      self.bluejay?.disconnect(immediate: immediate) // I don't know why we would force it
    }
  }
  
  /**
   * Exchange an apdu with the device, callback will receive the response
   */
  func exchange (_ apdu: String, callback: @escaping (String)->Void) throws -> Void {
    try self.exchange (APDU(raw: apdu), callback: callback)
  }
  
  func exchange (_ apdu: APDU, callback: @escaping (String)->Void) throws -> Void {
    if self.apdu != nil {
      throw BleTransportError.pendingActionOnDevice
    }
    
    print(BleTransport.tag, "->", apdu.data!.hexEncodedString())
    self.exchangeCallback = callback
    self.apdu = apdu
    self.nextFrame()
  }
  
  /**
   * Write the next ble frame to the device,  only triggered from the exchange/send methods.
   * Shouldn't be accessible from the outside world (!)
   **/
  private func nextFrame() {
    if (self.apdu) != nil && self.bluejay!.isConnected {
      self.bluejay!.write(to: self.writeCharacteristic, value: self.apdu!) { result in
        switch result {
        case .success:
          self.apdu!.next(); // Fetch the next ble frame of the queued apdu
          if !self.apdu!.chunks.isEmpty {
            self.nextFrame() // Only continue if it's a frame from same apdu
          } else {
            self.apdu = nil
          }
        case .failure(let error):
          self.apdu = nil; // TODO Throw an error I guess
          print(BleTransport.tag, "Failed to connect with error: \(error.localizedDescription)")
        }
      }
    }
  }
  
  /// Called whenever Bluetooth availability changes, as well as when an object first subscribes to become a ConnectionObserver.
  public func bluetoothAvailable(_ available: Bool) {
    if self.wantToScan && available { // Covers the case where we asked for scanning before ble was available
      self.listen(callback: self.scanCallback!)
    }
  }
  
  /// Called whenever a peripheral is connected, as well as when an object first subscribes to become a ConnectionObserver and the peripheral is already connected.
  public func connected(to peripheral: PeripheralIdentifier) {
    // Register the fact that we want to listen to this characteristic
    do {
      if try !self.bluejay!.isListening(to: notifyCharacteristic) {
        self.bluejay!.listen(to: self.notifyCharacteristic, multipleListenOption: .replaceable)
        { (result: ReadResult<APDU>) in
          switch result {
          case .success(let data):
            // This is a raw ble frame, we need to get the response data instead and only emit when we have a complete response?
            var offset = 6
            let hex = data.data!.hexEncodedString()
            
            if (self.currentAPDUResponse == "") {
              offset = 10

              let a = hex.index(hex.startIndex, offsetBy: 8)
              let b = hex.index(hex.startIndex, offsetBy: 10)// First frame includes data size too
              self.expectedLength = Int(hex[a..<b], radix: 16)!
              print(BleTransport.tag, "I expect length of", self.expectedLength)
            }

            // Extract the expected data size
            let cleanAPDU = String(hex[hex.index(hex.startIndex, offsetBy: offset)...])

            self.currentAPDUResponse += cleanAPDU
            self.expectedLength -= cleanAPDU.count // Decrease the remaining data size
            
            print(BleTransport.tag, "<-", cleanAPDU)
            
            if (self.expectedLength <= 0) {
              self.exchangeCallback!(self.currentAPDUResponse)
              self.currentAPDUResponse = "" // Clear the flag, the apdu is done.
            }
          case .failure(let error):
            print(BleTransport.tag, "Failed to listen with error: \(error.localizedDescription)")
          }
        }
      }
      // We're already listening, trigger callback
      self.connectCallback!()
    } catch (_) {
      print(BleTransport.tag, "GOT AN ERROR trying to listen to char")
    }
  }
  
  /// Called whenever a peripheral is disconnected.
  public func disconnected(from peripheral: PeripheralIdentifier) {
    print(BleTransport.tag, "disconnected", peripheral)
    if self.disconnectCallback != nil {
      self.disconnectCallback!()
    }
  }
}
