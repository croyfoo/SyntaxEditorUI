#if canImport(AppKit)
import Testing
@testable import SyntaxEditorUIAppKit

struct KillRingTests {
    /// Consecutive kills join one entry — forward kills append, backward ones
    /// prepend — and `M-y` rotates through entries, wrapping to the newest.
    @Test func killsJoinAndYankRotates() {
        var ring = KillRingEntries()
        ring.kill("one\n", continuing: false, backward: false)
        ring.kill("two\n", continuing: true, backward: false)
        #expect(ring.entries == ["one\ntwo\n"])

        ring.kill("word", continuing: false, backward: false)
        ring.kill("back ", continuing: true, backward: true)
        #expect(ring.entries == ["back word", "one\ntwo\n"])

        #expect(ring.yankText == "back word")
        #expect(ring.rotate() == "one\ntwo\n")
        #expect(ring.rotate() == "back word")
        ring.kill("new", continuing: false, backward: false)
        #expect(ring.yankText == "new")
    }
}
#endif
