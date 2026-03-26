import SwiftUI
import SyntaxEditorUI

struct ContentView: View {
    @State private var model: SyntaxEditorModel?

    var body: some View {
        if let model {
            MiniEditorHostView(model: model)
        } else {
            Color.clear
                .onAppear {
                    model = SyntaxEditorModel(configuration: .current)
                }
        }
    }
}

#Preview {
    ContentView()
}
