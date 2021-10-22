import Foundation
import SwiftUI


struct Details: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var history: History
    @EnvironmentObject var settings: Settings

    @State private var readingCountdown: Int = 0
    @State private var showingCalibrationInfoForm = false

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {

            Form {

                if app.device == nil && app.sensor == nil {
                    HStack {
                        Spacer()
                        Text("No device connected").foregroundColor(.red)
                        Spacer()
                    }
                }

                if app.device != nil {

                    Section(header: Text("Device")) {

                        Group {
                            if app.device.peripheral?.name != nil {
                                HStack {
                                    Text("Name")
                                    Spacer()
                                    Text(app.device.peripheral!.name!).foregroundColor(.yellow)
                                }
                            }
                            if settings.debugLevel > 0 && app.device.peripheral != nil {
                                HStack {
                                    Text("Identifier")
                                    Spacer()
                                    Text(app.device.peripheral!.identifier.uuidString).foregroundColor(.yellow)
                                }
                            }
                            if app.device.name != app.device.peripheral?.name ?? "Unnamed" {
                                HStack {
                                    Text("Type")
                                    Spacer()
                                    Text(app.device.name).foregroundColor(.yellow)
                                }
                            }
                        }
                        if !app.device.serial.isEmpty {
                            HStack {
                                Text("Serial")
                                Spacer()
                                Text(app.device.serial).foregroundColor(.yellow)
                            }
                        }
                        Group {
                            if !app.device.company.isEmpty && app.device.company != "< Unknown >" {
                                HStack {
                                    Text("Company")
                                    Spacer()
                                    Text(app.device.company).foregroundColor(.yellow)
                                }
                            }
                            if !app.device.manufacturer.isEmpty {
                                HStack {
                                    Text("Manufacturer")
                                    Spacer()
                                    Text(app.device.manufacturer).foregroundColor(.yellow)
                                }
                            }
                            if !app.device.model.isEmpty {
                                HStack {
                                    Text("Model")
                                    Spacer()
                                    Text(app.device.model).foregroundColor(.yellow)
                                }
                            }
                            if !app.device.firmware.isEmpty {
                                HStack {
                                    Text("Firmware")
                                    Spacer()
                                    Text(app.device.firmware).foregroundColor(.yellow)
                                }
                            }
                            if !app.device.hardware.isEmpty {
                                HStack {
                                    Text("Hardware")
                                    Spacer()
                                    Text(app.device.hardware).foregroundColor(.yellow)
                                }
                            }
                            if !app.device.software.isEmpty {
                                HStack {
                                    Text("Software")
                                    Spacer()
                                    Text(app.device.software).foregroundColor(.yellow)
                                }
                            }
                        }
                        if app.device.macAddress.count > 0 {
                            HStack {
                                Text("MAC Address")
                                Spacer()
                                Text(app.device.macAddress.hexAddress).foregroundColor(.yellow)
                            }
                        }
                        if app.device.rssi != 0 {
                            HStack {
                                Text("RSSI")
                                Spacer()
                                Text("\(app.device.rssi) dB").foregroundColor(.yellow)
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
                    }
                }


                if app.sensor != nil {

                    Section(header: Text("Sensor")) {

                        HStack {
                            Text("Status")
                            Spacer()
                            Text(app.sensor.state.description)
                                .foregroundColor(app.sensor.state == .active ? .green : .red)
                        }
                        HStack {
                            Text("Type")
                            Spacer()
                            Text("\(app.sensor.type.description)\(app.sensor.patchInfo.hex.hasPrefix("a2") ? " (new 'A2' kind)" : "")").foregroundColor(.yellow)
                        }
                        if app.sensor.serial != "" {
                            HStack {
                                Text("Serial")
                                Spacer()
                                Text(app.sensor.serial).foregroundColor(.yellow)
                            }
                        }
                        if app.sensor.region != 0 {
                            HStack {
                                Text("Region")
                                Spacer()
                                Text("\(SensorRegion(rawValue: app.sensor.region)?.description ?? "unknown")").foregroundColor(.yellow)
                            }
                        }
                        if app.sensor.maxLife > 0 {
                            HStack {
                                Text("Maximum Life")
                                Spacer()
                                Text(app.sensor.maxLife.formattedInterval).foregroundColor(.yellow)
                            }
                        }
                        if app.sensor.age > 0 {
                            HStack {
                                Text("Age")
                                Spacer()
                                Text(app.sensor.age.formattedInterval).foregroundColor(.yellow)
                            }
                            HStack {
                                Text("Started on")
                                Spacer()
                                Text("\((app.lastReadingDate - Double(app.sensor.age) * 60).shortDateTime)").foregroundColor(.yellow)
                            }
                        }
                        if !app.sensor.uid.isEmpty {
                            HStack {
                                Text("UID")
                                Spacer()
                                Text(app.sensor.uid.hex).foregroundColor(.yellow)
                            }
                        }
                        if !app.sensor.patchInfo.isEmpty {
                            HStack {
                                Text("Patch Info")
                                Spacer()
                                Text(app.sensor.patchInfo.hex).foregroundColor(.yellow)
                            }
                            HStack {
                                Text("Security Generation")
                                Spacer()
                                Text("\(app.sensor.securityGeneration)").foregroundColor(.yellow)
                            }
                        }

                    }
                }

                if app.device != nil && app.device.type == .transmitter(.abbott) || settings.preferredTransmitter == .abbott {

                    Section(header: Text("BLE Setup")) {

                        HStack {
                            Text("Patch Info")
                            TextField("Patch Info", value: $settings.activeSensorInitialPatchInfo, formatter: HexDataFormatter()).multilineTextAlignment(.trailing).foregroundColor(.blue)
                        }
                        // TODO: allow editing when a transmitter is not available
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
                                Section(header: Text("Calibration Info")) {
                                    HStack {
                                        Text("i1")
                                        TextField("i1", value: $settings.activeSensorCalibrationInfo.i1,
                                                  formatter: NumberFormatter()).multilineTextAlignment(.trailing).foregroundColor(.blue)
                                    }
                                    HStack {
                                        Text("i2")
                                        TextField("i2", value: $settings.activeSensorCalibrationInfo.i2,
                                                  formatter: NumberFormatter()).multilineTextAlignment(.trailing).foregroundColor(.blue)
                                    }
                                    HStack {
                                        Text("i3")
                                        TextField("i3", value: $settings.activeSensorCalibrationInfo.i3,
                                                  formatter: NumberFormatter()).multilineTextAlignment(.trailing).foregroundColor(.blue)
                                    }
                                    HStack {
                                        Text("i4")
                                        TextField("i4", value: $settings.activeSensorCalibrationInfo.i4,
                                                  formatter: NumberFormatter()).multilineTextAlignment(.trailing).foregroundColor(.blue)
                                    }
                                    HStack {
                                        Text("i5")
                                        TextField("i5", value: $settings.activeSensorCalibrationInfo.i5,
                                                  formatter: NumberFormatter()).multilineTextAlignment(.trailing).foregroundColor(.blue)
                                    }
                                    HStack {
                                        Text("i6")
                                        TextField("i6", value: $settings.activeSensorCalibrationInfo.i6,
                                                  formatter: NumberFormatter()).multilineTextAlignment(.trailing).foregroundColor(.blue)
                                    }
                                    HStack {
                                        Spacer()
                                        Button {
                                            showingCalibrationInfoForm = false
                                        } label: {
                                            Text("Set").bold().foregroundColor(Color.accentColor).padding(.horizontal, 4).padding(2).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor, lineWidth: 2))
                                        }.accentColor(.blue)
                                        Spacer()
                                    }
                                }
                            }
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Set") { showingCalibrationInfoForm = false }
                                }
                            }
                        }
                        HStack {
                            Text("Unlock Code")
                            TextField("Unlock Code", value: $settings.activeSensorStreamingUnlockCode, formatter: NumberFormatter()).multilineTextAlignment(.trailing).foregroundColor(.blue)
                        }
                        HStack {
                            Text("Unlock Count")
                            TextField("Unlock Count", value: $settings.activeSensorStreamingUnlockCount, formatter: NumberFormatter()).multilineTextAlignment(.trailing).foregroundColor(.blue)
                        }

                    }
                }

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

            HStack {

                Spacer()

                Button {
                    app.main.rescan()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise.circle").resizable().frame(width: 24, height: 24)
                            .foregroundColor(.blue)
                        Text(!app.deviceState.isEmpty && app.deviceState != "Disconnected" && (readingCountdown > 0 || app.deviceState == "Reconnecting...") ?
                                "\(readingCountdown) s" : "...")
                            .fixedSize()
                            .foregroundColor(.orange).font(Font.footnote.monospacedDigit())
                            .onReceive(timer) { _ in
                                // workaround: watchOS fails converting the interval to an Int32
                                if app.lastReadingDate == Date.distantPast {
                                    readingCountdown = 0
                                } else {
                                    readingCountdown = settings.readingInterval * 60 - Int(Date().timeIntervalSince(app.lastReadingDate))
                                }
                            }
                    }
                }

                Spacer()

                Button {
                    if app.device != nil {
                        app.main.centralManager.cancelPeripheralConnection(app.device.peripheral!)
                    }
                } label: {
                    Image(systemName: "escape").resizable().frame(width: 22, height: 22)
                        .foregroundColor(.blue)
                }

                Spacer()

            }
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationTitle("Details")
        .foregroundColor(Color(.lightGray))
        .buttonStyle(.plain)
    }
}


struct Details_Preview: PreviewProvider {
    static var previews: some View {
        Group {
            Details()
                .environmentObject(AppState.test(tab: .monitor))
                .environmentObject(Settings())
            NavigationView {
                Details()
                    .environmentObject(AppState.test(tab: .monitor))
                    .environmentObject(Settings())
            }
        }
    }
}
