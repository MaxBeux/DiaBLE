import Foundation
import SwiftUI


struct Monitor: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var history: History
    @EnvironmentObject var settings: Settings

    @State var showingHamburgerMenu = false

    @State private var showingCalibrationParameters = false
    @State private var editingCalibration = false

    @State private var showingNFCAlert = false

    @State private var readingCountdown: Int = 0
    @State private var minutesSinceLastReading: Int = 0

    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationView {

            ZStack(alignment: .topLeading) {

                VStack {

                    if !(editingCalibration && showingCalibrationParameters)  {
                        Spacer()
                    }

                    VStack {

                        HStack {

                            VStack {
                                if app.lastReadingDate != Date.distantPast {
                                    Text(app.lastReadingDate.shortTime).monospacedDigit()
                                    Text("\(minutesSinceLastReading) min ago").font(.footnote).monospacedDigit()
                                        .onReceive(minuteTimer) { _ in
                                            minutesSinceLastReading = Int(Date().timeIntervalSince(app.lastReadingDate)/60)
                                        }
                                } else {
                                    Text("---")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 12).foregroundColor(Color(.lightGray))
                            .onReceive(app.$lastReadingDate) { readingDate in
                                minutesSinceLastReading = Int(Date().timeIntervalSince(readingDate)/60)
                            }

                            Text(app.currentGlucose > 0 ? "\(app.currentGlucose.units) " : "--- ")
                                .font(.system(size: 42, weight: .black)).monospacedDigit()
                                .foregroundColor(.black)
                                .padding(5)
                                .background(app.currentGlucose > 0 && (app.currentGlucose > Int(settings.alarmHigh) || app.currentGlucose < Int(settings.alarmLow)) ?
                                            Color.red : Color.blue)
                                .cornerRadius(8)

                            // TODO
                            Group {
                                if app.trendDeltaMinutes > 0 {
                                    VStack {
                                        Text("\(app.trendDelta > 0 ? "+ " : app.trendDelta < 0 ? "- " : "")\(app.trendDelta == 0 ? "→" : abs(app.trendDelta).units)")
                                            .fontWeight(.black)
                                        Text("\(app.trendDeltaMinutes) min").font(.footnote)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
                                } else {
                                    Text(app.oopTrend.symbol).font(.largeTitle).bold()
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
                                }
                            }.foregroundColor(app.currentGlucose > 0 && (app.currentGlucose > Int(settings.alarmHigh) && app.trendDelta > 0 || app.currentGlucose < Int(settings.alarmLow)) && app.trendDelta < 0 ?
                                                .red : .blue)

                        }

                        Text("\(app.oopAlarm.description.replacingOccurrences(of: "_", with: " ")) - \(app.oopTrend.description.replacingOccurrences(of: "_", with: " "))")
                            .foregroundColor(.blue)

                        HStack {
                            Text(app.deviceState)
                                .foregroundColor(app.deviceState == "Connected" ? .green : .red)
                                .fixedSize()

                            if !app.deviceState.isEmpty && app.deviceState != "Disconnected" {
                                Text(readingCountdown > 0 || app.deviceState == "Reconnecting..." ?
                                     "\(readingCountdown) s" : "")
                                    .fixedSize()
                                    .font(Font.callout.monospacedDigit()).foregroundColor(.orange)
                                    .onReceive(timer) { _ in
                                        readingCountdown = settings.readingInterval * 60 - Int(Date().timeIntervalSince(app.lastConnectionDate))
                                    }
                            }
                        }
                    }

                    Graph().frame(width: 31 * 7 + 60, height: 150)

                    if !(editingCalibration && showingCalibrationParameters) {

                        VStack {

                            HStack(spacing: 12) {

                                if app.sensor != nil && (app.sensor.state != .unknown || app.sensor.serial != "") {
                                    VStack {
                                        Text(app.sensor.state.description)
                                            .foregroundColor(app.sensor.state == .active ? .green : .red)

                                        if app.sensor.age > 0 {
                                            Text(app.sensor.age.shortFormattedInterval)
                                        }
                                    }
                                }

                                if app.device != nil {
                                    VStack {
                                        if app.device.battery > -1 {
                                            Text("Battery: ").foregroundColor(Color(.lightGray)) +
                                            Text("\(app.device.battery)%").foregroundColor(app.device.battery > 10 ? .green : .red)
                                        }
                                        if app.device.rssi != 0 {
                                            Text("RSSI: ").foregroundColor(Color(.lightGray)) +
                                            Text("\(app.device.rssi) dB")
                                        }
                                    }
                                }

                            }.font(.footnote).foregroundColor(.yellow)

                            Text(app.status)
                                .font(.footnote)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity)

                            NavigationLink(destination: Details()) {
                                Text("Details").font(.footnote).bold().fixedSize()
                                    .padding(.horizontal, 4).padding(2).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor, lineWidth: 2))
                            }
                        }

                        Spacer()
                        Spacer()

                    }

                    VStack {

                        HStack {

                            Toggle(isOn: $settings.usingOOP.animation()) {
                                Text("OOP")
                            }
                            .toggleStyle(SwitchToggleStyle(tint: Color.blue))
                            .onChange(of: settings.usingOOP) { usingOOP in
                                Task {
                                    await app.main.applyOOP(sensor: app.sensor)
                                    app.main.didParseSensor(app.sensor)
                                }
                            }

                        }

                        CalibrationView(showingCalibrationParameters: $showingCalibrationParameters, editingCalibration: $editingCalibration)

                    }

                    Spacer()
                    Spacer()

                    HStack {

                        Button {
                            app.main.rescan()

                        } label: {
                            Image(systemName: "arrow.clockwise.circle").resizable().frame(width: 32, height: 32).padding(.bottom, 8).foregroundColor(.accentColor)
                        }

                        if (app.status.hasPrefix("Scanning") || app.status.hasSuffix("retrying...")) && app.main.centralManager.state != .poweredOff {
                            Button {
                                app.main.centralManager.stopScan()
                                app.main.status("Stopped scanning")
                                app.main.log("Bluetooth: stopped scanning")
                            } label: {
                                Image(systemName: "stop.circle").resizable().frame(width: 32, height: 32)
                            }.padding(.bottom, 8).foregroundColor(.red)
                        }

                    }

                }
                .multilineTextAlignment(.center)
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("DiaBLE  \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String)  -  Monitor")
                .onAppear {
                    timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
                    minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
                    if app.lastReadingDate != Date.distantPast {
                        minutesSinceLastReading = Int(Date().timeIntervalSince(app.lastReadingDate)/60)
                    }
                }
                .onDisappear {
                    timer.upstream.connect().cancel()
                    minuteTimer.upstream.connect().cancel()
                }
                .toolbar {

                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { showingHamburgerMenu.toggle() }
                        } label: {
                            Image(systemName: "line.horizontal.3")
                        }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            if app.main.nfc.isAvailable {
                                app.main.nfc.startSession()
                            } else {
                                showingNFCAlert = true
                            }
                        } label: {
                            VStack(spacing: 0) {
                                // original: .frame(width: 39, height: 27
                                Image("NFC").renderingMode(.template).resizable().frame(width: 26, height: 18)
                                Text("Scan").font(.footnote)
                            }
                        }
                    }
                }
                .alert("NFC not supported", isPresented: $showingNFCAlert) {
                } message: {
                    Text("This device doesn't allow scanning the Libre.")
                }

                HamburgerMenu(showingHamburgerMenu: $showingHamburgerMenu)
                    .frame(width: 180)
                    .offset(x: showingHamburgerMenu ? 0 : -180)
            }
        }.navigationViewStyle(.stack)
    }
}


struct CalibrationView: View {

    @EnvironmentObject var app: AppState
    @EnvironmentObject var history: History
    @EnvironmentObject var settings: Settings

    @Binding var showingCalibrationParameters: Bool
    @Binding var editingCalibration: Bool

    func endEditingCalibration() {
        withAnimation { editingCalibration = false }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

    }

    var body: some View {
        VStack(spacing: 0) {

            Toggle(isOn: $settings.calibrating.animation()) {
                Text("Calibration")
            }
            .toggleStyle(SwitchToggleStyle(tint: Color.purple))
            .onChange(of: settings.calibrating) { calibrating in

                if !calibrating {
                    withAnimation {
                        editingCalibration = false
                    }
                }
                app.main.didParseSensor(app.sensor)
            }

            if settings.calibrating {

                DisclosureGroup(isExpanded: $showingCalibrationParameters) {

                    VStack(spacing: 6) {
                        HStack {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Slope slope:")
                                    TextField("Slope slope", value: $app.calibration.slopeSlope,
                                              formatter: settings.numberFormatter) { editing in
                                        if !editing {
                                            // TODO: update when loosing focus
                                        }
                                    }
                                              .foregroundColor(.purple)
                                              .keyboardType(.numbersAndPunctuation)
                                              .onTapGesture { withAnimation { editingCalibration = true } }
                                }
                                if editingCalibration {
                                    Slider(value: $app.calibration.slopeSlope, in: 0.00001 ... 0.00002, step: 0.00000005)
                                }
                            }

                            VStack(spacing: 0) {
                                HStack {
                                    Text("Slope offset:")
                                    TextField("Slope offset", value: $app.calibration.offsetSlope,
                                              formatter: settings.numberFormatter) { editing in
                                        if !editing {
                                            // TODO: update when loosing focus
                                        }
                                    }
                                              .foregroundColor(.purple)
                                              .keyboardType(.numbersAndPunctuation)
                                              .onTapGesture { withAnimation { editingCalibration = true } }
                                }
                                if editingCalibration {
                                    Slider(value: $app.calibration.offsetSlope, in: -0.02 ... 0.02, step: 0.0001)
                                }
                            }
                        }

                        HStack {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Offset slope:")
                                    TextField("Offset slope", value: $app.calibration.slopeOffset,
                                              formatter: settings.numberFormatter) { editing in
                                        if !editing {
                                            // TODO: update when loosing focus
                                        }
                                    }
                                              .foregroundColor(.purple)
                                              .keyboardType(.numbersAndPunctuation)
                                              .onTapGesture { withAnimation { editingCalibration = true } }
                                }
                                if editingCalibration {
                                    Slider(value: $app.calibration.slopeOffset, in: -0.01 ... 0.01, step: 0.00005)
                                }
                            }

                            VStack(spacing: 0) {
                                HStack {
                                    Text("Offset offset:")
                                    TextField("Offset offset", value: $app.calibration.offsetOffset,
                                              formatter: settings.numberFormatter) { editing in
                                        if !editing {
                                            // TODO: update when loosing focus
                                        }
                                    }
                                              .foregroundColor(.purple)
                                              .keyboardType(.numbersAndPunctuation)
                                              .onTapGesture {  withAnimation { editingCalibration = true } }
                                }
                                if editingCalibration {
                                    Slider(value: $app.calibration.offsetOffset, in: -100 ... 100, step: 0.5)
                                }
                            }
                        }
                    }.font(.footnote)
                        .keyboardType(.numbersAndPunctuation)

                    if editingCalibration || history.calibratedValues.count == 0 {
                        Spacer()
                        HStack(spacing: 20) {

                            if editingCalibration {
                                Button {
                                    endEditingCalibration()
                                } label: {
                                    Text("Use").bold().padding(.horizontal, 4).padding(2).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor, lineWidth: 2))
                                }

                                if app.calibration != settings.calibration && app.calibration != settings.oopCalibration {
                                    Button {
                                        endEditingCalibration()
                                        settings.calibration = app.calibration
                                    } label: {
                                        Text("Save").bold().padding(.horizontal, 4).padding(2).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor, lineWidth: 2))
                                    }
                                }
                            }

                            if settings.calibration != .empty && (app.calibration != settings.calibration || app.calibration == .empty) {
                                Button {
                                    endEditingCalibration()
                                    app.calibration = settings.calibration
                                } label: {
                                    Text("Load").bold().padding(.horizontal, 4).padding(2).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor, lineWidth: 2))
                                }
                            }

                            if settings.oopCalibration != .empty && ((app.calibration != settings.oopCalibration && editingCalibration) || app.calibration == .empty) {
                                Button {
                                    endEditingCalibration()
                                    app.calibration = settings.oopCalibration
                                    settings.calibration = Calibration()
                                } label: {
                                    Text("Restore OOP").bold().padding(.horizontal, 4).padding(2).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor, lineWidth: 2))
                                }
                            }

                        }.font(.footnote)
                    }

                } label: {
                    Button {
                        withAnimation { showingCalibrationParameters.toggle() }
                    } label: {
                        Text("Parameters")}.foregroundColor(.purple)
                }

            }

        }.accentColor(.purple)
    }
}


struct Monitor_Previews: PreviewProvider {

    static var previews: some View {
        Group {
            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(AppState.test(tab: .monitor))
                .environmentObject(Log())
                .environmentObject(History.test)
                .environmentObject(Settings())
        }
    }
}
