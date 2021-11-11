import SwiftUI
import Combine

extension NSNotification.Name {
    static let onDataImported = Notification.Name("onDataImported")
}

struct ContentView: View {
    @State private var pulsate: Bool = true
    @EnvironmentObject var app: AppState
    @State private var showingNFCAlert = false
    
    var body: some View {
//        Image("LIVE")
//            .frame(width: 35, height: 5)
//            .onAppear() {
//                withAnimation(Animation.easeInOut(duration: 1).repeatForever(autoreverses: true).speed(0.5)) {
//                    self.pulsate.toggle()
//                }
//            }.opacity(pulsate ? 0 : 1)
        NavigationView {
            VStack(alignment: .leading, spacing: 10.0) {

                DateScrollerView()
                ChartUIView().frame(height: 400)
                BloodGlucoseView().environmentObject(app)
                
            }.frame(maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading)
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("HealthifyMe")
            .navigationBarItems(
                trailing:
                    /* Test code
                    Button(action: {
                        self.app.main.dummyDataGenerator.setUpDummyData()
                        self.glucoseView.viewModel.startTimer()
                    }) {
                        Image("NFC").renderingMode(.template).resizable().frame(width: 39, height: 27).padding(4).foregroundColor(.black)
                    }
                    */
                    Button(action: {
                        if self.app.main.nfcReader.isNFCAvailable {
                            self.app.main.nfcReader.startSession()
                        } else {
                            self.showingNFCAlert = true
                            //self.app.main.dummyDataGenerator.setUpDummyData()
                        }
                    }) {
                        Image("NFC").renderingMode(.template).resizable().frame(width: 39, height: 27).padding(4).foregroundColor(.black)
                    }.alert(isPresented: $showingNFCAlert) {
                        Alert(
                            title: Text("NFC not supported"),
                            message: Text("This device doesn't allow scanning the Libre."))
                    }
            )
        }.navigationViewStyle(StackNavigationViewStyle())
        
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct BloodGlucoseView: View {
    
    @EnvironmentObject var app: AppState
    @State private var pulsate: Bool = true
    @StateObject var viewModel = ViewModel()
    
    
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 10.0) {
            Text("Blood Glucose").font(.headline).bold()
            
            let glucoValue = viewModel.glucoseData?.value ?? 0
            //let glucoDate = viewModel.glucoseData?.date ?? Date()
            let glucoValueText = glucoValue > 0 ? "\(glucoValue)" :
                (glucoValue < 0 ? "(\(-glucoValue))" : "---")
            HStack(alignment: .center, spacing: 6) {
                
                Text(glucoValueText).font(.system(size: 44, weight: .bold, design: .default)).padding([.top], 10)
                
                VStack(alignment: .leading, spacing: 10.0) {
                    Text("").font(.caption).bold().scaledToFill()
                    Text("mg/dl").font(.system(size: 22, weight: .medium, design: .default)).scaledToFill().padding(2)
                    /*
                    let timeStamp = glucoDate.dateTime
                    //let minsLeft = (Int(Date().timeIntervalSince(glucoDate)/60))
                    
                    
                    if minsLeft > 0 {
                        Text(timeStamp).font(.caption).bold().scaledToFill()
                    } else {
                        Image("LIVE")
                            .frame(width: 35, height: 5)
                            .onAppear() {
                                withAnimation(Animation.easeInOut(duration: 1).repeatForever(autoreverses: true).speed(0.5)) {
                                    self.pulsate.toggle()
                                }
                            }.opacity(pulsate ? 0 : 1)
                            .padding([.top], 10)
                    }
 */
                    
                }.padding(10)
            }
            let sensorState = app.main.nfcReader.currentSenserState.description
            Text("Sensor state: \(sensorState)").font(.caption).bold().scaledToFill()
        }.padding([.leading, .top, .bottom], 10)
    }
}

class ViewModel: ObservableObject {
    @Published var glucoseData: DataStorageLayer.GlucoseDataStruct? = nil
    private var cancellable : AnyCancellable?
    let dataBase = DataStorageLayer()
    weak var timer: Timer?
    var timeActive = 0
   // var backgroundTaskIdentifier: UIBackgroundTaskIdentifier?
    
    init() {
        self.glucoseData = self.dataBase.getLatestGlucoseData()
        cancellable = NotificationCenter.default.publisher(for: .onDataImported)
        .receive(on: RunLoop.main)
        .sink { notification in
            self.glucoseData = self.dataBase.getLatestGlucoseData()
        }
    }
    /*
    func startTimer() {
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(expirationHandler: {
                    UIApplication.shared.endBackgroundTask(self.backgroundTaskIdentifier!)
                })
                timer = Timer.scheduledTimer(timeInterval: 5,
                                                 target: self,
                                                 selector: #selector(timerCallBack),
                                                 userInfo: nil,
                                                 repeats: true)
                timer?.fire()
    }
    func stopTimer() {
        timer?.invalidate()
        timer = nil
        timeActive = 0
    }
    
    @objc func timerCallBack(){
        timeActive = timeActive + 1
        let value = Int.random(in: 90...120)
            //Int(arc4random_uniform(100)) + 0;
        print("timer \(value)")
        let date = Date()
        self.dataBase.createGlucoseValueEntry(glucoseValue: value, date: date)
        if timeActive > 10 {
            stopTimer()
        }
        
    }
 */
}


