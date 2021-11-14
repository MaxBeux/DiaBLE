import Foundation

#if !os(watchOS)
import CoreNFC
#endif


typealias SensorUid = Data
typealias PatchInfo = Data


enum SensorType: String, CustomStringConvertible {
    case libre1       = "Libre 1"
    case libreUS14day = "Libre US 14d"
    case libreProH    = "Libre Pro/H"
    case libre2       = "Libre 2"
    case libre2US     = "Libre 2 US"
    case libre2CA     = "Libre 2 CA"
    case libreSense   = "Libre Sense"
    case libre3       = "Libre 3"
    case unknown      = "Libre"

    init(patchInfo: PatchInfo) {
        switch patchInfo[0] {
        case 0xDF: self = .libre1
        case 0xA2: self = .libre1
        case 0xE5: self = .libreUS14day
        case 0x70: self = .libreProH
        case 0x9D: self = .libre2
        case 0x76: self = patchInfo[3] == 0x02 ? .libre2US : patchInfo[3] == 0x04 ? .libre2CA : patchInfo[2] >> 4 == 7 ? .libreSense : .unknown
        default:
            if patchInfo.count > 6 { // Libre 3's NFC A1 command ruturns 35 or 28 bytes
                self = .libre3
            } else {
                self = .unknown
            }
        }
    }

    var description: String { self.rawValue }
}


enum SensorFamily: Int, CustomStringConvertible {
    case libre      = 0
    case librePro   = 1
    case libre2     = 3
    case libreSense = 7

    var description: String {
        switch self {
        case .libre:      return "Libre"
        case .librePro:   return "Libre Pro"
        case .libre2:     return "Libre 2"
        case .libreSense: return "Libre Sense"
        }
    }
}


enum SensorRegion: Int, CustomStringConvertible {
    case unknown            = 0
    case european           = 1
    case usa                = 2
    case australianCanadian = 4
    case eastern            = 8

    var description: String {
        switch self {
        case .unknown:            return "unknown"
        case .european:           return "European"
        case .usa:                return "USA"
        case .australianCanadian: return "Australian / Canadian"
        case .eastern:            return "Eastern"
        }
    }
}


enum SensorState: UInt8, CustomStringConvertible {
    case unknown      = 0x00

    case notActivated = 0x01
    case warmingUp    = 0x02    // 60 minutes
    case active       = 0x03    // ≈ 14.5 days
    case expired      = 0x04    // 12 hours more; Libre 2: Bluetooth shutdown
    case shutdown     = 0x05    // 15th day onwards
    case failure      = 0x06

    var description: String {
        switch self {
        case .notActivated: return "Not activated"
        case .warmingUp:    return "Warming up"
        case .active:       return "Active"
        case .expired:      return "Expired"
        case .shutdown:     return "Shut down"
        case .failure:      return "Failure"
        default:            return "Unknown"
        }
    }
}


// https://github.com/UPetersen/LibreMonitor/blob/Swift4/LibreMonitor/Model/SensorSerialNumber.swift

func serialNumber(uid: SensorUid, family: SensorFamily = .libre) -> String {
    let lookupTable = ["0","1","2","3","4","5","6","7","8","9","A","C","D","E","F","G","H","J","K","L","M","N","P","Q","R","T","U","V","W","X","Y","Z"]
    guard uid.count == 8 else { return "" }
    let bytes = Array(uid.reversed().suffix(6))
    var fiveBitsArray = [UInt8]()
    fiveBitsArray.append( bytes[0] >> 3 )
    fiveBitsArray.append( bytes[0] << 2 + bytes[1] >> 6 )
    fiveBitsArray.append( bytes[1] >> 1 )
    fiveBitsArray.append( bytes[1] << 4 + bytes[2] >> 4 )
    fiveBitsArray.append( bytes[2] << 1 + bytes[3] >> 7 )
    fiveBitsArray.append( bytes[3] >> 2 )
    fiveBitsArray.append( bytes[3] << 3 + bytes[4] >> 5 )
    fiveBitsArray.append( bytes[4] )
    fiveBitsArray.append( bytes[5] >> 3 )
    fiveBitsArray.append( bytes[5] << 2 )
    return fiveBitsArray.reduce("\(family.rawValue)", {
        $0 + lookupTable[ Int(0x1F & $1) ]
    })
}


// https://github.com/UPetersen/LibreMonitor/blob/Swift4/LibreMonitor/Model/CRC.swift

func crc16(_ data: Data) -> UInt16 {
    let crc16table: [UInt16] = [0, 4489, 8978, 12955, 17956, 22445, 25910, 29887, 35912, 40385, 44890, 48851, 51820, 56293, 59774, 63735, 4225, 264, 13203, 8730, 22181, 18220, 30135, 25662, 40137, 36160, 49115, 44626, 56045, 52068, 63999, 59510, 8450, 12427, 528, 5017, 26406, 30383, 17460, 21949, 44362, 48323, 36440, 40913, 60270, 64231, 51324, 55797, 12675, 8202, 4753, 792, 30631, 26158, 21685, 17724, 48587, 44098, 40665, 36688, 64495, 60006, 55549, 51572, 16900, 21389, 24854, 28831, 1056, 5545, 10034, 14011, 52812, 57285, 60766, 64727, 34920, 39393, 43898, 47859, 21125, 17164, 29079, 24606, 5281, 1320, 14259, 9786, 57037, 53060, 64991, 60502, 39145, 35168, 48123, 43634, 25350, 29327, 16404, 20893, 9506, 13483, 1584, 6073, 61262, 65223, 52316, 56789, 43370, 47331, 35448, 39921, 29575, 25102, 20629, 16668, 13731, 9258, 5809, 1848, 65487, 60998, 56541, 52564, 47595, 43106, 39673, 35696, 33800, 38273, 42778, 46739, 49708, 54181, 57662, 61623, 2112, 6601, 11090, 15067, 20068, 24557, 28022, 31999, 38025, 34048, 47003, 42514, 53933, 49956, 61887, 57398, 6337, 2376, 15315, 10842, 24293, 20332, 32247, 27774, 42250, 46211, 34328, 38801, 58158, 62119, 49212, 53685, 10562, 14539, 2640, 7129, 28518, 32495, 19572, 24061, 46475, 41986, 38553, 34576, 62383, 57894, 53437, 49460, 14787, 10314, 6865, 2904, 32743, 28270, 23797, 19836, 50700, 55173, 58654, 62615, 32808, 37281, 41786, 45747, 19012, 23501, 26966, 30943, 3168, 7657, 12146, 16123, 54925, 50948, 62879, 58390, 37033, 33056, 46011, 41522, 23237, 19276, 31191, 26718, 7393, 3432, 16371, 11898, 59150, 63111, 50204, 54677, 41258, 45219, 33336, 37809, 27462, 31439, 18516, 23005, 11618, 15595, 3696, 8185, 63375, 58886, 54429, 50452, 45483, 40994, 37561, 33584, 31687, 27214, 22741, 18780, 15843, 11370, 7921, 3960]
    var crc = data.reduce(UInt16(0xFFFF)) { ($0 >> 8) ^ crc16table[Int(($0 ^ UInt16($1)) & 0xFF)] }
    var reverseCrc = UInt16(0)
    for _ in 0 ..< 16 {
        reverseCrc = reverseCrc << 1 | crc & 1
        crc >>= 1
    }
    return reverseCrc
}


// https://github.com/dabear/LibreTransmitter/blob/main/LibreSensor/SensorContents/SensorData.swift

func readBits(_ buffer: Data, _ byteOffset: Int, _ bitOffset: Int, _ bitCount: Int) -> Int {
    guard bitCount != 0 else {
        return 0
    }
    var res = 0
    for i in 0 ..< bitCount {
        let totalBitOffset = byteOffset * 8 + bitOffset + i
        let byte = Int(floor(Float(totalBitOffset) / 8))
        let bit = totalBitOffset % 8
        if totalBitOffset >= 0 && ((buffer[byte] >> bit) & 0x1) == 1 {
            res |= 1 << i
        }
    }
    return res
}

func writeBits(_ buffer: Data, _ byteOffset: Int, _ bitOffset: Int, _ bitCount: Int, _ value: Int) -> Data {
    var res = buffer
    for i in 0 ..< bitCount {
        let totalBitOffset = byteOffset * 8 + bitOffset + i
        let byte = Int(floor(Double(totalBitOffset) / 8))
        let bit = totalBitOffset % 8
        let bitValue = (value >> i) & 0x1
        res[byte] = (res[byte] & ~(1 << bit) | (UInt8(bitValue) << bit))
    }
    return res
}


struct CalibrationInfo: Codable, Equatable {
    var i1: Int = 0
    var i2: Int = 0
    var i3: Int = 0
    var i4: Int = 0
    var i5: Int = 0
    var i6: Int = 0

    static var empty = CalibrationInfo()
}


class Sensor: ObservableObject, Logging {

    var type: SensorType = .unknown
    var family: SensorFamily = .libre
    var region: Int = 0
    var serial: String = ""

    var transmitter: Transmitter?
    var main: MainDelegate!

    @Published var state: SensorState = .unknown
    @Published var lastReadingDate = Date.distantPast
    @Published var age: Int = 0
    @Published var maxLife: Int = 0
    @Published var initializations: Int = 0

    var crcReport: String = ""

    var securityGeneration: Int = 0

    @Published var patchInfo: PatchInfo = Data() {
        willSet(info) {
            if info.count > 0 {
                type = SensorType(patchInfo: info)
            } else {
                type = .unknown
            }
            if info.count > 3 {
                region = Int(info[3])
            }
            if info.count >= 6 {
                family = SensorFamily(rawValue: Int(info[2] >> 4)) ?? .libre
                if serial != "" {
                    serial = "\(family.rawValue)\(serial.dropFirst())"
                }
                let generation = info[2] & 0x0F
                if family == .libre2 {
                    securityGeneration = generation < 9 ? 1 : 2
                }
                if family == .libreSense {
                    securityGeneration = generation < 4 ? 1 : 2
                }
            }
        }
    }

    var uid: SensorUid = Data() {
        willSet(uid) {
            serial = serialNumber(uid: uid, family: self.family)
        }
    }

    var trend: [Glucose] = []
    var history: [Glucose] = []

    var calibrationInfo = CalibrationInfo()

    var factoryTrend: [Glucose] { trend.map { factoryGlucose(rawGlucose: $0, calibrationInfo: calibrationInfo) }}
    var factoryHistory: [Glucose] { history.map { factoryGlucose(rawGlucose: $0, calibrationInfo: calibrationInfo) }}

    var fram: Data = Data() {
        didSet {
            parseFRAM()
        }
    }
    var encryptedFram: Data = Data()

    // Libre 2 and BLE streaming parameters
    @Published var initialPatchInfo: PatchInfo = Data()
    var streamingUnlockCode: UInt32 = 42
    @Published var streamingUnlockCount: UInt16 = 0

    // Gen2
    var streamingAuthenticationData: Data = Data(count: 10)    // formed when passed as third inout argument to verifyEnableStreamingResponse()


    init(transmitter: Transmitter? = nil, main: MainDelegate? = nil) {
        self.transmitter = transmitter
        if transmitter != nil {
            self.main = transmitter!.main
        } else {
            self.main = main
        }
    }


    func parseFRAM() {
        encryptedFram = Data()
        if (type == .libre2 || type == .libreUS14day) && UInt16(fram[0...1]) != crc16(fram[2...23]) {
            encryptedFram = fram
            if fram.count >= 344 {
                if let decryptedFRAM = try? Libre2.decryptFRAM(type: type, id: uid, info: patchInfo, data: fram) {
                    fram = decryptedFRAM
                }
            }
        }
        updateCRCReport()
        guard !crcReport.contains("FAILED") else {
            state = .unknown
            return
        }

        if fram.count < 344 && encryptedFram.count > 0 { return }

        if let sensorState = SensorState(rawValue: fram[4]) {
            state = sensorState
        }

        guard fram.count >= 320 else { return }

        age = Int(fram[316]) + Int(fram[317]) << 8    // body[-4]
        let startDate = lastReadingDate - Double(age) * 60
        initializations = Int(fram[318])

        trend = []
        history = []
        let trendIndex = Int(fram[26])      // body[2]
        let historyIndex = Int(fram[27])    // body[3]

        for i in 0 ... 15 {
            var j = trendIndex - 1 - i
            if j < 0 { j += 16 }
            let offset = 28 + j * 6         // body[4 ..< 100]
            let rawValue = readBits(fram, offset, 0, 0xe)
            let quality = UInt16(readBits(fram, offset, 0xe, 0xb)) & 0x1FF
            let qualityFlags = (readBits(fram, offset, 0xe, 0xb) & 0x600) >> 9
            let hasError = readBits(fram, offset, 0x19, 0x1) != 0
            let rawTemperature = readBits(fram, offset, 0x1a, 0xc) << 2
            var temperatureAdjustment = readBits(fram, offset, 0x26, 0x9) << 2
            let negativeAdjustment = readBits(fram, offset, 0x2f, 0x1)
            if negativeAdjustment != 0 { temperatureAdjustment = -temperatureAdjustment }
            let id = age - i
            let date = startDate + Double(age - i) * 60
            trend.append(Glucose(rawValue: rawValue, rawTemperature: rawTemperature, temperatureAdjustment: temperatureAdjustment, id: id, date: date, hasError: hasError, dataQuality: Glucose.DataQuality(rawValue: Int(quality)), dataQualityFlags: qualityFlags))
        }

        // FRAM is updated with a 3 minutes delay:
        // https://github.com/UPetersen/LibreMonitor/blob/Swift4/LibreMonitor/Model/SensorData.swift

        let preciseHistoryIndex = ((age - 3) / 15 ) % 32
        let delay = (age - 3) % 15 + 3
        var readingDate = lastReadingDate
        if preciseHistoryIndex == historyIndex {
            readingDate.addTimeInterval(60.0 * -Double(delay))
        } else {
            readingDate.addTimeInterval(60.0 * -Double(delay - 15))
        }

        for i in 0 ... 31 {
            var j = historyIndex - 1 - i
            if j < 0 { j += 32 }
            let offset = 124 + j * 6    // body[100 ..< 292]
            let rawValue = readBits(fram, offset, 0, 0xe)
            let quality = UInt16(readBits(fram, offset, 0xe, 0xb)) & 0x1FF
            let qualityFlags = (readBits(fram, offset, 0xe, 0xb) & 0x600) >> 9
            let hasError = readBits(fram, offset, 0x19, 0x1) != 0
            let rawTemperature = readBits(fram, offset, 0x1a, 0xc) << 2
            var temperatureAdjustment = readBits(fram, offset, 0x26, 0x9) << 2
            let negativeAdjustment = readBits(fram, offset, 0x2f, 0x1)
            if negativeAdjustment != 0 { temperatureAdjustment = -temperatureAdjustment }
            let id = age - delay - i * 15
            let date = id > -1 ? readingDate - Double(i) * 15 * 60 : startDate
            history.append(Glucose(rawValue: rawValue, rawTemperature: rawTemperature, temperatureAdjustment: temperatureAdjustment, id: id, date: date, hasError: hasError, dataQuality: Glucose.DataQuality(rawValue: Int(quality)), dataQualityFlags: qualityFlags))
        }

        guard fram.count >= 344 else { return }

        // fram[322...323] (footer[2..3]) corresponds to patchInfo[2...3]
        region = Int(fram[323])
        maxLife = Int(fram[326]) + Int(fram[327]) << 8
        DispatchQueue.main.async {
            self.main?.settings.activeSensorMaxLife = self.maxLife
        }

        let i1 = readBits(fram, 2, 0, 3)
        let i2 = readBits(fram, 2, 3, 0xa)
        let i3 = readBits(fram, 0x150, 0, 8)    // footer[-8]
        let i4 = readBits(fram, 0x150, 8, 0xe)
        let negativei3 = readBits(fram, 0x150, 0x21, 1) != 0
        let i5 = readBits(fram, 0x150, 0x28, 0xc) << 2
        let i6 = readBits(fram, 0x150, 0x34, 0xc) << 2

        calibrationInfo = CalibrationInfo(i1: i1, i2: i2, i3: negativei3 ? -i3 : i3, i4: i4, i5: i5, i6: i6)
        DispatchQueue.main.async {
            self.main?.settings.activeSensorCalibrationInfo = self.calibrationInfo
        }

    }


    func detailFRAM() {
        if encryptedFram.count > 0 && fram.count >= 344 {
            log("\(fram.hexDump(header: "Sensor decrypted FRAM:", startBlock: 0))")
        }
        if crcReport.count > 0 {
            log(crcReport)
            if crcReport.contains("FAILED") {
                if history.count > 0 && type != .libre2 { // bogus raw data with Libre 1
                    main?.errorStatus("Error while validating sensor data")
                    return
                }
            }
        }
        log("Sensor state: \(state.description.lowercased()) (0x\(state.rawValue.hex))")

        if state == .failure {
            let errorCode = fram[6]
            let failureAge = Int(fram[7]) + Int(fram[8]) << 8
            let failureInterval = failureAge == 0 ? "an unknown time" : "\(failureAge) minutes (\(failureAge.formattedInterval))"
            log("Sensor failure error 0x\(errorCode.hex) (\(decodeFailure(error: errorCode))) at \(failureInterval) after activation.")
        }

        // TODO:
        if main.settings.debugLevel > 0 {
            log("Sensor factory values: raw minimum threshold: \(fram[330]) (tied to SENSOR_SIGNAL_LOW error, should be 150 for a Libre 1), maximum ADC delta: \(fram[332]) (tied to FILTER_DELTA error, should be 90 for a Libre 1)")
        }

        if initializations > 0 {
            log("Sensor initializations: \(initializations)")
        }
        log("Sensor region: \(SensorRegion(rawValue: region)?.description ?? "unknown")\(region != 0 ? " (0x\(region.hex))" : "")")
        if maxLife > 0 {
            log("Sensor maximum life: \(maxLife) minutes (\(maxLife.formattedInterval))")
        }
        if age > 0 {
            log("Sensor age: \(age) minutes (\(age.formattedInterval)), started on: \((lastReadingDate - Double(age) * 60).shortDateTime)")
        }
    }


    func updateCRCReport() {
        if fram.count < 344 {
            crcReport = "NFC: FRAM read did not complete: can't verify CRC"

        } else {
            let headerCRC = UInt16(fram[0...1])
            let bodyCRC   = UInt16(fram[24...25])
            let footerCRC = UInt16(fram[320...321])
            let computedHeaderCRC = crc16(fram[2...23])
            let computedBodyCRC   = crc16(fram[26...319])
            let computedFooterCRC = crc16(fram[322...343])

            var report = "Sensor header CRC16: \(headerCRC.hex), computed: \(computedHeaderCRC.hex) -> \(headerCRC == computedHeaderCRC ? "OK" : "FAILED")"
            report += "\nSensor body CRC16: \(bodyCRC.hex), computed: \(computedBodyCRC.hex) -> \(bodyCRC == computedBodyCRC ? "OK" : "FAILED")"
            report += "\nSensor footer CRC16: \(footerCRC.hex), computed: \(computedFooterCRC.hex) -> \(footerCRC == computedFooterCRC ? "OK" : "FAILED")"

            if fram.count >= 344 + 195 * 8 {
                let commandsCRC = UInt16(fram[344...345])
                let computedCommandsCRC = crc16(fram[346 ..< 344 + 195 * 8])
                report += "\nSensor commands CRC16: \(commandsCRC.hex), computed: \(computedCommandsCRC.hex) -> \(commandsCRC == computedCommandsCRC ? "OK" : "FAILED")"
            }

            crcReport = report
        }
    }


#if !os(watchOS)
    func execute(nfc: NFC, taskRequest: TaskRequest) async throws {
    }
#endif

}


func encodeStatusCode(_ status: UInt64) -> String {
    let alphabet = Array("0123456789ACDEFGHJKLMNPQRTUVWXYZ")
    var code = ""
    for i in 0...9 {
        code.append(alphabet[Int(status >> (i * 5)) & 0x1F])
    }
    return code
}


func decodeStatusCode(_ code: String) -> UInt64 {
    let alphabet = Array("0123456789ACDEFGHJKLMNPQRTUVWXYZ")
    let chars = Array(code)
    var status: UInt64 = 0
    for i in 0...9 {
        status += UInt64(alphabet.firstIndex(of: chars[i])!) << (i * 5)
    }
    return status
}


func checksummedFRAM(_ data: Data) -> Data {
    var fram = data

    let headerCRC = crc16(fram[         2 ..<  3 * 8])
    let bodyCRC =   crc16(fram[ 3 * 8 + 2 ..< 40 * 8])
    let footerCRC = crc16(fram[40 * 8 + 2 ..< 43 * 8])

    fram[0 ... 1] = headerCRC.data
    fram[3 * 8 ... 3 * 8 + 1] = bodyCRC.data
    fram[40 * 8 ... 40 * 8 + 1] = footerCRC.data

    if fram.count > 43 * 8 {
        let commandsCRC = crc16(fram[43 * 8 + 2 ..< (244 - 6) * 8])    // Libre 1 DF: 429e, A2: f9ae
        fram[43 * 8 ... 43 * 8 + 1] = commandsCRC.data
    }
    return fram
}


struct LibreMemoryRegion {
    let numberOfBytes: Int
    let startAddress: Int
}


// TODO
func decodeFailure(error: UInt8) -> String {
    switch error {
    case 0x01: return "ADC IRQ overflow"
    case 0x05: return "MMI interrupt"
    case 0x09: return "error in patch table"
    case 0x0A: return "low voltage occurred"
    case 0x0B: return "low voltage occurred"
    case 0x0C: return "FRAM header section CRC error"
    case 0x0D: return "FRAM body section CRC error"
    case 0x0E: return "FRAM footer section CRC error"
    case 0x0F: return "FRAM code section CRC error"
    case 0x10: return "FRAM Lock Table error"
    case 0x13: return "brownout"
    case 0x28: return "battery low indication"
    case 0x34: return "from custom E1 and E2 command"
    default:   return "no specific info"
    }
}
