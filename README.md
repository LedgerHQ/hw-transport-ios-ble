<img src="https://user-images.githubusercontent.com/4631227/191834116-59cf590e-25cc-4956-ae5c-812ea464f324.png" height="100" />

[GitHub](https://github.com/LedgerHQ/ledger-live/),
[Ledger Devs Discord](https://developers.ledger.com/discord-pro),
[Developer Portal](https://developers.ledger.com/)

# BleTransport (beta)

Allows for communication with Ledger Hardware Wallets via BLE (Bluetooth Low Energy) on iOS (>=13.0) and macOS (>=12.0). Please note that this is a beta release and still under active development.

## Usage

The demo application is the best way to see `BleTransport` in action. Simply open the `BleTransport.xcodeproj` and run the `BleTransportDemo` or `BleTransportDemoMac` scheme.

Basic example:
```swift
import BleTransport

BleTransport.shared.scan(duration: 30.0) { discoveries in
    guard let id = discoveries.first?.peripheral else {
        return
    }

    BleTransport.shared.connect(toPeripheralID: id, disconnectedCallback: nil) { peripheral in
        print("Connected to device: \(peripheral.name)")
    } failure: { error in
        print("Error while connecting: \(error)")
    }

} stopped: { error in
    print("Error while scanning: \(error)")
}
```

## Installation

### CocoaPods

BleTransport is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```bash
pod 'BleTransport'
```

### Swift Package Manager

To integrate using Apple's [Swift Package Manager](https://swift.org/package-manager/), add the following as a dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/LedgerHQ/hw-transport-ios-ble.git", from: "1.0.0")
]
```
