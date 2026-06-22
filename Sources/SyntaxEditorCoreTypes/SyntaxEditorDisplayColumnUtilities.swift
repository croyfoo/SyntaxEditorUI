package enum SyntaxEditorDisplayColumnUtilities {
    package static func columnCount(in source: String, tabWidth: Int) -> Int {
        var currentColumns = 0
        for character in source {
            currentColumns += columnWidth(for: character, currentColumn: currentColumns, tabWidth: tabWidth)
        }
        return currentColumns
    }

    package static func maximumColumnCount(in source: String, tabWidth: Int) -> Int {
        var maxColumns = 0
        var currentColumns = 0

        for character in source {
            if isLineBreak(character) {
                maxColumns = max(maxColumns, currentColumns)
                currentColumns = 0
            } else {
                currentColumns += columnWidth(for: character, currentColumn: currentColumns, tabWidth: tabWidth)
            }
        }

        return max(maxColumns, currentColumns)
    }

    package static func spacesToNextTabStop(from column: Int, tabWidth: Int) -> Int {
        let tabWidth = max(1, tabWidth)
        let remainder = column % tabWidth
        return remainder == 0 ? tabWidth : tabWidth - remainder
    }
}

extension SyntaxEditorDisplayColumnUtilities {
    package static func columnWidth(for character: Character, currentColumn: Int, tabWidth: Int) -> Int {
        if isTab(character) {
            return spacesToNextTabStop(from: currentColumn, tabWidth: tabWidth)
        }

        if isZeroWidthCharacter(character) {
            return 0
        }

        if isWideCharacter(character) {
            return 2
        }

        return 1
    }

    static func isTab(_ character: Character) -> Bool {
        character.unicodeScalars.count == 1 && character.unicodeScalars.first?.value == 9
    }

    static func isLineBreak(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            scalar.value == 10 || scalar.value == 13
        }
    }

    static func isZeroWidthCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            isZeroWidthScalar(scalar.value)
        }
    }

    static func isWideCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            isWideScalar(scalar.value) || isRegionalIndicatorScalar(scalar.value)
        }
    }

    static func isZeroWidthScalar(_ value: UInt32) -> Bool {
        switch value {
        case 0x0300...0x036F,
             0x1AB0...0x1AFF,
             0x1DC0...0x1DFF,
             0x200B...0x200F,
             0x202A...0x202E,
             0x2060...0x206F,
             0x20D0...0x20FF,
             0xFE00...0xFE0F,
             0xFE20...0xFE2F:
            return true
        default:
            return false
        }
    }

    static func isWideScalar(_ value: UInt32) -> Bool {
        switch value {
        case 0x1100...0x115F,
             0x2329...0x232A,
             0x2600...0x27BF,
             0x2E80...0xA4CF,
             0xAC00...0xD7A3,
             0xF900...0xFAFF,
             0xFE10...0xFE19,
             0xFE30...0xFE6F,
             0xFF00...0xFF60,
             0xFFE0...0xFFE6,
             0x1F300...0x1FAFF,
             0x20000...0x3FFFD:
            return true
        default:
            return false
        }
    }

    static func isRegionalIndicatorScalar(_ value: UInt32) -> Bool {
        (0x1F1E6...0x1F1FF).contains(value)
    }
}
