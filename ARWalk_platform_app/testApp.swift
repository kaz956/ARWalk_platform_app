import SwiftUI

@main
struct testApp: App {
    @StateObject var panelModel = PanelModel()
    @StateObject var experimentManager = ExperimentTaskManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(panelModel)
                .environmentObject(experimentManager)
        }
        .defaultSize(width: 800, height: 1000)
        
        ImmersiveSpace(id: "ImmersiveHUD") {
            HUDImmersiveView()
                .environmentObject(panelModel)  // 同じ共有モデルを渡す
                .environmentObject(experimentManager)
        }
    }
}
