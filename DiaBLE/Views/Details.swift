import Foundation
import SwiftUI


struct Details: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: Settings

    @State private var showingNFCAlert = false
    @State private var showingCalibrationInfoForm = false

    @State private var readingCountdown: Int = 0
    @State private var secondsSinceLastConnection: Int = 0
    @State private var minutesSinceLastReading: Int = 0

    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()


    // TODO:
    @ViewBuilder func Row(_ label: String, _ value: String, foregroundColor: Color? = .secondary) -> some View {
        if !value.isEmpty {
            HStack {
                Text(label).foregroundColor(.primary)
                Spacer()
                Text(value).foregroundColor(foregroundColor)
            }
        } else {
            EmptyView()
        }
    }


    var body: some View {
        VStack {

            Spacer()

            Form {

                if app.status.starts(with: "Scanning") {
                    HStack {
                        Text("\(app.status)").font(.footnote).foregroundColor(.white)
                    }
                } else {
                    if app.device == nil && app.sensor == nil {
                        HStack {
                            Spacer()
                            Text("No device connected").foregroundColor(.red)
                            Spacer()
                        }
                    }
                }

                if app.device != nil {

                    Section(header: Text("Device").font(.headline)) {

                        Group {

                            Row("Name", app.device.peripheral?.name ?? app.device.name)

                            Row("State", (app.device.peripheral?.state ?? app.device.state).description.capitalized,
                                foregroundColor: (app.device.peripheral?.state ?? app.device.state) == .connected ? .green : .red)

                            if app.device.lastConnectionDate != .distantPast {
                                HStack {
                                    Text("Since")
                                    Spacer()
                                    Text("\(secondsSinceLastConnection.minsAndSecsFormattedInterval)")
                                        .monospacedDigit()
                                        .foregroundColor(app.device.state == .connected ? .secondary : .red)
                                        .onReceive(timer) { _ in
                                            if let device = app.device {
                                                secondsSinceLastConnection = Int(Date().timeIntervalSince(device.lastConnectionDate))
                                            } else {
                                                secondsSinceLastConnection = 1
                                            }
                                        }
                                }
                            }
                            if settings.debugLevel > 0 && app.device.peripheral != nil {
                                HStack {
                                    Text("Identifier")
                                    Spacer()
                                    Text(app.device.peripheral!.identifier.uuidString).foregroundColor(.secondary)
                                }
                            }
                            if app.device.name != app.device.peripheral?.name ?? "Unnamed" {
                                HStack {
                                    Text("Type")
                                    Spacer()
                                    Text(app.device.name).foregroundColor(.secondary)
                                }
                            }
                        }

                        if !app.device.serial.isEmpty {
                            HStack {
                                Text("Serial")
                                Spacer()
                                Text(app.device.serial).foregroundColor(.secondary)
                            }
                        }

                        Group {
                            if !app.device.company.isEmpty && app.device.company != "< Unknown >" {
                                HStack {
                                    Text("Company")
                                    Spacer()
                                    Text(app.device.company).foregroundColor(.secondary)
                                }
                            }
                            if !app.device.manufacturer.isEmpty {
                                HStack {
                                    Text("Manufacturer")
                                    Spacer()
                                    Text(app.device.manufacturer).foregroundColor(.secondary)
                                }
                            }
                            if !app.device.model.isEmpty {
                                HStack {
                                    Text("Model")
                                    Spacer()
                                    Text(app.device.model).foregroundColor(.secondary)
                                }
                            }
                            if !app.device.firmware.isEmpty {
                                HStack {
                                    Text("Firmware")
                                    Spacer()
                                    Text(app.device.firmware).foregroundColor(.secondary)
                                }
                            }
                            if !app.device.hardware.isEmpty {
                                HStack {
                                    Text("Hardware")
                                    Spacer()
                                    Text(app.device.hardware).foregroundColor(.secondary)
                                }
                            }
                            if !app.device.software.isEmpty {
                                HStack {
                                    Text("Software")
                                    Spacer()
                                    Text(app.device.software).foregroundColor(.secondary)
                                }
                            }
                        }
                        if app.device.macAddress.count > 0 {
                            HStack {
                                Text("MAC Address")
                                Spacer()
                                Text(app.device.macAddress.hexAddress).foregroundColor(.secondary)
                            }
                        }
                        if app.device.rssi != 0 {
                            HStack {
                                Text("RSSI")
                                Spacer()
                                Text("\(app.device.rssi) dB").foregroundColor(.secondary)
                            }
                        }
                        if app.device.battery > -1 {
                            HStack {
                                Text("Battery")
                                Spacer()
                                Text("\(app.device.battery)%")
                                    .foregroundColor(app.device.battery > 10 ? .green : .red)
                            }
                        }

                    }.font(.callout)
                }


                if app.sensor != nil {

                    Section(header: Text("Sensor").font(.headline)) {

                        HStack {
                            Text("State")
                            Spacer()
                            Text(app.sensor.state.description)
                                .foregroundColor(app.sensor.state == .active ? .green : .red)
                        }
                        HStack {
                            Text("Type")
                            Spacer()
                            Text("\(app.sensor.type.description)\(app.sensor.patchInfo.hex.hasPrefix("a2") ? " (new 'A2' kind)" : "")").foregroundColor(.secondary)
                        }
                        if app.sensor.serial != "" {
                            HStack {
                                Text("Serial")
                                Spacer()
                                Text(app.sensor.serial).foregroundColor(.secondary)
                            }
                        }
                        if app.sensor.region != 0 {
                            HStack {
                                Text("Region")
                                Spacer()
                                Text("\(SensorRegion(rawValue: app.sensor.region)?.description ?? "unknown")").foregroundColor(.secondary)
                            }
                        }
                        if app.sensor.maxLife > 0 {
                            HStack {
                                Text("Maximum Life")
                                Spacer()
                                Text(app.sensor.maxLife.formattedInterval).foregroundColor(.secondary)
                            }
                        }
                        if app.sensor.age > 0 {
                            HStack {
                                Text("Age")
                                Spacer()
                                Text((app.sensor.age + minutesSinceLastReading).formattedInterval).foregroundColor(.secondary)
                                    .onReceive(minuteTimer) { _ in
                                        minutesSinceLastReading = Int(Date().timeIntervalSince(app.sensor.lastReadingDate)/60)
                                    }
                            }
                            HStack {
                                Text("Started on")
                                Spacer()
                                Text("\((app.sensor.lastReadingDate - Double(app.sensor.age) * 60).shortDateTime)").foregroundColor(.secondary)
                            }
                        }
                        if !app.sensor.uid.isEmpty {
                            HStack {
                                Text("UID")
                                Spacer()
                                Text(app.sensor.uid.hex).foregroundColor(.secondary)
                            }
                        }
                        if !app.sensor.patchInfo.isEmpty {
                            HStack {
                                Text("Patch Info")
                                Spacer()
                                Text(app.sensor.patchInfo.hex).foregroundColor(.secondary)
                            }
                            HStack {
                                Text("Security Generation")
                                Spacer()
                                Text("\(app.sensor.securityGeneration)").foregroundColor(.secondary)
                            }
                        }
                    }.font(.callout)
                }

                if app.device != nil && app.device.type == .transmitter(.abbott) || settings.preferredTransmitter == .abbott {

                    Section(header: Text("BLE Setup").font(.headline)) {

                        HStack {
                            Text("Patch Info")
                            TextField("Patch Info", value: $settings.activeSensorInitialPatchInfo, formatter: HexDataFormatter()).multilineTextAlignment(.trailing).foregroundColor(.blue)
                        }
                        HStack {
                            Text("Calibration Info")
                            Spacer()
                            Text("[\(settings.activeSensorCalibrationInfo.i1), \(settings.activeSensorCalibrationInfo.i2), \(settings.activeSensorCalibrationInfo.i3), \(settings.activeSensorCalibrationInfo.i4), \(settings.activeSensorCalibrationInfo.i5), \(settings.activeSensorCalibrationInfo.i6)]")
                                .foregroundColor(.blue)
                        }
                        .onTapGesture {
                            showingCalibrationInfoForm.toggle()
                        }
                        .sheet(isPresented: $showingCalibrationInfoForm) {
                            Form {
                                Section(header: Text("Calibration Info").font(.headline)) {
                                    HStack {
                                        Text("i1")
                                        TextField("i1", value: $settings.activeSensorCalibrationInfo.i1,
                                                  formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundColor(.blue)
                                    }
                                    HStack {
                                        Text("i2")
                                        TextField("i2", value: $settings.activeSensorCalibrationInfo.i2,
                                                  formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundColor(.blue)
                                    }
                                    HStack {
                                        Text("i3")
                                        TextField("i3", value: $settings.activeSensorCalibrationInfo.i3,
                                                  formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundColor(.blue).foregroundColor(.blue)
                                    }
                                    HStack {
                                        Text("i4")
                                        TextField("i4", value: $settings.activeSensorCalibrationInfo.i4,
                                                  formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundColor(.blue)
                                    }
                                    HStack {
                                        Text("i5")
                                        TextField("i5", value: $settings.activeSensorCalibrationInfo.i5,
                                                  formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundColor(.blue)
                                    }
                                    HStack {
                                        Text("i6")
                                        TextField("i6", value: $settings.activeSensorCalibrationInfo.i6,
                                                  formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundColor(.blue)
                                    }
                                    HStack {
                                        Spacer()
                                        Button {
                                            showingCalibrationInfoForm = false
                                        } label: {
                                            Text("Set").bold().foregroundColor(Color.accentColor).padding(.horizontal, 4).padding(2).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor, lineWidth: 2))
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        }

                        HStack {
                            Text("Unlock Code")
                            TextField("Unlock Code", value: $settings.activeSensorStreamingUnlockCode, formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundColor(.blue)
                        }
                        HStack {
                            Text("Unlock Count")
                            TextField("Unlock Count", value: $settings.activeSensorStreamingUnlockCount, formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundColor(.blue)
                        }

                        HStack {
                            Spacer()
                            Button {
                                if app.main.nfc.isAvailable {
                                    app.main.nfc.taskRequest = .enableStreaming
                                    app.selectedTab = .console
                                } else {
                                    showingNFCAlert = true
                                }
                            } label: {
                                VStack(spacing: 0) {
                                    Image("NFC").renderingMode(.template).resizable().frame(width: 26, height: 18) .padding(.horizontal, 12).padding( .vertical, 6)
                                    Text("RePair").font(.footnote).bold().padding(.bottom, 4)
                                }.overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 2.5))
                            }
                            .foregroundColor(.accentColor)
                            .alert("NFC not supported", isPresented: $showingNFCAlert) {
                            } message: {
                                Text("This device doesn't allow scanning the Libre.")
                            }
                            Spacer()
                        }.padding(.vertical, 4)

                    }.font(.callout)
                }


                // Embed a specific device setup panel
                // if app.device?.type == Custom.type {
                //     CustomDetailsView(device: app.device as! Custom)
                //     .font(.callout)
                // }


                if settings.debugLevel > 0 {
                    Section(header: Text("Known Devices")) {
                        VStack(alignment: .leading) {
                            ForEach(app.main.bluetoothDelegate.knownDevices.sorted(by: <), id: \.key) { key, value in
                                Text(value).font(.callout).foregroundColor(.blue)
                            }
                        }
                    }
                }

            }

            Spacer()

            HStack(alignment: .top, spacing: 40) {

                Spacer()

                VStack(spacing: 0) {

                    Button {
                        app.main.rescan()
                        self.timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
                        self.minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
                    } label: {
                        Image(systemName: "arrow.clockwise.circle").resizable().frame(width: 32, height: 32).foregroundColor(.accentColor)
                    }

                    Text(!app.deviceState.isEmpty && app.deviceState != "Disconnected" && (readingCountdown > 0 || app.deviceState == "Reconnecting...") ?
                         "\(readingCountdown) s" : "...")
                        .fixedSize()
                        .foregroundColor(.orange).font(Font.caption.monospacedDigit())
                        .onReceive(timer) { _ in
                            readingCountdown = settings.readingInterval * 60 - Int(Date().timeIntervalSince(app.lastConnectionDate))
                        }
                }

                Button {
                    if app.device != nil {
                        app.main.centralManager.cancelPeripheralConnection(app.device.peripheral!)
                    }
                } label: {
                    Image(systemName: "escape").resizable().frame(width: 28, height: 28)
                        .foregroundColor(.blue)
                }

                Spacer()

            }.padding(.bottom, 8)

                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("Details")
        }
        .onAppear {
            if app.sensor != nil {
                minutesSinceLastReading = Int(Date().timeIntervalSince(app.sensor.lastReadingDate)/60)
            } else if app.lastReadingDate != Date.distantPast {
                minutesSinceLastReading = Int(Date().timeIntervalSince(app.lastReadingDate)/60)
            }
        }
    }
}


struct Details_Preview: PreviewProvider {
    static var previews: some View {
        Group {
            Details()
                .preferredColorScheme(.dark)
                .environmentObject(AppState.test(tab: .monitor))
                .environmentObject(Settings())
            NavigationView {
                Details()
                    .preferredColorScheme(.dark)
                    .environmentObject(AppState.test(tab: .monitor))
                    .environmentObject(Settings())
            }
        }
    }
}
