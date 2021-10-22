import SwiftUI


struct ContentView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var log: Log
    @EnvironmentObject var history: History
    @EnvironmentObject var settings: Settings

    var body: some View {

        TabView(selection: $app.selectedTab) {
            Monitor()
                .tabItem {
                    Image(systemName: "gauge")
                    Text("Monitor")
            }.tag(Tab.monitor)

            OnlineView()
                .tabItem {
                    Image(systemName: "globe")
                    Text("Online")
            }.tag(Tab.online)

            ConsoleTab()
                .tabItem {
                    Image(systemName: "terminal")
                    Text("Console")
            }.tag(Tab.console)

            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
            }.tag(Tab.settings)

            DataView()
                .tabItem {
                    Image(systemName: "tray.full.fill")
                    Text("Data")
            }.tag(Tab.data)

//            Plan()
//                .tabItem {
//                    Image(systemName: "map")
//                    Text("Plan")
//            }.tag(Tab.plan)

        }
    }
}


struct ContentView_Previews: PreviewProvider {

    static var previews: some View {

        Group {
            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(AppState.test(tab: .monitor))
                .environmentObject(Log())
                .environmentObject(History.test)
                .environmentObject(Settings())

            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(AppState.test(tab: .online))
                .environmentObject(Log())
                .environmentObject(History.test)
                .environmentObject(Settings())

            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(AppState.test(tab: .data))
                .environmentObject(Log())
                .environmentObject(History.test)
                .environmentObject(Settings())

            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(AppState.test(tab: .console))
                .environmentObject(Log())
                .environmentObject(History.test)
                .environmentObject(Settings())

            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(AppState.test(tab: .settings))
                .environmentObject(Log())
                .environmentObject(History.test)
                .environmentObject(Settings())
        }
    }
}
