import SwiftUI

struct ContentView: View {
    var body: some View {
        ExperimentView()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environmentObject(PanelModel())
        .environmentObject(ExperimentTaskManager())
}
