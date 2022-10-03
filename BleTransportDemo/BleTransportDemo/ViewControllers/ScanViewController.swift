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
    
    fileprivate func connectToPeripheral(_ peripheral: PeripheralIdentifier) {
        guard peripheralConnecting == nil else { return }
        peripheralConnecting = peripheral
        
        transport?.connect(toPeripheralID: peripheral) {
            print("Device disconnected!")
        } success: { [weak self] peripheralConnected in
            self?.connectedPeripheral = peripheralConnected
            self?.performSegue(withIdentifier: "connectedDeviceSegue", sender: nil)
            self?.peripheralConnecting = nil
        } failure: { [weak self] error in
            let alert = UIAlertController(title: "Error connecting", message: "\(error)", preferredStyle: .alert)
            let okAction = UIAlertAction(title: "Ok", style: .cancel)
            alert.addAction(okAction)
            self?.present(alert, animated: true, completion: nil)
            
            self?.peripheralConnecting = nil
        }

    }

    @IBAction func findDevicesButtonTapped(_ sender: Any) {
        if let transport = transport, transport.isBluetoothAvailable {
            self.scanningStateChanged(isScanning: true)
            transport.scan(duration: 5.0) { [weak self] discoveries in
                self?.peripheralsServicesTuple = discoveries
                self?.devicesFoundLabel.alpha = discoveries.isEmpty ? 0.0 : 1.0
                self?.devicesTableView.reloadData()
            } stopped: { [weak self] error in
                self?.scanningStateChanged(isScanning: false)
                self?.devicesFoundLabel.alpha = 0.0
                self?.peripheralsServicesTuple = []
                self?.devicesTableView.reloadData()
                if let error = error {
                    let alert = UIAlertController(title: "Error scanning", message: "\(error)", preferredStyle: .alert)
                    let okAction = UIAlertAction(title: "Ok", style: .cancel)
                    alert.addAction(okAction)
                    self?.present(alert, animated: true, completion: nil)
                }
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
                            print("Couldn't disconnect with error: \(error)")
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
