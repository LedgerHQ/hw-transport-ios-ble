//
//  ConnectedViewController.swift
//  Ledger Bluetooth
//
//  Created by Dante Puglisi on 5/10/22.
//

import UIKit
import BleTransport

class ConnectedViewController: UIViewController {

    @IBOutlet weak var deviceLabel: UILabel!
    @IBOutlet weak var progressLabel: UILabel!
    @IBOutlet weak var progressView: UIProgressView!
    
    var transport: BleTransportProtocol?
    var connectedDevice: PeripheralIdentifier?
    
    var appInstaller: AppInstaller?
    
    var disconnectTapped: ((PeripheralIdentifier)->())?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        progressLabel.alpha = 0.0
        progressView.alpha = 0.0
        
        if let connectedDevice = connectedDevice {
            deviceLabel.text = "Connected to \(connectedDevice.name)"
        }
    }
    
    @IBAction func installAppButtonTapped(_ sender: Any) {
        guard let transport = transport else { return }
        
        UIView.animate(withDuration: 0.3) {
            self.progressLabel.alpha = 1.0
        }

        progressLabel.alpha = 1.0
        
        appInstaller = AppInstaller(transport: transport, installingProtocol: self)
        appInstaller?.installBTC()
        
        /*BleTransport.shared.openAppIfNeeded("Solana") { result in
            switch result {
            case .success(_):
                print("Opened!")
            case .failure(let error):
                print(error)
            }
        }*/

    }
    
    @IBAction func disconnectButtonTapped(_ sender: Any) {
        guard let connectedDevice = connectedDevice else { return }
        disconnectTapped?(connectedDevice)
    }

}

extension ConnectedViewController: InstallingProtocol {
    func progressUpdated(percentageCompleted: Float, finished: Bool) {
        let percentageCompleted = percentageCompleted.isNaN ? 0.0 : percentageCompleted
        
        var progressViewNewAlpha = progressView.alpha
        
        if finished {
            print("FINISHED: \(Date())")
            progressLabel.text = "Install completed!"
        } else {
            if percentageCompleted == 0.0 {
                progressLabel.text = "Preparing..."
            } else {
                progressLabel.text = "Installing..."
            }
        }
        
        progressView.progress = percentageCompleted
        
        if percentageCompleted == 0.0 {
            progressViewNewAlpha = 0.0
        } else {
            progressViewNewAlpha = 1.0
        }
        
        if progressViewNewAlpha != progressView.alpha {
            UIView.animate(withDuration: 0.3) {
                self.progressView.alpha = progressViewNewAlpha
            }
        }
    }
}
