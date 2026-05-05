import SwiftUI
import SyntaxEditorUI

#if canImport(UIKit)
import UIKit

@MainActor
struct MiniEditorHostView: UIViewRepresentable {
    let model: SyntaxEditorModel
    private let launchConfiguration = MiniLaunchConfiguration.current

    func makeUIView(context: Context) -> SyntaxEditorView {
        let editorView = SyntaxEditorView(model: model)
        editorView.textView.accessibilityIdentifier = "mini.editor"
        applyHorizontalScrollOffsetIfNeeded(to: editorView)
        return editorView
    }

    func updateUIView(_ uiView: SyntaxEditorView, context: Context) {
        uiView.textView.accessibilityIdentifier = "mini.editor"
        applyHorizontalScrollOffsetIfNeeded(to: uiView)
    }

    private func applyHorizontalScrollOffsetIfNeeded(to editorView: SyntaxEditorView, remainingAttempts: Int = 4) {
        guard launchConfiguration.appliesHorizontalScrollOffset else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak editorView] in
            guard let editorView else { return }

            editorView.layoutIfNeeded()
            let maximumOffsetX = max(0, editorView.contentSize.width - editorView.bounds.width)
            logHorizontalScrollProof(
                "beforeOffset",
                editorView: editorView,
                maximumOffsetX: maximumOffsetX,
                remainingAttempts: remainingAttempts
            )
            if maximumOffsetX <= 0 {
                if remainingAttempts > 0 {
                    applyHorizontalScrollOffsetIfNeeded(to: editorView, remainingAttempts: remainingAttempts - 1)
                }
                return
            }

            editorView.setContentOffset(
                CGPoint(x: min(320, maximumOffsetX), y: editorView.contentOffset.y),
                animated: false
            )
            editorView.layoutIfNeeded()
            logHorizontalScrollProof(
                "afterOffset",
                editorView: editorView,
                maximumOffsetX: maximumOffsetX,
                remainingAttempts: remainingAttempts
            )
        }
    }

    private func logHorizontalScrollProof(
        _ event: String,
        editorView: SyntaxEditorView,
        maximumOffsetX: CGFloat,
        remainingAttempts: Int
    ) {
        guard isHorizontalLayoutDebugLoggingEnabled else { return }

        NSLog(
            "%@",
            "SyntaxEditorUI.horizontalScrollProof event=\(event) bounds=\(editorView.bounds) contentSize=\(editorView.contentSize) contentOffset=\(editorView.contentOffset) textContainer=\(editorView.textContainer.size) maxOffsetX=\(maximumOffsetX) remainingAttempts=\(remainingAttempts)"
        )
    }

    private var isHorizontalLayoutDebugLoggingEnabled: Bool {
        switch ProcessInfo.processInfo.environment["SYNTAXEDITORUI_HORIZONTAL_LAYOUT_LOGS"] {
        case "1":
            return true
        default:
            return false
        }
    }
}
#elseif canImport(AppKit)
import AppKit

@MainActor
struct MiniEditorHostView: NSViewRepresentable {
    let model: SyntaxEditorModel

    func makeNSView(context: Context) -> SyntaxEditorView {
        let editorView = SyntaxEditorView(model: model)
        editorView.textView.setAccessibilityIdentifier("mini.editor")
        return editorView
    }

    func updateNSView(_ nsView: SyntaxEditorView, context: Context) {
        nsView.textView.setAccessibilityIdentifier("mini.editor")
    }
}
#endif
