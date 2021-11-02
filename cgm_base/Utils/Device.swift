import Foundation
import CoreBluetooth


enum DeviceType: CaseIterable, Hashable, Identifiable {

    case none
    case transmitter(TransmitterType)

    static var allCases: [DeviceType] {
        return TransmitterType.allCases.map{.transmitter($0)} // + WatchType.allCases.map{.watch($0)}
    }

    var id: String {
        switch self {
        case .none:                  return "none"
        case .transmitter(let type): return type.id
        }
    }

    var type: AnyClass {
        switch self {
        case .none:                  return Device.self
        case .transmitter(let type): return type.type
        }
    }
}


class Device: ObservableObject {

    class var type: DeviceType { DeviceType.none }
    class var name: String { "Unknown" }

    class var knownUUIDs: [String] { [] }
    class var dataServiceUUID: String { "" }
    class var dataReadCharacteristicUUID: String { "" }
    class var dataWriteCharacteristicUUID: String { "" }

    var type: DeviceType = DeviceType.none
    @Published var name: String = "Unknown"


    /// Main app delegate to use its log()
    var main: CGMManager!

    var peripheral: CBPeripheral?
    var characteristics = [String: CBCharacteristic]()

    /// Updated when notified by the Bluetooth manager
    @Published var state: CBPeripheralState = .disconnected

    var readCharacteristic: CBCharacteristic?
    var writeCharacteristic: CBCharacteristic?

    @Published var battery: Int = -1
    @Published var rssi: Int = 0
    var company: String = ""
    var model: String = ""
    var serial: String = ""
    var firmware: String = ""
    var hardware: String = ""
    var software: String = ""
    var manufacturer: String = ""
    var macAddress: Data = Data()

    var buffer = Data()

    init(peripheral: CBPeripheral, main: CGMManager) {
        self.type = Self.type
        self.name = Self.name
        self.peripheral = peripheral
        self.main = main
    }

    init() {
        self.type = Self.type
        self.name = Self.name
    }

    // For log while testing
    convenience init(main: CGMManager) {
        self.init()
        self.main = main
    }

    // For UI testing
    convenience init(battery: Int, rssi: Int = 0, firmware: String = "", manufacturer: String = "", hardware: String = "", macAddress: Data = Data()) {
        self.init()
        self.battery = battery
        self.rssi = rssi
        self.firmware = firmware
        self.manufacturer = manufacturer
        self.hardware = hardware
        self.macAddress = macAddress
    }

    func write(_ bytes: [UInt8], for uuid: String = "", _ writeType: CBCharacteristicWriteType = .withoutResponse) {
        if uuid.isEmpty {
            peripheral?.writeValue(Data(bytes), for: writeCharacteristic!, type: writeType)
        } else {
            peripheral?.writeValue(Data(bytes), for: characteristics[uuid]!, type: writeType)
        }
    }

    func read(_ data: Data, for uuid: String) {
    }


    func readValue(for uuid: BLE.UUID) {
        peripheral?.readValue(for: characteristics[uuid.rawValue]!)
        debugPrint("\(name): requested value for \(uuid)")
    }

    /// varying reading interval
    func readCommand(interval: Int = 5) -> [UInt8] { [] }

    func parseManufacturerData(_ data: Data) {
        debugPrint("Bluetooth: \(name)'s advertised manufacturer data: \(data.hex)" )
    }

}


enum TransmitterType: String, CaseIterable, Hashable, Codable, Identifiable {
    case none, abbott
    var id: String { rawValue }
    var name: String {
        switch self {
        case .none:     return "Any"
        case .abbott:   return Libre.name
        }
    }
    var type: AnyClass {
        switch self {
        case .none:     return Transmitter.self
        case .abbott:   return Libre.self
        }
    }
}


class Transmitter: Device {
    @Published var sensor: Sensor?
}


class Libre: Transmitter {
    override class var type: DeviceType { DeviceType.transmitter(.abbott) }
    override class var name: String { "Libre" }

    enum UUID: String, CustomStringConvertible, CaseIterable {
        case abbottCustom     = "FDE3"
        case bleLogin         = "F001"
        case compositeRawData = "F002"

        var description: String {
            switch self {
            case .abbottCustom:     return "Abbott custom"
            case .bleLogin:         return "BLE login"
            case .compositeRawData: return "composite raw data"
            }
        }
    }

    override class var knownUUIDs: [String] { UUID.allCases.map{$0.rawValue} }

    override class var dataServiceUUID: String { UUID.abbottCustom.rawValue }
    override class var dataWriteCharacteristicUUID: String { UUID.bleLogin.rawValue }
    override class var dataReadCharacteristicUUID: String  { UUID.compositeRawData.rawValue }


    override func read(_ data: Data, for uuid: String) {
        switch UUID(rawValue: uuid) {
        case .compositeRawData:
            if sensor == nil {
                sensor = Sensor(transmitter: self)
                main.app.sensor = sensor
            }
            // The Libre always sends 46 bytes as three packets of 20 + 18 + 8 bytes
            if data.count == 20 {
                buffer = Data()
                sensor!.lastReadingDate = main.app.lastReadingDate
            }
            buffer.append(data)
            if buffer.count == 46 {
                mapLibreData()
            }
        default:
            break
        }
    }
    
    private func mapLibreData() {
        do {
            let bleGlucose = parseBLEData(Data(try Libre2.decryptBLE(id: sensor!.uid, data: buffer)))
            debugPrint("BLE raw values: \(bleGlucose.map{$0.raw})")
            
            guard !bleGlucose.isEmpty else {
                return
            }
            // Get latest precise first 7 values
            /// Refer Device.swift line no.255
            let trend = bleGlucose[0...6].map { factoryGlucose(raw: $0, calibrationInfo: main.settings.activeSensorCalibrationInfo) }
            
            // REQUIRED GLUCOSE VALUE
            /// The currrent glucose value in turn will be written to app.currentGlucose - Refer BluetoothDeligate.swift - peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?)
            if trend[0].raw > 0 { sensor!.currentGlucose = trend[0].value }
            
            var rawTrend = [Glucose](main.history.values)
            let rawTrendIds = rawTrend.map { $0.id }
            /// Filter for duplicates and append to existing glucose values
            rawTrend += bleGlucose.prefix(7).filter { !rawTrendIds.contains($0.id) }
            /// Sort glucose values based on time
            rawTrend = [Glucose](rawTrend.sorted(by: { $0.id > $1.id }).prefix(16))
            main.history.values = rawTrend
            
            debugPrint("Sensore Type \(sensor!.type)  +  BLE")
        }
        catch {
            // TODO: verify crc16
            debugPrint(error.localizedDescription)
            buffer = Data()
        }
    }

    // Parse data recived from bluetooth device to readable custom (Glucose) datamodel
    func parseBLEData( _ data: Data) -> [Glucose] {
        var bleGlucose: [Glucose] = []
        let wearTimeMinutes = UInt16(data[40...41]) // data.count = 46
        if sensor!.state == .unknown { sensor!.state = .active }
        if sensor!.age == 0 {sensor!.age = Int(wearTimeMinutes) }
        let startDate = sensor!.lastReadingDate - Double(wearTimeMinutes) * 60
        let delay = 2
        for i in 0 ..< 10 {
            let raw = readBits(data, i * 4, 0, 0xe)
            let rawTemperature = readBits(data, i * 4, 0xe, 0xc) << 2
            var temperatureAdjustment = readBits(data, i * 4, 0x1a, 0x5) << 2
            let negativeAdjustment = readBits(data, i * 4, 0x1f, 0x1)
            if negativeAdjustment != 0 {
                temperatureAdjustment = -temperatureAdjustment
            }

            var id = Int(wearTimeMinutes)

            if i < 7 {
                // sparse trend values
                id -= [0, 2, 4, 6, 7, 12, 15][i]

            } else {
                // TODO: precise id of the last three recent historic values
                id = ((id - delay) / 15) * 15 - 15 * (i - 7)
            }

            let date = startDate + Double(id * 60)
            let glucose = Glucose(raw: raw,
                                  rawTemperature: rawTemperature,
                                  temperatureAdjustment: temperatureAdjustment,
                                  id: id,
                                  date: date)
            bleGlucose.append(glucose)
        }
        let crc = UInt16(data[42], data[43])
        debugPrint("Bluetooth: received BLE data 0x\(data.hex) (wear time: \(wearTimeMinutes) minutes (0x\(String(format: "%04x", wearTimeMinutes))), CRC: \(String(format: "%04x", crc)), computed CRC: \(String(format: "%04x", crc16(Data(data[0...41]))))), glucose values: \(bleGlucose)")
        return bleGlucose
    }

}
