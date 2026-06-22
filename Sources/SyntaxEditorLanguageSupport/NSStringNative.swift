import Foundation

extension NSString {
    /// `substring(with:)` that returns a native (contiguous UTF-8) String.
    ///
    /// Plain `substring(with:)` yields an `__NSCFString`-backed String whose
    /// every comparison, hash, and Character access takes the foreign UTF-16,
    /// normalization-aware slow path. Hot paths that compare or hash the result
    /// (identifier texts, declaration names) pay one upfront transcode here
    /// instead.
    @inline(__always)
    package func nativeSubstring(with range: NSRange) -> String {
        var result = substring(with: range)
        result.makeContiguousUTF8()
        return result
    }
}
