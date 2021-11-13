import Foundation

#if !os(watchOS)
import CoreNFC
#endif

let libre2DumpMap = [
    0x000:  (40,  "Extended header"),
    0x028:  (32,  "Extended footer"),
    0x048:  (296, "Body right-rotated by 4"),
    0x170:  (24,  "FRAM header"),
    0x188:  (296, "FRAM body"),
    0x2b0:  (24,  "FRAM footer"),
    0x2c8:  (34,  "Keys"),
    0x2ea:  (10,  "MAC address"),
    0x26d8: (24,  "Table of enabled NFC commands")
]

// 0x2580: (4, "Libre 1 backdoor")
// 0x25c5: (7, "BLE trend offsets")
// 0x25d0 + 1: (4 + 8, "usefulFunction() and streaming unlock keys")

// 0c8a  CMP.W  #0xadc2, &RF13MRXF
// 0c90  JEQ  0c96
// 0c92  MOV.B  #0, R12
// 0c94  RET
// 0c96  CMP.W  #0x2175, &RF13MRXF
// 0c9c  JNE  0c92
// 0c9e  MOV.B  #1, R12
// 0ca0  RET

// function at 24e2:
//    if (param_1 == '\x1e') {
//      param_3 = param_3 ^ param_4;
//    }
//    else {
//      param_3 = 0x1b6a;
//    }

// 0800: RF13MCTL
// 0802: RF13MINT
// 0804: RF13MIV
// 0806: RF13MRXF
// 0808: RF13MTXF
// 080a: RF13MCRC
// 080c: RF13MFIFOFL
// 080e: RF13MWMCFG


// https://github.com/ivalkou/LibreTools/blob/master/Sources/LibreTools/Sensor/Libre2.swift

class Libre2: Sensor {

    static let key: [UInt16] = [0xA0C5, 0x6860, 0x0000, 0x14C6]
    static let secret: UInt16 = 0x1b6a


    static func prepareVariables(id: SensorUid, x: UInt16, y: UInt16) -> [UInt16] {
        let s1 = UInt16(truncatingIfNeeded: UInt(UInt16(id[5], id[4])) + UInt(x) + UInt(y))
        let s2 = UInt16(truncatingIfNeeded: UInt(UInt16(id[3], id[2])) + UInt(key[2]))
        let s3 = UInt16(truncatingIfNeeded: UInt(UInt16(id[1], id[0])) + UInt(x) * 2)
        let s4 = 0x241a ^ key[3]

        return [s1, s2, s3, s4]
    }


    static func processCrypto(input: [UInt16]) -> [UInt16] {
        func op(_ value: UInt16) -> UInt16 {
            // We check for last 2 bits and do the xor with specific value if bit is 1
            var res = value >> 2 // Result does not include these last 2 bits

            if value & 1 != 0 { // If last bit is 1
                res = res ^ key[1]
            }

            if value & 2 != 0 { // If second last bit is 1
                res = res ^ key[0]
            }

            return res
        }

        let r0 = op(input[0]) ^ input[3]
        let r1 = op(r0) ^ input[2]
        let r2 = op(r1) ^ input[1]
        let r3 = op(r2) ^ input[0]
        let r4 = op(r3)
        let r5 = op(r4 ^ r0)
        let r6 = op(r5 ^ r1)
        let r7 = op(r6 ^ r2)

        let f1 = r0 ^ r4
        let f2 = r1 ^ r5
        let f3 = r2 ^ r6
        let f4 = r3 ^ r7

        return [f4, f3, f2, f1]
    }


    static func usefulFunction(id: SensorUid, x: UInt16, y: UInt16) -> Data {
        let blockKey = processCrypto(input: prepareVariables(id: id, x: x, y: y))
        let low = blockKey[0]
        let high = blockKey[1]

        // https://github.com/ivalkou/LibreTools/issues/2: "XOR with inverted low/high words in usefulFunction()"
        let r1 = low ^ 0x4163
        let r2 = high ^ 0x4344

        return Data([
            UInt8(truncatingIfNeeded: r1),
            UInt8(truncatingIfNeeded: r1 >> 8),
            UInt8(truncatingIfNeeded: r2),
            UInt8(truncatingIfNeeded: r2 >> 8)
        ])
    }


    /// Decrypts 43 blocks of Libre 2 FRAM
    /// - Parameters:
    ///   - type: Supported sensor type (.libre2, .libreUS14day)
    ///   - id: ID/Serial of the sensor. Could be retrieved from NFC as uid.
    ///   - info: Sensor info. Retrieved by sending command '0xa1' via NFC.
    ///   - data: Encrypted FRAM data
    /// - Returns: Decrypted FRAM data
    static func decryptFRAM(type: SensorType, id: SensorUid, info: PatchInfo, data: Data) throws -> Data {
        guard type == .libre2 || type == .libreUS14day else {
            struct DecryptFRAMError: LocalizedError {
                var errorDescription: String? { "Unsupported sensor type" }
            }
            throw DecryptFRAMError()
        }

        func getArg(block: Int) -> UInt16 {
            switch type {
            case .libreUS14day:
                if block < 3 || block >= 40 {
                    // For header and footer it is a fixed value.
                    return 0xcadc
                }
                return UInt16(info[5], info[4])
            case .libre2:
                return UInt16(info[5], info[4]) ^ 0x44
            default: fatalError("Unsupported sensor type")
            }
        }

        var result = [UInt8]()

        for i in 0 ..< 43 {
            let input = prepareVariables(id: id, x: UInt16(i), y: getArg(block: i))
            let blockKey = processCrypto(input: input)

            result.append(data[i * 8 + 0] ^ UInt8(truncatingIfNeeded: blockKey[0]))
            result.append(data[i * 8 + 1] ^ UInt8(truncatingIfNeeded: blockKey[0] >> 8))
            result.append(data[i * 8 + 2] ^ UInt8(truncatingIfNeeded: blockKey[1]))
            result.append(data[i * 8 + 3] ^ UInt8(truncatingIfNeeded: blockKey[1] >> 8))
            result.append(data[i * 8 + 4] ^ UInt8(truncatingIfNeeded: blockKey[2]))
            result.append(data[i * 8 + 5] ^ UInt8(truncatingIfNeeded: blockKey[2] >> 8))
            result.append(data[i * 8 + 6] ^ UInt8(truncatingIfNeeded: blockKey[3]))
            result.append(data[i * 8 + 7] ^ UInt8(truncatingIfNeeded: blockKey[3] >> 8))
        }
        return Data(result)
    }


#if !os(watchOS)

    override func execute(nfc: NFC, taskRequest: TaskRequest) async throws {

        let subCmd: Sensor.Subcommand = (taskRequest == .enableStreaming) ?
            .enableStreaming : .unknown0x1c

        switch subCmd {

        case .enableStreaming:

            // `A1 1E` returns the peripheral MAC address to connect to.
            // streamingUnlockCode could be any 32 bit value. The streamingUnlockCode and
            // sensor Uid / patchInfo will have also to be provided to the login function
            // when connecting to peripheral.

            let parameters = [
                UInt8(streamingUnlockCode & 0xFF),
                UInt8((streamingUnlockCode >> 8) & 0xFF),
                UInt8((streamingUnlockCode >> 16) & 0xFF),
                UInt8((streamingUnlockCode >> 24) & 0xFF)
            ]
            let secret = UInt16(patchInfo[4...5]) ^ UInt16(parameters[1], parameters[0])

            let cmd = nfcCommand(subCmd, parameters: Data(parameters), secret: secret)
            log("NFC: sending \(type) command to \(cmd.description): code: 0x\(cmd.code.hex), parameters: 0x\(cmd.parameters.hex)")

            let currentUnlockCode = streamingUnlockCode
            streamingUnlockCode = UInt32(await main.settings.activeSensorStreamingUnlockCode)

            do {
                let output = try await nfc.connectedTag!.customCommand(requestFlags: .highDataRate, customCommandCode: cmd.code, customRequestParameters: cmd.parameters)

                log("NFC: '\(cmd.description)' command output (\(output.count) bytes): 0x\(output.hex)")

                if output.count == 6 {
                    log("NFC: enabled BLE streaming on \(type) \(serial) (unlock code: \(streamingUnlockCode), MAC address: \(Data(output.reversed()).hexAddress))")
                    // "Publishing changes from background threads is not allowed"
                    DispatchQueue.main.async {
                        self.main.settings.activeSensorSerial = self.serial
                        self.main.settings.activeSensorAddress = Data(output.reversed())
                        self.initialPatchInfo = self.patchInfo
                        self.main.settings.activeSensorInitialPatchInfo = self.patchInfo
                        self.streamingUnlockCount = 0
                        self.main.settings.activeSensorStreamingUnlockCount = 0

                        // TODO: cancel connections also before enabling streaming?
                        self.main.rescan()
                    }
                }

            } catch {
                log("NFC: '\(cmd.description)' command error: \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
                streamingUnlockCode = currentUnlockCode
            }

        default:
            break

        }
    }

#endif    // #if !os(watchOS)


    static func prepareVariables2(id: SensorUid, i1: UInt16, i2: UInt16, i3: UInt16, i4: UInt16) -> [UInt16] {
        let s1 = UInt16(truncatingIfNeeded: UInt(UInt16(id[5], id[4])) + UInt(i1))
        let s2 = UInt16(truncatingIfNeeded: UInt(UInt16(id[3], id[2])) + UInt(i2))
        let s3 = UInt16(truncatingIfNeeded: UInt(UInt16(id[1], id[0])) + UInt(i3) + UInt(key[2]))
        let s4 = UInt16(truncatingIfNeeded: UInt(i4) + UInt(key[3]))

        return [s1, s2, s3, s4]
    }


    static func streamingUnlockPayload(id: SensorUid, info: PatchInfo, enableTime: UInt32, unlockCount: UInt16) -> Data {

        // First 4 bytes are just int32 of timestamp + unlockCount
        let time = enableTime + UInt32(unlockCount)
        let b: [UInt8] = [
            UInt8(time & 0xFF),
            UInt8((time >> 8) & 0xFF),
            UInt8((time >> 16) & 0xFF),
            UInt8((time >> 24) & 0xFF)
        ]

        // Then we need data of activation command and enable command that were sent to sensor
        let ad = usefulFunction(id: id, x: UInt16(Sensor.Subcommand.activate.rawValue), y: secret)
        let ed = usefulFunction(id: id, x: UInt16(Sensor.Subcommand.enableStreaming.rawValue), y: UInt16(enableTime & 0xFFFF) ^ UInt16(info[5], info[4]))

        let t11 = UInt16(ed[1], ed[0]) ^ UInt16(b[3], b[2])
        let t12 = UInt16(ad[1], ad[0])
        let t13 = UInt16(ed[3], ed[2]) ^ UInt16(b[1], b[0])
        let t14 = UInt16(ad[3], ad[2])

        let t2 = processCrypto(input: prepareVariables2(id: id, i1: t11, i2: t12, i3: t13, i4: t14))

        // TODO extract if secret
        let t31 = crc16(Data([0xc1, 0xc4, 0xc3, 0xc0, 0xd4, 0xe1, 0xe7, 0xba, UInt8(t2[0] & 0xFF), UInt8((t2[0] >> 8) & 0xFF)]))
        let t32 = crc16(Data([UInt8(t2[1] & 0xFF), UInt8((t2[1] >> 8) & 0xFF),
                              UInt8(t2[2] & 0xFF), UInt8((t2[2] >> 8) & 0xFF),
                              UInt8(t2[3] & 0xFF), UInt8((t2[3] >> 8) & 0xFF)]))
        let t33 = crc16(Data([ad[0], ad[1], ad[2], ad[3], ed[0], ed[1]]))
        let t34 = crc16(Data([ed[2], ed[3], b[0], b[1], b[2], b[3]]))

        let t4 = processCrypto(input: prepareVariables2(id: id, i1: t31, i2: t32, i3: t33, i4: t34))

        let res = [
            UInt8(t4[0] & 0xFF),
            UInt8((t4[0] >> 8) & 0xFF),
            UInt8(t4[1] & 0xFF),
            UInt8((t4[1] >> 8) & 0xFF),
            UInt8(t4[2] & 0xFF),
            UInt8((t4[2] >> 8) & 0xFF),
            UInt8(t4[3] & 0xFF),
            UInt8((t4[3] >> 8) & 0xFF)
        ]

        return Data([b[0], b[1], b[2], b[3], res[0], res[1], res[2], res[3], res[4], res[5], res[6], res[7]])
    }


    /// Decrypts Libre 2 BLE payload
    /// - Parameters:
    ///   - id: ID/Serial of the sensor. Could be retrieved from NFC as uid.
    ///   - data: Encrypted BLE data
    /// - Returns: Decrypted BLE data
    static func decryptBLE(id: SensorUid, data: Data) throws -> Data {
        let d = usefulFunction(id: id, x: UInt16(Sensor.Subcommand.activate.rawValue), y: secret)
        let x = UInt16(d[1], d[0]) ^ UInt16(d[3], d[2]) | 0x63
        let y = UInt16(data[1], data[0]) ^ 0x63

        var key = [UInt8]()
        var initialKey = processCrypto(input: prepareVariables(id: id, x: x, y: y))

        for _ in 0 ..< 8 {
            key.append(UInt8(truncatingIfNeeded: initialKey[0]))
            key.append(UInt8(truncatingIfNeeded: initialKey[0] >> 8))
            key.append(UInt8(truncatingIfNeeded: initialKey[1]))
            key.append(UInt8(truncatingIfNeeded: initialKey[1] >> 8))
            key.append(UInt8(truncatingIfNeeded: initialKey[2]))
            key.append(UInt8(truncatingIfNeeded: initialKey[2] >> 8))
            key.append(UInt8(truncatingIfNeeded: initialKey[3]))
            key.append(UInt8(truncatingIfNeeded: initialKey[3] >> 8))
            initialKey = processCrypto(input: initialKey)
        }

        let result = data[2...].enumerated().map { i, value in
            value ^ key[i]
        }

        guard crc16(Data(result.prefix(42))) == UInt16(Data(result[42...43])) else {
            struct DecryptBLEError: LocalizedError {
                var errorDescription: String? { "BLE data decryption failed" }
            }
            throw DecryptBLEError()
        }

        return Data(result)
    }

}


extension Sensor {

    func parseBLEData( _ data: Data) -> [Glucose] {

        let wearTimeMinutes = Int(UInt16(data[40...41]))
        if state == .unknown { state = .active }
        age = wearTimeMinutes
        let startDate = lastReadingDate - Double(wearTimeMinutes) * 60
        let historyDelay = 2

        var bleTrend = [Glucose]()
        var bleHistory = [Glucose]()

        for i in 0 ..< 10 {
            let rawValue = readBits(data, i * 4, 0, 0xe)
            let rawTemperature = readBits(data, i * 4, 0xe, 0xc) << 2
            var temperatureAdjustment = readBits(data, i * 4, 0x1a, 0x5) << 2
            let negativeAdjustment = readBits(data, i * 4, 0x1f, 0x1)
            if negativeAdjustment != 0 {
                temperatureAdjustment = -temperatureAdjustment
            }

            var id = wearTimeMinutes

            if i < 7 {
                // sparse trend values
                id -= [0, 2, 4, 6, 7, 12, 15][i]

            } else {
                // latest three historic values
                id = ((id - historyDelay) / 15) * 15 - 15 * (i - 7)
            }

            let date = startDate + Double(id * 60)

            // lower 9 bits correspond to measurement errorbits & 0x1FF
            let quality = rawValue == 0 ? Glucose.DataQuality(rawValue: rawTemperature >> 2) : Glucose.DataQuality.OK
            let qualityFlags = rawValue == 0 ? ((rawTemperature >> 2) & 0x600) >> 9 : 0

            let glucose = Glucose(rawValue: rawValue,
                                  rawTemperature: rawValue != 0 ? rawTemperature : 0,
                                  temperatureAdjustment: temperatureAdjustment,
                                  id: id,
                                  date: date,
                                  hasError: rawValue == 0,
                                  dataQuality: quality,
                                  dataQualityFlags: qualityFlags)

            if i < 7 {
                bleTrend.append(glucose)
            } else {
                bleHistory.append(glucose)
            }
        }

        if bleTrend[0].rawValue > 0 { main.app.currentGlucose = bleTrend[0].value }

        let readingDate = bleTrend[0].date

        // Merge trend values setting them to -1 for missing ids
        var trendDict = [Int: Glucose]()
        for i in 0 ... 15 {
            let id = wearTimeMinutes - i
            let date = readingDate - Double(i * 60)
            trendDict[id] = Glucose(-1, id: id, date: date)
        }
        for glucose in (trend + bleTrend) {
            if glucose.id > wearTimeMinutes - 16 {
                trendDict[glucose.id] = glucose
            }
        }
        trend = [Glucose](trendDict.values.sorted(by: { $0.id > $1.id }).prefix(16))


        // Merge historic values setting them to -1 for missing ids
        var historyDict = [Int: Glucose]()
        let lastHistoryId = bleHistory[0].id
        let lastHistoryDate = bleHistory[0].date
        for i in 0 ... 31 {
            let id = lastHistoryId - i * 15
            let date = lastHistoryDate - Double(i * (60 * 15))
            historyDict[id] = Glucose(-1, id: id, date: date)
        }
        for glucose in (history + bleHistory) {
            if glucose.id > lastHistoryId - (32 * 15) {
                historyDict[glucose.id] = glucose
            }
        }
        history = [Glucose](historyDict.values
                                .sorted(by: { $0.id < $1.id })
                                .drop(while: { $0.value == -1 })
                                .reversed()
                                .prefix(32))

        return bleTrend + bleHistory
    }
}
