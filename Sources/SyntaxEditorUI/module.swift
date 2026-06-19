@_exported import SyntaxEditorCore
@_exported import SyntaxEditorUICommon
@_exported import SyntaxEditorUISwiftUI

#if os(macOS)
@_exported import SyntaxEditorUIAppKit
#endif

#if os(iOS) || targetEnvironment(macCatalyst) || os(visionOS)
@_exported import SyntaxEditorUIUIKit
#endif
