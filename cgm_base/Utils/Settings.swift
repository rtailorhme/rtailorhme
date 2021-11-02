import Foundation


class Settings: ObservableObject {

    static let defaults: [String: Any] = [
        "preferredTransmitter": TransmitterType.none.id,
        "preferredDevicePattern": BLE.knownDevicesIds.joined(separator: " "),
        "readingInterval": 5,
        "glucoseUnit": GlucoseUnit.mgdl.rawValue,

        "targetLow": 80.0,
        "targetHigh": 170.0,
        "alarmLow": 70.0,
        "alarmHigh": 200.0,
        "mutedAudio": false,
        "disabledNotifications": false,

        "logging": false,
        "reversedLog": true,
        "debugLevel": 1,

        "activeSensorSerial": "",
        "activeSensorAddress": Data(),
        "activeSensorUnlockCode": 0,
        "activeSensorUnlockCount": 0,
        "activeSensorCalibrationInfo": try! JSONEncoder().encode(CalibrationInfo()),
        // TODO: rename to activeSensorUid/patchInfo
        "patchUid": Data(),
        "patchInfo": Data(),

        "calibration": try! JSONEncoder().encode(Calibration()),
    ]


    @Published var preferredTransmitter: TransmitterType = TransmitterType(rawValue: UserDefaults.standard.string(forKey: "preferredTransmitter")!) ?? .none {
        willSet(type) {
            if type == .abbott {
                readingInterval = 1
            }
            if type != .none {
                preferredDevicePattern = type.id
            } else {
                preferredDevicePattern = ""
            }
        }
        didSet { UserDefaults.standard.set(self.preferredTransmitter.id, forKey: "preferredTransmitter") }
    }


    @Published var preferredDevicePattern: String = UserDefaults.standard.string(forKey: "preferredDevicePattern")! {
        willSet(pattern) {
            if !pattern.isEmpty {
                if !preferredTransmitter.id.matches(pattern) {
                    preferredTransmitter = .none
                }
            }
        }
        didSet { UserDefaults.standard.set(self.preferredDevicePattern, forKey: "preferredDevicePattern") }
    }

    @Published var readingInterval: Int = UserDefaults.standard.integer(forKey: "readingInterval")  {
        didSet { UserDefaults.standard.set(self.readingInterval, forKey: "readingInterval") }
    }

    @Published var glucoseUnit: GlucoseUnit = GlucoseUnit(rawValue: UserDefaults.standard.string(forKey: "glucoseUnit")!)!  {
        didSet { UserDefaults.standard.set(self.glucoseUnit.rawValue, forKey: "glucoseUnit") }
    }

    @Published var numberFormatter: NumberFormatter = NumberFormatter()

    @Published var targetLow: Double = UserDefaults.standard.double(forKey: "targetLow") {
        didSet { UserDefaults.standard.set(self.targetLow, forKey: "targetLow") }
    }
    @Published var targetHigh: Double = UserDefaults.standard.double(forKey: "targetHigh") {
        didSet { UserDefaults.standard.set(self.targetHigh, forKey: "targetHigh") }
    }

    @Published var logging: Bool = UserDefaults.standard.bool(forKey: "logging") {
        didSet { UserDefaults.standard.set(self.logging, forKey: "logging") }
    }

    @Published var reversedLog: Bool = UserDefaults.standard.bool(forKey: "reversedLog") {
        didSet { UserDefaults.standard.set(self.reversedLog, forKey: "reversedLog") }
    }

    @Published var debugLevel: Int = UserDefaults.standard.integer(forKey: "debugLevel") {
        didSet { UserDefaults.standard.set(self.debugLevel, forKey: "debugLevel") }
    }

    @Published var activeSensorSerial: String = UserDefaults.standard.string(forKey: "activeSensorSerial")! {
        didSet { UserDefaults.standard.set(self.activeSensorSerial, forKey: "activeSensorSerial") }
    }

    @Published var activeSensorAddress: Data = UserDefaults.standard.data(forKey: "activeSensorAddress")! {
        didSet { UserDefaults.standard.set(self.activeSensorAddress, forKey: "activeSensorAddress") }
    }

    @Published var activeSensorUnlockCode: Int = UserDefaults.standard.integer(forKey: "activeSensorUnlockCode") {
        didSet { UserDefaults.standard.set(self.activeSensorUnlockCode, forKey: "activeSensorUnlockCode") }
    }

    @Published var activeSensorUnlockCount: Int = UserDefaults.standard.integer(forKey: "activeSensorUnlockCount") {
        didSet { UserDefaults.standard.set(self.activeSensorUnlockCount, forKey: "activeSensorUnlockCount") }
    }

    @Published var activeSensorCalibrationInfo: CalibrationInfo = try! JSONDecoder().decode(CalibrationInfo.self, from: UserDefaults.standard.data(forKey: "activeSensorCalibrationInfo")!) {
        didSet { UserDefaults.standard.set(try! JSONEncoder().encode(self.activeSensorCalibrationInfo), forKey: "activeSensorCalibrationInfo") }
    }

    @Published var patchUid: SensorUid = UserDefaults.standard.data(forKey: "patchUid")! {
        didSet { UserDefaults.standard.set(self.patchUid, forKey: "patchUid") }
    }

    @Published var patchInfo: PatchInfo = UserDefaults.standard.data(forKey: "patchInfo")! {
        didSet { UserDefaults.standard.set(self.patchInfo, forKey: "patchInfo") }
    }

    @Published var calibration: Calibration = try! JSONDecoder().decode(Calibration.self, from: UserDefaults.standard.data(forKey: "calibration")!) {
        didSet { UserDefaults.standard.set(try! JSONEncoder().encode(self.calibration), forKey: "calibration") }
    }

}


// TODO: validate inputs

class HexDataFormatter: Formatter {
    override func string(for obj: Any?) -> String? {
        return (obj as! Data).hex
    }
    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        obj?.pointee = Data(string.bytes) as AnyObject
        return true
    }

}
