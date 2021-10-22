import Foundation
import CoreBluetooth


class Abbott: Transmitter {
    override class var type: DeviceType { DeviceType.transmitter(.abbott) }
    override class var name: String { "Libre" }

    enum UUID: String, CustomStringConvertible, CaseIterable {
        case abbottCustom         = "FDE3"
        case bleLogin             = "F001"
        case compositeRawData     = "F002"

        case libre3data           = "089810CC-EF89-11E9-81B4-2A2AE2DBCCE4"

        /// Requests past data by sending 13 zero-terminated bytes, receives 10 zero-terminated bytes at the end of stream
        case libre3data0x1338     = "08981338-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        /// Receiving error when activating notifications: Encryption is insufficient
        case libre3data0x1482     = "08981482-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Read"]

        /// The Libre 3 sends every minute 35 bytes as two packets of 15 + 20 zero-terminated bytes
        case libre3data0x177A     = "0898177A-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Receiving a first stream of 20-byte packets of past data while the curve is drawn on display
        case libre3data0x195A     = "0898195A-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Receiving a second longer stream of 20-byte packets of past data
        case libre3data0x1AB8     = "08981AB8-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        case libre3data0x1BEE     = "08981BEE-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]
        case libre3data0x1D24     = "08981D24-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        case libre3unknownService = "0898203A-EF89-11E9-81B4-2A2AE2DBCCE4"

        /// Writes the very first command: 0x11, receiving the two bytes 08 17
        case libre3unknown0x2198  = "08982198-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        /// Receives the very first data: 20 + 5 bytes, then three
        /// 20 + 20 + 6 packets starting with 0000, 1200, 2400 are written
        case libre3unknown0x22CE  = "089822CE-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        case libre3unknown0x23FA  = "089823FA-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        var description: String {
            switch self {
            case .abbottCustom:         return "Abbott custom"
            case .bleLogin:             return "BLE login"
            case .compositeRawData:     return "composite raw data"
            case .libre3data:           return "Libre 3 data service"
            case .libre3data0x1338:     return "Libre 3 data 0x1338"
            case .libre3data0x1482:     return "Libre 3 data 0x1482"
            case .libre3data0x177A:     return "Libre 3 data 0x177A"
            case .libre3data0x195A:     return "Libre 3 data 0x195A"
            case .libre3data0x1AB8:     return "Libre 3 data 0x1AB8"
            case .libre3data0x1BEE:     return "Libre 3 data 0x1BEE"
            case .libre3data0x1D24:     return "Libre 3 data 0x1D24"
            case .libre3unknownService: return "Libre 3 unknown service"
            case .libre3unknown0x2198:  return "Libre 3 unknown 0x2198"
            case .libre3unknown0x22CE:  return "Libre 3 unknown 0x22CE"
            case .libre3unknown0x23FA:  return "Libre 3 unknown 0x23FA"
            }
        }
    }


    // Libre 3:
    // enable notifications for 2198, 23FA and 22CE
    // write  2198  11
    // notify 2198  08 17
    // notify 22CE  20 + 5 bytes
    // write  22CE  20 + 20 + 6 bytes
    // write  2198  08
    // notify 2198  08 43
    // notify 22CE  20 + 20 + 20 + 11 bytes
    // enable notifications for 1338, 1BEE, 195A, 1AB8, 1D24, 1482
    // notify 1482  18 bytes
    // enable notifications for 177A
    // write  1338  13 bytes
    // notify 177A  15 + 20 bytes
    // notify 195A  20-byte packets of past data
    // notify 1338  10 bytes
    // write  1338  13 bytes
    // notify 1AB8  20-byte packets of past data
    // notify 1338  10 bytes

    override class var knownUUIDs: [String] { UUID.allCases.map{$0.rawValue} }

    override class var dataServiceUUID: String { UUID.abbottCustom.rawValue }
    override class var dataWriteCharacteristicUUID: String { UUID.bleLogin.rawValue }
    override class var dataReadCharacteristicUUID: String  { UUID.compositeRawData.rawValue }


    enum AuthenticationState: Int, CustomStringConvertible {
        case notAuthenticated   = 0
        // Gen2
        case enableNotification = 1
        case challengeResponse  = 2
        case getSessionInfo     = 3
        case authenticated      = 4
        // Gen1
        case bleLogin           = 5

        var description: String {
            switch self {
            case .notAuthenticated:   return "AUTH_STATE_NOT_AUTHENTICATED"
            case .enableNotification: return "AUTH_STATE_ENABLE_NOTIFICATION"
            case .challengeResponse:  return "AUTH_STATE_CHALLENGE_RESPONSE"
            case .getSessionInfo:     return "AUTH_STATE_GET_SESSION_INFO"
            case .authenticated:      return "AUTH_STATE_AUTHENTICATED"
            case .bleLogin:           return "AUTH_STATE_BLE_LOGIN"
            }
        }
    }

    var securityGeneration: Int = 0    // unknown; then 1 or 2
    var authenticationState: AuthenticationState = .notAuthenticated
    var sessionInfo = Data()    // 7 + 18 bytes

    var uid: SensorUid = Data()

    override func parseManufacturerData(_ data: Data) {
        if data.count > 7 {
            let sensorUid: SensorUid = Data(data[2...7]) + [0x07, 0xe0]
            // Gen2: doesn't match the sensor Uid, for example 0bf3b7aa48b8 != 5f5aab0100a4
            if data[7] == 0xa4 {
                uid = sensorUid
            }
            log("Bluetooth: advertised \(name)'s UID: \(sensorUid.hex)")
        }
    }

    override func read(_ data: Data, for uuid: String) {

        switch UUID(rawValue: uuid) {

        // Gen2
        case .bleLogin:
            if authenticationState == .challengeResponse {
                if data.count == 14 {
                    log("\(name): challenge response: \(data.hex)")
                    // TODO: processChallengeResponse(), compute streamingUnlockPayload (AUTH_COMMAND_PAYLOAD_LENGTH = 19) and write it
                    authenticationState = .getSessionInfo
                }
            } else if authenticationState == .getSessionInfo {
                if data.count == 7 {
                    sessionInfo = Data(data)
                } else if data.count == 18 {
                    sessionInfo.append(data)
                    if sessionInfo.count == 25 {
                        // TODO: createSecureStreamingSession(), enable read notification
                        authenticationState = .authenticated
                    }
                }
            }


        case .compositeRawData:

            // The Libre 2 always sends 46 bytes as three packets of 20 + 18 + 8 bytes

            if data.count == 20 {
                buffer = Data()
                sensor!.lastReadingDate = main.app.lastReadingDate
            }

            buffer.append(data)
            log("\(name): partial buffer size: \(buffer.count)")

            if buffer.count == 46 {
                do {
                    let bleData = try Libre2.decryptBLE(id: sensor!.uid, data: buffer)

                    let crc = UInt16(bleData[42...43])
                    let computedCRC = crc16(bleData[0...41])
                    // TODO: detect checksum failure

                    let bleGlucose = sensor!.parseBLEData(bleData)

                    let wearTimeMinutes = Int(UInt16(bleData[40...41]))

                    debugLog("Bluetooth: decrypted BLE data: 0x\(bleData.hex), wear time: 0x\(wearTimeMinutes.hex) (\(wearTimeMinutes) minutes, sensor age: \(sensor!.age.formattedInterval)), CRC: \(crc.hex), computed CRC: \(computedCRC.hex), glucose values: \(bleGlucose)")

                    let bleRawValues = bleGlucose.map{$0.rawValue}
                    log("BLE raw values: \(bleRawValues)")

                    // TODO
                    if bleRawValues.contains(0) {
                        debugLog("BLE values data quality: [\n\(bleGlucose.map{$0.dataQuality.description}.joined(separator: ",\n"))\n]")
                        debugLog("BLE values quality flags: [\(bleGlucose.map{("0"+String($0.dataQualityFlags,radix: 2)).suffix(2)}.joined(separator: ", "))]")
                    }

                    // TODO: move UI stuff to MainDelegate()

                    // TODO: call applyOOP(), didParseSensor()

                    let bleTrend = bleGlucose[0...6].map { factoryGlucose(rawGlucose: $0, calibrationInfo: main.settings.activeSensorCalibrationInfo) }
                    let bleHistory = bleGlucose[7...9].map { factoryGlucose(rawGlucose: $0, calibrationInfo: main.settings.activeSensorCalibrationInfo) }

                    log("BLE temperatures: \((bleTrend + bleHistory).map{Double(String(format: "%.1f", $0.temperature))!})")
                    log("BLE factory trend: \(bleTrend.map{$0.value})")
                    log("BLE factory history: \(bleHistory.map{$0.value})")

                    main.history.rawTrend = sensor!.trend
                    let factoryTrend = sensor!.factoryTrend
                    main.history.factoryTrend = factoryTrend
                    log("BLE merged trend: \(factoryTrend.map{$0.value})".replacingOccurrences(of: "-1", with: "… "))

                    // TODO: compute accurate delta and update trend arrow
                    let deltaMinutes = factoryTrend[6].value != 0 ? 6 : 7
                    let delta = (factoryTrend[0].value != 0 ? factoryTrend[0].value : (factoryTrend[1].value != 0 ? factoryTrend[1].value : factoryTrend[2].value)) - factoryTrend[deltaMinutes].value
                    main.app.trendDeltaMinutes = deltaMinutes
                    main.app.trendDelta = delta


                    main.history.rawValues = sensor!.history
                    let factoryHistory = sensor!.factoryHistory
                    main.history.factoryValues = factoryHistory
                    log("BLE merged history: \(factoryHistory.map{$0.value})".replacingOccurrences(of: "-1", with: "… "))

                    // Slide the OOP history
                    // TODO: apply the following also after a NFC scan
                    let historyDelay = 2
                    if (wearTimeMinutes - historyDelay) % 15 == 0 || wearTimeMinutes - sensor!.history[1].id > 16 {
                        if main.history.values.count > 0 {
                            let missingCount = (sensor!.history[0].id - main.history.values[0].id) / 15
                            var history = [Glucose](main.history.rawValues.prefix(missingCount) + main.history.values.prefix(32 - missingCount))
                            for i in 0 ..< missingCount { history[i].value = -1 }
                            main.history.values = history
                        }
                    }

                    // TODO: complete backfill

                    main.status("\(sensor!.type)  +  BLE")

                } catch {
                    // TODO: verify crc16
                    log(error.localizedDescription)
                    main.errorStatus(error.localizedDescription)
                    buffer = Data()
                }
            }


        // MARK: - Libre 3

        case .libre3unknown0x22CE:
            if buffer.count == 0 {
                buffer = Data(data)
            } else if buffer.count == 20 {
                buffer += data
                if buffer.count == 25 {
                    log("Libre 3: received first data (\(buffer.count) bytes):\n\(buffer.hexDump())")
                    buffer = Data()
                    log("Libre 3: test sending 0x22CE packets of 20 + 20 + 6 bytes prefixed by 0000, 1200, 2400")
                    write(Data("0000000000000000000000000000000000000000".bytes), for: uuid, .withResponse)
                    write(Data("1200000000000000000000000000000000000000".bytes), for: uuid, .withResponse)
                    write(Data("240000000000".bytes), for: uuid, .withResponse)

                    // TODO:
                    // writing 002400000000 causes the error `The value's length is invalid`...

                    // FIXME: writing 08 on 0x2198 makes the Libre 3 disconnect
                    // log("Libre 3: test writing the second command 0x08 on 0x2198")
                    // write(Data([0x08]), for: Abbott.UUID.libre3unknown0x2198.rawValue, .withResponse)
                }
            }

        default:
            break
        }
    }

}
