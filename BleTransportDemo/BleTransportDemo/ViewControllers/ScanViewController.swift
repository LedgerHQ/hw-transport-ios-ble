//
//  ScanViewController.swift
//  Ledger Bluetooth
//
//  Created by Dante Puglisi on 5/10/22.
//

import UIKit
import BleTransport
import CoreBluetooth

class ScanViewController: UIViewController {

    @IBOutlet weak var devicesTableView: UITableView!
    @IBOutlet weak var findDevicesButton: UIButton!
    @IBOutlet weak var infoLabel: UILabel!
    @IBOutlet weak var devicesFoundLabel: UILabel!
    
    var peripheralsServicesTuple = [PeripheralInfoTuple]()
    var peripheralConnecting: PeripheralIdentifier?
    var connectedPeripheral: PeripheralIdentifier?
    
    let configuration = BleTransportConfiguration(services: [BleService(serviceUUID: "13D63400-2C97-0004-0000-4C6564676572",
                                                                        notifyUUID: "13d63400-2c97-0004-0001-4c6564676572",
                                                                        writeWithResponseUUID: "13d63400-2c97-0004-0002-4c6564676572",
                                                                        writeWithoutResponseUUID: "13d63400-2c97-0004-0003-4c6564676572")])
    var transport: BleTransportProtocol? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        devicesFoundLabel.alpha = 0.0
        
        transport = BleTransport.shared
    }
    
    var apdus = [
        APDU(raw: "e001000000"),
        APDU(raw: "e00400000433000004"),
        APDU(raw: "e05000000836fa90b3beeac61c"),
        APDU(raw: "e0518000894104035411f40b6e9967107afcb8bbb3645cee64a6e691c8be2dfceb67af5fd5c236a4c07abd8eea30a4ce731fb886b54598989adacc75c060b259bf081964e261ac46304402200299ffc4d475e516797d72372001d4b4583683264c5397025472fc7057b04c0602203f75632b73ec07c26c886b8404a20969fbdf12b4ffc6d1d4d5e5f7594e7baa1d")
    ]
    
    func sendNextApdu() {
        if apdus.count > 0 {
            let apdu = apdus.removeFirst()
            print("WADUS :: SENDING APDU")
            transport?.exchange(apdu: apdu){ [self] response in
                print("WADUS :: APDU response", response)
                sendNextApdu()
            }
        }
    }

    var nonce = 1
    fileprivate func connectToPeripheral(_ peripheral: PeripheralIdentifier) {
        nonce += 1
        guard peripheralConnecting == nil else { return }
        peripheralConnecting = peripheral
        
        print("WADUS :: CONNECT SEND", nonce)
        transport?.connect(toPeripheralID: peripheral) {
            print("WADUS :: DEVICE DISCONNECTED", self.nonce)
            self.peripheralConnecting = nil
        } success: { [self] peripheralConnected in
            sendNextApdu()
            print("WADUS :: DISCONNECTED SEND", nonce)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)){
                transport?.disconnect(){ [self] maybeError in
                    self.peripheralConnecting = nil
                    print("WADUS :: DISCONNECTED CALLBACK", maybeError, nonce)
                    self.connectToPeripheral(peripheral)
                }
            }
        } failure: { [self] error in
           print("WADUS :: FAILURE TO CONNECT", nonce)
        }
        
        /*transport?.connect(toPeripheralID: peripheral, disconnectedCallback: nil, success: { peripheralConnected in
            self.sendNextApdu()
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                self.transport?.disconnect(){ [self] maybeError in
                    //self.peripheralConnecting = nil
                    print("WADUS :: DISCONNECTED CALLBACK", maybeError, nonce)
                    /*if nonce < 3 {
                        self.connectToPeripheral(peripheral)
                    }*/
                }
            }
        }, failure: { error in
            print("ERROR: \(error)")
        })*/

    }

    @IBAction func findDevicesButtonTapped(_ sender: Any) {
        if let transport = transport, transport.isBluetoothAvailable {
            self.scanningStateChanged(isScanning: true)
            
            transport.scan(duration: 5.0) { [weak self] discoveries in
                self?.peripheralsServicesTuple = discoveries
                self?.devicesFoundLabel.alpha = discoveries.isEmpty ? 0.0 : 1.0
                self?.devicesTableView.reloadData()
                /// We found something, stop
                transport.stopScanning()
            } stopped: { [weak self] error in
//                self?.scanningStateChanged(isScanning: false)
//                self?.devicesFoundLabel.alpha = 0.0
//                self?.peripheralsServicesTuple = []
//                self?.devicesTableView.reloadData()
//                if let error = error {
//                    let alert = UIAlertController(title: "Error scanning", message: "\(error)", preferredStyle: .alert)
//                    let okAction = UIAlertAction(title: "Ok", style: .cancel)
//                    alert.addAction(okAction)
//                    self?.present(alert, animated: true, completion: nil)
//                }
            }
        }
    }
    
    fileprivate func scanningStateChanged(isScanning: Bool) {
        findDevicesButton.isEnabled = !isScanning
        infoLabel.text = isScanning ? "Scanning for devices..." : "Click the button to find devices"
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "connectedDeviceSegue" {
            if let destVC = segue.destination as? ConnectedViewController {
                destVC.connectedDevice = connectedPeripheral
                destVC.transport = self.transport
                destVC.disconnectTapped = { [weak self] deviceToDisconnect in
                    self?.transport?.disconnect(completion: { error in
                        if let error = error {
                            print("WADUS :: Couldn't disconnect with error: \(error)")
                        } else {
                            self?.connectedPeripheral = nil
                            self?.devicesTableView.reloadData()
                            destVC.dismiss(animated: true)
                        }
                    })
                }
            }
        }
    }
    
}

/*extension ViewController: BluetoothReceivable {
    func scanningStateChanged(isScanning: Bool) {
        findDevicesButton.isEnabled = !isScanning
        infoLabel.text = isScanning ? "Scanning for devices..." : "Click the button to find devices"
    }
    
    func discoveries(_ devices: [PeripheralIdentifier]) {
        self.devices = devices
        devicesFoundLabel.alpha = devices.isEmpty ? 0.0 : 1.0
        devicesTableView.reloadData()
    }
    
    func didConnectToDevice(result: Result<PeripheralIdentifier, Error>) {
        switch result {
        case .success(let connectedDevice):
            self.connectedDevice = connectedDevice
            performSegue(withIdentifier: "connectedDeviceSegue", sender: nil)
        case .failure(let error):
            let alert = UIAlertController(title: "Error connecting", message: "\(error)", preferredStyle: .alert)
            let okAction = UIAlertAction(title: "Ok", style: .cancel)
            alert.addAction(okAction)
            self.present(alert, animated: true, completion: nil)
        }
        
        deviceConnecting = nil
    }
}*/

extension ScanViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return peripheralsServicesTuple.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "deviceCell") as! DeviceFoundTableViewCell
        
        let rowDevice = peripheralsServicesTuple[indexPath.row].peripheral
        cell.setupCell(deviceName: rowDevice.name, connecting: rowDevice == peripheralConnecting)
        
        cell.connectTapped = { [weak self] in
            self?.connectToPeripheral(rowDevice)
            tableView.reloadRows(at: [indexPath], with: .automatic)
        }
        
        cell.selectionStyle = .none
        return cell
    }
}
