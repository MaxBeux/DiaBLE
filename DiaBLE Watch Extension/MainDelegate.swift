import SwiftUI
import CoreBluetooth
import AVFoundation


//public class MainDelegate: NSObject, UNUserNotificationCenterDelegate {
public class MainDelegate: NSObject, WKExtendedRuntimeSessionDelegate {

    var app: AppState
    var log: Log
    var history: History
    var settings: Settings

    var extendedSession: WKExtendedRuntimeSession! // TODO

    var centralManager: CBCentralManager
    var bluetoothDelegate: BluetoothDelegate
    var healthKit: HealthKit?
    var nightscout: Nightscout?
    //    var eventKit: EventKit?


    override init() {

        UserDefaults.standard.register(defaults: Settings.defaults)

        app = AppState()
        log = Log()
        history = History()
        settings = Settings()

        extendedSession = WKExtendedRuntimeSession()

        bluetoothDelegate = BluetoothDelegate()
        centralManager = CBCentralManager(delegate: bluetoothDelegate,
                                          queue: nil,
                                          options: [CBCentralManagerOptionRestoreIdentifierKey: "DiaBLE"])

        healthKit = HealthKit()

        super.init()

        log.text = "Welcome to DiaBLE!\n\(settings.logging ? "Log started" : "Log stopped") \(Date().local)\n"
        debugLog("User defaults: \(Settings.defaults.keys.map{ [$0, UserDefaults.standard.dictionaryRepresentation()[$0]!] }.sorted{($0[0] as! String) < ($1[0] as! String) })")

        app.main = self
        extendedSession.delegate = self
        bluetoothDelegate.main = self

        if let healthKit = healthKit {
            healthKit.main = self
            healthKit.authorize {
                self.log("HealthKit: \( $0 ? "" : "not ")authorized")
                if healthKit.isAuthorized {
                    healthKit.read { [self] in debugLog("HealthKit last 12 stored values: \($0[..<(min(12, $0.count))])") }
                }
            }
        }

        nightscout = Nightscout(main: self)
        nightscout!.read()
        //        eventKit = EventKit(main: self)
        //        eventKit?.sync()
        //
        //
        //        UNUserNotificationCenter.current().delegate = self
        //        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }


        let numberFormatter = NumberFormatter()
        numberFormatter.minimumFractionDigits = 8
        settings.numberFormatter = numberFormatter
    }


    public func log(_ msg: String) {
        if self.settings.logging || msg.hasPrefix("Log") {
            DispatchQueue.main.async {
                if self.settings.reversedLog {
                    self.log.text = "\(msg)\n \n\(self.log.text)"
                } else {
                    self.log.text.append(" \n\(msg)\n")
                }
                print(msg)
            }
        }
    }


    public func debugLog(_ msg: String) {
        if settings.debugLevel > 0 {
            log(msg)
        }
    }

    public func status(_ text: String) {
        DispatchQueue.main.async {
            self.app.status = text
        }
    }

    public func errorStatus(_ text: String) {
        if !self.app.status.contains(text) {
            DispatchQueue.main.async {
                self.app.status.append("\n\(text)")
            }
        }
    }


    public func rescan() {
        if let device = app.device {
            centralManager.cancelPeripheralConnection(device.peripheral!)
        }
        if centralManager.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: nil, options: nil)
            status("Scanning...")
        }
        healthKit?.read()
        nightscout?.read()
    }


    public func playAlarm() {
        let currentGlucose = app.currentGlucose
        if !settings.mutedAudio {
            do {
                try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback, options: [.duckOthers])
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                log("Audio Session error: \(error)")
            }
            let soundName = currentGlucose > Int(settings.alarmHigh) ? "alarm_high" : "alarm_low"
            let audioPlayer = try! AVAudioPlayer(contentsOf: URL(fileURLWithPath: Bundle.main.path(forResource: soundName, ofType: "mp3")!), fileTypeHint: "mp3")
            audioPlayer.play()
            _ = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) {
                _ in audioPlayer.stop()
                // FIXME:
                do {
                    try AVAudioSession.sharedInstance().setActive(false)
                } catch { }
            }
        }
        if !settings.disabledNotifications {
            let hapticDirection: WKHapticType = currentGlucose > Int(settings.alarmHigh) ? .directionUp : .directionDown
            WKInterfaceDevice.current().play(hapticDirection)
            let times = currentGlucose > Int(settings.alarmHigh) ? 3 : 4
            let pause = times == 3 ? 1.0 : 5.0 / 6
            for s in 0 ..< times {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(s) * pause) {
                    WKInterfaceDevice.current().play(.notification) // FIXME: vibrates only once
                }
            }
        }
    }


    func parseSensorData(_ sensor: Sensor) {

        sensor.detailFRAM()

        if sensor.history.count > 0 && sensor.fram.count >= 344 {

            let calibrationInfo = sensor.calibrationInfo
            if sensor.serial == settings.activeSensorSerial {
                settings.activeSensorCalibrationInfo = calibrationInfo
            }

            history.rawTrend = sensor.trend
            log("Raw trend: \(sensor.trend.map{$0.rawValue})")
            debugLog("Raw trend temperatures: \(sensor.trend.map{$0.rawTemperature})")
            let factoryTrend = sensor.factoryTrend
            history.factoryTrend = factoryTrend
            log("Factory trend: \(factoryTrend.map{$0.value})")
            log("Trend temperatures: \(factoryTrend.map{Double(String(format: "%.1f", $0.temperature))!}))")
            history.rawValues = sensor.history
            log("Raw history: \(sensor.history.map{$0.rawValue})")
            debugLog("Raw historic temperatures: \(sensor.history.map{$0.rawTemperature})")
            let factoryHistory = sensor.factoryHistory
            history.factoryValues = factoryHistory
            log("Factory history: \(factoryHistory.map{$0.value})")
            log("Historic temperatures: \(factoryHistory.map{Double(String(format: "%.1f", $0.temperature))!})")

            // TODO
            debugLog("Trend has errors: \(sensor.trend.map{$0.hasError})")
            debugLog("Trend data quality: [\n\(sensor.trend.map{$0.dataQuality.description}.joined(separator: ",\n"))\n]")
            debugLog("Trend quality flags: [\(sensor.trend.map{("0"+String($0.dataQualityFlags,radix: 2)).suffix(2)}.joined(separator: ", "))]")
            debugLog("History has errors: \(sensor.history.map{$0.hasError})")
            debugLog("History data quality: [\n\(sensor.history.map{$0.dataQuality.description}.joined(separator: ",\n"))\n]")
            debugLog("History quality flags: [\(sensor.history.map{("0"+String($0.dataQualityFlags,radix: 2)).suffix(2)}.joined(separator: ", "))]")
        }

        debugLog("Sensor uid: \(sensor.uid.hex), saved uid:\(settings.patchUid.hex), patch info: \(sensor.patchInfo.hex.count > 0 ? sensor.patchInfo.hex : "<nil>"), saved patch info: \(settings.patchInfo.hex)")

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

        Task {

            await applyOOP(sensor: sensor)

            didParseSensor(sensor)

        }

    }


    func applyCalibration(sensor: Sensor?) {

        if let sensor = sensor, sensor.history.count > 0, settings.calibrating {

            if app.calibration != .empty {

                var calibratedTrend = sensor.trend
                for i in 0 ..< calibratedTrend.count {
                    calibratedTrend[i].calibration = app.calibration
                }

                var calibratedHistory = sensor.history
                for i in 0 ..< calibratedHistory.count {
                    calibratedHistory[i].calibration = app.calibration
                }

                self.history.calibratedTrend = calibratedTrend
                self.history.calibratedValues = calibratedHistory
                if calibratedTrend.count > 0 {
                    app.currentGlucose = calibratedTrend[0].value
                }
                return
            }

        } else {
            history.calibratedTrend = []
            history.calibratedValues = []
        }

    }


    func didParseSensor(_ sensor: Sensor?) {

        applyCalibration(sensor: sensor)

        guard let sensor = sensor else {
            return
        }

        if settings.usingOOP {
            app.currentGlucose = app.oopGlucose
            if history.values.count > 0 && history.values[0].value > 0 {
                if history.factoryTrend.count == 0 || (history.factoryTrend.count > 0 && history.factoryTrend[0].id < history.values[0].id) {
                    app.currentGlucose = history.factoryValues[0].value
                }
            }
        } else if history.calibratedTrend.count == 0 && history.factoryTrend.count > 0 {
            app.currentGlucose = history.factoryTrend[0].value
        }

        let currentGlucose = app.currentGlucose

        // var title = currentGlucose > 0 ? currentGlucose.units : "---"

        if currentGlucose > 0 && (currentGlucose > Int(settings.alarmHigh) || currentGlucose < Int(settings.alarmLow)) {
            log("ALARM: current glucose: \(currentGlucose.units) (settings: high: \(settings.alarmHigh.units), low: \(settings.alarmLow.units), muted: \(settings.mutedAudio ? "yes" : "no"))")
            playAlarm()
            //            if (settings.calendarTitle == "" || !settings.calendarAlarmIsOn) && !settings.disabledNotifications { // TODO: notifications settings
            //                title += "  \(settings.glucoseUnit)"
            //                title += "  \(app.oopAlarm.shortDescription)  \(app.oopTrend.symbol)"
            //                let content = UNMutableNotificationContent()
            //                content.title = title
            //                content.subtitle = ""
            //                content.sound = UNNotificationSound.default
            //                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            //                let request = UNNotificationRequest(identifier: "DiaBLE", content: content, trigger: trigger)
            //                UNUserNotificationCenter.current().add(request)
            //            }
        }

        //        if !settings.disabledNotifications {
        //            UIApplication.shared.applicationIconBadgeNumber = settings.displayingMillimoles ?
        //                Int(Float(currentGlucose.units)! * 10) : glucoseunit
        //        } else {
        //            UIApplication.shared.applicationIconBadgeNumber = 0
        //        }
        //
        //        eventKit?.sync()

        if history.values.count > 0 || history.factoryValues.count > 0 {
            var entries = [Glucose]()
            if history.values.count > 0 {
                entries += self.history.values
            } else {
                entries += self.history.factoryValues
            }
            entries += history.factoryTrend.dropFirst() + [Glucose(currentGlucose, date: sensor.lastReadingDate)]
            entries = entries.filter{ $0.value > 0 && $0.id > -1 }

            // TODO
            healthKit?.write(entries.filter { $0.date > healthKit?.lastDate ?? Calendar.current.date(byAdding: .hour, value: -8, to: Date())! })
            healthKit?.read()

            // TODO
            // nightscout?.delete(query: "find[device]=OOP&count=32") { data, response, error in

            nightscout?.read { values in
                if values.count > 0 {
                    entries = entries.filter { $0.date > values[0].date }
                }
                self.nightscout?.post(entries: entries) {
                    data, response, error in
                    self.nightscout?.read()
                }
            }
        }

        // TODO:
        extendedSession.start(at: max(app.lastReadingDate, app.lastConnectionDate) + Double(settings.readingInterval * 60) - 5.0)
    }


    public func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        debugLog("extended session did start")
    }

    public func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        debugLog("extended session wiil expire")
    }

    public func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        let errorDescription = error != nil ? error!.localizedDescription : "undefined"
        debugLog("extended session did invalidate: reason: \(reason), error: \(errorDescription)")
    }
}
