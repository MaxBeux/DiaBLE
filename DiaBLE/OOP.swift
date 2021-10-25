import Foundation


// https://github.com/bubbledevteam/bubble-client-swift/blob/master/LibreSensor/


struct OOPServer {
    var siteURL: String
    var token: String
    var calibrationEndpoint: String?
    var historyEndpoint: String?
    var historyAndCalibrationEndpoint: String?
    var historyAndCalibrationA2Endpoint: String?
    var bleHistoryEndpoint: String?
    var activationEndpoint: String?
    var nfcAuthEndpoint: String?
    var nfcAuth2Endpoint: String?
    var nfcDataEndpoint: String?
    var nfcDataAlgorithmEndpoint: String?

    // TODO: Gen2:

    // /openapi/xabetLibre libreoop2AndCalibrate("patchUid", "patchInfo", "content", "accesstoken" = "xabet-202104", "session")

    // /libre2ca/bleAuth ("p1", "patchUid", "authData")
    // /libre2ca/bleAuth2 ("p1", "authData")
    // /libre2ca/bleAlgorithm ("p1", "pwd", "bleData", "patchUid", "patchInfo")

    // /libre2ca/nfcAuth ("patchUid", "authData")
    // /libre2ca/nfcAuth2 ("p1", "authData")
    // /libre2ca/nfcData ("patchUid", "authData")
    // /libre2ca/nfcDataAlgorithm ("p1", "authData", "content", "patchUid", "patchInfo")


    static let `default`: OOPServer = OOPServer(siteURL: "https://www.glucose.space",
                                                token: "bubble-201907",
                                                calibrationEndpoint: "calibrateSensor",
                                                historyEndpoint: "libreoop2",
                                                historyAndCalibrationEndpoint: "libreoop2AndCalibrate",
                                                historyAndCalibrationA2Endpoint: "callnoxAndCalibrate",
                                                bleHistoryEndpoint: "libreoop2BleData",
                                                activationEndpoint: "activation")
    static let gen2: OOPServer = OOPServer(siteURL: "https://www.glucose.space",
                                           token: "xabet-202104",
                                           nfcAuthEndpoint: "libre2ca/nfcAuth",
                                           nfcAuth2Endpoint: "libre2ca/nfcAuth2",
                                           nfcDataEndpoint: "libre2ca/nfcData",
                                           nfcDataAlgorithmEndpoint: "libre2ca/nfcDataAlgorithm")

}

enum OOPError: LocalizedError {
    case noConnection
    case jsonDecoding

    var errorDescription: String? {
        switch self {
        case .noConnection: return "no connection"
        case .jsonDecoding: return "JSON decoding"
        }
    }
}

struct OOPGen2Response: Codable {
    let p1: Int
    let data: String
    let error: String
}


struct OOP {

    enum TrendArrow: Int, CustomStringConvertible, CaseIterable {
        case unknown        = -1
        case notDetermined  = 0
        case fallingQuickly = 1
        case falling        = 2
        case stable         = 3
        case rising         = 4
        case risingQuickly  = 5

        var description: String {
            switch self {
            case .notDetermined:  return "NOT_DETERMINED"
            case .fallingQuickly: return "FALLING_QUICKLY"
            case .falling:        return "FALLING"
            case .stable:         return "STABLE"
            case .rising:         return "RISING"
            case .risingQuickly:  return "RISING_QUICKLY"
            default:              return ""
            }
        }

        init(string: String) {
            for arrow in TrendArrow.allCases {
                if string == arrow.description {
                    self = arrow
                    return
                }
            }
            self = .unknown
        }

        var symbol: String {
            switch self {
            case .fallingQuickly: return "↓"
            case .falling:        return "↘︎"
            case .stable:         return "→"
            case .rising:         return "↗︎"
            case .risingQuickly:  return "↑"
            default:              return "---"
            }
        }
    }

    enum Alarm: Int, CustomStringConvertible, CaseIterable {
        case unknown              = -1
        case notDetermined        = 0
        case lowGlucose           = 1
        case projectedLowGlucose  = 2
        case glucoseOK            = 3
        case projectedHighGlucose = 4
        case highGlucose          = 5

        var description: String {
            switch self {
            case .notDetermined:        return "NOT_DETERMINED"
            case .lowGlucose:           return "LOW_GLUCOSE"
            case .projectedLowGlucose:  return "PROJECTED_LOW_GLUCOSE"
            case .glucoseOK:            return "GLUCOSE_OK"
            case .projectedHighGlucose: return "PROJECTED_HIGH_GLUCOSE"
            case .highGlucose:          return "HIGH_GLUCOSE"
            default:                    return ""
            }
        }

        init(string: String) {
            for alarm in Alarm.allCases {
                if string == alarm.description {
                    self = alarm
                    return
                }
            }
            self = .unknown
        }

        var shortDescription: String {
            switch self {
            case .lowGlucose:           return "LOW"
            case .projectedLowGlucose:  return "GOING LOW"
            case .glucoseOK:            return "OK"
            case .projectedHighGlucose: return "GOING HIGH"
            case .highGlucose:          return "HIGH"
            default:                    return ""
            }
        }
    }

}


// TODO: Codable
class OOPHistoryResponse {
    var currentGlucose: Int = 0
    var historyValues: [Glucose] = []
}

protocol GlucoseSpaceHistory {
    var isError: Bool { get }
    var sensorTime: Int? { get }
    var canGetParameters: Bool { get }
    var sensorState: SensorState { get }
    var valueError: Bool { get }
    func glucoseData(date: Date) -> (Glucose?, [Glucose])
}


struct OOPHistoryValue: Codable {
    let bg: Double
    let quality: Int
    let time: Int
}

struct GlucoseSpaceHistoricGlucose: Codable {
    let value: Int
    let dataQuality: Int    // if != 0, the value is erroneous
    let id: Int
}


class GlucoseSpaceHistoryResponse: OOPHistoryResponse, Codable { // TODO: implement the GlucoseSpaceHistory protocol
    var alarm: String?
    var esaMinutesToWait: Int?
    var historicGlucose: [GlucoseSpaceHistoricGlucose] = []
    var isActionable: Bool?
    var lsaDetected: Bool?
    var realTimeGlucose: GlucoseSpaceHistoricGlucose = GlucoseSpaceHistoricGlucose(value: 0, dataQuality: 0, id: 0)
    var trendArrow: String?
    var msg: String?
    var errcode: String?
    var endTime: Int?    // if != 0, the sensor expired

    enum Msg: String {
        case RESULT_SENSOR_STORAGE_STATE
        case RESCAN_SENSOR_BAD_CRC

        case TERMINATE_SENSOR_NORMAL_TERMINATED_STATE    // errcode: 10
        case TERMINATE_SENSOR_ERROR_TERMINATED_STATE
        case TERMINATE_SENSOR_CORRUPT_PAYLOAD

        // HTTP request bad arguments
        case FATAL_ERROR_BAD_ARGUMENTS

        // sensor state
        case TYPE_SENSOR_NOT_STARTED
        case TYPE_SENSOR_STARTING
        case TYPE_SENSOR_Expired
        case TYPE_SENSOR_END
        case TYPE_SENSOR_ERROR
        case TYPE_SENSOR_OK
        case TYPE_SENSOR_DETERMINED
    }


    func glucoseData(sensorAge: Int, readingDate: Date) -> [Glucose] {
        historyValues = [Glucose]()
        let startDate = readingDate - Double(sensorAge) * 60
        // let current = Glucose(realTimeGlucose.value, id: realTimeGlucose.id, date: startDate + Double(realTimeGlucose.id * 60))
        currentGlucose = realTimeGlucose.value
        var history = historicGlucose
        if (history.first?.id ?? 0) < (history.last?.id ?? 0) {
            history = history.reversed()
        }
        for g in history {
            let glucose = Glucose(g.value, id: g.id, date: startDate + Double(g.id * 60), dataQuality: Glucose.DataQuality(rawValue: g.dataQuality), source: "OOP" )
            historyValues.append(glucose)
        }
        return historyValues
    }
}

class GlucoseSpaceHistoryAndCalibrationResponse: OOPHistoryResponse, Codable { // TODO: implement the GlucoseSpaceHistory protocol
    var errcode: Int?
    var data: GlucoseSpaceHistoryResponse?
    var slope: Calibration?
    var oopType: String?    // "oop1", "oop2"
    var session: String?
}


// "callnox" endpoint specific for Libre 1 A2

struct OOPCurrentValue: Codable {
    let currentTime: Int?
    let currentTrend: Int?
    let serialNumber: String?
    let historyValues: [OOPHistoryValue]?
    let currentBg: Double?
    let timestamp: Int?
    enum CodingKeys: String, CodingKey {
        case currentTime
        case currentTrend = "currenTrend"
        case serialNumber
        case historyValues = "historicBg"
        case currentBg
        case timestamp
    }
}

struct GlucoseSpaceList: Codable {
    let content: OOPCurrentValue?
    let timestamp: Int?
}

class GlucoseSpaceA2HistoryResponse: OOPHistoryResponse, Codable { // TODO: implement the GlucoseSpaceHistory protocol
    var errcode: Int?
    var list: [GlucoseSpaceList]?

    var content: OOPCurrentValue? {
        return list?.first?.content
    }
}


/// errcode: 4, msg: "content crc16 false"
/// errcode: 5, msg: "oop result error" with terminated sensors

struct OOPCalibrationResponse: Codable {
    let errcode: Int
    let parameters: Calibration
    enum CodingKeys: String, CodingKey {
        case errcode
        case parameters = "slope"
    }
}



// https://github.com/bubbledevteam/bubble-client-swift/blob/master/LibreSensor/LibreOOPResponse.swift

// TODO: when adding URLQueryItem(name: "appName", value: "diabox")
struct GetCalibrationStatusResult: Codable {
    var status: String?
    var slopeSlope: String?
    var slopeOffset: String?
    var offsetOffset: String?
    var offsetSlope: String?
    var uuid: String?
    var isValidForFooterWithReverseCRCs: Double?

    enum CodingKeys: String, CodingKey {
        case status
        case slopeSlope = "slope_slope"
        case slopeOffset = "slope_offset"
        case offsetOffset = "offset_offset"
        case offsetSlope = "offset_slope"
        case uuid
        case isValidForFooterWithReverseCRCs = "isValidForFooterWithReverseCRCs"
    }
}


struct GlucoseSpaceActivationResponse: Codable {
    let error: Int
    let productFamily: Int
    let activationCommand: Int
    let activationPayload: String
}


func postToOOP(server: OOPServer, bytes: Data = Data(), date: Date = Date(), patchUid: SensorUid? = nil, patchInfo: PatchInfo? = nil, session: String? = "") async throws -> (Data?, URLResponse?, [URLQueryItem])  {

    var urlComponents = URLComponents(string: server.siteURL + "/" + (patchInfo == nil ? server.calibrationEndpoint! : (bytes.count > 0 ? (bytes.count > 46 ? (session == "" ? server.historyEndpoint! : server.historyAndCalibrationEndpoint!) : server.bleHistoryEndpoint!) : server.activationEndpoint!)))!

    var queryItems: [URLQueryItem] = bytes.count > 0 ? [URLQueryItem(name: "content", value: bytes.hex)] : []
    let date = Int64((date.timeIntervalSince1970 * 1000.0).rounded())
    if let patchInfo = patchInfo {
        queryItems += [
            URLQueryItem(name: "accesstoken", value: server.token),
            URLQueryItem(name: "patchUid", value: patchUid!.hex),
            URLQueryItem(name: "patchInfo", value: patchInfo.hex),
            URLQueryItem(name: "appName", value: "diabox"),
            URLQueryItem(name: "oopType", value: "OOP1AndOOP2"),
            URLQueryItem(name: "session", value: session)
        ]
        if bytes.count == 46 {
            queryItems += [
                URLQueryItem(name: "appName", value: "Diabox"),
                URLQueryItem(name: "cgmType", value: "libre2ble")
            ]
        }
    } else {
        queryItems += [
            URLQueryItem(name: "token", value: server.token),
            URLQueryItem(name: "timestamp", value: "\(date)")
            // , URLQueryItem(name: "appName", value: "diabox")
        ]
    }
    urlComponents.queryItems = queryItems
    var request = URLRequest(url: urlComponents.url!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    let (data, urlResponse) = try await URLSession.shared.data(for: request)
    return (data, urlResponse, queryItems)
}


extension MainDelegate {

    func post(_ endpoint: String, _ jsonObject: Any) async throws -> Any {
        let server = OOPServer.gen2
        let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject)
        var request = URLRequest(url: URL(string: "\(server.siteURL)/\(endpoint)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        do {
            log("OOP: posting to \(request.url!.absoluteString) \(jsonData!.string)")
            let (data, urlResponse) = try await URLSession.shared.data(for: request)
            log("OOP: response: \(data.string)")
            do {
                switch endpoint {
                case server.nfcDataEndpoint:
                    let json = try JSONDecoder().decode(OOPGen2Response.self, from: data)
                    log("OOP: decoded response: \(json)")
                    return json
                case server.historyAndCalibrationA2Endpoint:
                    let json = try JSONDecoder().decode(GlucoseSpaceA2HistoryResponse.self, from: data)
                    log("OOP: decoded response: \(json)")
                    return json
                default:
                    break
                }
            } catch {
                log("OOP: error while decoding response: \(error.localizedDescription), response header: \(urlResponse.description)")
                throw OOPError.jsonDecoding
            }
        } catch {
            log("OOP: server error: \(error.localizedDescription)")
            throw OOPError.noConnection
        }
        return ["": ""]
    }


    func applyOOP(sensor: Sensor?) async {

        if !settings.usingOOP {
            DispatchQueue.main.async {
                self.app.oopGlucose = 0
                self.app.oopAlarm = .unknown
                self.app.oopTrend = .unknown
                self.history.values = []
            }
            return
        }

        guard let sensor = sensor else {
            return
        }

        var session = UUID().uuidString

        if settings.debugLevel > 0 { session = "" } // test the old calibrationEndpoint and historyEndpoint

        if session.isEmpty {

            do {
                log("OOP: posting sensor data to \(settings.oopServer.siteURL)/\(settings.oopServer.calibrationEndpoint!)...")
                let (data, urlResponse, queryItems) = try await postToOOP(server: settings.oopServer, bytes: sensor.fram, date: app.lastReadingDate)
                log("OOP: post query parameters: \(queryItems)")
                if let data = data {
                    log("OOP: server calibration response: \(data.string)")
                    if let oopCalibration = try? JSONDecoder().decode(OOPCalibrationResponse.self, from: data) {
                        if oopCalibration.parameters.offsetOffset == -2.0 &&
                            oopCalibration.parameters.slopeSlope  == 0.0 &&
                            oopCalibration.parameters.slopeOffset == 0.0 &&
                            oopCalibration.parameters.offsetSlope == 0.0 {
                            log("OOP: null calibration")
                            errorStatus("OOP calibration not valid")
                        } else {
                            DispatchQueue.main.async {
                                self.settings.oopCalibration = oopCalibration.parameters
                                if self.app.calibration == .empty || (self.app.calibration != self.settings.calibration) {
                                    self.app.calibration = oopCalibration.parameters
                                }
                            }
                        }
                    } else {
                        if data.string.contains("errcode") {
                            errorStatus("OOP calibration error: \(data.string)")
                        }
                    }

                } else {
                    log("OOP: failed calibration: response header: \(urlResponse?.description ?? "[null response header]")")
                    errorStatus("OOP calibration failed")
                }

                if sensor.patchInfo.count == 0 {
                    didParseSensor(sensor)
                    return
                }

            } catch {
                log("OOP: connection failed: \(error.localizedDescription)")
                errorStatus("OOP connection failed")
            }

        }

        guard sensor.patchInfo.count > 0 else {
            errorStatus("Patch info not available")
            return
        }

        var fram = sensor.encryptedFram.count > 0 ? sensor.encryptedFram : sensor.fram

        guard fram.count >= 344 else {
            log("NFC: partially scanned FRAM (\(fram.count)/344): cannot proceed to OOP")
            return
        }

        // decryptFRAM() is symmetric: encrypt decrypted fram received from a Bubble
        if (sensor.type == .libre2 || sensor.type == .libreUS14day) && sensor.encryptedFram.count == 0 {
            fram = try! Data(Libre2.decryptFRAM(type: sensor.type, id: sensor.uid, info: sensor.patchInfo, data: fram))
        }

        // FIXME: "user ID not null" error
        if sensor.patchInfo[0] == 0xA2 {  // newer Libre 1
            let json: [String: Any] = [
                "userId": 1,
                "list": [
                    ["timestamp": "\(Int64(Date().timeIntervalSince1970 * 1000))",
                     "content": sensor.fram.hex]
                ]
            ]
            do {
                let response = try await post(OOPServer.default.historyAndCalibrationA2Endpoint!, json)
                if let oopData = response as? GlucoseSpaceA2HistoryResponse
                {
                    // TODO
                    log("OOP: data: \(oopData)")
                }
            } catch {
                log("OOP: error: \(error.localizedDescription)")
            }
        }

        log("OOP: posting sensor data to \(settings.oopServer.siteURL)/\(session == "" ? settings.oopServer.historyEndpoint! : settings.oopServer.historyAndCalibrationEndpoint!)...")

        do {
            let (data, urlResponse, queryItems) = try await postToOOP(server: settings.oopServer, bytes: sensor.fram, date: app.lastReadingDate, patchUid: sensor.uid, patchInfo: sensor.patchInfo, session: session)
            log("OOP: post query parameters: \(queryItems)")
            if let data = data {
                log("OOP: history response: \(data.string)")
                if data.string.contains("errcode") {
                    errorStatus("OOP history error: \(data.string)")
                    DispatchQueue.main.async {
                        self.history.values = []
                    }
                } else {
                    var oopData: GlucoseSpaceHistoryResponse?
                    if !session.isEmpty {
                        let oopResponse = try? JSONDecoder().decode(GlucoseSpaceHistoryAndCalibrationResponse.self, from: data)
                        oopData = oopResponse?.data
                        // TODO: verify calibration parameters
                        if let oopCalibration = oopResponse?.slope {
                            DispatchQueue.main.async {
                                self.settings.oopCalibration = oopCalibration
                                if self.app.calibration == .empty || (self.app.calibration != self.settings.calibration) {
                                    self.app.calibration = oopCalibration
                                }
                            }
                        }
                    } else {
                        oopData = try? JSONDecoder().decode(GlucoseSpaceHistoryResponse.self, from: data)
                    }
                    if let oopData = oopData {
                        let realTimeGlucose = oopData.realTimeGlucose.value
                        DispatchQueue.main.async {
                            if realTimeGlucose > 0 {
                                self.app.oopGlucose = realTimeGlucose
                            }
                            self.app.oopAlarm = OOP.Alarm(string: oopData.alarm ?? "")
                            self.app.oopTrend = OOP.TrendArrow(string: oopData.trendArrow ?? "")
                            self.app.trendDeltaMinutes = 0
                        }
                        var oopHistory = oopData.glucoseData(sensorAge: sensor.age, readingDate: app.lastReadingDate)
                        let oopHistoryCount = oopHistory.count
                        if oopHistoryCount > 1 && history.rawValues.count > 0 {
                            if oopHistory[0].value == 0 && oopHistory[1].id == history.rawValues[0].id {
                                oopHistory.removeFirst()
                                debugLog("OOP: dropped the first null OOP value newer than the corresponding raw one")
                            }
                        }
                        if oopHistoryCount > 0 {
                            if oopHistoryCount < 32 { // new sensor
                                oopHistory.append(contentsOf: [Glucose](repeating: Glucose(-1, date: app.lastReadingDate - Double(sensor.age) * 60), count: 32 - oopHistoryCount))
                            }
                            let oopValues = oopHistory
                            DispatchQueue.main.async {
                                self.history.values = oopValues
                            }
                        } else {
                            DispatchQueue.main.async {
                                self.history.values = []
                            }
                        }
                        log("OOP: current glucose: \(realTimeGlucose), history values: \(oopHistory.map{ $0.value })".replacingOccurrences(of: "-1", with: "… "))
                    } else {
                        log("OOP: error while decoding JSON data")
                        errorStatus("OOP server error: \(data.string)")
                    }
                }
            } else {
                log("OOP: response header: \(urlResponse?.description ?? "[null response header]")")
            }

        } catch {
            DispatchQueue.main.async {
                self.history.values = []
            }
            log("OOP: connection failed: \(error.localizedDescription)")
            errorStatus("OOP connection failed")
        }

    }
}


extension Sensor {

    func testOOPActivation() async {
        // FIXME: await main.settings.oopServer
        let server = OOPServer.default
        log("OOP: posting sensor data to \(server.siteURL)/\(server.activationEndpoint!)...")
        do {
            let (data, _, queryItems) = try await postToOOP(server: server, patchUid: uid, patchInfo: patchInfo)
            debugLog("OOP: query parameters: \(queryItems)")
            if let data = data {
                debugLog("OOP: server activation response: \(data.string)")
                if let oopActivationResponse = try? JSONDecoder().decode(GlucoseSpaceActivationResponse.self, from: data) {
                    log("OOP: activation response: \(oopActivationResponse), activation command: \(UInt8(Int16(oopActivationResponse.activationCommand) & 0xFF).hex)")
                }
                log("\(type) computed activation command: \(activationCommand.code.hex.uppercased()) \(activationCommand.parameters.hex.uppercased())" )
            }
        } catch {
            log("OOP: error while testing activation command: \(error.localizedDescription)")
        }

    }
}
