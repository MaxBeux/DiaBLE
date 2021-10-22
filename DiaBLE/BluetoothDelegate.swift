import Foundation
import CoreBluetooth


class BluetoothDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, Logging {

    var main: MainDelegate!
    var centralManager: CBCentralManager { main.centralManager }
    var app: AppState { main.app }
    var settings: Settings { main.settings }
    @Published var knownDevices: [String: String] = [:]


    public func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        switch manager.state {
        case .poweredOff:
            log("Bluetooth: state: powered off")
            main.errorStatus("Bluetooth powered off")
            if app.device != nil {
                centralManager.cancelPeripheralConnection(app.device.peripheral!)
                app.device.state = .disconnected
            }
            app.deviceState = "Disconnected"
        case .poweredOn:
            log("Bluetooth: state: powered on")
            centralManager.scanForPeripherals(withServices: nil, options: nil)
            main.status("Scanning...")
        case .resetting:    log("Bluetooth: state: resetting")
        case .unauthorized: log("Bluetooth: state: unauthorized")
        case .unknown:      log("Bluetooth: state: unknown")
        case .unsupported:  log("Bluetooth: state: unsupported")
        @unknown default:
            log("Bluetooth: state: unknown")
        }
    }


    public func centralManager(_ manager: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData advertisement: [String: Any], rssi: NSNumber) {
        var name = peripheral.name
        let manufacturerData = advertisement[CBAdvertisementDataManufacturerDataKey] as? Data
        let dataServiceUUIDs = advertisement[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]

        if let dataServiceUUIDs = dataServiceUUIDs, dataServiceUUIDs.count > 0, dataServiceUUIDs[0].uuidString == Abbott.UUID.libre3data.rawValue {
            name = "ABBOTT\(name ?? "unnamedLibre")"    // Libre 3 device name is 12 chars long
        }

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

        let identifier = peripheral.identifier
        var msg = "Bluetooth: \(name!)'s device identifier \(identifier)"
        if knownDevices[identifier.uuidString] == nil {
            msg += " not yet"
            knownDevices[identifier.uuidString] = name
        } else {
            msg += " already"
        }
        debugLog("\(msg) known")

        if advertisement[CBAdvertisementDataIsConnectable] as? Int == 0
            || (didFindATransmitter && !settings.preferredDevicePattern.isEmpty && !name!.matches(settings.preferredDevicePattern))
            || (!didFindATransmitter && (settings.preferredTransmitter != .none || (!settings.preferredDevicePattern.isEmpty && !name!.matches(settings.preferredDevicePattern)))) {
            var scanningFor = "Scanning"
            if !settings.preferredDevicePattern.isEmpty {
                scanningFor += " for '\(settings.preferredDevicePattern)'"
            }
            main.status("\(scanningFor)...\nSkipped \(name!)")
            msg = "Bluetooth: skipped \(name!)"
            if advertisement[CBAdvertisementDataIsConnectable] as? Int == 0 {
                if !settings.preferredDevicePattern.isEmpty && name!.matches(settings.preferredDevicePattern) {
                    msg += " because not connectable"
                    main.errorStatus("(not connectable)")
                }
                if main.settings.debugLevel > 0 { msg += " (advertised data: \(advertisement))" }
            }
            msg += ", \(scanningFor.lowercased())..."
            log(msg)
            return
        }

        centralManager.stopScan()
        if name!.lowercased().hasPrefix("abbott") {
            app.transmitter = Abbott(peripheral: peripheral, main: main)
            app.device = app.transmitter
            if name!.count == 18 { // fictitious "ABBOTT" + Libre 3 real device name
                app.device.name = "Libre 3"
                name = String(name!.suffix(12))
                (app.transmitter as! Abbott).securityGeneration = 3
                app.lastReadingDate = Date() // TODO
            } else {
                app.device.serial = String(name!.suffix(name!.count - 6))
                switch app.device.serial.prefix(1) {
                case "7":
                    app.device.name = "Libre Sense"
                    (app.transmitter as! Abbott).securityGeneration = 2
                case "3":
                    app.device.name = "Libre 2"
                default: app.device.name = "Libre"
                // TODO: Libre 2 US / CA
                }
            }
            settings.activeSensorSerial = app.device.serial

        } else if name!.prefix(6) == "Bubble" {
            app.transmitter = Bubble(peripheral: peripheral, main: main)
            app.device = app.transmitter

        } else if name!.matches("miaomiao") {
            app.transmitter = MiaoMiao(peripheral: peripheral, main: main)
            app.device = app.transmitter

            // } else if name.matches("custom") {
            //    custom = Custom(peripheral: peripheral, main: main)
            //    app.device = custom
            //    app.device.name = peripheral.name!
            //    app.transmitter = custom.transmitter
            //    app.transmitter.name = "bridge"

        } else if name!.prefix(13) == "Mi Smart Band" {
            app.device = Device(peripheral: peripheral, main: main)
            app.device.name = name!
            if manufacturerData!.count >= 8 {
                app.device.macAddress = Data(manufacturerData!.suffix(6))
                log("Bluetooth: \(name!) MAC address: \(app.device.macAddress.hex.uppercased())")
            }

        } else {
            app.device = Device(peripheral: peripheral, main: main)
            app.device.name = name!.replacingOccurrences(of: "an unnamed", with: "Unnamed")
        }

        app.device.rssi = Int(truncating: rssi)
        app.device.company = BLE.companies[companyId].name
        msg = "Bluetooth: found \(name!): RSSI: \(rssi), advertised data: \(advertisement)"
        if app.device.company == "< Unknown >" {
            if companyId != BLE.companies.count - 1 {
                msg += ", company id: \(companyId) (0x\(companyId.hex), unknown)"
            }
        } else {
            msg += ", company: \(app.device.company) (id: 0x\(companyId.hex))"
        }
        log(msg)
        if let manufacturerData = manufacturerData {
            app.device.parseManufacturerData(manufacturerData)
        }
        if let dataServiceUUIDs = dataServiceUUIDs {
            // TODO: assign to device instance vars
            log("Bluetooth: \(name!)'s data service UUIDs: \(dataServiceUUIDs)")
        }
        main.status("\(app.device.name)")
        app.device.peripheral?.delegate = self
        log("Bluetooth: connecting to \(name!)...")
        centralManager.connect(app.device.peripheral!, options: nil)
        app.device.state = app.device.peripheral!.state
        app.deviceState = app.device.state.description.capitalized + "..."
    }


    public func centralManager(_ manager: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name ?? "an unnamed peripheral"
        var msg = "Bluetooth: \(name) has connected"
        app.device.state = peripheral.state
        app.deviceState = app.device.state.description.capitalized
        app.device.lastConnectionDate = Date()
        app.lastConnectionDate = app.device.lastConnectionDate
        msg += ("; discovering services")
        peripheral.discoverServices(nil)
        log(msg)
    }


    public func centralManager(_ manager: CBCentralManager, willRestoreState dict: [String: Any]) {
        log("Bluetooth: will restore state to \(dict.debugDescription)")
    }


    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let name = peripheral.name ?? "unnamed peripheral"
        if app.device.name == "Unnamed peripheral" && name != "unnamed peripheral" {
            app.device.name = name
            main.status("\(app.device.name)")
        }
        app.device.state = peripheral.state
        if let services = peripheral.services {
            for service in services {
                let serviceUUID = service.uuid.uuidString
                var description = "unknown service"
                if serviceUUID == type(of: app.device).dataServiceUUID {
                    description = "data service"
                }
                // TODO
                if serviceUUID == Abbott.UUID.libre3data.rawValue {
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
                log(msg)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else {
            log("Bluetooth: unable to retrieve service characteristics")
            return
        }

        let serviceUUID = service.uuid.uuidString
        var serviceDescription = serviceUUID
        if serviceUUID == type(of: app.device).dataServiceUUID || serviceUUID == Abbott.UUID.libre3data.rawValue {
            serviceDescription = "data"
        }

        for characteristic in characteristics {
            let uuid = characteristic.uuid.uuidString

            var msg = "Bluetooth: discovered \(app.device.name) \(serviceDescription) service's characteristic \(uuid)"
            msg += (", properties: \(characteristic.properties)")

            if uuid == Abbott.UUID.libre3data0x1482.rawValue {
                msg += " (Libre 3 data read); avoid enabling notifications because of 'Encryption is insufficient' error"


            } else if uuid == Abbott.dataReadCharacteristicUUID || uuid == Bubble.dataReadCharacteristicUUID || uuid == MiaoMiao.dataReadCharacteristicUUID {
                app.device.readCharacteristic = characteristic
                msg += " (data read)"

                // enable Libre notifications only in didWriteValueFor()
                if uuid != Abbott.dataReadCharacteristicUUID {
                    app.device.peripheral?.setNotifyValue(true, for: app.device.readCharacteristic!)
                    msg += "; enabling notifications"
                }

            } else if uuid == Abbott.dataWriteCharacteristicUUID || uuid == Bubble.dataWriteCharacteristicUUID || uuid == MiaoMiao.dataWriteCharacteristicUUID {
                msg += " (data write)"
                app.device.writeCharacteristic = characteristic


                //   } else if let uuid = Custom.UUID(rawValue: uuid) {
                //      msg += " (\(uuid))"
                //      if uuid.description.contains("unknown") {
                //          if characteristic.properties.contains(.notify) {
                //              app.device.peripheral?.setNotifyValue(true, for: characteristic)
                //          }
                //          if characteristic.properties.contains(.read) {
                //              app.device.peripheral?.readValue(for: characteristic)
                //              msg += "; reading it"
                //          }
                //      }


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

            log(msg)

            app.device.characteristics[uuid] = characteristic

        }


        // TODO

        if serviceUUID == Abbott.UUID.libre3unknownService.rawValue {
            log("Bluetooth: sending the very first Libre 3 BLE command: 0x11")
            app.device.write(Data([0x11]), for: Abbott.UUID.libre3unknown0x2198.rawValue, .withResponse)
        }


        if app.device.type == .transmitter(.abbott) && serviceUUID == Abbott.dataServiceUUID {
            var sensor: Sensor! = app.sensor
            if app.sensor == nil {
                sensor = Libre2(transmitter: app.transmitter)
                app.sensor = sensor
                sensor.state = .active
                sensor.uid = (app.device as! Abbott).uid
                // TODO
                settings.patchUid = sensor.uid

                if settings.activeSensorSerial == app.device.serial {
                    if !settings.patchInfo.isEmpty {
                        sensor.patchInfo = settings.patchInfo

                    } else {
                        sensor.serial = app.device.serial
                        let family = Int(app.device.serial.prefix(1)) ?? 0
                        switch family {
                        case 7:  sensor.type = .libreSense
                        case 3:  sensor.type = .libre2
                        default: sensor.type = .libre2
                        // TODO: .libre2US / .libre2CA
                        }
                        sensor.family = SensorFamily(rawValue: family) ?? .libre
                    }
                }
            }

            app.transmitter.sensor = sensor

            if settings.activeSensorSerial == app.device.serial {
                sensor.initialPatchInfo = settings.activeSensorInitialPatchInfo
                sensor.streamingUnlockCode = UInt32(settings.activeSensorStreamingUnlockCode)
                sensor.streamingUnlockCount = UInt16(settings.activeSensorStreamingUnlockCount)
                sensor.calibrationInfo = settings.activeSensorCalibrationInfo
                sensor.maxLife = settings.activeSensorMaxLife
                log("Bluetooth: the active sensor \(app.device.serial) has reconnected: restoring settings: initial patch info: \(sensor.initialPatchInfo.hex), current patch info: \(sensor.patchInfo.hex), unlock count: \(sensor.streamingUnlockCount)")
            }
            app.device.macAddress = settings.activeSensorAddress

            if (app.transmitter as! Abbott).securityGeneration > 1 && (app.transmitter as! Abbott).authenticationState == .notAuthenticated {
                app.device.peripheral?.setNotifyValue(true, for: app.device.writeCharacteristic!)
                (app.transmitter as! Abbott).authenticationState = .enableNotification
                debugLog("Bluetooth: enabled \(app.device.name) security notification")
                // TODO: move to didUpdateNotificationStateFor()
                (app.transmitter as! Abbott).authenticationState = .challengeResponse
                app.device.write(Data([0x20]), .withResponse)
                debugLog("Bluetooth: sent \(app.device.name) read security challenge")

            } else if sensor.uid.count > 0 && sensor.patchInfo.count > 0 && settings.activeSensorInitialPatchInfo.count > 0 {
                sensor.streamingUnlockCount += 1
                settings.activeSensorStreamingUnlockCount += 1
                let unlockPayload = Libre2.streamingUnlockPayload(id: sensor.uid, info: settings.activeSensorInitialPatchInfo, enableTime: sensor.streamingUnlockCode, unlockCount: sensor.streamingUnlockCount)
                log("Bluetooth: writing streaming unlock payload: \(Data(unlockPayload).hex) (patch info: \(settings.activeSensorInitialPatchInfo.hex), unlock code: \(sensor.streamingUnlockCode), unlock count: \(sensor.streamingUnlockCount), sensor id: \(sensor.uid.hex), current patch info: \(sensor.patchInfo.hex))")
                app.device.write(unlockPayload, .withResponse)
            }
        }

        if app.device.type == .transmitter(.bubble) && serviceUUID == Bubble.dataServiceUUID {
            let readCommand = app.transmitter.readCommand(interval: settings.readingInterval)
            app.device.write(readCommand)
            log("Bubble: writing start reading command 0x\(Data(readCommand).hex)")
            // app.device.write([0x00, 0x01, 0x05])
            // log("Bubble: writing reset and send data every 5 minutes command 0x000105")
        }

        if app.device.type == .transmitter(.miaomiao) && serviceUUID == MiaoMiao.dataServiceUUID {
            let readCommand = app.device.readCommand(interval: settings.readingInterval)
            app.device.write(readCommand)
            log("\(app.device.name): writing start reading command 0x\(Data(readCommand).hex)")
            // app.device.write([0xD3, 0x01]); log("MiaoMiao: writing start new sensor command D301")
        }
    }


    public func centralManager(_ manager: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let name = peripheral.name ?? "an unnamed peripheral"
        app.device?.state = peripheral.state
        app.deviceState = peripheral.state.description.capitalized
        if error != nil {
            log("Bluetooth: \(name) has disconnected.")
            let errorCode = CBError.Code(rawValue: (error! as NSError).code)! // 6 = timed out when out of range
            log("Bluetooth: error type \(errorCode.rawValue): \(error!.localizedDescription)")
            if app.transmitter != nil && (settings.preferredTransmitter == .none || settings.preferredTransmitter.id == app.transmitter.type.id) {
                app.deviceState = "Reconnecting..."
                log("Bluetooth: reconnecting to \(name)...")
                if errorCode == .connectionTimeout { main.errorStatus("Connection timed out. Waiting...") }
                app.device.buffer = Data()
                centralManager.connect(peripheral, options: nil)
            } else {
                app.device.lastConnectionDate = Date()
                app.lastConnectionDate = app.device.lastConnectionDate
                // app.device = nil
                // app.transmitter = nil
            }
        } else {
            log("Bluetooth: stopped connecting with \(name).")
            app.device.lastConnectionDate = Date()
            app.lastConnectionDate = app.device.lastConnectionDate
            // app.device = nil
            // app.transmitter = nil
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
            main.errorStatus("Failed to connect: \(error!.localizedDescription)")
        } else {
            msg += "; retrying..."
            main.errorStatus("Failed to connect, retrying...")
            centralManager.connect(app.device.peripheral!, options: nil)
        }

        log(msg)
    }


    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let name = peripheral.name ?? "an unnamed peripheral"
        var characteristicString = characteristic.uuid.uuidString
        if [Abbott.dataWriteCharacteristicUUID, Bubble.dataWriteCharacteristicUUID, MiaoMiao.dataWriteCharacteristicUUID].contains(characteristicString) {
            characteristicString = "data write"
        }
        if error != nil {
            log("Bluetooth: error while writing \(name)'s \(characteristicString) characteristic value: \(error!.localizedDescription)")
        } else {
            log("Bluetooth: \(name) did write value for \(characteristicString) characteristic")
            if characteristic.uuid.uuidString == Abbott.dataWriteCharacteristicUUID {
                app.device.peripheral?.setNotifyValue(true, for: app.device.readCharacteristic!)
                log("Bluetooth: enabling data read notifications for \(name)")
            }
        }
    }


    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let name = peripheral.name ?? "an unnamed peripheral"
        var characteristicString = characteristic.uuid.uuidString
        if [Abbott.dataReadCharacteristicUUID, Bubble.dataReadCharacteristicUUID, MiaoMiao.dataReadCharacteristicUUID].contains(characteristicString) {
            characteristicString = "data read"
        }
        var msg = "Bluetooth: \(name) did update notification state for \(characteristicString) characteristic"
        msg += ": \(characteristic.isNotifying ? "" : "not ")notifying"
        if let descriptors = characteristic.descriptors { msg += ", descriptors: \(descriptors)" }
        if let error = error { msg += ", error: \(error.localizedDescription)" }
        log(msg)
    }


    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let name = peripheral.name ?? "an unnamed peripheral"
        var characteristicString = characteristic.uuid.uuidString
        if [Abbott.dataReadCharacteristicUUID, Bubble.dataReadCharacteristicUUID, MiaoMiao.dataReadCharacteristicUUID].contains(characteristicString) {
            characteristicString = "data read"
        }

        if let uuid = Abbott.UUID(rawValue: characteristicString), uuid.description.hasPrefix("Libre 3") {
            characteristicString = uuid.description
        }

        guard let data = characteristic.value else {
            log("Bluetooth: \(name)'s error updating value for \(characteristicString) characteristic: \(error!.localizedDescription)")
            return
        }

        var msg = "Bluetooth: \(name) did update value for \(characteristicString) characteristic (\(data.count) bytes received):"
        if data.count > 0 {
            msg += " hex: \(data.hex),"
        }

        if let uuid = BLE.UUID(rawValue: characteristic.uuid.uuidString) {

            log("\(msg) \(uuid): \(uuid != .batteryLevel ? "\"\(data.string)\"" : String(Int(data[0])))")

            switch uuid {

            case .batteryLevel:
                app.device.battery = Int(data[0])
            case .model:
                app.device.model = data.string
                if app.device.peripheral?.name == nil {
                    app.device.name = app.device.model
                    main.status(app.device.name)
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

            log("\(msg) string: \"\(data.string)\"")


            if app.device == nil { return }     // the connection timed out in the meantime

            app.device.lastConnectionDate = Date()
            app.lastConnectionDate = app.device.lastConnectionDate

            app.device.read(data, for: characteristic.uuid.uuidString)

            if app.device.type == .transmitter(.abbott) {
                if app.transmitter.buffer.count == 46 {
                    main.didParseSensor(app.transmitter.sensor!)
                    app.transmitter.buffer = Data()
                }

            } else if app.device.type == .transmitter(.bubble) || app.device.type == .transmitter(.miaomiao) {
                var headerLength = 0
                if app.device.type == .transmitter(.miaomiao) && characteristic.uuid.uuidString == MiaoMiao.dataReadCharacteristicUUID {
                    headerLength = 18 + 1
                }
                if let sensor = app.transmitter.sensor, sensor.fram.count > 0, app.transmitter.buffer.count >= (sensor.fram.count + headerLength) {
                    main.parseSensorData(sensor)
                    app.transmitter.buffer = Data()
                }

            } else if app.transmitter?.sensor != nil {
                main.didParseSensor(app.transmitter.sensor!)
                app.transmitter.buffer = Data()
            }
        }
    }
}
