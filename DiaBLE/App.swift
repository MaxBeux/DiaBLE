import SwiftUI


@main
struct DiaBLEApp: App {
    #if !os(watchOS)
    @UIApplicationDelegateAdaptor(MainDelegate.self) var main
    #else
    var main: MainDelegate = MainDelegate()
    #endif

    @SceneBuilder var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(main.app)
                .environmentObject(main.log)
                .environmentObject(main.history)
                .environmentObject(main.settings)
        }

        #if os(watchOS)
        WKNotificationScene(controller: NotificationController.self, category: "myCategory")
        #endif
    }
}


enum Tab: String {
    case monitor
    case online
    case console
    case settings
    case data
    case plan
}


class AppState: ObservableObject {

    @Published var device: Device!
    @Published var transmitter: Transmitter!
    @Published var sensor: Sensor!

    var main: MainDelegate!

    @AppStorage("selectedTab") var selectedTab: Tab = .monitor

    @Published var currentGlucose: Int = 0
    @Published var lastReadingDate: Date = Date.distantPast
    @Published var oopGlucose: Int = 0
    @Published var oopAlarm: OOP.Alarm = .unknown
    @Published var oopTrend: OOP.TrendArrow = .unknown
    @Published var trendDelta: Int = 0
    @Published var trendDeltaMinutes: Int = 0

    @Published var deviceState: String = ""
    @Published var lastConnectionDate: Date = Date.distantPast
    @Published var status: String = "Welcome to DiaBLE!"

    @Published var calibration: Calibration = Calibration() {
        didSet(value) {
            main?.applyCalibration(sensor: sensor)
        }
    }
    @Published var editingCalibration = false

    @Published var showingJavaScriptConfirmAlert = false
    @Published var JavaScriptConfirmAlertMessage: String = ""
    @Published var JavaScriptAlertReturn: String = ""
}


class Log: ObservableObject {
    @Published var text: String
    init(_ text: String = "Log \(Date().local)\n") {
        self.text = text
    }
}


class History: ObservableObject {
    @Published var values:        [Glucose] = []
    @Published var rawValues:     [Glucose] = []
    @Published var rawTrend:      [Glucose] = []
    @Published var factoryValues: [Glucose] = []
    @Published var factoryTrend:  [Glucose] = []
    @Published var calibratedValues: [Glucose] = []
    @Published var calibratedTrend:  [Glucose] = []
    @Published var storedValues:     [Glucose] = []
    @Published var nightscoutValues: [Glucose] = []
}


// For UI testing

extension AppState {
    static func test(tab: Tab) -> AppState {

        let app = AppState()

        app.transmitter = Transmitter(battery: 54, rssi: -75, firmware: "4.56", manufacturer: "Acme Inc.", hardware: "2.3", macAddress: Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]))
        app.transmitter.type = .transmitter(.abbott)
        app.device = app.transmitter
        app.sensor = Sensor(state: .active, serial: "3MH001DG75W", age: 18705, uid: Data("2fe7b10000a407e0".bytes), patchInfo: Data("9d083001712b".bytes))
        app.selectedTab = tab
        app.currentGlucose = 234
        app.trendDelta = -12
        app.trendDeltaMinutes = 6
        app.oopGlucose = 234
        app.oopAlarm = .highGlucose
        app.oopTrend = .falling
        app.deviceState = "Connected"
        app.status = "Sensor + Transmitter\nError about connection\nError about sensor"

        return app
    }
}


extension History {
    static var test: History {

        let history = History()

        let values = [231, 252, 253, 254, 245, 196, 177, 128, 149, 150, 101, 122, 133, 144, 155, 166, 177, 178, 149, 140, 141, 142, 143, 144, 155, 166, 177, 178, 169, 150, 141, 132].enumerated().map { Glucose($0.1, id: 5000 - $0.1 * 15, date: Date() - Double($0.1) * 15 * 60) }
        history.values = values

        let rawValues = [241, 252, 263, 254, 205, 196, 187, 138, 159, 160, 121, 132, 133, 154, 165, 176, 157, 148, 149, 140, 131, 132, 143, 154, 155, 176, 177, 168, 159, 150, 142].enumerated().map { Glucose($0.1, id: 5000 - $0.0 * 15, date: Date() - Double($0.1) * 15 * 60) }
        history.rawValues = rawValues

        let factoryArray = [231, 242, 243, 244, 255, 216, 197, 138, 159, 120, 101, 102, 143, 154, 165, 186, 187, 168, 139, 130, 131, 142, 143, 144, 155, 166, 177, 188, 169, 150, 141, 132]

        let factoryValues = factoryArray.enumerated().map { Glucose($0.1, id: 5000 - $0.1 * 15, date: Date() - Double($0.1) * 15 * 60) }
        history.factoryValues = factoryValues

        let calibratedArray = factoryArray.map { $0 + 5 - Int.random(in: 0...10) }

        let calibratedValues = calibratedArray.enumerated().map { Glucose($0.1, id: 5000 - $0.0 * 15, date: Date() - Double($0.1) * 15 * 60) }
        history.calibratedValues = calibratedValues

        let rawTrend = [241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 241, 242, 243, 244, 245].enumerated().map { Glucose($0.1, id: 5000 - $0.0, date: Date() - Double($0.1) * 60) }
        history.rawTrend = rawTrend

        let factoryTrend = [231, 232, 233, 234, 235, 236, 237, 238, 239, 230, 231, 232, 233, 234, 235].enumerated().map { Glucose($0.1, id: 5000 - $0.0, date: Date() - Double($0.1) * 60) }
        history.factoryTrend = factoryTrend

        let calibratedTrend = [231, 232, 233, 234, 235, 236, 237, 238, 239, 230, 231, 232, 233, 234, 235].enumerated().map { Glucose($0.1, id: 5000 - $0.0, date: Date() - Double($0.1) * 60) }
        history.calibratedTrend = calibratedTrend

        let storedValues = [231, 252, 253, 254, 245, 196, 177, 128, 149, 150, 101, 122, 133, 144, 155, 166, 177, 178, 149, 140, 141, 142, 143, 144, 155, 166, 177, 178, 169, 150, 141, 132].enumerated().map { Glucose($0.1, id: $0.0, date: Date() - Double($0.1) * 15 * 60, source: "SourceApp com.example.sourceapp") }
        history.storedValues = storedValues

        let nightscoutValues = [231, 252, 253, 254, 245, 196, 177, 128, 149, 150, 101, 122, 133, 144, 155, 166, 177, 178, 149, 140, 141, 142, 143, 144, 155, 166, 177, 178, 169, 150, 141, 132].enumerated().map { Glucose($0.1, id: $0.0, date: Date() - Double($0.1) * 15 * 60, source: "Device") }
        history.nightscoutValues = nightscoutValues

        return history
    }
}
