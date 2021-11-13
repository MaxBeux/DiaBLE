import Foundation
import AVFoundation    // AudioServicesPlaySystemSound()


struct NFCCommand {
    let code: Int
    var parameters: Data = Data()
    var description: String = ""
}

enum NFCError: LocalizedError {
    case commandNotSupported
    case customCommandError
    case read
    case readBlocks
    case write

    var errorDescription: String? {
        switch self {
        case .commandNotSupported: return "command not supported"
        case .customCommandError:  return "custom command error"
        case .read:                return "read error"
        case .readBlocks:          return "reading blocks error"
        case .write:               return "write error"
        }
    }
}


extension Sensor {

    var backdoor: Data {
        switch self.type {
        case .libre1:    return Data([0xc2, 0xad, 0x75, 0x21])
        case .libreProH: return Data([0xc2, 0xad, 0x00, 0x90])
        default:         return Data([0xde, 0xad, 0xbe, 0xef])
        }
    }

    var activationCommand: NFCCommand {
        switch self.type {
        case .libre1:
            return NFCCommand(code: 0xA0, parameters: backdoor, description: "activate")
        case .libreProH:
            return NFCCommand(code: 0xA0, parameters: backdoor + "4A454D573136382D5430323638365F23".bytes, description: "activate")
        case .libre2:
            return nfcCommand(.activate)
        default:
            return NFCCommand(code: 0x00)
        }
    }

    var universalCommand: NFCCommand    { NFCCommand(code: 0xA1, description: "A1 universal prefix") }
    var getPatchInfoCommand: NFCCommand { NFCCommand(code: 0xA1, description: "get patch info") }

    // Libre 1
    var lockCommand: NFCCommand         { NFCCommand(code: 0xA2, parameters: backdoor, description: "lock") }
    var readRawCommand: NFCCommand      { NFCCommand(code: 0xA3, parameters: backdoor, description: "read raw") }
    var unlockCommand: NFCCommand       { NFCCommand(code: 0xA4, parameters: backdoor, description: "unlock") }

    // Libre 2 / Pro
    // SEE: custom commands C0-C4 in TI RF430FRL15xH Firmware User's Guide
    var readBlockCommand: NFCCommand    { NFCCommand(code: 0xB0, description: "B0 read block") }
    var readBlocksCommand: NFCCommand   { NFCCommand(code: 0xB3, description: "B3 read blocks") }

    /// replies with error 0x12 (.contentCannotBeChanged)
    var writeBlockCommand: NFCCommand   { NFCCommand(code: 0xB1, description: "B1 write block") }

    /// replies with errors 0x12 (.contentCannotBeChanged) or 0x0f (.unknown)
    /// writing three blocks is not supported because it exceeds the 32-byte input buffer
    var writeBlocksCommand: NFCCommand  { NFCCommand(code: 0xB4, description: "B4 write blocks") }

    /// Usual 1252 blocks limit:
    /// block 04e3 => error 0x11 (.blockAlreadyLocked)
    /// block 04e4 => error 0x10 (.blockNotAvailable)
    var lockBlockCommand: NFCCommand   { NFCCommand(code: 0xB2, description: "B2 lock block") }


    enum Subcommand: UInt8, CustomStringConvertible {
        case unlock          = 0x1a    // lets read FRAM in clear and dump further blocks with B0/B3
        case activate        = 0x1b
        case enableStreaming = 0x1e
        case getSessionInfo  = 0x1f    // GEN_SECURITY_CMD_GET_SESSION_INFO
        case unknown0x10     = 0x10    // returns the number of parameters + 3
        case unknown0x1c     = 0x1c
        case unknown0x1d     = 0x1d    // disables Bluetooth
        // Gen2
        case readChallenge   = 0x20    // returns 25 bytes
        case readBlocks      = 0x21
        case readAttribute   = 0x22    // returns 6 bytes ([0]: sensor state)

        var description: String {
            switch self {
            case .unlock:          return "unlock"
            case .activate:        return "activate"
            case .enableStreaming: return "enable BLE streaming"
            case .getSessionInfo:  return "get session info"
            case .readChallenge:   return "read security challenge"
            case .readBlocks:      return "read FRAM blocks"
            case .readAttribute:   return "read patch attribute"
            default:               return "[unknown: 0x\(rawValue.hex)]"
            }
        }
    }


    /// The customRequestParameters for 0xA1 are built by appending
    /// code + parameters + usefulFunction(uid, code, secret)
    func nfcCommand(_ code: Subcommand, parameters: Data = Data(), secret: UInt16 = 0) -> NFCCommand {

        var parameters =  parameters
        let secret = secret != 0 ? secret : Libre2.secret

        if code.rawValue < 0x20 {
            parameters += Libre2.usefulFunction(id: uid, x: UInt16(code.rawValue), y: secret)
        }

        return NFCCommand(code: 0xA1, parameters: Data([code.rawValue]) + parameters, description: code.description)
    }
}


#if !os(watchOS)

import CoreNFC


enum IS015693Error: Int, CustomStringConvertible {
    case none                   = 0x00
    case commandNotSupported    = 0x01
    case commandNotRecognized   = 0x02
    case optionNotSupported     = 0x03
    case unknown                = 0x0f
    case blockNotAvailable      = 0x10
    case blockAlreadyLocked     = 0x11
    case contentCannotBeChanged = 0x12

    var description: String {
        switch self {
        case .none:                   return "none"
        case .commandNotSupported:    return "command not supported"
        case .commandNotRecognized:   return "command not recognized (e.g. format error)"
        case .optionNotSupported:     return "option not supported"
        case .unknown:                return "unknown"
        case .blockNotAvailable:      return "block not available (out of range, doesn’t exist)"
        case .blockAlreadyLocked:     return "block already locked -- can’t be locked again"
        case .contentCannotBeChanged: return "block locked -- content cannot be changed"
        }
    }
}


extension Error {
    var iso15693Code: Int {
        if let code = (self as NSError).userInfo[NFCISO15693TagResponseErrorKey] as? Int {
            return code
        } else {
            return 0
        }
    }
    var iso15693Description: String { IS015693Error(rawValue: self.iso15693Code)?.description ?? "[code: 0x\(self.iso15693Code.hex)]" }
}


enum TaskRequest {
    case enableStreaming
    case readFRAM
    case unlock
    case dump
    case reset
    case prolong
    case activate
}


class NFC: NSObject, NFCTagReaderSessionDelegate, Logging {

    var session: NFCTagReaderSession?
    var connectedTag: NFCISO15693Tag?
    var systemInfo: NFCISO15693SystemInfo!
    var sensor: Sensor!

    // Gen2
    var securityChallenge: Data = Data()
    var authContext: Int = 0
    var sessionInfo: Data = Data()

    var taskRequest: TaskRequest? {
        didSet {
            guard taskRequest != nil else { return }
            startSession()
        }
    }

    var main: MainDelegate!

    var isAvailable: Bool {
        return NFCTagReaderSession.readingAvailable
    }

    func startSession() {
        // execute in the .main queue because of publishing changes to main's observables
        session = NFCTagReaderSession(pollingOption: [.iso15693], delegate: self, queue: .main)
        session?.alertMessage = "Hold the top of your iPhone near the Libre sensor until the second longer vibration"
        session?.begin()
    }

    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        log("NFC: session did become active")
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        if let readerError = error as? NFCReaderError {
            if readerError.code != .readerSessionInvalidationErrorUserCanceled {
                session.invalidate(errorMessage: "Connection failure: \(readerError.localizedDescription)")
                log("NFC: \(readerError.localizedDescription)")
            }
        }
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        log("NFC: did detect tags")

        guard let firstTag = tags.first else { return }
        guard case .iso15693(let tag) = firstTag else { return }

        session.alertMessage = "Scan Complete"

        Task {

            do {
                try await session.connect(to: firstTag)
                connectedTag = tag
            } catch {
                log("NFC: \(error.localizedDescription)")
                session.invalidate(errorMessage: "Connection failure: \(error.localizedDescription)")
                return
            }

            var patchInfo: PatchInfo = Data()
            let retries = 5
            var requestedRetry = 0
            var failedToScan = false
            repeat {
                failedToScan = false
                if requestedRetry > 0 {
                    AudioServicesPlaySystemSound(1520)    // "pop" vibration
                    log("NFC: retry # \(requestedRetry)...")
                    // try await Task.sleep(nanoseconds: 250_000_000) not needed: too long
                }

                // Libre 3 workaround: calling A1 before tag.sytemInfo makes them work
                // The first reading prepends further 7 0xA5 dummy bytes

                do {
                    patchInfo = Data(try await tag.customCommand(requestFlags: .highDataRate, customCommandCode: 0xA1, customRequestParameters: Data()))
                } catch {
                    failedToScan = true
                }

                do {
                    systemInfo = try await tag.systemInfo(requestFlags: .highDataRate)
                    AudioServicesPlaySystemSound(1520)    // initial "pop" vibration
                } catch {
                    log("NFC: error while getting system info: \(error.localizedDescription)")
                    if requestedRetry > retries {
                        session.invalidate(errorMessage: "Error while getting system info: \(error.localizedDescription)")
                        return
                    }
                    failedToScan = true
                    requestedRetry += 1
                }

                do {
                    patchInfo = Data(try await tag.customCommand(requestFlags: .highDataRate, customCommandCode: 0xA1, customRequestParameters: Data()))
                } catch {
                    log("NFC: error while getting patch info: \(error.localizedDescription)")
                    if requestedRetry > retries && systemInfo != nil {
                        requestedRetry = 0 // break repeat
                    } else {
                        if !failedToScan {
                            failedToScan = true
                            requestedRetry += 1
                        }
                    }
                }

            } while failedToScan && requestedRetry > 0

            let uid = tag.identifier.hex
            log("NFC: IC identifier: \(uid)")

            let currentSensor = await main.app.sensor
            if currentSensor != nil && currentSensor!.uid == Data(tag.identifier.reversed()) {
                sensor = await main.app.sensor
            } else {
                let sensorType = SensorType(patchInfo: patchInfo)
                switch sensorType {
                case .libre2:
                    sensor = Libre2(main: main)
                case .libreProH:
                    sensor = LibrePro(main: main)
                default:
                    sensor = Sensor(main: main)
                }
                sensor.patchInfo = patchInfo
                DispatchQueue.main.async {
                    self.main.app.sensor = self.sensor
                }
            }

            // https://www.st.com/en/embedded-software/stsw-st25ios001.html#get-software

            var manufacturer = tag.icManufacturerCode.hex
            if manufacturer == "07" {
                manufacturer.append(" (Texas Instruments)")
            } else if manufacturer == "7a" {
                manufacturer.append(" (Abbott Diabetes Care)")
                sensor.type = .libre3
                sensor.securityGeneration = 3 // TODO
            }
            log("NFC: IC manufacturer code: 0x\(manufacturer)")
            debugLog("NFC: IC serial number: \(tag.icSerialNumber.hex)")

            var firmware = "RF430"
            switch tag.identifier[2] {
            case 0xA0: firmware += "TAL152H Libre 1 A0 "
            case 0xA4: firmware += "TAL160H Libre 2/Pro A4 "
            case 0x00: firmware = "unknown Libre 3 "
            default:   firmware += " unknown "
            }
            log("NFC: \(firmware)firmware")

            debugLog(String(format: "NFC: IC reference: 0x%X", systemInfo.icReference))
            if systemInfo.applicationFamilyIdentifier != -1 {
                debugLog(String(format: "NFC: application family id (AFI): %d", systemInfo.applicationFamilyIdentifier))
            }
            if systemInfo.dataStorageFormatIdentifier != -1 {
                debugLog(String(format: "NFC: data storage format id: %d", systemInfo.dataStorageFormatIdentifier))
            }

            log(String(format: "NFC: memory size: %d blocks", systemInfo.totalBlocks))
            log(String(format: "NFC: block size: %d", systemInfo.blockSize))

            sensor.uid = Data(tag.identifier.reversed())
            log("NFC: sensor uid: \(sensor.uid.hex)")

            if sensor.patchInfo.count > 0 {
                log("NFC: patch info: \(sensor.patchInfo.hex)")
                log("NFC: sensor type: \(sensor.type.rawValue)\(sensor.patchInfo.hex.hasPrefix("a2") ? " (new 'A2' kind)" : "")")
                log("NFC: sensor security generation [0-3]: \(sensor.securityGeneration)")

                DispatchQueue.main.async {
                    self.main.settings.patchUid = self.sensor.uid
                    self.main.settings.patchInfo = self.sensor.patchInfo
                }
            }

            log("NFC: sensor serial number: \(sensor.serial)")

            if taskRequest != .none {

                if sensor.securityGeneration > 1 {
                    await testGen2NFCCommands()
                }

                if sensor.type == .libre2 {
                    try await sensor.execute(nfc: self, taskRequest: taskRequest!)
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                }

                if taskRequest == .unlock ||
                    taskRequest == .dump ||
                    taskRequest == .reset ||
                    taskRequest == .prolong ||
                    taskRequest == .activate {

                    var invalidateMessage = ""

                    do {
                        try await execute(taskRequest!)
                    } catch let error as NFCError {
                        if error == .commandNotSupported {
                            let description = error.localizedDescription
                            invalidateMessage = description.prefix(1).uppercased() + description.dropFirst() + " by \(sensor.type)"
                        }
                    }

                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                    sensor.detailFRAM()

                    taskRequest = .none

                    if invalidateMessage.isEmpty {
                        session.invalidate()
                    } else {
                        session.invalidate(errorMessage: invalidateMessage)
                    }
                    return
                }

            }

            var blocks = sensor.type != .libreProH ? 43 : 22 + 24    // (32 * 6 / 8)
            if taskRequest == .readFRAM {
                if sensor.type == .libre1 {
                    blocks = 244
                }
            }

            do {

                if sensor.securityGeneration == 2 {

                    // TODO: use Gen2.communicateWithPatch(nfc: self)

                    // FIXME: OOP nfcAuth endpoint still offline

                    securityChallenge = try await send(sensor.nfcCommand(.readChallenge))
                    do {

                        // FIXME: "404 Not Found"
                        _ = try await main.post(OOPServer.gen2.nfcAuthEndpoint!, ["patchUid": sensor.uid.hex, "authData": securityChallenge.hex])

                        let oopResponse = try await main.post(OOPServer.gen2.nfcDataEndpoint!, ["patchUid": sensor.uid.hex, "authData": securityChallenge.hex]) as! OOPGen2Response
                        authContext = oopResponse.p1
                        let authenticatedCommand = Data(oopResponse.data.bytes)
                        log("OOP: context: \(authContext), authenticated `A1 1F get session info` command: \(authenticatedCommand.hex)")
                        var getSessionInfoCommand = sensor.nfcCommand(.getSessionInfo)
                        getSessionInfoCommand.parameters = authenticatedCommand.suffix(authenticatedCommand.count - 3)
                        sessionInfo = try! await send(getSessionInfoCommand)
                        // TODO: drop leading 0xA5s?
                        // sessionInfo = sessionInfo.suffix(sessionInfo.count - 8)
                        log("NFC: session info = \(sessionInfo.hex)")
                    } catch {
                        log("NFC: OOP error: \(error.localizedDescription)")
                    }
                }

                let (start, data) = try await sensor.securityGeneration < 2 ?
                read(fromBlock: 0, count: blocks) : readBlocks(from: 0, count: blocks)

                let lastReadingDate = Date()

                // "Publishing changes from background threads is not allowed"
                DispatchQueue.main.async {
                    self.main.app.lastReadingDate = lastReadingDate
                }
                sensor.lastReadingDate = lastReadingDate

                // TODO: test; convert history blocks to Libre 1 layout
                if sensor.type == .libreProH {
                    let historyIndex = Int(data[78]) + Int(data[79]) << 8
                    let startIndex = min(((historyIndex - 1) * 6) / 8 - 31, 0)
                    let offset = (8 - ((historyIndex - 1) * 6) % 8) % 8
                    let blockCount = min(historyIndex - 1, offset == 0 ? 24 : 25)
                    let (start, historyData) = try await readBlocks(from: 22 + startIndex + offset, count: blockCount)
                    log(historyData.hexDump(header: "NFC: did read \(historyData.count / 8) FRAM blocks:", startingBlock: start))
                    let history = Data(historyData[(offset * 8)...(offset + blockCount * 8)])
                    log(history.hexDump(header: "Libre Pro: 32 6-byte measuremets:", startingBlock: historyIndex))
                }

                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                session.invalidate()

                log(data.hexDump(header: "NFC: did read \(data.count / 8) FRAM blocks:", startingBlock: start))

                // FIXME: doesn't accept encrypted content
                if sensor.securityGeneration == 2 {
                    do {
                        _ = try await main.post(OOPServer.gen2.nfcDataAlgorithmEndpoint!, ["p1": authContext, "authData": sessionInfo.hex, "content": data.hex, "patchUid": sensor.uid.hex, "patchInfo": sensor.patchInfo.hex])
                    } catch {
                        log("NFC: OOP error: \(error.localizedDescription)")
                    }
                }

                sensor.fram = Data(data)

            } catch {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                session.invalidate(errorMessage: "\(error.localizedDescription)")
            }

            if taskRequest == .readFRAM {
                sensor.detailFRAM()
                taskRequest = .none
                return
            }

            await main.parseSensorData(sensor)

            await main.status("\(sensor.type)  +  NFC")

        }

    }


    @discardableResult
    func send(_ cmd: NFCCommand) async throws -> Data {
        var data = Data()
        do {
            debugLog("NFC: sending \(sensor.type) '\(cmd.code.hex) \(cmd.parameters.hex)' custom command\(cmd.description == "" ? "" : " (\(cmd.description))")")
            let output = try await connectedTag?.customCommand(requestFlags: .highDataRate, customCommandCode: cmd.code, customRequestParameters: cmd.parameters)
            data = Data(output!)
        } catch {
            log("NFC: \(sensor.type) '\(cmd.description) \(cmd.code.hex) \(cmd.parameters.hex)' custom command error: \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
            throw error
        }
        return data
    }


    func read(fromBlock start: Int, count blocks: Int, requesting: Int = 3, retries: Int = 5) async throws -> (Int, Data) {

        var buffer = Data()

        var remaining = blocks
        var requested = requesting
        var retry = 0

        while remaining > 0 && retry <= retries {

            let blockToRead = start + buffer.count / 8

            do {
                let dataArray = try await connectedTag?.readMultipleBlocks(requestFlags: .highDataRate, blockRange: NSRange(blockToRead ... blockToRead + requested - 1))

                for data in dataArray! {
                    buffer += data
                }

                remaining -= requested

                if remaining != 0 && remaining < requested {
                    requested = remaining
                }

            } catch {

                log("NFC: error while reading multiple blocks #\(blockToRead.hex) - #\((blockToRead + requested - 1).hex) (\(blockToRead)-\(blockToRead + requested - 1)): \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")

                retry += 1
                if retry <= retries {
                    AudioServicesPlaySystemSound(1520)    // "pop" vibration
                    log("NFC: retry # \(retry)...")
                    try await Task.sleep(nanoseconds: 250_000_000)

                } else {
                    if sensor.securityGeneration < 2 || taskRequest == .none {
                        session?.invalidate(errorMessage: "Error while reading multiple blocks: \(error.localizedDescription.localizedLowercase)")
                    }
                    throw NFCError.read
                }
            }
        }

        return (start, buffer)
    }


    func readBlocks(from start: Int, count blocks: Int, requesting: Int = 3) async throws -> (Int, Data) {

        if sensor.securityGeneration < 1 && sensor.type != .libreProH {
            debugLog("readBlocks() B3 command not supported by \(sensor.type)")
            throw NFCError.commandNotSupported
        }

        var buffer = Data()

        var remaining = blocks
        var requested = requesting

        while remaining > 0 {

            let blockToRead = start + buffer.count / 8

            var readCommand = NFCCommand(code: 0xB3, parameters: Data([UInt8(blockToRead & 0xFF), UInt8(blockToRead >> 8), UInt8(requested - 1)]))
            if requested == 1 {
                readCommand = NFCCommand(code: 0xB0, parameters: Data([UInt8(blockToRead & 0xFF), UInt8(blockToRead >> 8)]))
            }

            // FIXME: the Libre 3 replies to 'A1 21' with the error code C1

            if sensor.securityGeneration > 1 {
                if blockToRead <= 255 {
                    readCommand = sensor.nfcCommand(.readBlocks, parameters: Data([UInt8(blockToRead), UInt8(requested - 1)]))
                }
            }

            if buffer.count == 0 { debugLog("NFC: sending '\(readCommand.code.hex) \(readCommand.parameters.hex)' custom command (\(sensor.type) read blocks)") }

            do {
                let output = try await connectedTag?.customCommand(requestFlags: .highDataRate, customCommandCode: readCommand.code, customRequestParameters: readCommand.parameters)
                let data = Data(output!)

                if sensor.securityGeneration < 2 {
                    buffer += data
                } else {
                    debugLog("'\(readCommand.code.hex) \(readCommand.parameters.hex) \(readCommand.description)' command output (\(data.count) bytes): 0x\(data.hex)")
                    buffer += data.suffix(data.count - 8)    // skip leading 0xA5 dummy bytes
                }
                remaining -= requested

                if remaining != 0 && remaining < requested {
                    requested = remaining
                }

            } catch {

                log(buffer.hexDump(header: "\(sensor.securityGeneration > 1 ? "`A1 21`" : "B0/B3") command output (\(buffer.count/8) blocks):", startingBlock: start))

                if requested == 1 {
                    log("NFC: error while reading block #\(blockToRead.hex): \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
                } else {
                    log("NFC: error while reading multiple blocks #\(blockToRead.hex) - #\((blockToRead + requested - 1).hex) (\(blockToRead)-\(blockToRead + requested - 1)): \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
                }
                throw NFCError.readBlocks
            }
        }

        return (start, buffer)
    }


    // MARK: - Libre 1 only

    func readRaw(_ address: Int, _ bytes: Int) async throws -> (Int, Data) {

        if sensor.type != .libre1 {
            debugLog("readRaw() A3 command not supported by \(sensor.type)")
            throw NFCError.commandNotSupported
        }

        var buffer = Data()
        var remainingBytes = bytes

        while remainingBytes > 0 {

            let addressToRead = address + buffer.count
            let bytesToRead = min(remainingBytes, 24)

            var remainingWords = remainingBytes / 2
            if remainingBytes % 2 == 1 || ( remainingBytes % 2 == 0 && addressToRead % 2 == 1 ) { remainingWords += 1 }
            let wordsToRead = min(remainingWords, 12)   // real limit is 15

            let readRawCommand = NFCCommand(code: 0xA3, parameters: sensor.backdoor + [UInt8(addressToRead & 0xFF), UInt8(addressToRead >> 8), UInt8(wordsToRead)])

            if buffer.count == 0 { debugLog("NFC: sending '\(readRawCommand.code.hex) \(readRawCommand.parameters.hex)' custom command (\(sensor.type) read raw)") }

            do {
                let output = try await connectedTag?.customCommand(requestFlags: .highDataRate, customCommandCode: readRawCommand.code, customRequestParameters: readRawCommand.parameters)
                var data = Data(output!)

                if addressToRead % 2 == 1 { data = data.subdata(in: 1 ..< data.count) }
                if data.count - bytesToRead == 1 { data = data.subdata(in: 0 ..< data.count - 1) }

                buffer += data
                remainingBytes -= data.count

            } catch {
                debugLog("NFC: error while reading \(wordsToRead) words at raw memory 0x\(addressToRead.hex): \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
                throw NFCError.customCommandError
            }
        }

        return (address, buffer)

    }


    // Libre 1 only: overwrite mirrored FRAM blocks

    func writeRaw(_ address: Int, _ data: Data) async throws {

        if sensor.type != .libre1 {
            debugLog("FRAM overwriting not supported by \(sensor.type)")
            throw NFCError.commandNotSupported
        }

        do {

            try await send(sensor.unlockCommand)

            let addressToRead = (address / 8) * 8
            let startOffset = address % 8
            let endAddressToRead = ((address + data.count - 1) / 8) * 8 + 7
            let blocksToRead = (endAddressToRead - addressToRead) / 8 + 1

            let (readAddress, readData) = try await readRaw(addressToRead, blocksToRead * 8)
            var msg = readData.hexDump(header: "NFC: blocks to overwrite:", address: readAddress)
            var bytesToWrite = readData
            bytesToWrite.replaceSubrange(startOffset ..< startOffset + data.count, with: data)
            msg += "\(bytesToWrite.hexDump(header: "\nwith blocks:", address: addressToRead))"
            debugLog(msg)

            let startBlock = addressToRead / 8
            let blocks = bytesToWrite.count / 8

            if address >= 0xF860 {    // write to FRAM blocks

                let requestBlocks = 2    // 3 doesn't work

                let requests = Int(ceil(Double(blocks) / Double(requestBlocks)))
                let remainder = blocks % requestBlocks
                var blocksToWrite = [Data](repeating: Data(), count: blocks)

                for i in 0 ..< blocks {
                    blocksToWrite[i] = Data(bytesToWrite[i * 8 ... i * 8 + 7])
                }

                for i in 0 ..< requests {

                    let startIndex = startBlock - 0xF860 / 8 + i * requestBlocks
                    // TODO: simplify by using min()
                    let endIndex = startIndex + (i == requests - 1 ? (remainder == 0 ? requestBlocks : remainder) : requestBlocks) - (requestBlocks > 1 ? 1 : 0)
                    let blockRange = NSRange(startIndex ... endIndex)

                    var dataBlocks = [Data]()
                    for j in startIndex ... endIndex { dataBlocks.append(blocksToWrite[j - startIndex]) }

                    do {
                        try await connectedTag?.writeMultipleBlocks(requestFlags: .highDataRate, blockRange: blockRange, dataBlocks: dataBlocks)
                        debugLog("NFC: wrote blocks 0x\(startIndex.hex) - 0x\(endIndex.hex) \(dataBlocks.reduce("", { $0 + $1.hex })) at 0x\(((startBlock + i * requestBlocks) * 8).hex)")
                    } catch {
                        log("NFC: error while writing multiple blocks 0x\(startIndex.hex)-0x\(endIndex.hex) \(dataBlocks.reduce("", { $0 + $1.hex })) at 0x\(((startBlock + i * requestBlocks) * 8).hex): \(error.localizedDescription)")
                        throw NFCError.write
                    }
                }
            }

            try await send(sensor.lockCommand)

        } catch {

            // TODO: manage errors

            debugLog(error.localizedDescription)
        }

    }


    func write(fromBlock startBlock: Int, _ data: Data) async throws {
        var startIndex = startBlock
        let endBlock = startBlock + data.count / 8 - 1
        let requestBlocks = 2    // 3 doesn't work
        while startIndex <= endBlock {
            let endIndex = min(startIndex + requestBlocks - 1, endBlock)
            var dataBlocks = [Data]()
            for i in startIndex ... endIndex {
                dataBlocks.append(Data(data[(i - startBlock) * 8 ... (i - startBlock) * 8 + 7]))
            }
            let blockRange = NSRange(startIndex ... endIndex)
            do {
                try await connectedTag?.writeMultipleBlocks(requestFlags: .highDataRate, blockRange: blockRange, dataBlocks: dataBlocks)
                debugLog("NFC: wrote blocks 0x\(startIndex.hex) - 0x\(endIndex.hex) \(dataBlocks.reduce("", { $0 + $1.hex }))")
            } catch {
                log("NFC: error while writing multiple blocks 0x\(startIndex.hex)-0x\(endIndex.hex) \(dataBlocks.reduce("", { $0 + $1.hex }))")
                throw NFCError.write
            }
            startIndex = endIndex + 1
        }
    }

}

#endif    // !os(watchOS)
