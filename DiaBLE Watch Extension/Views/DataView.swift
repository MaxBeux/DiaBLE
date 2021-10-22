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
        ScrollView {

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
                    // .font(Font.caption.monospacedDigit())
                    .foregroundColor(.orange)
                    .onReceive(timer) { _ in
                        // workaround: watchOS fails converting the interval to an Int32
                        if app.lastReadingDate == Date.distantPast {
                            readingCountdown = 0
                        } else {
                            readingCountdown = settings.readingInterval * 60 - Int(Date().timeIntervalSince(app.lastReadingDate))
                        }
                    }
            }


            HStack {

                VStack {

                    if history.factoryTrend.count > 0 {
                        VStack(spacing: 4) {
                            Text("Trend").bold()
                            ScrollView {
                                ForEach(history.factoryTrend) { glucose in
                                    (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                                }
                            }.frame(maxWidth: .infinity, alignment: .topLeading)
                        }.foregroundColor(.orange)
                    }

                }

                VStack {

                    if history.rawTrend.count > 0 {
                        VStack(spacing: 4) {
                            Text("Raw trend").bold()
                            ScrollView {
                                ForEach(history.rawTrend) { glucose in
                                    (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                                }
                            }.frame(maxWidth: .infinity, alignment: .topLeading)
                        }.foregroundColor(.yellow)
                    }

                }
            }.frame(idealHeight: 300)


            HStack(spacing: 0) {

                if history.storedValues.count > 0 {
                    VStack(spacing: 0) {
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
                    VStack(spacing: 0) {
                        Text("Nightscout").bold()
                        List {
                            ForEach(history.nightscoutValues) { glucose in
                                (Text("\(String(glucose.source[..<(glucose.source.lastIndex(of: " ") ?? glucose.source.endIndex)])) \(glucose.date.shortDateTime)") + Text("  \(glucose.value, specifier: "%3d")").bold())
                                    .fixedSize(horizontal: false, vertical: true).listRowInsets(EdgeInsets())
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                    .foregroundColor(.cyan)
                    .onAppear { if let nightscout = app.main?.nightscout { nightscout.read() } }
                }
            }.frame(idealHeight: 300)


            HStack {

                if history.calibratedValues.count > 0 {
                    VStack(spacing: 4) {
                        Text("Calibrated history").bold()
                        ScrollView {
                            ForEach(history.calibratedValues) { glucose in
                                (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                            }
                        }.frame(maxWidth: .infinity, alignment: .topLeading)
                    }.foregroundColor(.purple)
                }

                if history.calibratedTrend.count > 0 {
                    VStack(spacing: 4) {
                        Text("Calibrated trend").bold()
                        ScrollView {
                            ForEach(history.calibratedTrend) { glucose in
                                (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                            }
                        }.frame(maxWidth: .infinity, alignment: .topLeading)
                    }.foregroundColor(.purple)
                }
            }.frame(idealHeight: 200)


            HStack {

                VStack {

                    if history.values.count > 0 {
                        VStack(spacing: 4) {
                            Text("OOP history").bold()
                            ScrollView {
                                ForEach(history.values) { glucose in
                                    (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                                }
                            }.frame(maxWidth: .infinity, alignment: .topLeading)
                        }.foregroundColor(.blue)
                    }

                    if history.factoryValues.count > 0 {
                        VStack(spacing: 4) {
                            Text("History").bold()
                            ScrollView {
                                ForEach(history.factoryValues) { glucose in
                                    (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
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
                                (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                            }
                        }.frame(maxWidth: .infinity, alignment: .topLeading)
                    }.foregroundColor(.yellow)
                }
            }.frame(idealHeight: 200)

        }
        .navigationTitle("Data")
        .edgesIgnoringSafeArea([.bottom])
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // .font(.system(.footnote, design: .monospaced)).foregroundColor(Color(.lightGray))
        .font(.footnote).foregroundColor(Color(.lightGray))
    }
}


struct DataView_Previews: PreviewProvider {

    static var previews: some View {
        Group {
            DataView()
                .environmentObject(AppState.test(tab: .data))
                .environmentObject(History.test)
                .environmentObject(Log())
                .environmentObject(Settings())
        }
    }
}
