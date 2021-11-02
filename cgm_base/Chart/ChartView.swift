//
//  ChartView.swift
//  cgm_base
//
//  Created by Rajneesh on 29/10/21.
//

import SwiftUI

struct ChartView: View {
    let dataBase = DataStorageLayer()
    @State var text = NSMutableAttributedString(string: "")
    
    var body: some View {
        VStack {
            ChartUIView()
                .onAppear(perform: {})
        }
    }
    
}

struct ChartView_Previews: PreviewProvider {
    static var previews: some View {
        ChartView()
    }
}

struct TextView: UIViewRepresentable {
    @Binding var text: NSMutableAttributedString
    
    func makeUIView(context: Context) -> UITextView {
        UITextView()
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = text
    }
}

struct ChartUIView: UIViewRepresentable {
    
    @StateObject var viewModel = ChartViewModel()
    
    //@Binding var text: NSMutableAttributedString
    //var curvedlineChart: LineChart!
    func makeUIView(context: Context) -> LineChart {
        
        return LineChart()
    }
    
    func updateUIView(_ uiView: LineChart, context: Context) {
        let dataEntries = viewModel.glucoseList
        uiView.dataEntries = dataEntries
        uiView.isCurved = true
    }
    
    
    private func generatePointEntries() -> [PointEntry] {
        var result: [PointEntry] = []
        let glucoseEntry = fetchData()
        glucoseEntry.forEach {item in
            
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            
            let itemValue = Int(item.value)
            
            let dateString = formatter.string(from: item.date)
//            print("Item value = \(Int(item.value))")
//            print("Item Time = \(dateString)")
            result.append(PointEntry(value: itemValue, label: dateString))
        }
        return result
        
//        for i in 0..<100 {
//            let value = Int(arc4random_uniform(100)) + 0;
//            print(value)
//
//            let formatter = DateFormatter()
//            formatter.dateFormat = "d MMM"
//            var date = Date()
//            date.addTimeInterval(TimeInterval(24*60*60*i))
//
//            result.append(PointEntry(value: value, label: formatter.string(from: date)))
//        }
//        return result
    }
    
    
    func fetchData() -> [DataStorageLayer.GlucoseDataStruct]{
        let dataBase = DataStorageLayer()
        return dataBase.getGlucoseValues()
    }

}


import Combine

class ChartViewModel: ObservableObject {
    @Published var glucoseList: [PointEntry] = []
    private var cancellable : AnyCancellable?
    let dataBase = DataStorageLayer()
    
    init() {
        self.glucoseList = self.generatePointEntries()
        cancellable = NotificationCenter.default.publisher(for: .onDataImported)
        .receive(on: RunLoop.main)
        .sink { notification in
            if self.glucoseList.count <= 0 {
                self.glucoseList = self.generatePointEntries()
            } else {
                if let glucoData = self.dataBase.getLatestGlucoseData() {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "h:mm a"

                    let itemValue = Int(glucoData.value)
                    var dateString: String = ""

                    if self.checkIfMinIsMultipleOf15(date: glucoData.date) {
                        dateString = formatter.string(from: glucoData.date)
                    }
                    let pointEntry = PointEntry(value: itemValue, label: dateString)
                    if !self.glucoseList.contains(pointEntry) {
                        self.glucoseList.append(pointEntry)
                    }
//                    print("Item value = \(Int(glucoData.value))")
//                    print("Item Time = \(dateString)")
                }
            }
        }
    }
    private func generatePointEntries() -> [PointEntry] {
        var result: [PointEntry] = []
        let glucoseEntry = fetchNewData()
        glucoseEntry.forEach {item in

            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"

            let itemValue = Int(item.value)
            var dateString: String = ""
            if checkIfMinIsMultipleOf15(date: item.date) {
                dateString = formatter.string(from: item.date)
            }
            dateString = formatter.string(from: item.date)

//            print("Item value = \(Int(item.value))")
//            print("Item Time = \(dateString)")
            result.append(PointEntry(value: itemValue, label: dateString))
        }
        return result
    }

    private func checkIfMinIsMultipleOf15(date: Date) -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.minute], from: date)
        let minute = components.minute!
        return minute % 15 == 0
    }
    
    func fetchNewData() -> [DataStorageLayer.GlucoseDataStruct]{
        let dataBase = DataStorageLayer()
        return dataBase.getGlucoseValues()
    }
}
