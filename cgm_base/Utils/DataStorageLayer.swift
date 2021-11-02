//
// Created by Chandraaditya Putrevu on 29/10/21.
//

import CoreData
import Foundation

class DataStorageLayer: NSObject {
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "StorageModel")
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        return container
    }()
    
    func resetAllRecords() // entity = Your_Entity_Name
        {

        let context = persistentContainer.viewContext
            let deleteFetch = NSFetchRequest<NSFetchRequestResult>(entityName: "GlucoseData")
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: deleteFetch)
            do
            {
                try context.execute(deleteRequest)
                try context.save()
            }
            catch
            {
                print ("There was an error")
            }
        }


    func createGlucoseValueEntry(glucoseValue: Int, date: Date) {
        if glucoseValue <= 0 {
            return
        }
        let context = persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "GlucoseData")
        fetchRequest.predicate = NSPredicate(format: "datetime == %@", date as CVarArg)
        do {

            let result = try context.fetch(fetchRequest)
            if (result.count > 0) {
                let objectUpdate = result[0] as! GlucoseData
                objectUpdate.value = Int64(glucoseValue)
            } else {
                let entity = NSEntityDescription.entity(forEntityName: "GlucoseData", in: context)
                let newGlucoseValueEntry: GlucoseData = NSManagedObject(entity: entity!, insertInto: context) as! GlucoseData
                newGlucoseValueEntry.value = Int64(glucoseValue)
                newGlucoseValueEntry.datetime = date
            }

            try context.save()
        } catch {
            print("Failed saving")
        }
        
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.notifyDBChange), object: nil)
        self.perform(#selector(self.notifyDBChange), with: nil, afterDelay: 0.2)
    }
    
    @objc func notifyDBChange() {
        NotificationCenter.default.post(name: .onDataImported, object: nil)
    }

    struct GlucoseDataStruct {
        var value: Int64
        var date: Date
    }

    func getGlucoseValues() -> [GlucoseDataStruct] {
        let context = persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "GlucoseData")
        let sortDescriptor = NSSortDescriptor(key: "datetime", ascending: true)
        fetchRequest.sortDescriptors = [sortDescriptor]
        do {
            let result = try context.fetch(fetchRequest)
            var response: [GlucoseDataStruct] = []
            var previousValue: Int64 = 0
            for data in result as! [GlucoseData] {
                if data.value != 0 {
                    previousValue = data.value
                } else {
                    data.value = previousValue
                }
                let glucoseDataStruct = GlucoseDataStruct(value: data.value, date: data.datetime ?? Date.distantPast)
                response.append(glucoseDataStruct)
            }
            return response
        } catch {
            print("Failed to fetch glucose values")
            return []
        }
    }

    func getLatestGlucoseData() -> GlucoseDataStruct? {
        let context = persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "GlucoseData")
        let sortDescriptor = NSSortDescriptor(key: "datetime", ascending: false)
        fetchRequest.sortDescriptors = [sortDescriptor]
        fetchRequest.fetchLimit = 1
        do {
            let result = try context.fetch(fetchRequest)
            if (result.count > 0) {
                let data = result[0] as! GlucoseData
                let glucoseDataStruct = GlucoseDataStruct(value: data.value, date: data.datetime ?? Date.distantPast)
                return glucoseDataStruct
            } else {
                return nil
            }
        } catch {
            print("Failed to fetch glucose values")
            return nil
        }
    }

    func getFirstGlucoseValue() -> GlucoseDataStruct? {
        let context = persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "GlucoseData")
        let sortDescriptor = NSSortDescriptor(key: "datetime", ascending: true)
        fetchRequest.sortDescriptors = [sortDescriptor]
        fetchRequest.fetchLimit = 5
        do {
            let result = try context.fetch(fetchRequest)
            if (result.count > 0) {
                for data in result as! [GlucoseData] {
                    let glucoseDataStruct = GlucoseDataStruct(value: data.value, date: data.datetime ?? Date.distantPast)
                    if glucoseDataStruct.value > 0 {
                        return glucoseDataStruct
                    }
                }
                return nil
            } else {
                return nil
            }
        } catch {
            print("Failed to fetch glucose values")
            return nil
        }
    }

    func stripSecondsFromDate(date: Date) -> Date {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let str = dateFormatter.string(from: date)
        let newDate = dateFormatter.date(from: str)!

        return newDate
    }
}
extension Date {
    func adding(minutes: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: self)!
    }
}


class DatalayerDummyGenerator {
    private let dataBase = DataStorageLayer()
    weak var timer: Timer?
    
    
    func setUpDummyData() {
        stopTimer()
        self.dataBase.resetAllRecords()
        
        for i in 0..<100 {
            let value = Int.random(in: 80...120)
                //Int(arc4random_uniform(100)) + 0;
            print(value)
            var date = Date()
            date.addTimeInterval(TimeInterval(-60*i))
            self.dataBase.createGlucoseValueEntry(glucoseValue: value, date: stripSecondsFromDate(date: date))
            //result.append(PointEntry(value: value, label: formatter.string(from: date)))
        }
        
        //NotificationCenter.default.post(name: .onDataImported, object: nil)
        //startTimer()
        
    }
    
    func stripSecondsFromDate(date: Date) -> Date {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let str = dateFormatter.string(from: date)
        let newDate = dateFormatter.date(from: str)!

        return newDate
    }
    
    func startTimer() {
        timer?.invalidate()   // just in case you had existing `Timer`, `invalidate` it before we lose our reference to it
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            // do something here
            let value = Int.random(in: 60...120)
                //Int(arc4random_uniform(100)) + 0;
            print("timer \(value)")
            let date = Date()
            if let selfie = self {
                selfie.dataBase.createGlucoseValueEntry(glucoseValue: value, date: selfie.stripSecondsFromDate(date: date))
                //NotificationCenter.default.post(name: .onDataImported, object: nil)
            }
        }
        
        /*
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(expirationHandler: {
                    UIApplication.shared.endBackgroundTask(self.backgroundTaskIdentifier!)
                })
 */
    }

    func stopTimer() {
        timer?.invalidate()
    }
    //dataStorageLayer.createGlucoseValueEntry(glucoseValue: value, date: stripSecondsFromDate(date: date))
}
