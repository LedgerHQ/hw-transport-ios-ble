//
//  DeviceFoundTableViewCell.swift
//  Ledger Bluetooth
//
//  Created by Dante Puglisi on 5/10/22.
//

import UIKit

class DeviceFoundTableViewCell: UITableViewCell {

    @IBOutlet weak var deviceNameLabel: UILabel!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    var connectTapped: (()->())?
    
    func setupCell(deviceName: String, connecting: Bool) {
        deviceNameLabel.text = deviceName
        connectButton.alpha = connecting ? 0.0 : 1.0
        activityIndicator.alpha = connecting ? 1.0 : 0.0
        activityIndicator.startAnimating()
    }
    
    @IBAction func connectButtonTapped(_ sender: Any) {
        connectTapped?()
    }
}
