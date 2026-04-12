import SwiftUI
import SyntaxEditorUI

@MainActor
struct ContentView: View {
    @State private var model = MiniContentViewModel(configuration: MiniLaunchConfiguration.current)

    var body: some View {
        NavigationSplitView {
            List(MiniPreviewPreset.all, id: \.id, selection: $model.selectedPresetID) { preset in
                NavigationLink(value: preset.id) {
                    Text(preset.title)
                }
                .accessibilityIdentifier(preset.accessibilityIdentifier)
            }
            .navigationTitle("Languages")
        } detail: {
            MiniEditorHostView(model: model.editorModel)
                .id(ObjectIdentifier(model.editorModel))
                .navigationTitle(model.currentPreset.title)
        }
    }
}

#Preview {
    ContentView()
}
