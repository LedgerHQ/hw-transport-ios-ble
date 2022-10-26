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
        BleTransport.shared.bluetoothAvailabilityCallback { availability in
            if !self.created && availability {
                self.created = true
                self.create()
            }
        }
    }
}

