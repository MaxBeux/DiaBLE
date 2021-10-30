import Foundation
import SwiftUI


struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var history: History
    @EnvironmentObject var settings: Settings

    @State private var showingCalendarPicker = false


    var body: some View {

        VStack {

            HStack {
                Picker(selection: $settings.preferredTransmitter, label: Text("Preferred")) {
                    ForEach(TransmitterType.allCases) { t in
                        Text(t.name).tag(t)
                    }
                }
                .labelsHidden()

                TextField("device name pattern", text: $settings.preferredDevicePattern)
                    .frame(alignment: .center)
            }
            .frame(height: 20)
            .padding(.top, 57)
            .font(.footnote)
            .foregroundColor(.blue)

            HStack {
                Spacer()

                Button {
                    settings.usingOOP.toggle()
                    Task {
                        await app.main.applyOOP(sensor: app.sensor)
                        app.main.didParseSensor(app.sensor)
                    }
                } label: {
                    Image(systemName: settings.usingOOP ? "globe" : "wifi.slash").resizable().frame(width: 20, height: 20).foregroundColor(.blue)
                }

                Picker(selection: $settings.displayingMillimoles, label: Text("Unit")) {
                    ForEach(GlucoseUnit.allCases) { unit in
                        Text(unit.description).tag(unit == .mmoll)
                    }
                }
                .font(.footnote)
                .labelsHidden()
                .frame(width: 80, height: 20)

                Button {
                    settings.calibrating.toggle()
                    app.main.didParseSensor(app.sensor)
                } label: {
                    Image(systemName: settings.calibrating ? "tuningfork" : "tuningfork").resizable().frame(width: 20, height: 20).foregroundColor(settings.calibrating ? .blue : .primary)
                }

                Spacer()
            }

            VStack {
                VStack(spacing: 0) {
                    HStack(spacing: 20) {
                        Image(systemName: "hand.thumbsup.fill").foregroundColor(.green)
                            .offset(x: -10) // align to the bell
                        Text("\(settings.targetLow.units) - \(settings.targetHigh.units)").foregroundColor(.green)
                        Spacer().frame(width: 20)
                    }
                    HStack {
                        Slider(value: $settings.targetLow,  in: 40 ... 99, step: 1).frame(height: 20).scaleEffect(0.6)
                        Slider(value: $settings.targetHigh, in: 140 ... 300, step: 1).frame(height: 20).scaleEffect(0.6)
                    }
                }.accentColor(.green)

                VStack(spacing: 0) {
                    HStack(spacing: 20) {
                        Image(systemName: "bell.fill").foregroundColor(.red)
                        Text("< \(settings.alarmLow.units)   > \(settings.alarmHigh.units)").foregroundColor(.red)
                        Spacer().frame(width: 20)
                    }
                    HStack {
                        Slider(value: $settings.alarmLow,  in: 40 ... 99, step: 1).frame(height: 20).scaleEffect(0.6)
                        Slider(value: $settings.alarmHigh, in: 140 ... 300, step: 1).frame(height: 20).scaleEffect(0.6)
                    }
                }.accentColor(.red)
            }

            HStack {

                Spacer()

                HStack(spacing: 3) {
                    NavigationLink(destination: Monitor()) {
                        Image(systemName: "timer").resizable().frame(width: 20, height: 20)
                    }.simultaneousGesture(TapGesture().onEnded {
                        // app.selectedTab = (settings.preferredTransmitter != .none) ? .monitor : .log
                        app.main.rescan()
                    })

                    Picker(selection: $settings.readingInterval, label: Text("")) {
                        ForEach(Array(stride(from: 1,
                                             through: settings.preferredTransmitter == .miaomiao || (settings.preferredTransmitter == .none && app.transmitter != nil && app.transmitter.type == .transmitter(.miaomiao)) ? 5 :
                                                settings.preferredTransmitter == .abbott || (settings.preferredTransmitter == .none && app.transmitter != nil && app.transmitter.type == .transmitter(.abbott)) ? 1 : 15,
                                             by: settings.preferredTransmitter == .miaomiao || (settings.preferredTransmitter == .none && app.transmitter != nil && app.transmitter.type == .transmitter(.miaomiao)) ? 2 : 1)),
                                id: \.self) { t in
                            Text("\(t) min")
                        }
                    }.labelsHidden().frame(width: 60, height: 20)
                }.font(.footnote).foregroundColor(.orange)

                Spacer()

                Button {
                    settings.mutedAudio.toggle()
                } label: {
                    Image(systemName: settings.mutedAudio ? "speaker.slash.fill" : "speaker.2.fill").resizable().frame(width: 20, height: 20).foregroundColor(.blue)
                }

                Spacer()

                Button(action: {
                    settings.disabledNotifications.toggle()
                    if settings.disabledNotifications {
                        // UIApplication.shared.applicationIconBadgeNumber = 0
                    } else {
                        // UIApplication.shared.applicationIconBadgeNumber = settings.displayingMillimoles ?
                        //     Int(Float(app.currentGlucose.units)! * 10) : Int(app.currentGlucose.units)!
                    }
                }) {
                    Image(systemName: settings.disabledNotifications ? "zzz" : "app.badge.fill").resizable().frame(width: 20, height: 20).foregroundColor(.blue)
                }

                Spacer()
            }.padding(.top, 6)

        }
        .edgesIgnoringSafeArea([.top, .bottom])
        .navigationTitle("Settings")
        .font(Font.body.monospacedDigit())
        .buttonStyle(.plain)
    }
}


struct SettingsView_Previews: PreviewProvider {

    static var previews: some View {
        Group {
            SettingsView()
                .environmentObject(AppState.test(tab: .settings))
                .environmentObject(History.test)
                .environmentObject(Settings())
        }
    }
}
