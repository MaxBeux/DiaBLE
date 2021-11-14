import Foundation
import AVFoundation    // AudioServicesPlaySystemSound()

#if !os(watchOS)

import CoreNFC


// https://github.com/ivalkou/LibreTools/blob/master/Sources/LibreTools/NFC/NFCManager.swift

// https://fortinetweb.s3.amazonaws.com/fortiguard/research/techreport.pdf
// https://github.com/travisgoodspeed/goodtag/wiki/RF430TAL152H
// https://github.com/travisgoodspeed/GoodV/blob/master/app/src/main/java/com/kk4vcz/goodv/NfcRF430TAL.java
// https://github.com/cryptax/misc-code/blob/master/glucose-tools/readdump.py
// https://github.com/travisgoodspeed/goodtag/blob/master/firmware/gcmpatch.c
// https://github.com/captainbeeheart/openfreestyle/blob/master/docs/reverse.md


extension NFC {


    func execute(_ taskRequest: TaskRequest) async throws {

        switch taskRequest {


        case .dump:

            // Libre 1 memory layout:
            // config: 0x1A00, 64    (sensor UID and calibration info)
            // sram:   0x1C00, 512
            // rom:    0x4400 - 0x5FFF
            // fram lock table: 0xF840, 32
            // fram:   0xF860, 1952

            do {
                var (address, data) = try await readRaw(0x1A00, 64)
                log(data.hexDump(header: "Config RAM (patch UID at 0x1A08):", address: address))
                (address, data) = try await readRaw(0x1C00, 512)
                log(data.hexDump(header: "SRAM:", address: address))
                (address, data) = try await readRaw(0xFFAC, 36)
                log(data.hexDump(header: "Patch table for A0-A4 E0-E2 commands:", address: address))
                (address, data) = try await readRaw(0xF860, 43 * 8 + (sensor.type == .libre1 ? 201 * 8 : 0))
                log(data.hexDump(header: "FRAM:", address: address))
            } catch {}

            do {
                let (start, data) = try await read(fromBlock: 0, count: 43 + (sensor.type == .libre1 ? 201 : 0))
                log(data.hexDump(header: "ISO 15693 FRAM blocks:", startBlock: start))
                sensor.fram = Data(data)
                if sensor.encryptedFram.count > 0 && sensor.fram.count >= 344 {
                    log("\(sensor.fram.hexDump(header: "Decrypted FRAM:", startBlock: 0))")
                }
            } catch {
            }

            /// count is limited to 89 with an encrypted sensor (header as first 3 blocks);
            /// after sending the A1 1A subcommand the FRAM is decrypted in-place
            /// and mirrored in the last 43 blocks of 89 but the max count becomes 1252
            var count = sensor.encryptedFram.count > 0 ? 89 : 1252
            if sensor.securityGeneration > 1 { count = 43 }

            let command = sensor.securityGeneration > 1 ? "A1 21" : "B0/B3"

            do {

                let (start, data) = try await readBlocks(from: 0, count: count)

                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

                let blocks = data.count / 8

                log(data.hexDump(header: "\'\(command)' command output (\(blocks) blocks):", startBlock: start))

                // await main actor
                if await main.settings.debugLevel > 0 {
                    let bytes = min(89 * 8 + 34 + 10, data.count)
                    var offset = 0
                    var i = offset + 2
                    while offset < bytes - 3 && i < bytes - 1 {
                        if UInt16(data[offset ... offset + 1]) == data[offset + 2 ... i + 1].crc16 {
                            log("CRC matches for \(i - offset + 2) bytes at #\((offset / 8).hex) [\(offset + 2)...\(i + 1)] \(data[offset ... offset + 1].hex) = \(data[offset + 2 ... i + 1].crc16.hex)\n\(data[offset ... i + 1].hexDump(header: "\(libre2DumpMap[offset]?.1 ?? "[???]"):", address: 0))")
                            offset = i + 2
                            i = offset
                        }
                        i += 2
                    }
                }

            } catch {
                log("NFC: 'read blocks \(command)' command error: \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
            }


        case .reset:

            if sensor.type != .libre1 && sensor.type != .libreProH {
                log("E0 reset command not supported by \(sensor.type)")
                throw NFCError.commandNotSupported
            }

            switch sensor.type {


            case .libre1:

                let (commandsFramAddress, commmandsFram) = try await readRaw(0xF860 + 43 * 8, 195 * 8)

                let e0Offset = 0xFFB6 - commandsFramAddress
                let a1Offset = 0xFFC6 - commandsFramAddress
                let e0Address = UInt16(commmandsFram[e0Offset ... e0Offset + 1])
                let a1Address = UInt16(commmandsFram[a1Offset ... a1Offset + 1])

                debugLog("E0 and A1 commands' addresses: \(e0Address.hex) \(a1Address.hex) (should be fbae and f9ba)")

                let originalCRC = crc16(commmandsFram[2 ..< 195 * 8])
                debugLog("Commands section CRC: \(UInt16(commmandsFram[0...1]).hex), computed: \(originalCRC.hex) (should be 429e or f9ae for a Libre 1 A2)")

                var patchedFram = Data(commmandsFram)
                patchedFram[a1Offset ... a1Offset + 1] = e0Address.data
                let patchedCRC = crc16(patchedFram[2 ..< 195 * 8])
                patchedFram[0 ... 1] = patchedCRC.data

                debugLog("CRC after replacing the A1 command address with E0: \(patchedCRC.hex) (should be 6e01 or d531 for a Libre 1 A2)")

                do {
                    try await writeRaw(commandsFramAddress + a1Offset, e0Address.data)
                    try await writeRaw(commandsFramAddress, patchedCRC.data)
                    try await send(sensor.getPatchInfoCommand)
                    try await writeRaw(commandsFramAddress + a1Offset, a1Address.data)
                    try await writeRaw(commandsFramAddress, originalCRC.data)

                    let (start, data) = try await read(fromBlock: 0, count: 43)
                    log(data.hexDump(header: "NFC: did reset FRAM:", startBlock: start))
                    sensor.fram = Data(data)
                } catch {

                    // TODO: manage errors and verify integrity

                }


            case .libreProH:

                // TODO: use Libre Pro E0 instead of simply overwriting the FRAM with fresh values

                do {
                    try await send(sensor.unlockCommand)

                    // header
                    try await write(fromBlock: 0x00, Data([0x6A, 0xBC, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00]))
                    try await write(fromBlock: 0x01, Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
                    try await write(fromBlock: 0x02, Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
                    try await write(fromBlock: 0x03, Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
                    try await write(fromBlock: 0x04, Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))

                    // footer
                    try await write(fromBlock: 0x05, Data([0x99, 0xDD, 0x10, 0x00, 0x14, 0x08, 0xC0, 0x4E]))
                    try await write(fromBlock: 0x06, Data([0x14, 0x03, 0x96, 0x80, 0x5A, 0x00, 0xED, 0xA6]))
                    try await write(fromBlock: 0x07, Data([0x12, 0x56, 0xDA, 0xA0, 0x04, 0x0C, 0xD8, 0x66]))
                    try await write(fromBlock: 0x08, Data([0x29, 0x02, 0xC8, 0x18, 0x00, 0x00, 0x00, 0x00]))

                    // age, trend and history indexes
                    try await write(fromBlock: 0x09, Data([0xBD, 0xD1, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
                    // trend
                    for b in 0x0A ... 0x15 {
                        try await write(fromBlock: b, Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
                    }

                    // duplicated in activation
                    var readCommand = sensor.readBlockCommand
                    readCommand.parameters = "DF 04".bytes
                    var output = try await send(readCommand)
                    debugLog("NFC: 'B0 read 0x04DF' command output: \(output.hex)")
                    var writeCommand = sensor.writeBlockCommand
                    writeCommand.parameters = "DF 04 20 00 DF 88 00 00 00 00".bytes
                    output = try await send(writeCommand)
                    debugLog("NFC: 'B1 write' command output: \(output.hex)")
                    output = try await send(readCommand)
                    debugLog("NFC: 'B0 read 0x04DF' command output: \(output.hex)")

                    try await send(sensor.lockCommand)

                } catch {

                    // TODO: manage errors and verify integrity

                }


            default:
                break

            }


        case .prolong:

            if sensor.type != .libre1 {
                log("FRAM overwriting not supported by \(sensor.type)")
                throw NFCError.commandNotSupported
            }

            let (footerAddress, footerFram) = try await readRaw(0xF860 + 40 * 8, 3 * 8)

            let maxLifeOffset = 6
            let maxLife = Int(footerFram[maxLifeOffset]) + Int(footerFram[maxLifeOffset + 1]) << 8
            log("\(sensor.type) current maximum life: \(maxLife) minutes (\(maxLife.formattedInterval))")

            var patchedFram = Data(footerFram)
            patchedFram[maxLifeOffset ... maxLifeOffset + 1] = Data([0xFF, 0xFF])
            let patchedCRC = crc16(patchedFram[2 ..< 3 * 8])
            patchedFram[0 ... 1] = patchedCRC.data

            do {
                try await writeRaw(footerAddress + maxLifeOffset, patchedFram[maxLifeOffset ... maxLifeOffset + 1])
                try await writeRaw(footerAddress, patchedCRC.data)

                let (_, data) = try await read(fromBlock: 0, count: 43)
                log(Data(data.suffix(3 * 8)).hexDump(header: "NFC: did overwite FRAM footer:", startBlock: 40))
                sensor.fram = Data(data)
            } catch {

                // TODO: manage errors and verify integrity

            }


        case .unlock:

            if sensor.securityGeneration < 1 {
                log("'A1 1A unlock' command not supported by \(sensor.type)")
                throw NFCError.commandNotSupported
            }

            do {
                let output = try await send(sensor.unlockCommand)

                // Libre 2
                if output.count == 0 {
                    log("NFC: FRAM should have been decrypted in-place")
                }

            } catch {

                // TODO: manage errors and verify integrity

            }

            let (_, data) = try await read(fromBlock: 0, count: 43)
            sensor.fram = Data(data)


        case .activate:

            if sensor.securityGeneration > 1 {
                log("Activating a \(sensor.type) is not supported")
                throw NFCError.commandNotSupported
            }

            do {
                if await sensor.main.settings.debugLevel > 0 {
                    await sensor.testOOPActivation()
                }


                if sensor.type == .libreProH {
                    var readCommand = sensor.readBlockCommand
                    readCommand.parameters = "DF 04".bytes
                    var output = try await send(readCommand)
                    debugLog("NFC: 'B0 read 0x04DF' command output: \(output.hex)")
                    try await send(sensor.unlockCommand)
                    var writeCommand = sensor.writeBlockCommand
                    writeCommand.parameters = "DF 04 20 00 DF 88 00 00 00 00".bytes
                    output = try await send(writeCommand)
                    debugLog("NFC: 'B1 write' command output: \(output.hex)")
                    try await send(sensor.lockCommand)
                    output = try await send(readCommand)
                    debugLog("NFC: 'B0 read 0x04DF' command output: \(output.hex)")
                }

                let output = try await send(sensor.activationCommand)
                log("NFC: after trying to activate received \(output.hex) for the patch info \(sensor.patchInfo.hex)")

                // Libre 2
                if output.count == 4 {
                    // receiving 9d081000 for a patchInfo 9d0830010000
                    log("NFC: \(sensor.type) should be activated and warming up")
                }

            } catch {

                // TODO: manage errors and verify integrity

            }

            let (_, data) = try await read(fromBlock: 0, count: 43)
            sensor.fram = Data(data)


        default:
            break

        }

    }

}

#endif    // !os(watchOS)
