// Macro storage formats: the UniKey-compatible text file and the binary `macroData` blob.

/// A macro: typing `text` followed by space or punctuation replaces it with `content`.
public struct Macro: Codable, Hashable, Identifiable, Sendable {
    public var id: String { text }

    public var text: String
    public var content: String

    public init(text: String, content: String) {
        self.text = text
        self.content = content
    }
}

/// Macro table. Keys are `text` converted to engine codes (`convert`), so "btw" and "Btw" are distinct
/// keys. Iteration is in ascending key order.
public struct MacroTable: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var text: String
        var content: String
        var contentCode: [UInt32]
    }

    private(set) var entries: [[UInt32]: Entry] = [:]

    public init() {}

    /// Adds macros in order; a later macro with the same key replaces the earlier one.
    public init(macros: [Macro]) {
        for macro in macros {
            let key = Self.convert(macro.text)
            entries[key] = Entry(text: macro.text, content: macro.content, contentCode: Self.convert(macro.content))
        }
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    /// All macros, in key order.
    public var macros: [Macro] {
        entries.sorted { $0.key.lexicographicallyPrecedes($1.key) }.map { Macro(text: $0.value.text, content: $0.value.content) }
    }

    /// Whether a macro exists for `text`.
    public func has(_ text: String) -> Bool {
        entries[Self.convert(text)] != nil
    }

    /// Adds a macro, or updates its content if it already exists.
    public mutating func add(_ text: String, content: String) {
        let key = Self.convert(text)
        if entries[key] == nil {
            entries[key] = Entry(text: text, content: content, contentCode: Self.convert(content))
        } else {
            entries[key]?.content = content
            entries[key]?.contentCode = Self.convert(content)
        }
    }

    /// Removes the macro for `text`; returns whether one existed.
    @discardableResult
    public mutating func delete(_ text: String) -> Bool {
        entries.removeValue(forKey: Self.convert(text)) != nil
    }

    func contentCode(for key: [UInt32]) -> [UInt32]? {
        entries[key]?.contentCode
    }

    /// Converts a string to engine codes: ASCII → key code (with caps), accented letters → Unicode code
    /// (`charCode`), anything else → pure character (`pureCharacter`). Works on UTF-16 units, so an emoji
    /// becomes two pure characters (a surrogate pair) and is still typed correctly.
    static func convert(_ string: String) -> [UInt32] {
        var out: [UInt32] = []
        for unit in string.utf16 {
            let t = UInt32(unit)
            if let code = VietnameseData.characterKeyCode[t] {
                out.append(code)
                continue
            }
            if let code = unicodeCode(for: unit) {
                out.append(code)
                continue
            }
            out.append(t | EngineMasks.pureCharacter)
        }
        return out
    }

    /// Looks up an accented letter in the Unicode table (searched in key order).
    private static func unicodeCode(for unit: UInt16) -> UInt32? {
        for entry in VietnameseData.unicodeTable {
            for value in entry.value where value == unit {
                return UInt32(value) | EngineMasks.charCode
            }
        }
        return nil
    }

    // MARK: - Text file (UniKey-compatible)

    /// First line of a macro text file.
    public static let fileHeader = ";Compatible OpenKey Macro Data file for UniKey*** version=1 ***"

    /// The table as a macro text file.
    public var fileText: String {
        var text = Self.fileHeader + "\n"
        for macro in macros {
            text += macro.text + ":" + macro.content + "\n"
        }
        return text
    }

    /// Loads a macro text file: skips the first line, then one "text:content" per line; existing macros
    /// are kept. With `append == false` the table is cleared first. Strips a trailing `\r` (UniKey files
    /// from Windows use CRLF).
    public mutating func load(fileText: String, append: Bool) {
        if !append { entries.removeAll() }
        var lineNumber = 0
        // Split on '\n' bytes: String treats "\r\n" as one Character, so splitting by Character would miss it
        for rawLine in fileText.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false) {
            lineNumber += 1
            if lineNumber == 1 { continue }
            var line = String(decoding: rawLine, as: UTF8.self)
            if line.hasSuffix("\r") { line.removeLast() }
            guard let colon = line.firstIndex(of: ":") else { continue }
            var name = String(line[..<colon])
            var content = String(line[line.index(after: colon)...])
            // Macro text that starts with ":" (e.g. ":)")
            while name.isEmpty && !content.isEmpty {
                guard let next = content.firstIndex(of: ":") else { break }
                name += ":" + content[..<next]
                content = String(content[content.index(after: next)...])
            }
            if !name.isEmpty && !has(name) {
                add(name, content: content)
            }
        }
    }

    // MARK: - Binary format (`macroData`)

    /// 2-byte entry count, then per entry: 1-byte text length + text (UTF-8), 2-byte content length +
    /// content (UTF-8). Integers are little-endian.
    ///
    /// Entries whose text exceeds 255 bytes or content exceeds 65,535 bytes can't encode their length in
    /// this format; writing them anyway would misalign every later entry on read and lose the whole table.
    /// They are skipped, and the count covers only the entries written.
    public var openKeyData: [UInt8] {
        var entries: [(text: [UInt8], content: [UInt8])] = []
        for macro in macros {
            let text = Array(macro.text.utf8)
            let content = Array(macro.content.utf8)
            guard text.count <= Int(UInt8.max), content.count <= Int(UInt16.max) else { continue }
            entries.append((text, content))
        }
        let total = entries.prefix(Int(UInt16.max))
        var data: [UInt8] = []
        data.append(UInt8(truncatingIfNeeded: total.count))
        data.append(UInt8(truncatingIfNeeded: total.count >> 8))
        for entry in total {
            data.append(UInt8(entry.text.count))
            data.append(contentsOf: entry.text)
            data.append(UInt8(truncatingIfNeeded: entry.content.count))
            data.append(UInt8(truncatingIfNeeded: entry.content.count >> 8))
            data.append(contentsOf: entry.content)
        }
        return data
    }

    /// Decodes binary macro data, ignoring truncated trailing data instead of reading past the end.
    public init(openKeyData data: [UInt8]) {
        var macros: [Macro] = []
        guard data.count >= 2 else { self.init(); return }
        let count = Int(data[0]) | Int(data[1]) << 8
        var cursor = 2
        for _ in 0..<count {
            guard cursor < data.count else { break }
            let textSize = Int(data[cursor]); cursor += 1
            guard cursor + textSize + 2 <= data.count else { break }
            let text = String(decoding: data[cursor..<cursor + textSize], as: UTF8.self)
            cursor += textSize
            let contentSize = Int(data[cursor]) | Int(data[cursor + 1]) << 8
            cursor += 2
            guard cursor + contentSize <= data.count else { break }
            let content = String(decoding: data[cursor..<cursor + contentSize], as: UTF8.self)
            cursor += contentSize
            macros.append(Macro(text: text, content: content))
        }
        self.init(macros: macros)
    }
}
