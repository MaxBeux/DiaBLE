import Foundation

#if !os(watchOS)
import CoreNFC
#endif


class Gen2 {

    static let GEN_SECURITY_CMD_GET_SESSION_INFO      =  0x1f

    static let GEN2_CMD_DECRYPT_BLE_DATA              =   773
    static let GEN2_CMD_DECRYPT_NFC_DATA              = 12545
    static let GEN2_CMD_DECRYPT_NFC_STREAM            =  6520
    static let GEN2_CMD_END_SESSION                   = 37400
    static let GEN2_CMD_GET_AUTH_CONTEXT              = 28960
    static let GEN2_CMD_GET_BLE_AUTHENTICATED_CMD     =  6505
    static let GEN2_CMD_GET_CREATE_SESSION            = 29465
    static let GEN2_CMD_GET_NFC_AUTHENTICATED_CMD     =  6440
    static let GEN2_CMD_GET_PVALUES                   =  6145
    static let GEN2_CMD_INIT_LIB                      =     0
    static let GEN2_CMD_PERFORM_SENSOR_CONTEXT_CRYPTO = 18712
    static let GEN2_CMD_VERIFY_RESPONSE               = 22321


    enum Gen2Error: Int, Error, CaseIterable {
        case GEN2_SEC_ERROR_INIT            = -1
        case GEN2_SEC_ERROR_CMD             = -2
        case GEN2_SEC_ERROR_KDF             = -9
        case GEN2_SEC_ERROR_RESPONSE_SIZE   = -10
        case GEN2_ERROR_AUTH_CONTEXT        = -11
        case GEN2_ERROR_PRNG_ERROR          = -12
        case GEN2_ERROR_KEY_NOT_FOUND       = -13
        case GEN2_ERROR_SKB_ERROR           = -14
        case GEN2_ERROR_INVALID_RESPONSE    = -15
        case GEN2_ERROR_INSUFFICIENT_BUFFER = -16
        case GEN2_ERROR_CRC_MISMATCH        = -17
        case GEN2_ERROR_MISSING_NATIVE      = -98
        case GEN2_ERROR_PROCESS_ERROR       = -99

        init(value: Int) {
            for error in Gen2Error.allCases {
                if value == error.rawValue {
                    self = error
                    return
                }
            }
            self = .GEN2_ERROR_MISSING_NATIVE
        }

        var ordinal: Int {
            switch self {
            case .GEN2_ERROR_AUTH_CONTEXT:        return 1
            case .GEN2_ERROR_KEY_NOT_FOUND:       return 2
            case .GEN2_SEC_ERROR_INIT:            return 3
            case .GEN2_SEC_ERROR_CMD:             return 4
            case .GEN2_SEC_ERROR_RESPONSE_SIZE:   return 5
            case .GEN2_ERROR_INSUFFICIENT_BUFFER: return 6
            case .GEN2_ERROR_MISSING_NATIVE:      return 7
            case .GEN2_SEC_ERROR_KDF:             return 8
            case .GEN2_ERROR_PRNG_ERROR:          return 9
            case .GEN2_ERROR_CRC_MISMATCH:        return 10
            case .GEN2_ERROR_SKB_ERROR:           return 11
            case .GEN2_ERROR_INVALID_RESPONSE:    return 12
            case .GEN2_ERROR_PROCESS_ERROR:       return 13
            }
        }

    }

    struct Result {
        let data: Data?
        let error: Gen2Error?
    }


    static func p1(command: Int, _ i2: Int, _ d1: Data?, _ d2: Data?) -> Int {
        return 0
    }

    static func p2(command: Int, p1: Int, _ d1: Data, _ d2: Data?) -> Result {
        return Result(data: Data(), error: nil)
    }


    static func createSecureSession(context: Int, _ i2: Int, data: Data) -> Int {
        return p1(command: GEN2_CMD_GET_CREATE_SESSION, context, Data([UInt8(i2)]), data)
    }

    static func endSession(context: Int) -> Int {
        return p1(command: GEN2_CMD_END_SESSION, context, nil, nil)
    }

    static func getNfcAuthenticatedCommandBLE(command: Int, uid: SensorUid, challenge: Data, output: inout Data) -> Int {
        let authContext = p1(command: GEN2_CMD_GET_AUTH_CONTEXT, 0, uid, nil)
        if authContext < 0 {
            return authContext
        }
        let commandArg = Data([1, UInt8(command)])
        let result = p2(command: GEN2_CMD_GET_BLE_AUTHENTICATED_CMD, p1: authContext, commandArg, challenge)
        if result.data == nil {
            _ = Gen2.endSession(context: authContext)
            return result.error != nil ? result.error!.rawValue : Gen2Error.GEN2_ERROR_PROCESS_ERROR.rawValue
        }
        output = result.data!
        return authContext
    }

    static func getNfcAuthenticatedCommandNfc(command: Int, uid: SensorUid, challenge: Data, output: inout Data) -> Int {
        let authContext = p1(command: GEN2_CMD_GET_AUTH_CONTEXT, 0, uid, nil)
        if authContext < 0 {
            return authContext
        }
        let commandArg = Data([0, UInt8(command)])
        let result = p2(command: GEN2_CMD_GET_NFC_AUTHENTICATED_CMD, p1: authContext, commandArg, challenge)
        if result.data == nil {
            _ = Gen2.endSession(context: authContext)
            return result.error != nil ? result.error!.rawValue : Gen2Error.GEN2_ERROR_PROCESS_ERROR.rawValue
        }
        output = result.data!
        output[0 ... 3] = Data([2, 0xA1, 7, UInt8(command)])
        return authContext
    }


#if !os(watchOS)

    static func getAuthenticatedCommand(nfc: NFC, command: Int, output: inout Data) async throws -> Int {
        let challenge = try await nfc.send(nfc.sensor.nfcCommand(.readChallenge))
        if challenge.count == 0 {
            return -1
        }
        return getNfcAuthenticatedCommandNfc(command: command, uid: nfc.sensor.uid, challenge: challenge, output: &output)
    }

    static func communicateWithPatch(nfc: NFC) async throws -> Int {
        var getSessionInfoCommand = nfc.sensor.nfcCommand(.getSessionInfo)
        var commandData = Data()
        let context = try await getAuthenticatedCommand(nfc: nfc, command: Int(Sensor.Subcommand.getSessionInfo.rawValue), output: &commandData)
        if context < 0 {
            nfc.log("NFC: scan error - failed to build authenticated command [context: \(context)]")
        }
        getSessionInfoCommand.parameters = commandData.suffix(commandData.count - 3)  // drop [02 A1 07]
        do {
            let sessionInfo = try await nfc.send(getSessionInfoCommand)
            let errorContext = createSecureSession(context: context, 0, data: sessionInfo)
            if errorContext < 0 {
                nfc.log("NFC: failed session creation due to error \(errorContext)")
            }

            // TODO: detect errors and close session

        } catch {
            nfc.debugLog("Scan error - authenticated command failed")
            if context > 0 {
                _ = endSession(context: context)
            }
        }

        return context
    }

#endif


    static func decrytpNfcData(context: Int, fromBlock: Int, count: Int, data: Data) -> Result {
        return p2(command: GEN2_CMD_DECRYPT_NFC_STREAM, p1: context, Data([UInt8(fromBlock), UInt8(count)]), data)
    }

    static func streamingContext(uid: SensorUid, challenge: Data, output: inout Data) -> Int {
        return getNfcAuthenticatedCommandBLE(command: GEN_SECURITY_CMD_GET_SESSION_INFO, uid: uid, challenge: challenge, output: &output)
    }

    static func decryptStreamingData(context: Int, data: Data) -> Result {
        return p2(command: GEN2_CMD_DECRYPT_BLE_DATA, p1: context, data, nil)
    }

    static func verifyCommandResponse(context: Int, _ i2: Int, challenge: Data, output: inout Data) -> Int {
        let commandArg = Data([UInt8(i2), UInt8(output.count)])
        let result = p2(command: GEN2_CMD_VERIFY_RESPONSE, p1: context, commandArg, challenge)
        if result.data == nil {
            _ = Gen2.endSession(context: context)
            return result.error != nil ? result.error!.rawValue : Gen2Error.GEN2_ERROR_PROCESS_ERROR.rawValue
        }
        output = result.data!
        return output.count
    }


    static func verifyEnableStreamingResponse(context: Int, challenge: Data, authenticationData: inout Data, output: inout Data) -> Int {
        var verifyOutput = Data(count: 9)
        let verify = verifyCommandResponse(context: context, 0, challenge: challenge, output: &verifyOutput)
        if verify < 0 {
            return verify
        }
        let commandArg = Data([7])
        let result = p2(command: GEN2_CMD_GET_PVALUES, p1: context, commandArg, nil)
        if result.data == nil {
            _ = Gen2.endSession(context: context)
            return result.error != nil ? result.error!.rawValue : Gen2Error.GEN2_ERROR_PROCESS_ERROR.rawValue
        }
        // join the 7 bytes of GET_PVALUES result.data and the last 3 bytes of 9 of verifyOutput
        authenticationData[0 ..< result.data!.count] = result.data!
        authenticationData[result.data!.count ..< result.data!.count + 3] = verifyOutput[6 ... 8]
        // copy the first 6 bytes of 9 of verifyOutput in the second array `output` passed by reference
        output[0 ..< 6] = Data(verifyOutput.prefix(6))
        return 0
    }

}


// MARK: - test Gen2 / Libre 3 NFC A0...DF commands

#if !os(watchOS)

extension NFC {

    func testGen2NFCCommands() async {

        var commands: [NFCCommand] = [sensor.nfcCommand(.readAttribute),
                                      sensor.nfcCommand(.readChallenge)
        ]

        if await main.settings.debugLevel > 0 {

            for c in 0xA0 ... 0xDF {
                commands.append(NFCCommand(code: c, description: c.hex))
            }

            // Gen2 supported commands: A1, B1, B2, B4

            // Libre 3:
            // getting 28 bytes from A1: a5 00 01 00 01 00 00 00 c0 4e 1e 0f 00 01 04 0c 01 30 34 34 5a 41 38 43 4c 36 79 38
            // getting 0xC1 error from A0, A1 20-22, A8, A9, C8, C9
            // getting 64 0xA5 bytes from A2-A7, AB-C7, CA-DF
            // getting 22 bytes from AA: 44 4f 43 34 32 37 31 35 2d 31 30 31 11 26 20 12 09 00 80 67 73 e0
            // getting zeros from standard read command 0x23
        }
        for cmd in commands {
            log("NFC: sending \(sensor.type) '\(cmd.description)' command: code: 0x\(cmd.code.hex), parameters: 0x\(cmd.parameters.hex)")
            do {
                let output = try await connectedTag!.customCommand(requestFlags: .highDataRate, customCommandCode: cmd.code, customRequestParameters: cmd.parameters)
                log("NFC: '\(cmd.description)' command output (\(output.count) bytes): 0x\(output.hex)")
                if output.count == 6 { // .readAttribute
                    let state = SensorState(rawValue: output[0]) ?? .unknown
                    sensor.state = state
                    log("\(sensor.type) state: \(state.description.lowercased()) (0x\(state.rawValue.hex))")
                }
            } catch {
                log("NFC: '\(cmd.description)' command error: \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
            }
        }
    }

}

#endif
