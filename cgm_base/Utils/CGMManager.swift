//
//  CGMManager.swift
//  cgm_base
//
//  Created by Rashika Poonacha on 25/10/21.
//

import Foundation
import CoreBluetooth

class CGMManager: NSObject {
    static let shared: CGMManager = CGMManager()
    
    var app: AppState!
    var history: History!
    var settings: Settings!
    
    var centralManager: CBCentralManager!
    var bluetoothDelegate: BluetoothDelegate!
    var nfcReader: NFCReader!
    
    var dummyDataGenerator: DatalayerDummyGenerator!
    
    private override init() {
        super.init()
        print("singleton created")
        
        setUp()
    }
    
    func setUp() {
        UserDefaults.standard.register(defaults: Settings.defaults)
        
        app = AppState()
        history = History()
        settings = Settings()
        
        centralManager = CBCentralManager(delegate: nil, queue: nil)
        bluetoothDelegate = BluetoothDelegate()
        nfcReader = NFCReader()
        dummyDataGenerator = DatalayerDummyGenerator()
        
        app.main = self
        bluetoothDelegate.main = self
        centralManager.delegate = bluetoothDelegate
        nfcReader.main = self
        
        let numberFormatter = NumberFormatter()
        numberFormatter.minimumFractionDigits = 8
        settings.numberFormatter = numberFormatter

        let dataStorageLayer = DataStorageLayer()
        let values = dataStorageLayer.getGlucoseValues()
        for value in values {
            debugPrint(value)
        }

    }
    
    func startNFCSession() {
        if nfcReader.isNFCAvailable {
            nfcReader.startSession()
        }
    }
     
    // MARK: - NFC Scan callbacks
    
    func parseSensorData(_ sensor: Sensor) {
        if sensor.history.count > 0 && sensor.fram.count >= 344 {
            debugPrint(" Sensor age: \(sensor.age) \n minutes (\(String(format: "%.2f", Double(sensor.age)/60/24)) days), \n started on: \((app.lastReadingDate - Double(sensor.age) * 60).shortDateTime)")
            
            let calibrationInfo = sensor.calibrationInfo
            if sensor.serial == settings.activeSensorSerial {
                settings.activeSensorCalibrationInfo = calibrationInfo
            }
            
            if history.values.count > 0 {
                sensor.currentGlucose = -history.values[0].value
            }
        }
        /// settings & Logs
        debugPrint("Sensor state: \(sensor.state)")
        if sensor.reinitializations > 0 {
            debugPrint("Sensor reinitializations: \(sensor.reinitializations)")
        }
        if sensor.maxLife > 0 {
            debugPrint("Sensor maximum life: \(String(format: "%.2f", Double(sensor.maxLife)/60/24)) days (\(sensor.maxLife) minutes)")
        }
        if sensor.uid.count > 0 && sensor.patchInfo.count > 0 {
            settings.patchUid = sensor.uid
            settings.patchInfo = sensor.patchInfo
        }
        if sensor.uid.count == 0 || settings.patchUid.count > 0 {
            if sensor.uid.count == 0 {
                sensor.uid = settings.patchUid
            }
            if sensor.uid == settings.patchUid {
                sensor.patchInfo = settings.patchInfo
            }
        }
        if sensor.patchInfo.count > 0 {
            let fram = sensor.encryptedFram.count > 0 ? sensor.encryptedFram : sensor.fram
            if fram.count < 344 {
                debugPrint("Partially scanned FRAM (\(fram.count)/344): cannot proceed to OOP")
            }
        } else {
            debugPrint("Patch info not available")
            return
        }
    }
    
    /// currentGlucose is negative when set to the last trend raw value (no online connection)
    func didParseSensor(_ sensor: Sensor) {
        var currentGlucose = sensor.currentGlucose
        app.currentGlucose = currentGlucose
        currentGlucose = abs(currentGlucose)
        print("not latest glucose value: \(currentGlucose)")
    }
    
}
