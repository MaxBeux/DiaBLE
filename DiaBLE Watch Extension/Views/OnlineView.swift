import Foundation
import SwiftUI


struct OnlineView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var history: History
    @EnvironmentObject var settings: Settings

    @State private var readingCountdown: Int = 0

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()


    var body: some View {
        VStack {
            VStack(spacing: 0) {
                HStack {
                    Image("Nightscout").resizable().frame(width: 24, height: 24).shadow(color: .cyan, radius: 4.0 )
                    Text("https://").foregroundColor(Color(.lightGray))
                    Spacer()
                    Text("token").foregroundColor(Color(.lightGray))

                    VStack(spacing: 0) {

                        Button {
                            app.main.rescan()
                        } label: {
                                Image(systemName: "arrow.clockwise.circle").resizable().frame(width: 16, height: 16)
                                    .foregroundColor(.blue)
                                Text(app.deviceState != "Disconnected" && (readingCountdown > 0 || app.deviceState == "Reconnecting...") ?
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
                }

                HStack {
                    TextField("Nightscout URL", text: $settings.nightscoutSite)
                        .textContentType(.URL)
                    SecureField("token", text: $settings.nightscoutToken)
                }

            }.font(.footnote)

            List {
                ForEach(history.nightscoutValues) { glucose in
                    (Text("\(String(glucose.source[..<(glucose.source.lastIndex(of: " ") ?? glucose.source.endIndex)])) \(glucose.date.shortDateTime)") + Text("  \(glucose.value, specifier: "%3d")").bold())
                        .fixedSize(horizontal: false, vertical: true).listRowInsets(EdgeInsets())
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            // .font(.system(.footnote, design: .monospaced))
            .foregroundColor(.cyan)
            .onAppear { if let nightscout = app.main?.nightscout { nightscout.read()
                app.main.log("nightscoutValues count \(history.nightscoutValues.count)")

            } }
        }
        .navigationTitle("Online")
        .edgesIgnoringSafeArea([.bottom])
        .buttonStyle(.plain)
        .foregroundColor(.cyan)

    }
}


struct OnlineView_Previews: PreviewProvider {

    static var previews: some View {
        Group {
            OnlineView()
                .environmentObject(AppState.test(tab: .online))
                .environmentObject(History.test)
                .environmentObject(Settings())
        }
    }
}
