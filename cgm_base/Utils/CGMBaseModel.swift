//
//  CGMBaseModel.swift
//  cgm_base
//
//  Created by Rashika Poonacha on 26/10/21.
//

import Foundation

class History: ObservableObject {
    @Published var values: [Glucose] = []
}

class AppState: ObservableObject {
    var main: CGMManager!

    @Published var device: Device! // bluetooth device data
    @Published var transmitter: Transmitter!
    @Published var sensor: Sensor!

    @Published var currentGlucose: Int = 0
    @Published var lastReadingDate: Date = Date()
}
