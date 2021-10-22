import Foundation
import CoreBluetooth

class MiaoMiao: Transmitter {
    override class var type: DeviceType { DeviceType.transmitter(.miaomiao) }
    override class var name: String { "MiaoMiao" }

    enum UUID: String, CustomStringConvertible, CaseIterable {
        case data      = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
        case dataWrite = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
        case dataRead  = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

        var description: String {
            switch self {
            case .data:      return "data"
            case .dataWrite: return "data write"
            case .dataRead:  return "data read"
            }
        }
    }

    override class var knownUUIDs: [String] { UUID.allCases.map{$0.rawValue} }

    override class var dataServiceUUID: String             { UUID.data.rawValue }
    override class var dataWriteCharacteristicUUID: String { UUID.dataWrite.rawValue }
    override class var dataReadCharacteristicUUID: String  { UUID.dataRead.rawValue }

    enum ResponseType: UInt8, CustomStringConvertible {
        case dataPacket = 0x28
        case newSensor  = 0x32
        case noSensor   = 0x34
        case frequencyChange = 0xD1

        var description: String {
            switch self {
            case .dataPacket:      return "data packet"
            case .newSensor:       return "new sensor"
            case .noSensor:        return "no sensor"
            case .frequencyChange: return "frequency change"
            }
        }
    }

    override init(peripheral: CBPeripheral?, main: MainDelegate) {
        super.init(peripheral: peripheral!, main: main)
        if let peripheral = peripheral, peripheral.name!.contains("miaomiao2") {
            name += " 2"
        }
    }

    override func readCommand(interval: Int = 5) -> Data {
        var command = [UInt8(0xF0)]
        if [1, 3].contains(interval) {
            command.insert(contentsOf: [0xD1, UInt8(interval)], at: 0)
        }
        return Data(command)
    }

    override func parseManufacturerData(_ data: Data) {
        if data.count >= 8 {
            macAddress = data.suffix(6)
            log("\(Self.name): MAC address: \(macAddress.hexAddress)")
        }
    }

    override func read(_ data: Data, for uuid: String) {

        // https://github.com/NightscoutFoundation/xDrip/blob/master/app/src/main/java/com/eveningoutpost/dexdrip/Models/Tomato.java
        // https://github.com/UPetersen/LibreMonitor/blob/Swift4/LibreMonitor/Bluetooth/MiaoMiaoManager.swift
        // https://github.com/gshaviv/ninety-two/blob/master/WoofWoof/MiaoMiao.swift

        let response = ResponseType(rawValue: data[0])
        if buffer.count == 0 {
            log("\(name) response: \(response?.description ?? "unknown") (0x\(data[0...0].hex))")
        }
        if data.count == 1 {
            if response == .noSensor {
                main.status("\(name): no sensor")
            }
            // TODO: prompt the user and allow writing the command 0xD301 to change sensor
            if response == .newSensor {
                main.status("\(name): detected a new sensor")
            }
        } else if data.count == 2 {
            if response == .frequencyChange {
                if data[1] == 0x01 {
                    log("\(name): success changing frequency")
                } else {
                    log("\(name): failed to change frequency")
                }
            }
        } else {
            if sensor == nil {
                sensor = Sensor(transmitter: self)
                main.app.sensor = sensor
            }
            if buffer.count == 0 { sensor!.lastReadingDate = main.app.lastReadingDate }
            buffer.append(data)
            log("\(name): partial buffer size: \(buffer.count)")
            if buffer.count >= 363 {
                log("\(name): data size: \(Int(buffer[1]) << 8 + Int(buffer[2]))")

                battery = Int(buffer[13])
                firmware = buffer[14...15].hex
                hardware = buffer[16...17].hex
                log("\(name): battery: \(battery), firmware: \(firmware), hardware: \(hardware)")

                sensor!.age = Int(buffer[3]) << 8 + Int(buffer[4])
                sensor!.uid = Data(buffer[5...12])
                main.settings.patchUid = sensor!.uid
                log("\(name): sensor age: \(sensor!.age) minutes (\(String(format: "%.1f", Double(sensor!.age)/60/24)) days), patch uid: \(sensor!.uid.hex)")

                if buffer.count >= 369 {
                    sensor!.patchInfo = Data(buffer[363...368])
                    main.settings.patchInfo = sensor!.patchInfo
                    main.settings.activeSensorSerial = sensor!.serial
                    log("\(name): patch info: \(sensor!.patchInfo.hex), sensor type: \(sensor!.type.rawValue), serial number: \(sensor!.serial)")
                } else {
                    // https://github.com/dabear/LibreOOPAlgorithm/blob/master/app/src/main/java/com/hg4/oopalgorithm/oopalgorithm/AlgorithmRunner.java
                    sensor!.patchInfo = Data([0xDF, 0x00, 0x00, 0x01, 0x01, 0x02])
                }
                sensor!.fram = Data(buffer[18 ..< 362])
                main.status("\(sensor!.type)  +  \(name)")
            }
        }
    }
}
