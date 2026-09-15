#if canImport(UIKit)
import SyntaxEditorCore
import SyntaxEditorUICommon
import UIKit

@MainActor
extension SyntaxEditorView {
    public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if isUndoAction(action) {
            return model.isEditable && (activeUndoManager?.canUndo ?? false)
        }

        if isRedoAction(action) {
            return model.isEditable && (activeUndoManager?.canRedo ?? false)
        }

        if isLineWrappingCommandAction(action) {
            return true
        }

        if isFontSizeCommandAction(action) {
            return true
        }

        if action == #selector(handlePasteCommand) {
            return model.isEditable
        }

        if action == #selector(handleInsertTabCommand) {
            return model.isEditable
        }

        if isEditorCommandAction(action) {
            return model.isEditable && model.language.supportsCodeEditingCommands
        }

        switch action {
        case #selector(UIResponderStandardEditActions.useSelectionForFind(_:)):
            return isFindInteractionEnabled && findInteraction != nil && selectedRange.length > 0
        case #selector(UIResponderStandardEditActions.copy(_:)):
            return isSelectable && selectedRange.length > 0
        case #selector(UIResponderStandardEditActions.cut(_:)),
             #selector(UIResponderStandardEditActions.delete(_:)):
            return model.isEditable && selectedRange.length > 0
        case #selector(UIResponderStandardEditActions.paste(_:)):
            return model.isEditable && UIPasteboard.general.hasStrings
        case #selector(UIResponderStandardEditActions.selectAll(_:)):
            return isSelectable && !text.isEmpty
        default:
            if isFindAndReplaceCommandAction(action) {
                return model.isEditable && isFindInteractionEnabled && findInteraction != nil
            }
            if isFindCommandAction(action) {
                return isFindInteractionEnabled && findInteraction != nil
            }
            return super.canPerformAction(action, withSender: sender)
        }
    }

    public override func validate(_ command: UICommand) {
        super.validate(command)

        guard let editorCommand = SyntaxEditorMenu.Command(selector: command.action) else {
            return
        }

        command.attributes = canPerformAction(command.action, withSender: command) ? [] : .disabled
        command.state = editorCommand == .wrapLines && model.lineWrappingEnabled ? .on : .off
    }

    /// Copies the selected text to the general pasteboard.
    ///
    /// This responder-chain action also works in a read-only editor. An empty
    /// selection leaves the pasteboard unchanged.
    ///
    /// - Parameter sender: The object requesting the action, or `nil`.
    public override func copy(_ sender: Any?) {
        guard selectedRange.length > 0,
              let selectedText = string(in: selectedRange)
        else {
            return
        }
        UIPasteboard.general.string = selectedText
    }

    /// Copies the selected text to the general pasteboard, then deletes it.
    ///
    /// This responder-chain action has no effect when ``isEditable`` is `false`
    /// or the selection is empty.
    ///
    /// - Parameter sender: The object requesting the action, or `nil`.
    public override func cut(_ sender: Any?) {
        guard model.isEditable, selectedRange.length > 0 else { return }
        copy(sender)
        applyUserReplacement(in: selectedRange, replacement: "", deletionIntent: .unspecified)
    }

    /// Inserts the general pasteboard's string using the editor's text-input rules.
    ///
    /// This responder-chain action replaces active marked text, or the selection
    /// when there is no composition. It has no effect when ``isEditable`` is
    /// `false` or the pasteboard has no string.
    ///
    /// - Parameter sender: The object requesting the action, or `nil`.
    public override func paste(_ sender: Any?) {
        guard model.isEditable,
              let pastedText = UIPasteboard.general.string
        else {
            return
        }
        insertPastedText(pastedText)
    }

    func insertPastedText(_ pastedText: String) {
        guard model.isEditable else { return }
        insertText(pastedText)
    }

    /// Deletes the selection, or deletes backward when the selection is empty.
    ///
    /// Calling this responder-chain action has no effect when ``isEditable``
    /// is `false`. At an insertion point it uses the same deletion behavior as
    /// the Backspace key, including code-aware pair deletion.
    ///
    /// - Parameter sender: The object requesting the action, or `nil`.
    public override func delete(_ sender: Any?) {
        guard model.isEditable else { return }
        if selectedRange.length > 0 {
            applyUserReplacement(in: selectedRange, replacement: "", deletionIntent: .unspecified)
        } else {
            deleteBackward()
        }
    }

    /// Selects the whole document through the responder chain.
    ///
    /// This action also works in a read-only editor, but has no effect when
    /// ``isSelectable`` is `false`.
    ///
    /// - Parameter sender: The object requesting the action, or `nil`.
    public override func selectAll(_ sender: Any?) {
        guard isSelectable else { return }
        selectedRange = NSRange(location: 0, length: text.utf16.count)
    }

    /// Presents the native find interface without replacement controls.
    ///
    /// This responder-chain action also works in a read-only editor. It has no
    /// effect when ``findInteraction`` is `nil`.
    ///
    /// - Parameter sender: The object requesting the action, or `nil`.
    public override func find(_ sender: Any?) {
        findInteraction?.presentFindNavigator(showingReplace: false)
    }

    /// Presents the native find interface with replacement controls.
    ///
    /// This responder-chain action has no effect when ``isEditable`` is `false`
    /// or ``findInteraction`` is `nil`.
    ///
    /// - Parameter sender: The object requesting the action, or `nil`.
    public override func findAndReplace(_ sender: Any?) {
        guard model.isEditable else { return }
        findInteraction?.presentFindNavigator(showingReplace: true)
    }

    /// Asks the native find interaction to advance to the next match.
    ///
    /// This responder-chain action has no effect when ``findInteraction`` is `nil`.
    ///
    /// - Parameter sender: The object requesting the action, or `nil`.
    public override func findNext(_ sender: Any?) {
        findInteraction?.findNext()
    }

    /// Asks the native find interaction to move to the previous match.
    ///
    /// This responder-chain action has no effect when ``findInteraction`` is `nil`.
    ///
    /// - Parameter sender: The object requesting the action, or `nil`.
    public override func findPrevious(_ sender: Any?) {
        findInteraction?.findPrevious()
    }

    /// Uses the selected text as the query and presents the native find interface.
    ///
    /// This responder-chain action also works in a read-only editor. It has no
    /// effect when the selection is empty or ``findInteraction`` is `nil`.
    ///
    /// - Parameter sender: The object requesting the action, or `nil`.
    public override func useSelectionForFind(_ sender: Any?) {
        guard selectedRange.length > 0,
              let selectedText = string(in: selectedRange)
        else {
            return
        }
        findInteraction?.searchText = selectedText
        findInteraction?.presentFindNavigator(showingReplace: false)
    }

    @objc private func undo(_ sender: Any?) {
        handleUndoCommand()
    }

    @objc private func redo(_ sender: Any?) {
        handleRedoCommand()
    }

    func configureUndoObservation() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleUndoManagerStateDidChange),
            name: .NSUndoManagerDidCloseUndoGroup,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleUndoManagerStateDidChange),
            name: .NSUndoManagerDidUndoChange,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleUndoManagerStateDidChange),
            name: .NSUndoManagerDidRedoChange,
            object: nil
        )
    }

    @objc
    func handleUndoManagerStateDidChange(_ notification: Notification) {
        guard notification.object as AnyObject? === guardedUndoManager else { return }
        refreshKeyboardAccessoryState()
    }

    func editorKeyCommands() -> [UIKeyCommand]? {
        let supportsCodeEditingCommands = model.isEditable && model.language.supportsCodeEditingCommands
        var commands = SyntaxEditorMenu.makeKeyCommands(includeEditingCommands: supportsCodeEditingCommands)

        guard model.isEditable else {
            return commands
        }

        commands.append(
            makeKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleInsertTabCommand), title: "Insert Tab")
        )

        if supportsCodeEditingCommands {
            commands.append(
                makeKeyCommand(input: "\t", modifierFlags: [.shift], action: #selector(handleOutdentCommand), title: "Outdent")
            )
        }

        commands.append(contentsOf: [
            makeKeyCommand(
                input: "v",
                modifierFlags: [.command],
                action: #selector(handlePasteCommand),
                title: "Paste"
            ),
        ])
        return commands
    }

    func isEditorCommandAction(_ action: Selector) -> Bool {
        if let command = SyntaxEditorMenu.Command(selector: action) {
            return command.isEditingCommand
        }

        return action == #selector(handleInsertTabCommand)
            || action == #selector(handleOutdentCommand)
    }

    func isLineWrappingCommandAction(_ action: Selector) -> Bool {
        SyntaxEditorMenu.Command(selector: action) == .wrapLines
    }

    func isFontSizeCommandAction(_ action: Selector) -> Bool {
        switch SyntaxEditorMenu.Command(selector: action) {
        case .increaseFontSize, .decreaseFontSize, .resetFontSize:
            true
        case .shiftRight, .shiftLeft, .commentSelection, .wrapLines, nil:
            false
        }
    }

    func isFindCommandAction(_ action: Selector) -> Bool {
        action == #selector(UIResponderStandardEditActions.find(_:))
            || action == #selector(UIResponderStandardEditActions.findNext(_:))
            || action == #selector(UIResponderStandardEditActions.findPrevious(_:))
    }

    func isFindAndReplaceCommandAction(_ action: Selector) -> Bool {
        action == #selector(UIResponderStandardEditActions.findAndReplace(_:))
    }

    func isUndoAction(_ action: Selector) -> Bool {
        NSStringFromSelector(action) == "undo:"
    }

    func isRedoAction(_ action: Selector) -> Bool {
        let actionName = NSStringFromSelector(action)
        return actionName == "redo:"
    }

    func makeKeyCommand(
        input: String,
        modifierFlags: UIKeyModifierFlags,
        action: Selector,
        title: String
    ) -> UIKeyCommand {
        let command = UIKeyCommand(input: input, modifierFlags: modifierFlags, action: action)
        command.discoverabilityTitle = title
        command.wantsPriorityOverSystemBehavior = true
        return command
    }

    #if !os(visionOS)
    func makeInputAccessoryView() -> UIView {
        let accessoryModel = SyntaxEditorKeyboardAccessoryModel(
            onUndo: { [weak self] in
                self?.handleUndoCommand()
            },
            onRedo: { [weak self] in
                self?.handleRedoCommand()
            },
            onDismissKeyboard: { [weak self] in
                self?.handleDismissKeyboardCommand()
            }
        )
        keyboardAccessoryModel = accessoryModel
        return SyntaxEditorKeyboardAccessoryView(model: accessoryModel)
    }
    #endif

    var activeUndoManager: UndoManager? {
        guardedUndoManager
    }

    func refreshKeyboardAccessoryState() {
        #if !os(visionOS)
        guard let keyboardAccessoryModel else { return }
        keyboardAccessoryModel.isUndoable = model.isEditable && (activeUndoManager?.canUndo ?? false)
        keyboardAccessoryModel.isRedoable = model.isEditable && (activeUndoManager?.canRedo ?? false)
        #endif
    }
    /// Indents the selected lines, or the current line at an insertion point.
    ///
    /// The Editor menu routes this action through the responder chain. It has
    /// no effect when editing is disabled or the language is plain text.
    ///
    /// - Parameter sender: The object requesting the action, or `nil`.
    @objc public func syntaxEditorShiftRight(_ sender: Any?) {
        handleIndentCommand()
    }

    /// Removes one level of indentation from the selected lines or current line.
    ///
    /// The Editor menu routes this action through the responder chain. It has
    /// no effect when editing is disabled, the language is plain text, or the
    /// affected lines have no removable indentation.
    ///
    /// - Parameter sender: The object requesting the action, or `nil`.
    @objc public func syntaxEditorShiftLeft(_ sender: Any?) {
        handleOutdentCommand()
    }

    /// Toggles comments using the current language's rules for the selection.
    ///
    /// The Editor menu routes this action through the responder chain. It has
    /// no effect when editing is disabled or the language cannot toggle a
    /// comment at the current selection.
    ///
    /// - Parameter sender: The object requesting the action, or `nil`.
    @objc public func syntaxEditorCommentSelection(_ sender: Any?) {
        handleToggleCommentCommand()
    }

    /// Toggles the model's line-wrapping setting from the Editor menu.
    ///
    /// This responder-chain action remains available in a read-only editor.
    ///
    /// - Parameter sender: The object requesting the action, or `nil`.
    @objc public func syntaxEditorToggleLineWrapping(_ sender: Any?) {
        handleToggleLineWrappingCommand()
    }

    /// Invokes the model's font-size increase command from the Editor menu.
    ///
    /// This responder-chain action remains available in a read-only editor.
    /// The model applies the supported font-size limits.
    ///
    /// - Parameter sender: The object requesting the action, or `nil`.
    @objc public func syntaxEditorIncreaseFontSize(_ sender: Any?) {
        handleIncreaseFontSizeCommand()
    }

    /// Invokes the model's font-size decrease command from the Editor menu.
    ///
    /// This responder-chain action remains available in a read-only editor.
    /// The model applies the supported font-size limits.
    ///
    /// - Parameter sender: The object requesting the action, or `nil`.
    @objc public func syntaxEditorDecreaseFontSize(_ sender: Any?) {
        handleDecreaseFontSizeCommand()
    }

    /// Resets the model's font-size adjustment to zero from the Editor menu.
    ///
    /// This restores the selected theme's font sizes. The responder-chain
    /// action remains available in a read-only editor.
    ///
    /// - Parameter sender: The object requesting the action, or `nil`.
    @objc public func syntaxEditorResetFontSize(_ sender: Any?) {
        handleResetFontSizeCommand()
    }

    @objc private func handleIndentCommand() {
        guard model.isEditable, model.language.supportsCodeEditingCommands else { return }

        guard let result = commandEngine.indentSelection(
            source: text,
            selection: selectedRange,
            language: model.language
        ) else {
            return
        }
        applyCommandResult(result)
    }

    @objc private func handleInsertTabCommand() {
        guard model.isEditable else { return }

        guard model.language.supportsCodeEditingCommands else {
            insertText("\t")
            return
        }

        guard let result = commandEngine.insertTab(
            source: text,
            selection: selectedRange,
            language: model.language
        ) else {
            return
        }
        applyCommandResult(result)
    }

    @objc private func handleOutdentCommand() {
        guard model.isEditable, model.language.supportsCodeEditingCommands else { return }

        guard let result = commandEngine.outdentSelection(
            source: text,
            selection: selectedRange,
            language: model.language
        ) else {
            return
        }
        applyCommandResult(result)
    }

    @objc private func handleToggleCommentCommand() {
        guard model.isEditable, model.language.supportsCodeEditingCommands else { return }

        guard let result = commandEngine.toggleComment(
            source: text,
            selection: selectedRange,
            language: model.language
        ) else {
            return
        }
        applyCommandResult(result)
    }

    @objc private func handlePasteCommand() {
        paste(nil)
    }

    @objc private func handleToggleLineWrappingCommand() {
        model.lineWrappingEnabled.toggle()
    }

    @objc private func handleIncreaseFontSizeCommand() {
        model.increaseFontSize()
    }

    @objc private func handleDecreaseFontSizeCommand() {
        model.decreaseFontSize()
    }

    @objc private func handleResetFontSizeCommand() {
        model.resetFontSize()
    }

    @objc private func handleUndoCommand() {
        guard model.isEditable else {
            refreshKeyboardAccessoryState()
            return
        }

        activeUndoManager?.undo()
        refreshKeyboardAccessoryState()
    }

    @objc private func handleRedoCommand() {
        guard model.isEditable else {
            refreshKeyboardAccessoryState()
            return
        }

        activeUndoManager?.redo()
        refreshKeyboardAccessoryState()
    }

    @objc private func handleDismissKeyboardCommand() {
        window?.endEditing(true)
    }
}
#endif
