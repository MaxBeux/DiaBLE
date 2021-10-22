import Foundation
import SwiftUI


struct Console: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var log: Log
    @EnvironmentObject var settings: Settings

    @State private var readingCountdown: Int = 0

    @State private var showingFilterField = false
    @State private var filterString = ""

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {

            if showingFilterField {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(Color(.lightGray))
                    TextField("Filter", text: $filterString)
                        .foregroundColor(.blue)
                    if filterString.count > 0 {
                        Button {
                            filterString = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .frame(maxWidth: 24)
                        .padding(0)
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                    }
                }
            }

            ScrollView(showsIndicators: true) {
                if filterString.isEmpty {
                    Text(log.text)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    Text(log.text.split(separator: "\n").filter({$0.lowercased().contains(filterString.lowercased()
                    )}).joined(separator: ("\n \n")) + "\n")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            // .font(.system(.footnote, design: .monospaced)).foregroundColor(Color(.lightGray))
            .font(.footnote).foregroundColor(Color(.lightGray))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { showingFilterField.toggle() }
                    } label: {
                        Image(systemName: filterString.isEmpty ? "line.horizontal.3.decrease.circle" : "line.horizontal.3.decrease.circle.fill").font(.title3)
                        Text("Filter")
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.blue)


            HStack(alignment: .center, spacing: 0) {

                VStack(spacing: 0) {

                    Button {
                        app.main.rescan()
                    } label: {
                        VStack {
                            Image("Bluetooth").renderingMode(.template).resizable().frame(width: 24, height: 24)
                        }
                    }
                }.foregroundColor(.blue)

                if (app.status.hasPrefix("Scanning") || app.status.hasSuffix("retrying...")) && app.main.centralManager.state != .poweredOff {
                    Button {
                        app.main.centralManager.stopScan()
                        app.main.status("Stopped scanning")
                        app.main.log("Bluetooth: stopped scanning")
                    } label: {
                        Image(systemName: "octagon").resizable().frame(width: 24, height: 24)
                            .overlay((Image(systemName: "hand.raised.fill").resizable().frame(width: 12, height: 12).offset(x: 1)))
                    }.foregroundColor(.red)

                } else if app.deviceState == "Connected" || app.deviceState == "Reconnecting..." || app.status.hasSuffix("retrying...") {
                    Button {
                        if app.device != nil {
                            app.main.centralManager.cancelPeripheralConnection(app.device.peripheral!)
                        }
                    } label: {
                        Image(systemName: "escape").resizable().padding(3).frame(width: 24, height: 24)
                            .foregroundColor(.blue)
                    }

                } else {
                    Image(systemName: "octagon").resizable().frame(width: 24, height: 24)
                        .hidden()
                }

                if !app.deviceState.isEmpty && app.deviceState != "Disconnected" {
                    VStack(spacing: 0) {
                        Text(readingCountdown > 0 || app.deviceState == "Reconnecting..." ?
                                "\(readingCountdown)" : " ")
                        Text(readingCountdown > 0 || app.deviceState == "Reconnecting..." ?
                                "s" : " ")
                    }
                    .font(Font.footnote.monospacedDigit()).foregroundColor(.orange)
                    .frame(width: 24, height: 24)
                    .fixedSize()
                    .onReceive(timer) { _ in
                        // workaround: watchOS fails converting the interval to an Int32
                        if app.lastReadingDate == Date.distantPast {
                            readingCountdown = 0
                        } else {
                            readingCountdown = settings.readingInterval * 60 - Int(Date().timeIntervalSince(app.lastReadingDate))
                        }
                    }
                } else {
                    Text(" ").font(Font.footnote.monospacedDigit()).frame(width: 24, height: 24).fixedSize().hidden()
                }

                Spacer()

                Button {
                    settings.debugLevel = 1 - settings.debugLevel
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5).fill(settings.debugLevel == 1 ? Color.blue : Color.clear)
                        Image(systemName: settings.debugLevel == 0 ? "wrench.fill" : "ladybug").resizable().frame(width: 22, height: 22).foregroundColor(settings.debugLevel == 1 ? .black : .blue)
                    }.frame(width: 24, height: 24)
                }

                //      Button {
                //          UIPasteboard.general.string = log.text
                //      } label: {
                //          VStack {
                //              Image(systemName: "doc.on.doc").resizable().frame(width: 24, height: 24)
                //              Text("Copy").offset(y: -6)
                //          }
                //      }

                Button {
                    DispatchQueue.main.async {
                        log.text = "Log cleared \(Date().local)\n"
                    }
                } label: {
                    VStack {
                        Image(systemName: "clear").resizable().foregroundColor(.blue).frame(width: 24, height: 24)
                    }
                }

                Button {
                    settings.reversedLog.toggle()
                    log.text = log.text.split(separator: "\n").reversed().joined(separator: "\n")
                    if !settings.reversedLog { log.text.append(" \n") }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5).fill(settings.reversedLog ? Color.blue : Color.clear)
                        RoundedRectangle(cornerRadius: 5).stroke(settings.reversedLog ? Color.clear : Color.blue, lineWidth: 2)
                        Image(systemName: "backward.fill").resizable().frame(width: 12, height: 12).foregroundColor(settings.reversedLog ? .black : .blue)
                    }.frame(width: 24, height: 24)
                }

                Button {
                    settings.logging.toggle()
                    app.main.log("\(settings.logging ? "Log started" : "Log stopped") \(Date().local)")
                } label: {
                    VStack {
                        Image(systemName: settings.logging ? "stop.circle" : "play.circle").resizable().frame(width: 24, height: 24).foregroundColor(settings.logging ? .red : .green)
                    }
                }

            }.font(.footnote)
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationTitle("Console")
    }
}


struct Console_Previews: PreviewProvider {

    static var previews: some View {
        Group {
            Console()
                .environmentObject(AppState.test(tab: .console))
                .environmentObject(Log())
                .environmentObject(Settings())
        }
    }
}
