import Foundation


// https://github.com/bubbledevteam/bubble-client-swift/blob/master/BubbleClient/LibrePro.swift


/// Some notes on the Libre Pro still to be verified:
/// =================================================

// 5 + 4 + 13 FRAM blocks readable by ISO commands:
//   0:  ( 40, "Header")
//  40:  ( 32, "Footer")
//  72:  (104, "Body")
//
// 176:  historic measurements (no CRC)
//
// header[4]: sensor state
// header[6]: failure error code when state = 06
// header[7...8]: sensor age when failure occurred [0 = unknown]
//
// footer[6...7]: maximum life
//
// body[2...3]:   sensor age
// body[4...5]:   trend index
// body[6...7]:   history index
// body[8...103]: 16 6-byte trend values
//
// The following blocks storing 14 days of historic data (≈ 8 KB) are to be read by
// using B0/B3 when their index > 255
//
// blocks 0x0406 - 0x04DD: section ending with the patch table for the commands
//                         A0 A1 A2 A4 A3 ?? E0 E1 E2
//
// The raw value is masked by 0x1FFF and needs a conversion factor of 8.5
//
// Libre Pro memory dump:
// config: 0x1A00, 64
// sram:   0x1C00, 4096


class LibrePro: Sensor {

#if !os(watchOS)

    override func execute(nfc: NFC, taskRequest: TaskRequest) async throws {

        switch taskRequest {

        case .readFRAM:

            let historyIndex = Int(fram[78]) + Int(fram[79]) << 8
            let startIndex = max(((historyIndex - 1) * 6) / 8 - 31, 0)
            let offset = (8 - ((historyIndex - 1) * 6) % 8) % 8
            let blockCount = min(((historyIndex - 1) * 6) / 8, offset == 0 ? 24 : 25)

            // var blockCount = min(((historyIndex - 1) * 6) / 8, offset == 0 ? 24 : 25) // TEST
            // print("DEBUG: original historyIndex: \(historyIndex), startIndex: \(startIndex), offset: \(offset), blockCount: \(blockCount), start: \(22 + startIndex ), offset...(offset + blockCount * 8): \(offset)...\(offset + blockCount * 8)")
            // let start = 22 + min(startIndex, fram.count / 8 - 22)     // TEST
            // let historyData = Data(fram[176...].prefix(46 * 8))       // TEST
            // blockCount = min(blockCount, (fram.count - 176) / 8 - 8)  // TEST
            // print("DEBUG: TEST fram: \(fram), historyIndex: \(historyIndex), startIndex: \(startIndex), offset: \(offset), blockCount: \(blockCount), start: \(start), historyData: \(historyData), offset...(offset + blockCount * 8): \(offset)...\(offset + blockCount * 8)")

            let (start, historyData) = try await nfc.readBlocks(from: 22 + startIndex, count: blockCount)
            log(historyData.hexDump(header: "NFC: did read \(historyData.count / 8) FRAM blocks:", startingBlock: start))
            let measurements = (blockCount * 8) / 6
            let history = Data(historyData[offset..<(offset + measurements * 6)])
            log(history.hexDump(header: "Libre Pro: \(measurements) 6-byte measurements:", startingBlock: historyIndex))

        default:
            break

        }
    }

#endif    // #if !os(watchOS)


    // TODO: convert history blocks to Libre 1 layout

    override func parseFRAM() {
        updateCRCReport()
        guard !crcReport.contains("FAILED") else {
            state = .unknown
            return
        }

        if let sensorState = SensorState(rawValue: fram[4]) {
            state = sensorState
        }

        guard fram.count >= 176 else { return }

        age = Int(fram[74]) + Int(fram[75]) << 8                 // body[2...3]
        let startDate = lastReadingDate - Double(age) * 60

        //  TODO: initializations = Int(fram[??])

        trend = []
        history = []
        let trendIndex = Int(fram[76]) + Int(fram[77]) << 8      // body[4...5]
        let historyIndex = Int(fram[78]) + Int(fram[79]) << 8    // body[6...7]

        log("DEBUG: Libre Pro: trend index: \(trendIndex), history index: \(historyIndex), age: \(age) minutes (\(age.formattedInterval))")


        // MARK: - continue C&P review from the Sensor base class


        for i in 0 ... 15 {
            var j = trendIndex - 1 - i
            if j < 0 { j += 16 }
            let offset = 80 + j * 6                              // body[8 ..< 104]
            // TODO: test the 13-bit mask; use a 8.5 conversion factor?
            let rawValue = readBits(fram, offset, 0, 0xe) & 0x1FFF
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

            let j = historyIndex - 1 - i
            var offset = 176 + j * 6

            // TODO: on a real Libre Pro scan the 32 historic measurements by using B3

            if fram.count < offset + 6 {
                // test the first history blocks which were scanned anyway
                let scanned = (fram.count - 176) / 6
                offset = 176 + (scanned - 1 - i) * 6
                if offset < 176 { continue }
            }

            // TODO: test the 13-bit mask; use a 8.5 conversion factor?
            let rawValue = readBits(fram, offset, 0, 0xe) & 0x1FFF
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


        // Libre Pro: fram[42...43] (footer[2..3]) corresponds to patchInfo[2...3]

        // TODO: with a Libre Pro footer[2...3] = 1000 family = 1 but region = 00 ???
        region = Int(fram[43])

        maxLife = Int(fram[46]) + Int(fram[47]) << 8   // footer[6...7]
        DispatchQueue.main.async {
            self.main?.settings.activeSensorMaxLife = self.maxLife
        }

        let b = 14 + 42                                // footer[16]
        let i1 = readBits(fram, 26, 0, 3)
        let i2 = readBits(fram, 26, 3, 0xa)
        let i3 = readBits(fram, b, 0, 8)
        let i4 = readBits(fram, b, 8, 0xe)
        let negativei3 = readBits(fram, b, 0x21, 1) != 0
        let i5 = readBits(fram, b, 0x28, 0xc) << 2
        let i6 = readBits(fram, b, 0x34, 0xc) << 2

        calibrationInfo = CalibrationInfo(i1: i1, i2: i2, i3: negativei3 ? -i3 : i3, i4: i4, i5: i5, i6: i6)
        DispatchQueue.main.async {
            self.main?.settings.activeSensorCalibrationInfo = self.calibrationInfo
        }
    }


    override func detailFRAM() {
        log("\(fram.prefix(46 * 8).hexDump(header: "\(type) \(serial) FRAM:", startingBlock: 0))")
        debugLog("\(fram.hexDump(header: "TEST: \(type) \(serial) full FRAM:", startingBlock: 0))")
        if crcReport.count > 0 {
            log(crcReport)
            if crcReport.contains("FAILED") {
                if history.count > 0 { // bogus raw data
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
        //        if main.settings.debugLevel > 0 {
        //            log("Sensor factory values: raw minimum threshold: \(fram[330]) (tied to SENSOR_SIGNAL_LOW error, should be 150 for a Libre 1), maximum ADC delta: \(fram[332]) (tied to FILTER_DELTA error, should be 90 for a Libre 1)")
        //        }
        //
        //        if initializations > 0 {
        //            log("Sensor initializations: \(initializations)")
        //        }

        log("Sensor region: \(SensorRegion(rawValue: region)?.description ?? "unknown")\(region != 0 ? " (0x\(region.hex))" : "")")
        if maxLife > 0 {
            log("Sensor maximum life: \(maxLife) minutes (\(maxLife.formattedInterval))")
        }
        if age > 0 {
            log("Sensor age: \(age) minutes (\(age.formattedInterval)), started on: \((lastReadingDate - Double(age) * 60).shortDateTime)")
        }
    }


    override func updateCRCReport() {
        if fram.count < 176 {
            crcReport = "NFC: FRAM read did not complete: can't verify CRC"

        } else {
            let headerCRC = UInt16(fram[0...1])
            let footerCRC = UInt16(fram[40...41])
            let bodyCRC   = UInt16(fram[72...73])
            let computedHeaderCRC = crc16(fram[2...39])
            let computedFooterCRC = crc16(fram[42...71])
            let computedBodyCRC   = crc16(fram[74...175])

            var report = "Sensor header CRC16: \(headerCRC.hex), computed: \(computedHeaderCRC.hex) -> \(headerCRC == computedHeaderCRC ? "OK" : "FAILED")"
            report += "\nSensor footer CRC16: \(footerCRC.hex), computed: \(computedFooterCRC.hex) -> \(footerCRC == computedFooterCRC ? "OK" : "FAILED")"
            report += "\nSensor body CRC16: \(bodyCRC.hex), computed: \(computedBodyCRC.hex) -> \(bodyCRC == computedBodyCRC ? "OK" : "FAILED")"

            //            if fram.count >= 344 + 195 * 8 {
            //                let commandsCRC = UInt16(fram[344...345])
            //                let computedCommandsCRC = crc16(fram[346 ..< 344 + 195 * 8])
            //                report += "\nSensor commands CRC16: \(commandsCRC.hex), computed: \(computedCommandsCRC.hex) -> \(commandsCRC == computedCommandsCRC ? "OK" : "FAILED")"
            //            }

            crcReport = report
        }
    }


    // https://github.com/gui-dos/DiaBLE/discussions/2

    static func test(main: MainDelegate) -> Sensor {

        let sensor = LibrePro(main: main)
        sensor.lastReadingDate = Date()

        sensor.uid = Data("6e58b50300a407e0".bytes)
        sensor.patchInfo = Data("70001000e42e3a03".bytes)

        let header = """
        #00  D3 40 00 00 03 00 00 00  .@......
        #01  00 00 00 00 00 00 00 00  ........
        #02  00 00 00 00 00 00 00 00  ........
        #03  4A 46 47 55 32 36 39 2D  JFGU269-
        #04  54 30 33 31 31 47 04 0E  T0311G..
        """
        let footer = """
        #05  C7 DD 10 00 F0 0B C0 4E  .......N
        #06  14 03 96 80 5A 00 ED A6  ....Z...
        #07  0E 6E 5A AF 04 4D 5A 63  .nZ..MZc
        #08  3A 03 CB 1B 00 00 00 00  :.......
        """
        let body = """
        #09  6E 6F E6 14 05 00 64 01  no....d.
        #0a  77 43 AF FC DC 00 80 43  wC.....C
        #0b  AF 10 DD 00 6D 43 AF 00  ....mC..
        #0c  DD 00 9F 43 AF 20 DD 00  ...C. ..
        #0d  79 43 AF 5C DD 00 7A 43  yC.\\..zC
        #0e  AF CC DC 00 55 43 AF D0  ....UC..
        #0f  DC 00 8B 43 AF D8 DC 00  ...C....
        #10  84 43 AF DC DC 00 85 43  .C.....C
        #11  AF F4 DC 00 84 43 AF E4  .....C..
        #12  DC 00 58 43 AF DC DC 00  ..XC....
        #13  85 43 AF E0 DC 00 7F 43  .C.....C
        #14  AF E4 DC 00 76 43 AF E8  ....vC..
        #15  DC 00 A9 43 AF E4 DC 00  ...C....
        """
        let history = """
        #16  7D 83 80 B6 97 01 C0 43  }......C
        #17  AF F4 D6 01 BE 43 AF 80  .....C..
        #18  D6 01 CC 43 AF 30 D6 01  ...C.0..
        #19  4A 43 AF 08 D6 01 D7 40  JC.....@
        #1a  AF F4 D5 01 20 42 AF 20  .... B.
        #1b  D6 01 70 42 AF E4 D5 01  ..pB....
        #1c  34 43 AF E8 15 02 B3 43  4C.....C
        #1d  AF CC D5 01 44 43 AF F0  ....DC..
        #1e  D5 01 52 43 AF FC D5 01  ..RC....
        #1f  A7 43 AF EC 15 02 A8 43  .C.....C
        #20  AF BC 15 02 CE 43 AF AC  .....C..
        #21  15 02 B8 43 AF B4 15 02  ...C....
        #22  49 42 AF 8C D6 01 8B 41  IB.....A
        #23  AF 64 D6 01 E1 40 AF 30  .d...@.0
        #24  D6 01 62 41 AF 20 D6 01  ..bA. ..
        #25  5D 41 AF 00 D6 01 BE 42  ]A.....B
        #26  AF DC 15 02 E5 42 AF F4  .....B..
        #27  D5 01 DF 42 AF 28 D6 01  ...B.(..
        #28  55 43 AF 2C D6 01 A0 42  UC.,...B
        #29  AF 28 D6 01 45 43 AF 3C  .(..EC.<
        #2a  D6 01 33 43 AF 34 D6 01  ..3C.4..
        """

        sensor.fram = Data(header.bytes + footer.bytes + body.bytes + history.bytes)
        sensor.detailFRAM()
        main.log("TEST: Libre Pro: trend values: \(sensor.trend.map(\.value))")
        main.debugLog("TEST: Libre Pro: trend: \(sensor.trend)")
        main.log("TEST: Libre Pro: history values: \(sensor.history.map(\.value))")
        main.debugLog("TEST: Libre Pro: history: \(sensor.history)")
        DispatchQueue.main.async {
            main.history.rawTrend  = sensor.trend
            main.history.rawValues = sensor.history
        }


        sensor.uid = Data("42D43E0000A407E0".bytes)
        sensor.patchInfo = Data("70001000E633".bytes)

        sensor.fram = Data("fc62000003000000000000000000000000000000000000004a454d593033322d543031303943aaea4dbd10005f0ac04e140396805a00eda6106a1abb04ff9b759402c81b000000008d903a340a007b030604887e5d801104bb845d800e04bb8c5d800d04bb8c5d800b04bb7c5d800904885a9d800904bb605d800704bb585d800404bb385d800404bb3c5d80a803bb7c5d80ba03886e9d80cf03bbd45d80df03bbec5d80ef03bb9c5d80f903bb945d802802bbc85e801702bb945e807602bb685e802c03bbd85d802c03bbc861805403bb486080cf03bb606080bf03bba45e807703bb145f806b03bb345f808403bb945f808703bba05f80db03bb285d80b503bb505f804e03bbd85f805003bb0ca0803703bbfc9e80ed02bbb8a080e202bb985f808a02bbdc62809b02bb689f808802bb7c9f807202bb3ca0808702bb346080a702bb68a080b302bbc49f803903bb4c9f805503bb7c5f805403bb609f80d502bba45f805802bb0c9f804c02bbf45e805702bb105f803a02bb489f803202bb506080af01bbb86480fa01bbe860807501bb305d80fc01bb489c804c01bb049b80bd01bb3c5a80c201bbd899801502bbb459805002bbb059800502bbc45980ff01bbb05b805a02bb685c805902bb485c80b401bba09a804d02bb185c802802bbb85b80ed01bb145c80c301bb505c80a501bb545c809101bb345c80a001bbc45b80b901bb8c5b80e401bb905c80ec01bb9c5e800502bb605f802e02bb9c5f808302bb905e805202bb485d808c02bbf85d806702bb945e806802bbe05e80cf02bb5c5e801e03bb985e801b03bb585f80f002bbe85f801d03bb989f80f702bbc05f80d102bb445f80d702bb485f80e102bb445f804e03bb089f804603bbe45f806003bb08a0805003bb885f802703bb0460800203bbf05f80d802bb485f80ea02bb105e80e302bbbc5e80f702bb8c5e804403bbc85e80f203bbb45e800304bb945e803d04bb149e801f04bbdc9d806e03bb045e80be02bbf45c80d002bb8c9c80da02bbfc9b80aa02bb785c808f02bbd85c806902bbd85c80bc02bb405d806402bb349c808302bb0c5c807f02bb005c80bc02bb089c80ea02bb5c5b80a202bb505b800403bbbc5c805103bbf05b805f03bb509b809403bb805b805c03bb385c808503bbe09a808903bb149b805803bbe45b807503bbdc5b807903bb685b80fe03bb589b80b204bb805b802405bbb45b808905bba45c801305bbd89e80e204bb9c5f807b04bb0460805404bbec5f802504bbf85f800a04bbd060809003bb4860808503bbb860801603bb50a0801203bb405f808d02bb9463807a02bba462808002bbbc61808102bb5860803802bb645e80f801bbac5d80a502bb605d80e002bb145e80bc02bbd05e80cd02bbe09e80dc02bbd45e80fb02bbe45e80cb02bb385f80ae02bb545f80b802bbec5e80d902bbc85c800c03bbd45b801703bba05b802903bb2c5b803603bbb85c803603bb045d804b03bbd85b80f902bbe85a80dd02bb749a80e902bb205a800903bbc49980a403bb809b80b603bb449c80e003bba49d808203bb385d80e103bb9c5d805804bbf05c803504bb385e804604bbc49d806304bb789d807904bb745d807e04bb605e808804bbcc5e807904bbd85e807604bb805f802a04bb505f803704bb1c5e804104bb945d808a04bb885d806304bbc05d805b04bb5c5d805804bb405d804504bb445d802004bb4c5d803204bb6c5d802c04bbd45d801204bbc05d800204bb1c5e80c803bb045e80c903bb645e807204bbf05e80ca04bb005f801905bbec5e80f404bb905f80cd04bb105f805205bbb85e801806bbf85e80d605bb0c5f808c05bbfc9e809e05bbb05f808305bb205f805c05bbd45e804b05bbd45e80e004bb049f809304bbf45e808104bbdc5e806b04bbec5e802d04bb145f804a04bb345f805d04bba85f800c04bba89f80cd03bbf05e807f03bb8c5e803103bb645e802903bbfc5e803003bb785f803d03bbe45f803603bb4c5f804003bb145e802e03bb645e804103bb405e806703bb545e808003bbf45e80aa03bb045f80a503bb6c5f808003bb8c5f806203bbec5f802a03bb6c60803703bb1c60804903bb0860805803bbb460807303bbf8a0803b04bbb46180f704bb24a0807505bbac5f80ac05bbd860800906bb4860805006bb205e806406bb749c80b906bbcc5b80e806bb705b80f806bb109b80a906bb3c5b807906bb545b805f06bb685b805406bb5c5c80fd05bb9c5c80dd05bb9c5c80a205bbf85e803c05bb585f809e05bb8c5c80e905bb285b80f805bb905a808c05bb585a80ca05bb145a809e05bbe499809805bb685a802d05bb585d800305bb505e80ef04bb9c5e802405bb8c5e804005bbf05c804205bb085e80e404bbf85f80b004bbf45f803605bb585f809405bb4c60806205bbd860801005bbc460800105bb9060800505bbd46080fe04bb7c6080cf04bb606080b304bb6860807f04bb8460807a04bbb85f806b04bb845f806c04bb485f807f04bb7c5e808a04bb585e806b04bb505e805304bb985e800804bbb49f80cd03bb6c20802903bbe85f803002bbf05f801c02bb3c60807f02bb3060801003bb405f801b03bb505e80a202bb405e804402bb6c5e80dd0288525f800003bbb05f80f002bbac5f80d402bb005f800303bb6c5e800403bb745d806602bb885d801602bb805d804302bb945c803a03bb785e804004bb345f80c004bb4c5f80cd04bb045e805f04bb485e809804bbe05d804a04bbcc5e80c303bb185f801803bbd05e800403bbd060802d03bb6461806703bb0822806703bb6860802303bb546080f502bbe05f801c03bba45f807d03bb705f80a303bb685f80ce03bb805f809d03bb149f801603bb545f809102bb1c5f809402bbdc5e80580288fe5e805902885a5e816d02883e1e81970288aa1d81a002bb145e809902bb7c5d806f02bb4460808002bbf05f807902bb30a0807302bb1c5f80f902bba45e801f03bb545b804503bb445a808103bbd85980b203bb3c5a80af03bb705a807603bb9459808a03bb6059807f03bb485980a803bb345980dd03bbc41980bf03bb445a80ca03bb645a80eb03bb3c5a802004bb005c802b04bb305b805b04bb785a809b04bb289a80aa04bbfc59806204bbd85980860488c65c808104bb605d80ac04bb505d80ad04bbc85b80ef04bb785c80c404bb105e80b704bb285f801905bb705e805d05bb785e807f05bb685f804f05bbbc5f802805bb7c60802105bb806080fa04bb846080ed04bbd85f80e904bb505f80e404bbd85e80cf04bb845e80be04bb705e80b904bb185f808504bb8060804d04bb8c20805204bb6c5f805204bbc05f804f04bbac5f805104bb205f804404bb505f802004bb685f80ca03bbf85f808704bbb05f80aa04bb805f80cf04bbe85f802e05bbbc5f807605bbf45f80ae05bba05f80bb05bbb05f807305bb945f803005bbbc5f800605bb1860800105bba45f80e504bb9820800305bb385f800d05bb745f80ff04bbe45e80f004bbb85e80e804bb305f80a604bbe05e808c04bb245f807704bb745e809a04bbf05e809504bb7c5e80a004bbdc5e806a04bbc81e803e04bbfc5e803504bba85e802204bb385f800004bb0c5f80ec03bbf05e80cc03bbc45f80c103bbfc5e80b603bbe05e80af03bb085f807603bbf05e80be02bbd45e806102bb1c60803e02bbc05f80f501bb585f806602bb005f809603bbdc5e80e303bbb0a1801104bb2c60801a04bb145f807d04bbd05f807604bb4420809d04bb4c6080c104bbf45c80e904bb545b804f05bb585a805f05bb185a805905bbbc59807105bbe059807105bbb859804305bb9059804e05bb7859802f05bb6459800905bb6459800505bb6459800405bb185a80f504bb7c5a800305bb9c5a80f504bbc85a804405bb205b800305bb105a803a05bbd459804305bbc859804e05bb945980a904bb8059800005bbc45b80f804bbf81c801305bb985c800e05bbc05c80fd04bb9c60802405bbd85e803705bb4060804805bb2c5f803f05bb9c60801d05bbe060800c05bbc461800705bb7861801b05bb70a080fb04bbe02080db04bb286080c304bbc05f80b304bba45f80b204bbf85e80b004bb0c5f80bc04bbcc5e80c204bbc85e809e04bb785f807d04bbcc60804704bb3461805c04bb4460804804bb745f805604bba820802b04bb6c6080e103bb046180d003bbc06080ec03bb3c6080eb03bb6c6180e903bb8061802104bbd460808d04bba85e80e504bb7c60802005bbd45f809105bba45e800206bb485e801706bb085e80fa05bb405e80df05bb785e80d005bb185e80bf05bb205e80c105bbd45d806d05bb305f802a05bbc85f80f104bba46080e004bb8ca080e904bb985e80db04bb945e80b604bbb85e80d104bb605e80e204bb985e80ce04bbe85e809e04bb109f807804bbf85e805304bb585e803504bbac5e802a04bb845e801004bb805e800804bb685e801204bb905e803404bb305e806504bba85e809704bb805e80a304bb889e809004bbcc5e808504bbdc5e807604bbf05f80f103bb606280ea03bb2860800504bb585f80f103bb685f80dc03bb149f80d103bb2c5f80b103bb805e80b803bb445e80b203bb105e80b503bbdc5d80b203bbac5b80bf03bb2c5b80bc03bbac5c80b703bb945c80a403bbf85c807203bbb05c804803bb445d805903bb185d808503bbec5c80a803bbe05c80bc03bbc45b80c503bbb85a808e03bb1c5d809e03bb945b80b303bb3c5c80c203bb785d800004bb945d801a04bbf85d803504bb5c5c801a04bb5c5d80f303bb1c5e80e103bb905e80dd03bb409e80e003bb785e80e603bbb45c80ea03bbd05b80f903bb305b800904bb685b80fa03bb545c800404bb745b801004bb605b80de03bbe85b80d803bb7c5d80e903bb485f80b003bb006080b203bb6460809d03bbc460808b03bb0061807e03bb985f80ac03bbb85e80b203bba45e806903bb805e80cf03bb0c5c80f303bb0c5d806e03bb205f804303bb7060800603bb0460800303bbcc60808203bbd86080b304bbdc5e804105bbe85e80a305bbd05e800506bb7c5e80be05bb945d80a905bbb85d803f05bb885d80f604bb0c5e808304bb885e804104bbc85e801204bb885f80b703bbdc9f809003bbd85f808203bb1860804604bbc060802d05bb6c6280a505bb6c61807a05bb6c61800305bbbc61805e04bb805f809103bb1c60806c03bbf45d804e03bb249c806a03bb8c5c804d03bb249e806403bbe45d804d03bb4c5e805203bbe85d806003bb445d805903bb449d804103bbf05c803903bb185e800c03bb8c5c801203bb345d80ee02bb405e80d602bb405d80b002bb585d809902bb305e809402bbfc5c80aa02bbc45c80ae02bbc05d80ae02bb989c80c302bb2c5b804303bb509b807e03bb309c807d03bbf05b807403bb285c805603bb405c804303bbd09a802e03bb749a804803bb9c9a802103bb249a803903bbd05b804703bb809c804a03bb845b806303bb909a807803bb445a809903bb1c9a80b403bbdc5980ad03bb9c59809403bbd05980aa03bb509a806b03bb8c59807203bb445b807a03bb945b808603bbd45b80a503bb445b808503bb745a809303bb1c5a80a603bbe09980ae03bbd45b809503bb845c808603bba45c807d03bbd09c806a03bb705d806303bb045d807f03bb3c5d808f03bbe05d808703bb045c808703bb785b801204bb185b809f03bbc05a808b03bb745a80c403bbc05d807603bbb05d806403bb249d805803bba45d806f03bb305e803903bb2c5f802b03bb505f802903bb145f800003bb8860801203bbc05e801403bb005d800b03bb205d80de02bbd05d80c202bb045f808b02bb6c5f808102bbac5e809d02bb285e80c002bb885e80d402bbac5e80d702bbec5e805603bbf45e802c04bb745e808d04bbe45d801b05bbf85d804a05bbe45b801d05bb7c5d80f804bbe45d802705bbe89d80e904bbd85d807b04bb705f801a04bb445f80f703bbe85e80d603bb985e80c703bb649e80d103bb549e807a03bb785f80e902bba85e80ff02bb785f802103bb945f80ce02bbd45e802003bbdc5e80cb03bbc05e802a04bbc05e80e003bbc45e809903bb7c5e805403bbb05e809903bbb85e805a03bb1c5e808a03bb20a0803e03bb186080be03bb1c60802404bbf85d808704bbd45d809404bb485e808a04bb485f808504bb885f801005bbe05c802605bb685b802a05bbb45a802805bb385a805705bb485a803605bb009a80f104bbd05980eb04bb845980e104bb509980f404bb3459800605bb5c5980e704bb685b80a904bb485c80b20488be5c808f0488925c80480488925a804004880e5a80500488c659806904bba85980aa04bb1c5a80de04bb745980f604bb4459800c05bb585980a804bb285c80aa04bbfc5b80c804bbc45a80f404bb309b80e104bb405c80cd04bbd85c80b804bb849d80b304bbd49d80c304bb585d80b804bb649d80ba04bb3c9c80bf04bb9c9b80ae04bbac5c808204bb0c5d808704bb985d807504bb7c5e808204bb745e80ac04bb705d80c604bb4c9d80c704bb085e80cb04bb3c9e80cf04bb809e80e204bb789d801905bb2c9d800505bbec5d80d904885a9e80e804bb405e80a004bb205e806704bb805e80eb04bb905e80b80488b6a0802204bb7c6080d503bbd860805c04bba86080fc04bb3c60808205887e60804b06bb589e807b07bb9c5d803c07bb145f800f07bb945d802f07bb085d80f506bbb45c80a406bb989c807006bbc49b804506bb805b800906884a5c80950588325c813905881e5c805a0588fa5b804f05bb205c805505bb385c80f10488865c806b04880a9d804b04bb245d806504885a5c80cc04886a9d80850588ea5d80710588ee9d80810588765e816c05884ade803105bba45e804505bb245e804405bb4c5e800505bbc85c807f04bbcca0803904bbe860805004bb7c61800004bb346080f803bb086080be03bbc05e80b203bb449e809e03bb545d808c03bbe45c809103bbc45c808c03bb809c807803bba45c806203bbf09d803c03bba05e802d03bb509e801103bb085f802e03bb145d802903bb209c805003bb749b807703bb005b80b903bb889a80b303884edb80b80388925b80cf03bbec5a80e303bb649a80f203bb149a801004bbd05980e403bb245a801304bb205a802a04bb145a806904bbf45a806604bbdc5b809604bbdc1b80be04bbe45c80db04bbdc5c80dd04bbd45c80dc04bbfc5c80bb04bba45e809504bbac5e80720488ea5e81760488d65e80640488965e806504888a5e806704bbac5e807504bb045e806a0488d65d81720488261e815e04887a5e81470488f25e80370488225f803e04880a5f803304888a9f802604889e9f800e0488961f811c04887a5f80120488069f80c40388fade801c03bbd05f800e03bb885f80ae03bb245f808b04bbf05e801405bb1c5f805305bbf45e804105bbe09e800f05bbf85e80e404bbe05e80c204bbdc5e807604bbd85f805d04bbb45f802d04bb185f802604bb645f80f003bb605f80cc03bb14a080c003bb945f809503bb845f80a403bbf85f808403bb1061808003bb185e805e03bb789d801d03bb7860800203bbb05f80e902bb286080d402bbb46080c102bb785f80b802bbec9e80a602bb085f80ce02bb345e80db02bbf45d80f702bbd45d803703bbcc5d805d03bbbc5d800b04bb7c5d8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044230200a2c3000182430201b24000a56001b24010016801b24041046a01b240c1006c01c243610110428a1c0a124a4cb0123e646a9210207e400b003d4016003c4018d992125e1c824cea1c9252ea1cea1c9252ea1cea1c3a41304192920ed92ad9022c10429e1c6d427c4005009212c81ca2c30007b240805a5c01b2f0cfff4003304014f99212b61c9212b81c003c3f4033053f53fe2fa2b3220114283f404ec303430e433f533e63fd2fb2b0100022010628b2b000020008022c4c4330417c400a0030417c400b0030410a120b1208125b42e4d8584211d96b831c3c7b900300192c4c4a7c50130092127a1c58b303287a9006000f2468b303287a900e000a246a930420b2b00002000804287c4006009212a61c1a429e014a93e0235e42e4d86e837e9003000f2cb01296f94c9303249212aa1c083c4c439212ba1c9212c61c4c439212761c3040a66a304100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000".bytes)
        sensor.detailFRAM()
        main.log("TEST: Libre Pro: trend values: \(sensor.trend.map(\.value))")
        main.debugLog("TEST: Libre Pro: trend: \(sensor.trend)")
        main.log("TEST: Libre Pro: history values: \(sensor.history.map(\.value))")
        main.debugLog("TEST: Libre Pro: history: \(sensor.history)")
        DispatchQueue.main.async {
            main.history.rawTrend  = sensor.trend
            main.history.rawValues = sensor.history
        }

        return sensor

    }

}
