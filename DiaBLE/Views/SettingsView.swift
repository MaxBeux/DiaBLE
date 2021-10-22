import Foundation
import SwiftUI


struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: Settings

    @State private var showingCalendarPicker = false


    var body: some View {

        NavigationView {
            VStack {

                Spacer()

                VStack(spacing: 20) {
                    VStack {
                        HStack(spacing: 0) {
                            Button {
                            } label: {
                                Image("Bluetooth").renderingMode(.template).resizable().frame(width: 32, height: 32)
                            }
                            Picker(selection: $settings.preferredTransmitter, label: Text("Preferred")) {
                                ForEach(TransmitterType.allCases) { t in
                                    Text(t.name).tag(t)
                                }
                            }.pickerStyle(.segmented)
                        }
                        HStack(spacing: 0) {
                            Button {
                            } label: {
                                Image(systemName: "line.horizontal.3.decrease.circle").resizable().frame(width: 20, height: 20).padding(.leading, 6)
                            }
                            TextField("device name pattern", text: $settings.preferredDevicePattern)
                                .padding(.horizontal, 12)
                                .frame(alignment: .center)
                        }
                    }.foregroundColor(.accentColor)

                    NavigationLink(destination: Details()) {
                        Text("Details").bold().padding(.horizontal, 4).padding(2).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor, lineWidth: 2))
                    }
                }

                Spacer()

                HStack {
                    Stepper(value: $settings.readingInterval,
                            in: settings.preferredTransmitter == .miaomiao || (settings.preferredTransmitter == .none && app.transmitter != nil && app.transmitter.type == .transmitter(.miaomiao)) ?
                                1 ... 5 : settings.preferredTransmitter == .abbott || (settings.preferredTransmitter == .none && app.transmitter != nil && app.transmitter.type == .transmitter(.abbott)) ?
                                1 ... 1 : 1 ... 15,
                            step: settings.preferredTransmitter == .miaomiao || (settings.preferredTransmitter == .none && app.transmitter != nil && app.transmitter.type == .transmitter(.miaomiao)) ?
                                2 : 1,
                            label: {
                                Image(systemName: "timer").resizable().frame(width: 32, height: 32)
                                Text(" \(settings.readingInterval) min") })
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 80)

                Spacer()

                Button {
                    app.selectedTab = (settings.preferredTransmitter != .none) ? .monitor : .console
                    app.main.rescan()
                } label: {
                    Text("Rescan").bold().padding(.horizontal, 4).padding(2).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor, lineWidth: 2))
                }

                Spacer()

                VStack {

                    // TODO
                    HStack {
                        Spacer()
                        Picker(selection: $settings.displayingMillimoles, label: Text("Unit")) {
                            ForEach(GlucoseUnit.allCases) { unit in
                                Text(unit.description).tag(unit == .mmoll)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                        Spacer()
                    }.padding(.bottom)

                    VStack(spacing: 0) {
                        Image(systemName: "hand.thumbsup.fill").foregroundColor(.green).padding(4)
                        Text("\(settings.targetLow.units) - \(settings.targetHigh.units)").foregroundColor(.green)
                        HStack {
                            Slider(value: $settings.targetLow,  in: 40 ... 99, step: 1)
                            Slider(value: $settings.targetHigh, in: 140 ... 300, step: 1)
                        }
                    }.accentColor(.green)

                    VStack(spacing: 0) {
                        Image(systemName: "bell.fill").foregroundColor(.red).padding(4)
                        Text("< \(settings.alarmLow.units)   > \(settings.alarmHigh.units)").foregroundColor(.red)
                        HStack {
                            Slider(value: $settings.alarmLow,  in: 40 ... 99, step: 1)
                            Slider(value: $settings.alarmHigh, in: 140 ... 300, step: 1)
                        }
                    }.accentColor(.red)
                }.padding(.horizontal, 40)

                HStack(spacing: 24) {
                    Button {
                        settings.mutedAudio.toggle()
                    } label: {
                        Image(systemName: settings.mutedAudio ? "speaker.slash.fill" : "speaker.2.fill").resizable().frame(width: 24, height: 24).foregroundColor(.accentColor)
                    }

                    Button {
                        settings.disabledNotifications.toggle()
                        if settings.disabledNotifications {
                            UIApplication.shared.applicationIconBadgeNumber = 0
                        } else {
                            UIApplication.shared.applicationIconBadgeNumber = settings.displayingMillimoles ?
                                Int(Float(app.currentGlucose.units)! * 10) : Int(app.currentGlucose.units)!
                        }
                    } label: {
                        Image(systemName: settings.disabledNotifications ? "zzz" : "app.badge.fill").resizable().frame(width: 24, height: 24).foregroundColor(.accentColor)
                    }

                    Button {
                        showingCalendarPicker = true
                    } label: {
                        Image(systemName: settings.calendarTitle != "" ? "calendar.circle.fill" : "calendar.circle").resizable().frame(width: 32, height: 32).foregroundColor(.accentColor)
                    }
                    .popover(isPresented: $showingCalendarPicker, arrowEdge: .bottom) {
                        VStack {
                            Section {
                                Button {
                                    settings.calendarTitle = ""
                                    showingCalendarPicker = false
                                    app.main.eventKit?.sync()
                                } label: { Text("None").bold().padding(.horizontal, 4).padding(2).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor, lineWidth: 2)) }
                                .disabled(settings.calendarTitle == "")
                            }
                            Section {
                                Picker(selection: $settings.calendarTitle, label: Text("Calendar")) {
                                    ForEach([""] + (app.main.eventKit?.calendarTitles ?? [""]), id: \.self) { title in
                                        Text(title != "" ? title : "None")
                                    }
                                }
                                .pickerStyle(.wheel)
                            }
                            Section {
                                HStack {
                                    Image(systemName: "bell.fill").foregroundColor(.red).padding(8)
                                    Toggle("High / Low", isOn: $settings.calendarAlarmIsOn)
                                        .disabled(settings.calendarTitle == "")
                                }
                            }
                            Section {
                                Button {
                                    showingCalendarPicker = false
                                    app.main.eventKit?.sync()
                                } label: {
                                    Text(settings.calendarTitle == "" ? "Don't remind" : "Remind").bold().padding(.horizontal, 4).padding(2).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor, lineWidth: 2)).animation(.default, value: settings.calendarTitle)
                                }

                            }.padding(.top, 40)
                        }.padding(60)
                    }
                }.padding(.top, 16)

                Spacer()

            }
            .font(Font.body.monospacedDigit())
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("DiaBLE  \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String)  -  Settings")
        }.navigationViewStyle(.stack)
    }
}


struct SettingsView_Previews: PreviewProvider {

    static var previews: some View {
        Group {
            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(AppState.test(tab: .settings))
                .environmentObject(Log())
                .environmentObject(History.test)
                .environmentObject(Settings())
        }
    }
}
