import SwiftUI
import SyntaxEditorUI

#if canImport(UIKit)
import UIKit

@MainActor
struct MiniEditorHostView: UIViewRepresentable {
    let model: SyntaxEditorModel
    private let launchConfiguration = MiniLaunchConfiguration.current

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SyntaxEditorView {
        let editorView = SyntaxEditorView(model: model)
        applyHorizontalScrollOffsetIfNeeded(to: editorView, coordinator: context.coordinator)
        return editorView
    }

    func updateUIView(_ uiView: SyntaxEditorView, context: Context) {
        applyHorizontalScrollOffsetIfNeeded(to: uiView, coordinator: context.coordinator)
    }

    private func applyHorizontalScrollOffsetIfNeeded(to editorView: SyntaxEditorView, coordinator: Coordinator) {
        guard launchConfiguration.appliesHorizontalScrollOffset else {
            coordinator.cancelHorizontalScrollOffset()
            return
        }

        coordinator.scheduleHorizontalScrollOffset(
            for: editorView,
            logsHorizontalLayout: isHorizontalLayoutDebugLoggingEnabled
        )
    }

    final class Coordinator {
        private var horizontalScrollOffsetTask: Task<Void, Never>?
        private weak var horizontalScrollOffsetEditorView: SyntaxEditorView?

        deinit {
            horizontalScrollOffsetTask?.cancel()
        }

        func cancelHorizontalScrollOffset() {
            horizontalScrollOffsetTask?.cancel()
            horizontalScrollOffsetTask = nil
            horizontalScrollOffsetEditorView = nil
        }

        func scheduleHorizontalScrollOffset(for editorView: SyntaxEditorView, logsHorizontalLayout: Bool) {
            if horizontalScrollOffsetTask != nil, horizontalScrollOffsetEditorView === editorView {
                return
            }

            horizontalScrollOffsetTask?.cancel()
            horizontalScrollOffsetEditorView = editorView
            horizontalScrollOffsetTask = Task { @MainActor [weak editorView] in
                var remainingAttempts = 4

                while true {
                    do {
                        try await Task.sleep(for: .milliseconds(100))
                    } catch {
                        return
                    }

                    guard !Task.isCancelled, let editorView else { return }

                    editorView.layoutIfNeeded()
                    let maximumOffsetX = max(0, editorView.contentSize.width - editorView.bounds.width)
                    Self.logHorizontalScrollProof(
                        "beforeOffset",
                        editorView: editorView,
                        maximumOffsetX: maximumOffsetX,
                        remainingAttempts: remainingAttempts,
                        logsHorizontalLayout: logsHorizontalLayout
                    )
                    if maximumOffsetX <= 0 {
                        if remainingAttempts > 0 {
                            remainingAttempts -= 1
                            continue
                        }
                        return
                    }

                    editorView.setContentOffset(
                        CGPoint(x: min(320, maximumOffsetX), y: editorView.contentOffset.y),
                        animated: false
                    )
                    editorView.layoutIfNeeded()
                    Self.logHorizontalScrollProof(
                        "afterOffset",
                        editorView: editorView,
                        maximumOffsetX: maximumOffsetX,
                        remainingAttempts: remainingAttempts,
                        logsHorizontalLayout: logsHorizontalLayout
                    )
                    return
                }
            }
        }

        private static func logHorizontalScrollProof(
            _ event: String,
            editorView: SyntaxEditorView,
            maximumOffsetX: CGFloat,
            remainingAttempts: Int,
            logsHorizontalLayout: Bool
        ) {
            guard logsHorizontalLayout else { return }

            NSLog(
                "%@",
                "SyntaxEditorUI.horizontalScrollProof event=\(event) bounds=\(editorView.bounds) contentSize=\(editorView.contentSize) contentOffset=\(editorView.contentOffset) textContainer=\(editorView.textContainer.size) maxOffsetX=\(maximumOffsetX) remainingAttempts=\(remainingAttempts)"
            )
        }
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
        SyntaxEditorView(model: model)
    }

    func updateNSView(_ nsView: SyntaxEditorView, context: Context) {
    }
}
#endif
