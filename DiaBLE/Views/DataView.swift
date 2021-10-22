import Foundation
import SwiftUI


struct DataView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var history: History
    @EnvironmentObject var log: Log
    @EnvironmentObject var settings: Settings

    @State private var readingCountdown: Int = 0

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()


    var body: some View {
        NavigationView {
            VStack {

                Text("\((app.lastReadingDate != Date.distantPast ? app.lastReadingDate : Date()).dateTime)")
                    .foregroundColor(.white)

                if app.status.hasPrefix("Scanning") {
                    Text("Scanning...").foregroundColor(.orange)
                } else if !app.deviceState.isEmpty && app.deviceState != "Connected" {
                    Text(app.deviceState).foregroundColor(.red)
                } else {
                    Text(readingCountdown > 0 || app.deviceState == "Reconnecting..." ?
                            "\(readingCountdown) s" : "")
                        .fixedSize()
                        .font(Font.caption.monospacedDigit()).foregroundColor(.orange)
                        .onReceive(timer) { _ in
                            readingCountdown = settings.readingInterval * 60 - Int(Date().timeIntervalSince(app.lastReadingDate))
                        }
                }

                VStack {

                    HStack {

                        VStack {

                            if history.values.count > 0 {
                                VStack(spacing: 4) {
                                    Text("OOP history").bold()
                                    ScrollView {
                                        ForEach(history.values) { glucose in
                                            (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold())
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                                }.foregroundColor(.blue)
                            }

                            if history.factoryValues.count > 0 {
                                VStack(spacing: 4) {
                                    Text("History").bold()
                                    ScrollView {
                                        ForEach(history.factoryValues) { glucose in
                                            (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold())
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                                }.foregroundColor(.orange)
                            }

                        }

                        if history.rawValues.count > 0 {
                            VStack(spacing: 4) {
                                Text("Raw history").bold()
                                ScrollView {
                                    ForEach(history.rawValues) { glucose in
                                        (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold())
                                    }
                                }.frame(maxWidth: .infinity, alignment: .topLeading)
                            }.foregroundColor(.yellow)
                        }
                    }

                    HStack {

                        VStack {

                            if history.factoryTrend.count > 0 {
                                VStack(spacing: 4) {
                                    Text("Trend").bold()
                                    ScrollView {
                                        ForEach(history.factoryTrend) { glucose in
                                            (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold())
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                                }.foregroundColor(.orange)
                            }

                            if history.calibratedValues.count > 0 {
                                VStack(spacing: 4) {
                                    Text("Calibrated history").bold()
                                    ScrollView {
                                        ForEach(history.calibratedValues) { glucose in
                                            (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold())
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                                }.foregroundColor(.purple)
                            }

                        }

                        VStack {

                            if history.rawTrend.count > 0 {
                                VStack(spacing: 4) {
                                    Text("Raw trend").bold()
                                    ScrollView {
                                        ForEach(history.rawTrend) { glucose in
                                            (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold())
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                                }.foregroundColor(.yellow)
                            }

                            if history.calibratedTrend.count > 0 {
                                VStack(spacing: 4) {
                                    Text("Calibrated trend").bold()
                                    ScrollView {
                                        ForEach(history.calibratedTrend) { glucose in
                                            (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold())
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                                }.foregroundColor(.purple)
                            }

                        }
                    }

                    HStack(spacing: 0) {

                        if history.storedValues.count > 0 {
                            VStack(spacing: 4) {
                                Text("HealthKit").bold()
                                List {
                                    ForEach(history.storedValues) { glucose in
                                        (Text("\(String(glucose.source[..<(glucose.source.lastIndex(of: " ") ?? glucose.source.endIndex)])) \(glucose.date.shortDateTime)") + Text("  \(glucose.value, specifier: "%3d")").bold())
                                            .fixedSize(horizontal: false, vertical: true).listRowInsets(EdgeInsets()).listRowInsets(EdgeInsets())
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }.foregroundColor(.red)
                            .onAppear { if let healthKit = app.main?.healthKit { healthKit.read() } }
                        }

                        if history.nightscoutValues.count > 0 {
                            VStack(spacing: 4) {
                                Text("Nightscout").bold()
                                List {
                                    ForEach(history.nightscoutValues) { glucose in
                                        (Text("\(String(glucose.source[..<(glucose.source.lastIndex(of: " ") ?? glucose.source.endIndex)])) \(glucose.date.shortDateTime)") + Text("  \(glucose.value, specifier: "%3d")").bold())
                                            .fixedSize(horizontal: false, vertical: true).listRowInsets(EdgeInsets())
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                            }.foregroundColor(.cyan)
                            .onAppear { if let nightscout = app.main?.nightscout { nightscout.read() } }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .font(.system(.caption, design: .monospaced)).foregroundColor(Color(.lightGray))
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Data")

        }.navigationViewStyle(.stack)
    }
}


struct DataView_Previews: PreviewProvider {

    static var previews: some View {
        Group {
            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(AppState.test(tab: .data))
                .environmentObject(Log())
                .environmentObject(History.test)
                .environmentObject(Settings())
        }
    }
}
