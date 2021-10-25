import SwiftUI


struct ContentView: View {

    @EnvironmentObject var app: AppState
    @EnvironmentObject var log: Log
    @EnvironmentObject var history: History
    @EnvironmentObject var settings: Settings

    @State var isMonitorActive = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: -4) {
                    HStack(spacing: 10) {
                        NavigationLink(destination: Monitor(), isActive: $isMonitorActive) {
                            VStack {
                                Image(systemName: "gauge").resizable().frame(width: 40, height: 40).offset(y: 4)
                                Text("Monitor").bold().foregroundColor(.blue)
                            }.frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        NavigationLink(destination: Details()) {
                            VStack {
                                Image(systemName: "info.circle").resizable().frame(width: 40, height: 40).offset(y: 4)
                                Text("Details").bold().foregroundColor(.blue).bold()
                            }.frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                    }
                    HStack(spacing: 10) {
                        NavigationLink(destination: Console()) {
                            VStack {
                                Image(systemName: "terminal").resizable().frame(width: 40, height: 40).offset(y: 4)
                                Text("Console").bold().foregroundColor(.blue)
                            }.frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        NavigationLink(destination: SettingsView()) {
                            VStack {
                                Image(systemName: "gear").resizable().frame(width: 40, height: 40).offset(y: 4)
                                Text("Settings").bold().tracking(-0.5).foregroundColor(.blue)
                            }.frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                    }
                    HStack(spacing: 10) {
                        NavigationLink(destination: DataView()) {
                            VStack {
                                Image(systemName: "tray.full.fill").resizable().frame(width: 40, height: 40).offset(y: 4)
                                Text("Data").bold().foregroundColor(.blue)
                            }.frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        NavigationLink(destination: OnlineView()) {
                            VStack {
                                Image(systemName: "globe").resizable().frame(width: 40, height: 40).offset(y: 4)
                                Text("Online").bold().foregroundColor(.blue)
                            }.frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                    }
                }
                .foregroundColor(.red)
                .buttonStyle(.plain)
            }
            .navigationTitle("DiaBLE  \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String)")
        }
        .edgesIgnoringSafeArea([.bottom])
    }
}

struct ContentView_Previews: PreviewProvider {

    static var previews: some View {
        Group {
            ContentView()
                .environmentObject(AppState.test(tab: .monitor))
                .environmentObject(Log())
                .environmentObject(History.test)
                .environmentObject(Settings())
        }
    }
}
