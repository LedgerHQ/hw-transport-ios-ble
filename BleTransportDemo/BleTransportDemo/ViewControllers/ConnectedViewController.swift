//
//  ConnectedViewController.swift
//  Ledger Bluetooth
//
//  Created by Dante Puglisi on 5/10/22.
//

import UIKit
import Bluejay
import BleTransport
import JavaScriptCore

class ConnectedViewController: UIViewController {

    @IBOutlet weak var deviceLabel: UILabel!
    @IBOutlet weak var progressLabel: UILabel!
    @IBOutlet weak var progressView: UIProgressView!
    
    var transport: BleTransportProtocol?
    var connectedDevice: PeripheralIdentifier?
    
    var appInstaller: AppInstaller?
    
    var disconnectTapped: ((PeripheralIdentifier)->())?
    
    lazy var jsContext: JSContext? = {
        let jsContext = JSContext()
        
        guard let
                commonJSPath = Bundle.main.path(forResource: "solanaBundle", ofType: "js") else {
            print("Unable to read resource files.")
            return nil
        }
        
        do {
            let common = try String(contentsOfFile: commonJSPath, encoding: String.Encoding.utf8)
            _ = jsContext?.evaluateScript(common)
        } catch (let error) {
            print("Error while processing script file: \(error)")
        }
        
        return jsContext
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        progressLabel.alpha = 0.0
        progressView.alpha = 0.0
        
        if let connectedDevice = connectedDevice {
            deviceLabel.text = "Connected to \(connectedDevice.name)"
        }
    }
    
    @IBAction func installAppButtonTapped(_ sender: Any) {
        /*guard let transport = transport else { return }
        
        UIView.animate(withDuration: 0.3) {
            self.progressLabel.alpha = 1.0
        }

        progressLabel.alpha = 1.0
        
        appInstaller = AppInstaller(transport: transport, installingProtocol: self)
        appInstaller?.installBTC()*/
        
        guard let jsContext = jsContext else {
            print("JSContext not found.")
            fatalError()
        }
        
        jsContext.setObject(TransportJS.self, forKeyedSubscript: "SwiftTransport" as (NSCopying & NSObjectProtocol))
        
        jsContext.exceptionHandler = { _, error in
            print("Caught exception:", error as Any)
        }
        
        jsContext.setObject(
            {()->@convention(block) (JSValue)->Void in { print($0) }}(),
            forKeyedSubscript: "print" as NSString
        )
        
        guard let module = jsContext.objectForKeyedSubscript("TransportModule") else { return }
        guard let transportModule = module.objectForKeyedSubscript("TransportBLEiOS") else { return }
        guard let transportInstance = transportModule.construct(withArguments: []) else { return }
        guard let solanaModule = module.objectForKeyedSubscript("Solana") else { return }
        guard let solanaInstance = solanaModule.construct(withArguments: [transportInstance]) else { return }
        solanaInstance.invokeMethodAsync("getAppConfiguration", withArguments: [], completionHandler: { resolve, reject in
            if let resolve = resolve {
                print("RESOLVED. Value: \(String(describing: resolve.toObject()))")
            } else if let reject = reject {
                print("REJECTED. Value: \(reject)")
            }
        })
        
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
