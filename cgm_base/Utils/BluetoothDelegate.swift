import Foundation
import CoreBluetooth


class BluetoothDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    var main: CGMManager!
    var centralManager: CBCentralManager { main.centralManager }
    var app: AppState { main.app }
    var settings: Settings { main.settings }

    public func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        switch manager.state {
        case .poweredOff:
            debugPrint("Bluetooth: state: powered off")
            if app.device != nil {
                centralManager.cancelPeripheralConnection(app.device.peripheral!)
                app.device.state = .disconnected
            }
        case .poweredOn:
            debugPrint("Bluetooth: state: powered on")
            
            let serviceUUIDs:[CBUUID] = [CBUUID(string: "180A")]
            let lastPeripherals = centralManager.retrieveConnectedPeripherals(withServices: serviceUUIDs)
            debugPrint("listing connected stuff")
            debugPrint(String(lastPeripherals.count))
            var connected = false
            for peripheral in lastPeripherals {
                if peripheral.name != nil {
                    let name = peripheral.name
                    debugPrint(peripheral.name!)
                    if name!.lowercased().hasPrefix("abbott") {
                        app.transmitter = Libre(peripheral: peripheral, main: main)
                        app.device = app.transmitter
                        app.device.name = "Libre 2"
                        app.device.serial = String(name!.suffix(name!.count - 6))
                        settings.activeSensorSerial = app.device.serial
                        app.device.rssi = 10
                        app.device.company = BLE.companies[955].name
                        app.device.peripheral?.delegate = self
                        debugPrint("Bluetooth: connecting to \(name!)...")
                        centralManager.connect(app.device.peripheral!, options: nil)
                        debugPrint("Device Connecting...")
                        connected = true
                        debugPrint("hopefully getting data now")
                    }
                } else {
                    debugPrint("unknown peripheral i guess")
                }
            }
            debugPrint("end of listing stuff for now")
            if (!connected){
                centralManager.scanForPeripherals(withServices: nil, options: nil)
                debugPrint("Scanning...")
            }
        case .resetting:    debugPrint("Bluetooth: state: resetting")
        case .unauthorized: debugPrint("Bluetooth: state: unauthorized")
        case .unknown:      debugPrint("Bluetooth: state: unknown")
        case .unsupported:  debugPrint("Bluetooth: state: unsupported")
        @unknown default:
            debugPrint("Bluetooth: state: unknown")
        }
    }


    public func centralManager(_ manager: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData advertisement: [String : Any], rssi: NSNumber) {
        var name = peripheral.name
        let manufacturerData = advertisement["kCBAdvDataManufacturerData"] as? Data

        var didFindATransmitter = false

        if let name = name {
            for transmitterType in TransmitterType.allCases {
                if name.matches(transmitterType.id) {
                    didFindATransmitter = true
                    if settings.preferredTransmitter != .none && transmitterType != settings.preferredTransmitter {
                        didFindATransmitter = false
                    }
                }
            }
        }

        var companyId = BLE.companies.count - 1 // "< Unknown >"
        if let manufacturerData = manufacturerData {
            companyId = Int(manufacturerData[0]) + Int(manufacturerData[1]) << 8
            if companyId >= BLE.companies.count { companyId = BLE.companies.count - 1 }    // when 0xFFFF
        }

        if name == nil {
            name = "an unnamed peripheral"
            if BLE.companies[companyId].name != "< Unknown >" {
                name = "\(BLE.companies[companyId].name)'s unnamed peripheral"
            }
        }

        if (didFindATransmitter && !settings.preferredDevicePattern.isEmpty && !name!.matches(settings.preferredDevicePattern))
            || !didFindATransmitter && (settings.preferredTransmitter != .none || (!settings.preferredDevicePattern.isEmpty && !name!.matches(settings.preferredDevicePattern))) {
            var scanningFor = "Scanning"
            if !settings.preferredDevicePattern.isEmpty {
                scanningFor += " for '\(settings.preferredDevicePattern)'"
            }
            
            debugPrint("\(scanningFor)...\nSkipping \(name!)...")
            debugPrint("Bluetooth: \(scanningFor.lowercased()), skipping \(name!)")

            return
        }

        centralManager.stopScan()
        if name!.lowercased().hasPrefix("abbott") {
            app.transmitter = Libre(peripheral: peripheral, main: main)
            app.device = app.transmitter
            app.device.name = "Libre 2"
            app.device.serial = String(name!.suffix(name!.count - 6))
            settings.activeSensorSerial = app.device.serial
        } else {
            app.device = Device(peripheral: peripheral, main: main)
            app.device.name = name!
        }

        app.device.rssi = Int(truncating: rssi)
        app.device.company = BLE.companies[companyId].name
        var msg = "Bluetooth: found \(name!): RSSI: \(rssi), advertised data: \(advertisement)"
        if app.device.company == "< Unknown >" {
            if companyId != BLE.companies.count - 1 {
                msg += ", company id: \(companyId) (0x\(String(format: "%04x", companyId)), unknown)"
            }
        }
        else {
            msg += ", company: \(app.device.company) (id: 0x\(String(format: "%04x", companyId)))"
        }
        debugPrint(msg)
        if let manufacturerData = manufacturerData {
            app.device.parseManufacturerData(manufacturerData)
        }
        debugPrint("\(app.device.name)")
        app.device.peripheral?.delegate = self
        debugPrint("Bluetooth: connecting to \(name!)...")
        centralManager.connect(app.device.peripheral!, options: nil)
    }


    public func centralManager(_ manager: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name ?? "an unnamed peripheral"
        var msg = "Bluetooth: \(name) has connected"
        if app.device.state == .disconnected {
            app.device.state = peripheral.state
            msg += ("; discovering services")
            peripheral.discoverServices(nil)
        }
        debugPrint(msg)
    }


    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let name = peripheral.name ?? "unnamed peripheral"
        app.device.state = peripheral.state
        if let services = peripheral.services {
            for service in services {
                let serviceUUID = service.uuid.uuidString
                var description = "unknown service"
                if serviceUUID == type(of: app.device).dataServiceUUID {
                    description = "data service"
                }
                if let uuid = BLE.UUID(rawValue: serviceUUID) {
                    description = uuid.description
                }
                var msg = "Bluetooth: discovered \(name)'s service \(serviceUUID) (\(description))"
                if !(serviceUUID == BLE.UUID.device.rawValue && app.device.characteristics[BLE.UUID.manufacturer.rawValue] != nil) {
                    msg += "; discovering characteristics"
                    peripheral.discoverCharacteristics(nil, for: service)
                }
                debugPrint(msg)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else {
            debugPrint("Bluetooth: unable to retrieve service characteristics")
            return
        }

        let serviceUUID = service.uuid.uuidString
        var serviceDescription = serviceUUID
        if serviceUUID == type(of: app.device).dataServiceUUID {
            serviceDescription = "data"
        }

        for characteristic in characteristics {
            let uuid = characteristic.uuid.uuidString

            var msg = "Bluetooth: discovered \(app.device.name) \(serviceDescription) service's characteristic \(uuid)"
            msg += (", properties: \(characteristic.properties)")

            if uuid == Libre.dataReadCharacteristicUUID {
                app.device.readCharacteristic = characteristic
                msg += " (data read)"

                // enable Libre notifications only in didWriteValueFor()
                if uuid != Libre.dataReadCharacteristicUUID {
                    app.device.peripheral?.setNotifyValue(true, for: app.device.readCharacteristic!)
                    msg += "; enabling notifications"
                }

            } else if uuid == Libre.dataWriteCharacteristicUUID {
                msg += " (data write)"
                app.device.writeCharacteristic = characteristic


                //           } else if let uuid = Custom.UUID(rawValue: uuid) {
                //              msg += " (\(uuid))"
                //              if uuid.description.contains("unknown") {
                //                  if characteristic.properties.contains(.notify) {
                //                      app.device.peripheral?.setNotifyValue(true, for: characteristic)
                //                  }
                //                  if characteristic.properties.contains(.read) {
                //                      app.device.peripheral?.readValue(for: characteristic)
                //                      msg += "; reading it"
                //                  }
                //              }


            } else if let uuid = BLE.UUID(rawValue: uuid) {
                if uuid == .batteryLevel {
                    app.device.peripheral?.setNotifyValue(true, for: characteristic)
                }

                if app.device.characteristics[uuid.rawValue] != nil {
                    msg += " (\(uuid)); already read it"
                } else {
                    app.device.peripheral?.readValue(for: characteristic)
                    msg += " (\(uuid)); reading it"
                }

                // } else if let uuid = OtherDevice.UUID(rawValue: uuid) {
                //    msg += " (\(uuid))"

            } else {
                msg += " (unknown)"
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
                if characteristic.properties.contains(.read) {
                    peripheral.readValue(for: characteristic)
                    msg += "; reading it"
                }
            }

            debugPrint(msg)

            app.device.characteristics[uuid] = characteristic

        }

        if app.device.type == .transmitter(.abbott) && serviceUUID == Libre.dataServiceUUID {
            var sensor: Sensor! = app.sensor
            if app.sensor == nil {
                sensor = Sensor(transmitter: app.transmitter)
                app.sensor = sensor

                if settings.activeSensorSerial == app.device.serial {
                    sensor.uid = settings.patchUid
                    sensor.patchInfo = settings.patchInfo
                } else { // TEST
                    sensor.uid = Data("2fe7b10000a407e0".bytes)
                    sensor.patchInfo = Data("9d083001712b".bytes)
                }
            }

            app.transmitter.sensor = sensor

            if settings.activeSensorSerial == app.device.serial {
                sensor.unlockCode = UInt32(settings.activeSensorUnlockCode)
                sensor.unlockCount = UInt16(settings.activeSensorUnlockCount)
                debugPrint("Bluetooth: the active sensor \(app.device.serial) has reconnected: restoring settings: unlock count: \(sensor.unlockCount )")
            }
            app.device.macAddress = settings.activeSensorAddress
            sensor.unlockCount += 1
            settings.activeSensorUnlockCount += 1
            debugPrint("Bluetooth: writing streaming unlock payload: \(Data(Libre2.streamingUnlockPayload(id: sensor.uid, info: sensor.patchInfo, enableTime: sensor.unlockCode, unlockCount: sensor.unlockCount)).hex) (unlock code: \(sensor.unlockCode), unlock count: \(sensor.unlockCount), sensor id: \(sensor.uid.hex), patch info: \(sensor.patchInfo.hex))")
            app.device.write([UInt8](Data(Libre2.streamingUnlockPayload(id: sensor.uid, info: sensor.patchInfo, enableTime: sensor.unlockCode, unlockCount: sensor.unlockCount))), .withResponse)
        }
    }


    public func centralManager(_ manager: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let name = peripheral.name ?? "an unnamed peripheral"
        app.device.state = peripheral.state
        debugPrint("Bluetooth: \(name) has disconnected.")
        if error != nil {
            let errorCode = CBError.Code(rawValue: (error! as NSError).code)! // 6 = timed out when out of range
            debugPrint("Bluetooth: error type \(errorCode.rawValue): \(error!.localizedDescription)")
            if app.transmitter != nil && (settings.preferredTransmitter == .none || settings.preferredTransmitter.id == app.transmitter.type.id) {
                debugPrint("Bluetooth: reconnecting to \(name)...")
                if errorCode == .connectionTimeout { debugPrint("Connection timed out. Waiting...") }
                app.device.buffer = Data()
                centralManager.connect(peripheral, options: nil)
            } else {
                app.device = nil
                app.transmitter = nil
            }
        } else {
            app.device = nil
            app.transmitter = nil
        }
    }

    public func centralManager(_ manager: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let name = peripheral.name ?? "an unnamed peripheral"
        var msg = "Bluetooth: failed to connect to \(name)"
        var errorCode: CBError.Code?

        if let error = error {
            errorCode = CBError.Code(rawValue: (error as NSError).code)
            msg += ", error type \(errorCode!.rawValue): \(error.localizedDescription)"
        }

        if let errorCode = errorCode, errorCode.rawValue == 14 { // Peer removed pairing information
            debugPrint("Failed to connect: \(error!.localizedDescription)")
        } else {
            msg += "; retrying..."
            debugPrint("Failed to connect, retrying...")
            centralManager.connect(app.device.peripheral!, options: nil)
        }

        debugPrint(msg)
    }


    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let name = peripheral.name ?? "an unnamed peripheral"
        var characteristicString = characteristic.uuid.uuidString
        if [Libre.dataWriteCharacteristicUUID].contains(characteristicString) {
            characteristicString = "data write"
        }
        if error != nil {
            debugPrint("Bluetooth: error while writing \(name)'s \(characteristicString) characteristic value: \(error!.localizedDescription)")
        } else {
            debugPrint("Bluetooth: \(name) did write value for \(characteristicString) characteristic")
            if characteristic.uuid.uuidString == Libre.dataWriteCharacteristicUUID {
                app.device.peripheral?.setNotifyValue(true, for: app.device.readCharacteristic!)
                debugPrint("Bluetooth: enabling data read notifications for \(name)")
            }
        }
    }


    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let name = peripheral.name ?? "an unnamed peripheral"
        var characteristicString = characteristic.uuid.uuidString
        if [Libre.dataReadCharacteristicUUID].contains(characteristicString) {
            characteristicString = "data read"
        }
        var msg = "Bluetooth: \(name) did update notification state for \(characteristicString) characteristic"
        msg += ": \(characteristic.isNotifying ? "" : "not ")notifying"
        if let descriptors = characteristic.descriptors { msg += ", descriptors: \(descriptors)" }
        if let error = error { msg += ", error: \(error.localizedDescription)" }
        debugPrint(msg)
    }


    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let name = peripheral.name ?? "an unnamed peripheral"
        var characteristicString = characteristic.uuid.uuidString
        if [Libre.dataReadCharacteristicUUID].contains(characteristicString) {
            characteristicString = "data read"
        }

        guard let data = characteristic.value else {
            debugPrint("Bluetooth: \(name)'s error updating value for \(characteristicString) characteristic: \(error!.localizedDescription)")
            return
        }

        var msg = "Bluetooth: \(name) did update value for \(characteristicString) characteristic (\(data.count) bytes received):"
        if data.count > 0 {
            msg += " hex: \(data.hex),"
        }

        if let uuid = BLE.UUID(rawValue: characteristic.uuid.uuidString) {

            debugPrint("\(msg) \(uuid): \(uuid != .batteryLevel ? "\"\(data.string)\"" : String(Int(data[0])))")

            switch uuid {

            case .batteryLevel:
                app.device.battery = Int(data[0])
            case .model:
                app.device.model = data.string
                if app.device.peripheral?.name == nil {
                    app.device.name = app.device.model
                    debugPrint(app.device.name)
                }
            case .serial:
                app.device.serial = data.string
            case .firmware:
                app.device.firmware = data.string
            case .hardware:
                app.device.hardware += data.string
            case .software:
                app.device.software = data.string
            case .manufacturer:
                app.device.manufacturer = data.string

            default:
                break
            }

        } else {
            debugPrint("\(msg) string: \"\(data.string)\"")
            app.lastReadingDate = Date()
            app.device.read(data, for: characteristic.uuid.uuidString)

            if app.device.type == .transmitter(.abbott)  {
                if app.transmitter.buffer.count == 46 {
                    main.didParseSensor(app.transmitter.sensor!)
                    app.transmitter.buffer = Data()
                }
            } else if app.transmitter?.sensor != nil {
                main.didParseSensor(app.transmitter.sensor!)
            }
        }
    }

        
}
