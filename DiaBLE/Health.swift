import Foundation
import HealthKit

// https://github.com/gshaviv/ninety-two/blob/master/WoofWoof/HealthKitManager.swift

class HealthKit: Logging {

    class var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var store: HKHealthStore?
    var glucoseUnit = HKUnit(from: "mg/dl")
    var lastDate: Date?

    var main: MainDelegate!


    init() {
        if HKHealthStore.isHealthDataAvailable() {
            store = HKHealthStore()
        }
    }

    func authorize(_ handler: @escaping (Bool) -> Void) {
        guard let glucoseQuantity = HKQuantityType.quantityType(forIdentifier: .bloodGlucose),
            let insulingDelivery = HKQuantityType.quantityType(forIdentifier: .insulinDelivery) else {
                handler(false)
                return
        }
        store?.requestAuthorization(toShare: [glucoseQuantity, insulingDelivery], read: [glucoseQuantity, insulingDelivery], completion: { success, error in
            handler(success)
        })
    }

    var isAuthorized: Bool {
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return false
        }
        return store?.authorizationStatus(for: glucoseType) == .sharingAuthorized
    }

    func getAuthorizationState(_ handler: @escaping (Bool) -> Void) {
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose), let insulingDelivery = HKQuantityType.quantityType(forIdentifier: .insulinDelivery) else {
            handler(false)
            return
        }
        store?.getRequestStatusForAuthorization(toShare: [glucoseType, insulingDelivery], read: [glucoseType, insulingDelivery]) { status, err in
            if let _ = err {
                handler(false)
            } else {
                handler(status == .unnecessary)
            }
        }
    }


    func write(_ glucoseData: [Glucose]) {
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return
        }
        let samples = glucoseData.map {
            HKQuantitySample(type: glucoseType,
                             quantity: HKQuantity(unit: glucoseUnit, doubleValue: Double($0.value)),
                             start: $0.date,
                             end: $0.date,
                             metadata: nil)
        }
        store?.save(samples) { [self] success, error in
            if let error = error {
                log("HealthKit: error while saving: \(error.localizedDescription)")
            }
            self.lastDate = samples.last?.endDate
        }
    }


    func read(handler: (([Glucose]) -> Void)? = nil) {
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            let msg = "HealthKit error: unable to create glucose quantity type"
            log(msg)
            return
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: glucoseType, predicate: nil, limit: 12 * 8, sortDescriptors: [sortDescriptor]) { [self] query, results, error in
            guard let results = results as? [HKQuantitySample] else {
                if let error = error {
                    log("HealthKit error: \(error.localizedDescription)")
                } else {
                    log("HealthKit: no records")
                }
                return
            }

            self.lastDate = results.first?.endDate

            if results.count > 0 {
                let values = results.enumerated().map { Glucose(Int($0.1.quantity.doubleValue(for: self.glucoseUnit)), id: $0.0, date: $0.1.endDate, source: $0.1.sourceRevision.source.name + " " + $0.1.sourceRevision.source.bundleIdentifier) }
                DispatchQueue.main.async {
                    self.main.history.storedValues = values
                    handler?(values)
                }
            }
        }
        store?.execute(query)
    }
}
