#if canImport(AppKit)
import AppKit

/// Emacs's kill ring: recent kills, newest first, that `C-y` yanks back and
/// `M-y` cycles through. A plain value so its rules are testable without a
/// pasteboard; `KillRing` wraps it with the clipboard sync.
struct KillRingEntries: Equatable {
    /// Emacs's `kill-ring-max`.
    static let capacity = 120
    private(set) var entries: [String] = []
    /// The entry `C-y` yanks: back to the newest on every kill, stepped
    /// older by `M-y`.
    private(set) var yankIndex = 0

    /// Record `text` as a kill. A `continuing` kill — straight after another,
    /// nothing edited in between — extends the newest entry instead, appended
    /// or (for a backward kill) prepended, so repeated `C-k` gathers several
    /// lines into one entry, as in emacs.
    mutating func kill(_ text: String, continuing: Bool, backward: Bool) {
        if continuing, let newest = entries.first {
            entries[0] = backward ? text + newest : newest + text
        } else {
            entries.insert(text, at: 0)
            if entries.count > Self.capacity {
                entries.removeLast(entries.count - Self.capacity)
            }
        }
        yankIndex = 0
    }

    var yankText: String? { entries.isEmpty ? nil : entries[yankIndex] }

    /// Step `C-y`'s choice one entry older, wrapping round to the newest.
    mutating func rotate() -> String? {
        guard !entries.isEmpty else { return nil }
        yankIndex = (yankIndex + 1) % entries.count
        return entries[yankIndex]
    }
}

/// The one kill ring every editor shares, as emacs has one per session. Kept
/// in step with the system clipboard like emacs's `select-enable-clipboard`:
/// a kill goes on the clipboard too, and text copied elsewhere since becomes
/// the newest entry before the next yank.
@MainActor
enum KillRing {
    static var ring = KillRingEntries()
    /// The clipboard's change count right after the ring last wrote it; any
    /// other value means something else (another app, ⌘C) has written since.
    private static var ownChangeCount = -1

    static func kill(_ text: String, continuing: Bool, backward: Bool) {
        ring.kill(text, continuing: continuing, backward: backward)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(ring.entries[0], forType: .string)
        ownChangeCount = pasteboard.changeCount
    }

    /// What `C-y` inserts, after taking in anything copied since the last kill.
    static func yankText() -> String? {
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount != ownChangeCount,
           let copied = pasteboard.string(forType: .string),
           copied != ring.entries.first {
            ring.kill(copied, continuing: false, backward: false)
        }
        ownChangeCount = pasteboard.changeCount
        return ring.yankText
    }
}

extension SyntaxEditorTextInputView {
    var isMarkActive: Bool { mark != nil }

    /// The end of the selection the caret is at: the far end from the mark
    /// when one is set (motion extends from the mark), else the selection's end.
    private var caretEnd: Int {
        guard let mark else { return selectedRangeStorage.upperBound }
        return selectedRangeStorage.location == mark
            ? selectedRangeStorage.upperBound : selectedRangeStorage.location
    }

    /// Delete `range` onto the kill ring. `caret` is where the command began
    /// (before any selection it extended): a kill starting where the last one
    /// ended, with nothing edited since, joins its entry.
    func kill(_ range: NSRange, backward: Bool = false, from caret: Int? = nil) {
        guard isEditable, range.length > 0 else { return }
        let start = caret ?? selectedRangeStorage.location
        let continuing = lastKill.map { $0.revision == textRevision && $0.caret == start } ?? false
        KillRing.kill((string as NSString).substring(with: range),
                      continuing: continuing, backward: backward)
        replaceText(in: range, with: "", selectedRange: NSRange(location: range.location, length: 0))
        lastKill = (range.location, textRevision)
    }

    /// `C-w` (emacs `kill-region`): kill the selection — the region, while the
    /// mark is set. Nothing selected: beep, as emacs does without a mark.
    func killRegion() {
        guard selectedRangeStorage.length > 0 else { return NSSound.beep() }
        kill(selectedRangeStorage)
    }

    /// `M-w` (emacs `kill-ring-save`): copy the selection onto the kill ring
    /// without deleting it, and drop the mark, leaving the caret where it was.
    func copyRegionAsKill() {
        guard selectedRangeStorage.length > 0 else { return NSSound.beep() }
        let caret = caretEnd
        KillRing.kill((string as NSString).substring(with: selectedRangeStorage),
                      continuing: false, backward: false)
        mark = nil
        lastKill = nil
        setSelectedRange(NSRange(location: caret, length: 0))
    }

    /// `C-y` (emacs `yank`): insert the newest kill — or text copied in
    /// another app since — at the caret, replacing any selection.
    func yank() {
        guard isEditable, let text = KillRing.yankText() else { return NSSound.beep() }
        insertYank(text, replacing: selectedRangeStorage)
    }

    /// `M-y` (emacs `yank-pop`): straight after a yank, swap the yanked text
    /// for the next-older kill, cycling round to the newest.
    func yankPop() {
        guard isEditable, let yank = lastYank, yank.revision == textRevision,
              selectedRangeStorage == NSRange(location: yank.range.upperBound, length: 0),
              let text = KillRing.ring.rotate()
        else { return NSSound.beep() }
        insertYank(text, replacing: yank.range)
    }

    private func insertYank(_ text: String, replacing range: NSRange) {
        let length = (text as NSString).length
        replaceText(in: range, with: text,
                    selectedRange: NSRange(location: range.location + length, length: 0))
        lastYank = (NSRange(location: range.location, length: length), textRevision)
        lastKill = nil
    }

    /// `C-SPC` (emacs `set-mark-command`): start a region at the caret. Motion
    /// then extends the selection from here until an edit, `C-g`, or a click.
    func setMark() {
        let caret = caretEnd
        mark = caret
        setSelectedRange(NSRange(location: caret, length: 0))
    }

    /// `C-g` with a mark set: drop it and its region, keeping the caret.
    /// Returns whether there was one.
    @discardableResult
    func deactivateMark() -> Bool {
        guard mark != nil else { return false }
        let caret = caretEnd
        mark = nil
        setSelectedRange(NSRange(location: caret, length: 0))
        return true
    }
}

extension SyntaxEditorView {
    /// Drop the emacs mark and its region (`C-g`); false when none was set.
    @discardableResult
    public func deactivateMark() -> Bool { textView.deactivateMark() }
}
#endif
