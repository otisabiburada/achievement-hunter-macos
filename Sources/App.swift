import SwiftUI

@main
struct AchievementHunterApp: App {
    @StateObject private var state = AppState()
    
    var body: some Scene {
        WindowGroup("Achievement Hunter") {
            ContentView(state: state)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1140, height: 750)
        
        MenuBarExtra("Achievement Hunter", systemImage: "trophy.fill") {
            MenuBarView(state: state)
        }
        .menuBarExtraStyle(.window)
    }
}
