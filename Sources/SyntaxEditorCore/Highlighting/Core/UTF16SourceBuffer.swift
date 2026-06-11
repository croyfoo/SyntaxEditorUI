import Foundation
import SwiftTreeSitter

/// Session-owned contiguous UTF-16 image of the layered source.
///
/// tree-sitter reads the document through a byte callback; serving it from
/// `String` costs an index conversion, a UTF-16 transcode, and a `Data`
/// allocation per chunk on every parse. The session keeps this buffer in sync
/// with the layered source (one tail memmove per edit) and hands the parser
/// zero-copy windows instead.
///
/// Lifetime contract: windows returned by `readBlock()` borrow the buffer and
/// are valid only until the next `apply`/`reset`. The engine actor parses
/// synchronously inside one update, so no window outlives its content.
final class UTF16SourceBuffer {
    private var storage: UnsafeMutableBufferPointer<UInt16>
    private(set) var count: Int

    init() {
        storage = UnsafeMutableBufferPointer<UInt16>.allocate(capacity: 0)
        count = 0
    }

    deinit {
        storage.deallocate()
    }

    func reset(_ source: String) {
        let nsSource = source as NSString
        reserve(minimumCapacity: nsSource.length)
        if nsSource.length > 0 {
            nsSource.getCharacters(
                storage.baseAddress!,
                range: NSRange(location: 0, length: nsSource.length)
            )
        }
        count = nsSource.length
    }

    /// Splices the edit through (pre-edit coordinates, same contract as the
    /// line table). Out-of-bounds coordinates clamp; the session validates
    /// mutations before committing, so clamping is never observed in practice.
    func apply(mutation: SyntaxHighlightMutation) {
        let location = min(max(0, mutation.location), count)
        let removed = min(max(0, mutation.length), count - location)
        let replacement = mutation.replacement.utf16
        let inserted = replacement.count
        let newCount = count - removed + inserted

        if newCount > storage.count {
            let grown = UnsafeMutableBufferPointer<UInt16>.allocate(
                capacity: max(newCount, storage.count + storage.count / 2)
            )
            grown.baseAddress!.update(from: storage.baseAddress!, count: location)
            (grown.baseAddress! + location + inserted).update(
                from: storage.baseAddress! + location + removed,
                count: count - location - removed
            )
            storage.deallocate()
            storage = grown
        } else if removed != inserted {
            (storage.baseAddress! + location + inserted).update(
                from: storage.baseAddress! + location + removed,
                count: count - location - removed
            )
        }
        var offset = location
        for unit in replacement {
            storage[offset] = unit
            offset += 1
        }
        count = newCount
    }

    /// Parser read callback: returns the whole remaining buffer per call
    /// (zero-copy), so an incremental parse issues a handful of seeks instead
    /// of thousands of chunk transcodes.
    func readBlock() -> Parser.ReadBlock {
        { [self] byteOffset, _ in
            let location = byteOffset / 2
            guard location >= 0, location < count else { return nil }
            return Data(
                bytesNoCopy: UnsafeMutableRawPointer(storage.baseAddress! + location),
                count: (count - location) * 2,
                deallocator: .none
            )
        }
    }

    private func reserve(minimumCapacity: Int) {
        guard minimumCapacity > storage.count else { return }
        storage.deallocate()
        storage = UnsafeMutableBufferPointer<UInt16>.allocate(capacity: minimumCapacity)
    }
}
