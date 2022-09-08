Pod::Spec.new do |s|
  s.name = 'BleTransport'
  s.version = '0.0.1'
  s.license = { type: 'MIT', file: 'LICENSE' }
  s.homepage = 'https://github.com/LedgerHQ/ios-ble'
  s.authors = { 'Dante Puglisi' => 'dante.puglisi-ext@ledger.fr', 'Juan Cortes' => 'juan.cortes-ext@ledger.fr' }
  s.summary = 'BleTransport for Ledger devices written in Swift'
  s.source = { git: 'https://github.com/LedgerHQ/ios-ble.git', tag: 'v0.8.9' }
  s.source_files = 'Sources/BleTransport/*.{m,h,swift}', 'Sources/BleTransport/Module/*.{m,h,swift}'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
end
