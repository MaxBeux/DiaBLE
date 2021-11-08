import Foundation


// https://github.com/NightscoutFoundation/xDrip/blob/master/app/src/main/java/com/eveningoutpost/dexdrip/UtilityModels/Blukon.java
// https://github.com/JohanDegraeve/xdripswift/tree/master/xdrip/BluetoothTransmitter/CGM/Libre/Blucon


// TODO: complete restore from 2020/04/11 https://github.com/nshtg/DiaBLE/commit/4a6ed3e5ee488019b71b467c5b503a500403d1c0


class BluCon: Transmitter {
    override class var type: DeviceType { DeviceType.transmitter(.blu) }
    override class var name: String { "BluCon" }

    enum UUID: String, CustomStringConvertible, CaseIterable {
        case data      = "436A62C0-082E-4CE8-A08B-01D81F195B24"
        case dataWrite = "436AA6E9-082E-4CE8-A08B-01D81F195B24"
        case dataRead  = "436A0C82-082E-4CE8-A08B-01D81F195B24"

        var description: String {
            switch self {
            case .data:      return "data"
            case .dataWrite: return "data write"
            case .dataRead:  return "data read"
            }
        }
    }

    override class var dataServiceUUID: String             { UUID.data.rawValue }
    override class var dataWriteCharacteristicUUID: String { UUID.dataWrite.rawValue }
    override class var dataReadCharacteristicUUID: String  { UUID.dataRead.rawValue }


    enum ResponseType: String, CustomStringConvertible {
        case ack            = "8b0a00"
        case patchUidInfo   = "8b0e"
        case noSensor       = "8b1a02000f"
        case readingError   = "8b1a020011"
        case timeout        = "8b1a020014"
        case sensorInfo     = "8bd9"
        case battery        = "8bda"
        case firmware       = "8bdb"
        case singleBlock    = "8bde"
        case multipleBlocks = "8bdf"
        case wakeup         = "cb010000"
        case batteryLow1    = "cb020000"
        case batteryLow2    = "cbdb0000"

        var description: String {
            switch self {
            case .ack:            return "ack"
            case .patchUidInfo:   return "patch uid/info"
            case .noSensor:       return "no sensor"
            case .readingError:   return "reading error"
            case .timeout:        return "timeout"
            case .sensorInfo:     return "sensor info"
            case .battery:        return "battery"
            case .firmware:       return "firmware"
            case .singleBlock:    return "single block"
            case .multipleBlocks: return "multiple blocks"
            case .wakeup:         return "wake up"
            case .batteryLow1:    return "battery low 1"
            case .batteryLow2:    return "battery low 2"
            }
        }
    }


    // read single block:    01-0d-0e-01-<block number>
    // read multiple blocks: 01-0d-0f-02-<start block>-<end block>

    enum RequestType: String, CustomStringConvertible {
        case none            = ""
        case ack             = "810a00"
        case sleep           = "010c0e00"
        case sensorInfo      = "010d0900"
        case fram            = "010d0f02002b"
        case battery         = "010d0a00"
        case firmware        = "010d0b00"
        case patchUid        = "010e0003260100"
        case patchInfo       = "010e000302a107"

        var description: String {
            switch self {
            case .none:            return "none"
            case .ack:             return "ack"
            case .sleep:           return "sleep"
            case .sensorInfo:      return "sensor info"
            case .fram:            return "fram"
            case .battery:         return "battery"
            case .firmware:        return "firmware"
            case .patchUid:        return "patch uid"
            case .patchInfo:       return "patch info"
            }
        }
    }

    var currentRequest: RequestType = .none

    func write(request: RequestType) {
        write(Data(request.rawValue.bytes), .withResponse)
        currentRequest = request
        main.log("\(name): did write request for \(request)")
    }


    override func readCommand(interval: Int = 5) -> Data {
        return Data([0x00]) // TODO
    }


    override func read(_ data: Data, for uuid: String) {

        let dataHex = data.hex

        let response = ResponseType(rawValue: dataHex)
        main.log("\(name) response: \(response?.description ?? "data") (0x\(dataHex))")

        guard data.count > 0 else { return }

        if response == .timeout {
            main.status("\(name): timeout")
            write(request: .sleep)

        } else if response == .noSensor {
            main.status("\(name): no sensor")
            // write(request: .sleep) // FIXME: causes an immediate .wakeup

        } else if response == .wakeup {
            write(request: .sensorInfo)

        } else {
            if sensor == nil {
                sensor = Sensor(transmitter: self)
                main.app.sensor = sensor
            }
            if dataHex.hasPrefix(ResponseType.sensorInfo.rawValue) {
                sensor!.uid = Data(data[3...10])
                // FIXME: doesn't work with Libre 2
                if let sensorState = SensorState(rawValue: data[17]) {
                    sensor!.state = sensorState
                }
                main.log("\(name): patch uid: \(sensor!.uid.hex), serial number: \(sensor!.serial), sensor state: \(sensor!.state)")
                if sensor!.state == .active {
                    write(request: .ack)
                } else {
                    write(request: .sleep)
                }

            } else if response == .ack {
                if currentRequest == .ack {
                    write(request: .firmware)
                } else { // after a .sleep request
                    currentRequest = .none
                }

            } else if dataHex.hasPrefix(ResponseType.firmware.rawValue) {
                let firmware = dataHex.bytes.dropFirst(2).map { String($0) }.joined(separator: ".")
                self.firmware = firmware
                main.log("\(name): firmware: \(firmware)")
                write(request: .battery)

            } else if dataHex.hasPrefix(ResponseType.battery.rawValue) {
                if data[2] == 0xaa {
                    // battery = 100 // TODO
                } else if data[2] == 0x02 {
                    battery = 5
                }
                write(request: .patchInfo)
                // write(request: .patchUid) // will give same .patchUidInfo response type

            } else if dataHex.hasPrefix(ResponseType.patchUidInfo.rawValue) {
                if currentRequest == .patchInfo {
                    let patchInfo = Data(data[3...])
                    sensor!.patchInfo = patchInfo
                    main.log("\(name): patch info: \(sensor!.patchInfo.hex) (sensor type: \(sensor!.type.rawValue))")
                } else if currentRequest == .patchUid {
                    sensor!.uid = Data(data[4...])
                    main.log("\(name): patch uid: \(sensor!.uid.hex), serial number: \(sensor!.serial)")
                }
                write(request: .fram)

            } else if dataHex.hasPrefix(ResponseType.multipleBlocks.rawValue) {
                if buffer.count == 0 { sensor!.lastReadingDate = main.app.lastReadingDate }
                buffer.append(data.suffix(from: 4))
                main.log("\(name): partial buffer size: \(buffer.count)")
                if buffer.count == 344 {
                    write(request: .sleep)
                    let fram = buffer[..<344]
                    sensor!.fram = Data(fram)
                    main.status("\(sensor!.type)  +  \(name)")
                }
            }
        }
    }
}