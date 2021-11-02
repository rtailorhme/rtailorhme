import Foundation


// https://fortinetweb.s3.amazonaws.com/fortiguard/research/techreport.pdf
// https://github.com/travisgoodspeed/goodtag/wiki/RF430TAL152H
// https://github.com/travisgoodspeed/GoodV/blob/master/app/src/main/java/com/kk4vcz/goodv/NfcRF430TAL.java
// https://github.com/cryptax/misc-code/blob/master/glucose-tools/readdump.py
// https://github.com/travisgoodspeed/goodtag/blob/master/firmware/gcmpatch.c
// https://github.com/captainbeeheart/openfreestyle/blob/master/docs/reverse.md


struct NFCCommand {
    let code: UInt8
    let parameters: Data
}

extension SensorType {
    var backdoor: [UInt8] {
        switch self {
        case .libre1:    return "c2ad7521".bytes
        case .libreProH: return "c2ad0090".bytes
        default:         return "deadbeef".bytes
        }
    }
}

extension Sensor {

    var activationCommand: NFCCommand {
        switch self.type {
        case .libre1:    return NFCCommand(code: 0xA0, parameters: Data(SensorType.libre1.backdoor))
        case .libreProH: return NFCCommand(code: 0xA0, parameters: Data(SensorType.libreProH.backdoor))
        case .libre2:    return nfcCommand(.activate)
        default:         return NFCCommand(code: 0x00, parameters: Data())
        }
    }

    enum Subcommand: UInt8, CustomStringConvertible {
        case activate        = 0x1b
        case enableStreaming = 0x1e
        case unknown0x1a     = 0x1a
        case unknown0x1c     = 0x1c
        case unknown0x1d     = 0x1d
        case unknown0x1f     = 0x1f


        var description: String {
            switch self {
            case .activate:        return "activate"
            case .enableStreaming: return "enable BLE streaming"
            default:               return "[unknown: 0x\(String(format: "%x", rawValue))]"
            }
        }
    }


    /// The customRequestParameters for 0xA1 are built by appending
    /// code + params (b) + usefulFunction(uid, code, secret (y))
    ///
    /// 0x1a [] 0x1b6a
    ///
    /// 0x1b [] 0x1b6a: activate
    ///
    /// 0x1c [] 0x1b6a
    ///
    /// 0x1d [] 0x1b6a
    ///
    /// 0x1e [params]: enable Bluetooth streaming
    ///
    /// 0x1f
    func nfcCommand(_ code: Subcommand) -> NFCCommand {

        var b: [UInt8] = []
        var y: UInt16

        if code == .enableStreaming {

            // Enables Bluetooth on Libre 2. Returns peripheral MAC address to connect to.
            // unlockCode could be any 32 bit value. The unlockCode and sensor Uid / patchInfo
            // will have also to be provided to the login function when connecting to peripheral.

            b = [
                UInt8(unlockCode & 0xFF),
                UInt8((unlockCode >> 8) & 0xFF),
                UInt8((unlockCode >> 16) & 0xFF),
                UInt8((unlockCode >> 24) & 0xFF)
            ]
            y = UInt16(patchInfo[4...5]) ^ UInt16(b[1], b[0])

        } else {
            y = 0x1b6a
        }

        let d = Libre2.usefulFunction(id: uid, x: UInt16(code.rawValue), y: y)

        var parameters = Data([code.rawValue])

        if code == .enableStreaming {
            parameters += b
        }

        parameters += d

        return NFCCommand(code: 0xA1, parameters: parameters)
    }
}


#if !os(watchOS)

import CoreNFC


// https://github.com/ivalkou/LibreTools/blob/master/Sources/LibreTools/NFC/NFCManager.swift


// TODO: reimplement using Combine

class NFCReader: NSObject, NFCTagReaderSessionDelegate {

    var tagSession: NFCTagReaderSession?
    var connectedTag: NFCISO15693Tag?
    var sensor: Sensor!
    @Published var currentSenserState: SensorState = SensorState.unknown

    /// Main app delegate to use its log()
    var main: CGMManager!

    var isNFCAvailable: Bool {
        return NFCTagReaderSession.readingAvailable
    }

    func startSession() {
        // execute in the .main queue because of publishing changes to main's observables
        tagSession = NFCTagReaderSession(pollingOption: [.iso15693], delegate: self, queue: .main)
        tagSession?.alertMessage = "Hold the top of your iPhone near the Libre sensor"
        tagSession?.begin()
    }

    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        debugPrint("NFC: session did become active")
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        if let readerError = error as? NFCReaderError {
            if readerError.code != .readerSessionInvalidationErrorUserCanceled {
                debugPrint("NFC: \(readerError.localizedDescription)")
                session.invalidate(errorMessage: "Connection failure: \(readerError.localizedDescription)")
            }
        }
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        debugPrint("NFC: did detect tags")

        guard let firstTag = tags.first else { return } // OS Sends tags in list
        guard case .iso15693(let tag) = firstTag else { return } // Check if first tag is indeed an iso15693 tag, if not return

        session.alertMessage = "Scan Complete"

        let blocks = 43
        let requestBlocks = 3

        let requests = Int(ceil(Double(blocks) / Double(requestBlocks)))
        let remainder = blocks % requestBlocks
        var dataArray = [Data](repeating: Data(), count: blocks)

        session.connect(to: firstTag) { error in
            if error != nil {
                debugPrint("NFC: \(error!.localizedDescription)")
                session.invalidate(errorMessage: "Connection failure: \(error!.localizedDescription)")
                return
            }
            self.connectedTag = tag

            // https://www.st.com/en/embedded-software/stsw-st25ios001.html#get-software

            #if !targetEnvironment(macCatalyst)    // the new getSystemInfo doesn't compile in iOS 14 beta

            self.connectedTag?.getSystemInfo(requestFlags: [.address, .highDataRate]) { result in

                switch result {

                case .failure(let error):
                    session.invalidate(errorMessage: "Error while getting system info: " + error.localizedDescription)
                    debugPrint("NFC: error while getting system info: \(error.localizedDescription)")
                    return

                case .success(let systemInfo):

                    self.connectedTag?.customCommand(requestFlags: [.highDataRate], customCommandCode: 0xA1, customRequestParameters: Data()) { (customResponse: Data, error: Error?) in
                        if error != nil {
                            // session.invalidate(errorMessage: "Error while getting patch info: " + error!.localizedDescription)
                            debugPrint("NFC: error while getting patch info: \(error!.localizedDescription)")
                        }

                        for i in 0..<requests {

                            self.connectedTag?.readMultipleBlocks(requestFlags: [.highDataRate, .address],
                                    blockRange: NSRange(UInt8(i * requestBlocks)...UInt8(i * requestBlocks + (i == requests - 1 ? (remainder == 0 ? requestBlocks : remainder) : requestBlocks) - (requestBlocks > 1 ? 1 : 0)))
                            ) { blockArray, error in

                                if error != nil {
                                    debugPrint("NFC: error while reading multiple blocks (#\(i * requestBlocks) - #\(i * requestBlocks + (i == requests - 1 ? (remainder == 0 ? requestBlocks : remainder) : requestBlocks) - (requestBlocks > 1 ? 1 : 0))): \(error!.localizedDescription)")
                                    session.invalidate(errorMessage: "Error while reading multiple blocks: \(error!.localizedDescription)")
                                    if i != requests - 1 {
                                        return
                                    }

                                } else {
                                    for j in 0..<blockArray.count {
                                        dataArray[i * requestBlocks + j] = blockArray[j]
                                    }
                                }


                                if i == requests - 1 {

                                    if self.main.settings.debugLevel == 0 {
                                        session.invalidate()
                                    }

                                    if self.main.app.sensor != nil {
                                        self.sensor = self.main.app.sensor
                                    } else {
                                        self.sensor = Sensor()
                                        self.main.app.sensor = self.sensor
                                    }

                                    var fram = Data()

                                    self.main.app.lastReadingDate = Date()
                                    self.sensor.lastReadingDate = self.main.app.lastReadingDate

                                    var msg = ""
                                    for (n, data) in dataArray.enumerated() {
                                        if data.count > 0 {
                                            fram.append(data)
                                            msg += "NFC: block #\(String(format: "%02d", n))  \(data.reduce("", { $0 + String(format: "%02X", $1) + " " }).dropLast())\n"
                                        }
                                    }
                                    if !msg.isEmpty {
                                        debugPrint(String(msg.dropLast()))
                                    }

                                    let uid = self.connectedTag!.identifier.hex
                                    debugPrint("NFC: IC identifier: \(uid)")

                                    var manufacturer = String(tag.icManufacturerCode)
                                    if manufacturer == "7" {
                                        manufacturer.append(" (Texas Instruments)")
                                    }
                                    debugPrint("NFC: IC manufacturer code: \(manufacturer)")
                                    debugPrint("NFC: IC serial number: \(tag.icSerialNumber.hex)")

                                    var rom = "RF430"
                                    switch self.connectedTag?.identifier[2] {
                                    case 0xA0: rom += "TAL152H Libre 1 A0"
                                    case 0xA4: rom += "TAL160H Libre 2 A4"
                                    default:   rom += " unknown"
                                    }
                                    debugPrint("NFC: \(rom) ROM")

                                    debugPrint(String(format: "NFC: IC reference: 0x%X", systemInfo.icReference))
                                    if systemInfo.applicationFamilyIdentifier != -1 {
                                        debugPrint(String(format: "NFC: application family id (AFI): %d", systemInfo.applicationFamilyIdentifier))
                                    }
                                    if systemInfo.dataStorageFormatIdentifier != -1 {
                                        debugPrint(String(format: "NFC: data storage format id: %d", systemInfo.dataStorageFormatIdentifier))
                                    }

                                    debugPrint(String(format: "NFC: memory size: %d blocks", systemInfo.totalBlocks))
                                    debugPrint(String(format: "NFC: block size: %d", systemInfo.blockSize))

                                    self.sensor.uid = Data(tag.identifier.reversed())
                                    debugPrint("NFC: sensor uid: \(self.sensor.uid.hex)")
                                    debugPrint("NFC: sensor serial number: \(self.sensor.serial)")

                                    let patchInfo = customResponse
                                    self.sensor.patchInfo = Data(patchInfo)
                                    if customResponse.count > 0 {
                                        debugPrint("NFC: patch info: \(patchInfo.hex)")
                                        debugPrint("NFC: sensor type: \(self.sensor.type.rawValue)")

                                        self.main.settings.patchUid = self.sensor.uid
                                        self.main.settings.patchInfo = self.sensor.patchInfo
                                    }

                                    debugPrint("\(self.sensor.type)  +  NFC")

                                    if self.main.settings.debugLevel > 0 {
                                        let msg = "NFC: dump of "
                                        self.readRaw(0xF860, 43 * 8) {
                                            debugPrint(msg + ($2?.localizedDescription ?? $1.hexDump(address: Int($0), header: "FRAM:")))
                                            self.readRaw(0x1A00, 64) {
                                                debugPrint(msg + ($2?.localizedDescription ?? $1.hexDump(address: Int($0), header: "config RAM\n(patchUid at 0x1A08):")))
                                                self.readRaw(0xFFAC, 36) {
                                                    debugPrint(msg + ($2?.localizedDescription ?? $1.hexDump(address: Int($0), header: "patch table for A0-A4 E0-E2 commands:")))
                                                    // self.writeRaw(0xFFB8, Data([0xE0, 0x00])) { // to restore: Data([0xAB, 0xAB]))
                                                    // TODO: overwrite commands CRC
                                                    // debugPrint("NFC: did write at address: 0x\(String(format: "%04X", $0)), bytes: 0x\($1.hex), error: \($2?.localizedDescription ?? "none")")

                                                    if self.sensor.type == .libre2 {
                                                        // let subCmd:Sensor.Subcommand = .unknown0x1a // TEST
                                                        var subCmd: Sensor.Subcommand = .activate
                                                        var currentUnlockCode = self.sensor.unlockCode
                                                        self.sensor.unlockCode = UInt32(self.main.settings.activeSensorUnlockCode)
                                                        var cmd = self.sensor.nfcCommand(subCmd)
                                                        debugPrint("NFC: sending \(self.sensor.type) command to \(subCmd.description): code: 0x\(String(format: "%0X", cmd.code)), parameters: 0x\(cmd.parameters.hex) (unlock code: \(self.sensor.unlockCode))")
                                                        self.sendBLEAndActivateCommandToSensor(cmd: cmd, subCmd: subCmd, currentUnlockCode: currentUnlockCode, patchInfo: patchInfo, session: session)

                                                        subCmd = .enableStreaming
                                                        currentUnlockCode = self.sensor.unlockCode
                                                        self.sensor.unlockCode = UInt32(self.main.settings.activeSensorUnlockCode)
                                                        cmd = self.sensor.nfcCommand(subCmd)
                                                        debugPrint("NFC: sending \(self.sensor.type) command to \(subCmd.description): code: 0x\(String(format: "%0X", cmd.code)), parameters: 0x\(cmd.parameters.hex) (unlock code: \(self.sensor.unlockCode))")
                                                        self.sendBLEAndActivateCommandToSensor(cmd: cmd, subCmd: subCmd, currentUnlockCode: currentUnlockCode, patchInfo: patchInfo, session: session)
                                                    } else {

                                                        session.invalidate()

                                                    }

                                                    // same final code as for debugLevel = 0

                                                    if fram.count > 0 {
                                                        self.sensor.fram = Data(fram)
                                                    }
                                                    self.main.parseSensorData(self.sensor)
                                                    // } // TEST writeRaw
                                                }
                                            }
                                        }
                                    } else {

                                        // same final code as for debugLevel > 0

                                        if fram.count > 0 {
                                            self.sensor.fram = Data(fram)
                                        }
                                        self.main.parseSensorData(self.sensor)
                                    }
                                    self.currentSenserState = self.sensor.state
                                }
                            }
                        }
                    }


//                    let cmdT = self.sensor.nfcCommand(.activate)
//
//                    self.connectedTag?.customCommand(requestFlags: [.highDataRate], customCommandCode: Int(cmdT.code), customRequestParameters: cmdT.parameters) {(customResponse: Data, error: Error?) in
//                        if error != nil {
//                            debugPrint("NFC Failed IDK why don't ask me", error)
//                        }
//
//                        debugPrint("NFC Succeded maybe?")
//                        debugPrint(customResponse.string)
//
//                    }

                }
            }

            #endif
        }
        debugPrint("done")
    }

    private func sendBLEAndActivateCommandToSensor(cmd: NFCCommand, subCmd: Sensor.Subcommand, currentUnlockCode: UInt32, patchInfo: Data, session: NFCTagReaderSession) -> ()? {
        self.connectedTag?.customCommand(requestFlags: [.highDataRate], customCommandCode: Int(cmd.code), customRequestParameters: cmd.parameters) { (customResponse: Data, error: Error?) in
            debugPrint("NFC: '\(subCmd.description)' command response (\(customResponse.count) bytes): 0x\(customResponse.hex), error: \(error?.localizedDescription ?? "none")")
            if subCmd == .enableStreaming && customResponse.count == 6 {
                debugPrint("NFC: enabled BLE streaming on \(self.sensor.type) \(self.sensor.serial) (unlock code: \(self.sensor.unlockCode), MAC address: \(Data(customResponse.reversed()).hexAddress))")
                self.main.settings.activeSensorSerial = self.sensor.serial
                self.main.settings.patchInfo = self.sensor.patchInfo
                self.main.settings.activeSensorAddress = Data(customResponse.reversed())
                self.sensor.unlockCount = 0
                self.main.settings.activeSensorUnlockCount = 0
                self.main.settings.activeSensorCalibrationInfo = self.sensor.calibrationInfo
            } else {
                self.sensor.unlockCode = currentUnlockCode
            }
//                                                            if subCmd == .activate && customResponse.count == 4 {
            if subCmd == .activate {
                debugPrint("NFC: after trying activating received \(customResponse.hex) for the patch info \(patchInfo.hex)")
                // receiving 9d081000 for a patchInfo 9d0830010000 but state remaining .notActivated
                // TODO

//                                                                cmd = self.sensor.nfcCommand(subCmd)

//                                                                self.connectedTag?.customCommand(requestFlags: [.highDataRate], customCommandCode: Int(cmd.code), customRequestParameters: cmd.parameters) {(customResponse: Data, error: Error?) in
//                                                                    if error != nil {
//                                                                        debugPrint("NFC Failed IDK why don't ask me", error)
//                                                                    }
//
//                                                                    debugPrint("NFC Succeded maybe?")
//
//                                                                }
                debugPrint(self.sensor.state)
            }

            session.invalidate()
        }
    }

    // TODO: test
    /// config: 0x1A00, 64    (serial number and calibration)
    /// sram:   0x1C00, 512
    /// rom:    0x4400 - 0x5FFF
    /// fram lock table: 0xF840, 32
    /// fram:   0xF860, 1952


    func readRaw(_ address: UInt16, _ bytes: Int, buffer: Data = Data(), handler: @escaping (UInt16, Data, Error?) -> Void) {

        var buffer = buffer
        let addressToRead = address + UInt16(buffer.count)

        var remainingBytes = bytes
        let bytesToRead = remainingBytes > 24 ? 24 : bytes

        var remainingWords = bytes / 2
        if bytes % 2 == 1 || ( bytes % 2 == 0 && addressToRead % 2 == 1 ) { remainingWords += 1 }
        let wordsToRead = UInt8(remainingWords > 12 ? 12 : remainingWords)    // real limit is 15

        if buffer.count == 0 { debugPrint("NFC: sending 0xa3 0x07 0x\(Data(sensor.type.backdoor).hex) command (\(sensor.type) read raw)") }

        self.connectedTag?.customCommand(requestFlags: [.highDataRate], customCommandCode: 0xA3, customRequestParameters: Data(self.sensor.type.backdoor + [UInt8(addressToRead & 0x00FF), UInt8(addressToRead >> 8), wordsToRead])) { (customResponse: Data, error: Error?) in

            var data = customResponse

            if error != nil {
                debugPrint("NFC: error while reading \(wordsToRead) words at raw memory 0x\(String(format: "%04X", addressToRead))")
                remainingBytes = 0
            } else {
                if addressToRead % 2 == 1 { data = data.subdata(in: 1 ..< data.count) }
                if data.count - Int(bytesToRead) == 1 { data = data.subdata(in: 0 ..< data.count - 1) }
            }

            buffer += data
            remainingBytes -= data.count

            if remainingBytes == 0 {
                handler(address, buffer, error)
            } else {
                self.readRaw(address, remainingBytes, buffer: buffer) { address, data, error in handler(address, data, error) }
            }
        }
    }


    func writeRaw(_ address: UInt16, _ data: Data, handler: @escaping (UInt16, Data, Error?) -> Void) {

        // Unlock
        debugPrint("NFC: sending 0xa4 0x07 0x\(Data(sensor.type.backdoor).hex) command (\(sensor.type) unlock)")
        self.connectedTag?.customCommand(requestFlags: [.highDataRate], customCommandCode: 0xA4, customRequestParameters: Data(self.sensor.type.backdoor)) { (customResponse: Data, error: Error?) in
            debugPrint("NFC: unlock command response: 0x\(customResponse.hex), error: \(error?.localizedDescription ?? "none")")

            let addressToRead = (address / 8) * 8
            let startOffset = Int(address % 8)
            let endAddressToRead = ((Int(address) + data.count - 1) / 8) * 8 + 7
            let blocksToRead = (endAddressToRead - Int(addressToRead)) / 8 + 1
            self.readRaw(addressToRead, blocksToRead * 8) { readAddress, readData, error in
                var msg = error?.localizedDescription ?? readData.hexDump(address: Int(readAddress), header: "NFC: blocks to overwrite:")
                if error != nil {
                    handler(address, data, error)
                    return
                }
                var bytesToWrite = readData
                bytesToWrite.replaceSubrange(startOffset ..< startOffset + data.count, with: data)
                msg += "\(bytesToWrite.hexDump(address: Int(addressToRead), header: "\nwith blocks:"))"
                debugPrint(msg)

                let startBlock = Int(addressToRead / 8)
                let blocks = bytesToWrite.count / 8

                if address < 0xF860 { // lower than FRAM blocks

                    for i in 0 ..< blocks {

                        let blockToWrite = bytesToWrite[i * 8 ... i * 8 + 7]

                        // FIXME: doesn't work as the custom commands C1 or A5 for other chips
                        self.connectedTag?.extendedWriteSingleBlock(requestFlags: [.highDataRate], blockNumber: startBlock + i, dataBlock: blockToWrite) { error in

                            if error != nil {
                                debugPrint("NFC: error while writing block 0x\(String(format: "%X", startBlock + i)) (\(i + 1) of \(blocks)) \(blockToWrite.hex) at 0x\(String(format: "%X", (startBlock + i) * 8)): \(error!.localizedDescription)")
                                if i != blocks - 1 { return }

                            } else {
                                debugPrint("NFC: wrote block 0x\(String(format: "%X", startBlock + i)) (\(i + 1) of \(blocks)) \(blockToWrite.hex) at 0x\(String(format: "%X", (startBlock + i) * 8))")
                            }

                            if i == blocks - 1 {

                                // Lock
                                self.connectedTag?.customCommand(requestFlags: [.highDataRate], customCommandCode: 0xA2, customRequestParameters: Data(self.sensor.type.backdoor)) { (customResponse: Data, error: Error?) in
                                    debugPrint("NFC: lock command response: 0x\(customResponse.hex), error: \(error?.localizedDescription ?? "none")")
                                    handler(address, data, error)
                                }

                            }
                        }
                    }

                } else { // address >= 0xF860: write to FRAM blocks

                    let requestBlocks = 2    // 3 doesn't work

                    let requests = Int(ceil(Double(blocks) / Double(requestBlocks)))
                    let remainder = blocks % requestBlocks
                    var blocksToWrite = [Data](repeating: Data(), count: blocks)

                    for i in 0 ..< blocks {
                        blocksToWrite[i] = Data(bytesToWrite[i * 8 ... i * 8 + 7])
                    }

                    for i in 0 ..< requests {

                        let startIndex = startBlock - 0xF860 / 8 + i * requestBlocks
                        let endIndex = startIndex + (i == requests - 1 ? (remainder == 0 ? requestBlocks : remainder) : requestBlocks) - (requestBlocks > 1 ? 1 : 0)
                        let blockRange = NSRange(UInt8(startIndex) ... UInt8(endIndex))

                        var dataBlocks = [Data]()
                        for j in startIndex ... endIndex { dataBlocks.append(blocksToWrite[j - startIndex]) }

                        // TODO: write to 16-bit addresses as the custom cummand C4 for other chips
                        self.connectedTag?.writeMultipleBlocks(requestFlags: [.highDataRate, .address], blockRange: blockRange, dataBlocks: dataBlocks) { error in // TEST

                            if error != nil {
                                debugPrint("NFC: error while writing multiple blocks 0x\(String(format: "%X", startIndex)) - 0x\(String(format: "%X", endIndex))) \(dataBlocks.reduce("", { $0 + $1.hex })) at 0x\(String(format: "%X", (startBlock + i * requestBlocks) * 8)): \(error!.localizedDescription)")
                                if i != requests - 1 { return }

                            } else {
                                debugPrint("NFC: wrote blocks 0x\(String(format: "%X", startIndex)) - 0x\(String(format: "%X", endIndex))) \(dataBlocks.reduce("", { $0 + $1.hex })) at 0x\(String(format: "%X", (startBlock + i * requestBlocks) * 8))")
                            }

                            if i == requests - 1 {

                                // Lock
                                self.connectedTag?.customCommand(requestFlags: [.highDataRate], customCommandCode: 0xA2, customRequestParameters: Data(self.sensor.type.backdoor)) { (customResponse: Data, error: Error?) in
                                    debugPrint("NFC: lock command response: 0x\(customResponse.hex), error: \(error?.localizedDescription ?? "none")")
                                    handler(address, data, error)
                                }
                            }
                        } // TEST writeMultipleBlocks
                    }
                }
            }
        }
    }

}

#endif
