//
//  ViewController.swift
//  BleTransportDemoMac
//
//  Created by Dante Puglisi on 10/26/22.
//

import Cocoa
import BleTransport

class ViewController: NSViewController {

    @IBOutlet weak var titleLabel: NSTextField!
    @IBOutlet weak var searchButton: NSButton!
    
    var created = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        titleLabel.stringValue = "Click the button to connect to a device"
    }
    
    fileprivate func create() {
        self.titleLabel.stringValue = "Looking for a device to connect to..."
        BleTransport.shared.create(scanDuration: 5.0, disconnectedCallback: {
            print("Device disconnected!")
        }, success: { result in
            self.titleLabel.stringValue = "Connected to \(result.name)"
        }, failure: { error in
            print("Error connecting to device: \(error.localizedDescription)")
        })
    }

    @IBAction func searchButtonTapped(_ sender: Any) {
        searchButton.isEnabled = false
        BleTransport.shared.bluetoothStateCallback { state in
            if !self.created {
                switch state {
                case .poweredOn:
                    self.created = true
                    self.create()
                case .poweredOff:
                    self.showBluetoothError(message: "Bluetooth is off, try turning it on.")
                case .unauthorized:
                    self.showBluetoothError(message: "Bluetooth is not authorized, please go to Settings and allow Bluetooth access.")
                case .unsupported:
                    self.showBluetoothError(message: "Bluetooth is not supported on this device.")
                default:
                    break
                }
            }
        }
        BleTransport.shared.bluetoothAvailabilityCallback { availability in
            if !self.created && availability {
                self.created = true
                self.create()
            }
        }
    }
    
    func showBluetoothError(message: String) {
        let alert = NSAlert()
        alert.messageText = "Bluetooth error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

