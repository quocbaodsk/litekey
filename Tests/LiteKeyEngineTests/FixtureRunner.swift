import Foundation
import LiteKeyEngine

/// Runs `Tests/fixtures/*.tsv` through an engine in the order the fixtures were generated: files sorted
/// by name, one engine instance throughout; per row: reconfigure if the config differs from the previous
/// row, `newSession()`, then type each key.
struct FixtureRunner<Engine: TypingEngine> {
    struct Row {
        var file: String
        var line: Int
        var config: String
        var keys: String
        var expected: String
    }

    struct Failure: CustomStringConvertible {
        var row: Row
        var got: String
        var description: String {
            "\(row.file):\(row.line) [\(row.config)] \(row.keys) -> \(got) (expected: \(row.expected))"
        }
    }

    static var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures")
    }

    static func loadRows() throws -> [Row] {
        let files = try FileManager.default.contentsOfDirectory(atPath: fixturesDirectory.path)
            .filter { $0.hasSuffix(".tsv") }
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        var rows: [Row] = []
        for file in files {
            let text = try String(contentsOf: fixturesDirectory.appendingPathComponent(file), encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where !line.isEmpty {
                let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                precondition(cols.count == 3, "\(file):\(index + 1) does not have 3 columns")
                rows.append(Row(file: file, line: index + 1, config: cols[0], keys: cols[1], expected: cols[2]))
            }
        }
        return rows
    }

    var engine: Engine
    private var lastConfig: String?

    /// Macro table shared by rows with the "macro" flag (the same file used to generate the fixtures)
    static var macroTable: MacroTable {
        var table = MacroTable()
        let text = (try? String(contentsOf: fixturesDirectory.appendingPathComponent("macros.txt"), encoding: .utf8)) ?? ""
        table.load(fileText: text, append: false)
        return table
    }

    init(engine: Engine) {
        self.engine = engine
        self.engine.setMacros(Self.macroTable)
    }

    /// Runs every row and returns the ones that don't match
    mutating func run(_ rows: [Row]) -> [Failure] {
        var failures: [Failure] = []
        for row in rows {
            let got = type(row)
            let expected = FixtureExceptions.expected(file: row.file, line: row.line) ?? row.expected
            if got != expected { failures.append(Failure(row: row, got: got)) }
        }
        return failures
    }

    mutating func type(_ row: Row) -> String {
        let (config, capsLock) = Self.parse(row.config)
        let english = row.config.split(separator: ",").contains("english")
        if row.config != lastConfig {
            engine.configure(config)
            lastConfig = row.config
        }
        engine.newSession()
        var screen: [UInt16] = []
        var output = EngineOutput()
        for ch in row.keys {
            if ch == "⌃" { engine.tempOffSpellChecking(); continue }
            if ch == "⌘" { engine.tempOffEngine(); continue }
            guard let key = FixtureKeys.table[ch] else { fatalError("Unknown key \(ch) at \(row.file):\(row.line)") }
            let caps: CapsState = key.shift ? .shift : (capsLock ? .capsLock : .none)
            if english {
                engine.handleEnglishModeKey(code: key.code, caps: caps, otherModifier: false, into: &output)
            } else {
                engine.handleKey(code: key.code, caps: caps, otherModifier: false, into: &output)
            }
            var typed = String(ch)
            if capsLock, ch.isASCII, ch.isLowercase { typed = typed.uppercased() }
            if output.action == .macro {
                // Macro: delete, type the content, then resend the key just pressed
                screen.removeLast(min(output.backspaces, screen.count))
                screen.append(contentsOf: output.characters.map(\.unit).filter { $0 != 0 })
                screen.append(contentsOf: typed.utf16)
            } else if output.action == .pass {
                if ch == "<" {
                    if !screen.isEmpty { screen.removeLast() }
                } else {
                    screen.append(contentsOf: typed.utf16)
                }
            } else {
                if output.backspaces > 0 && output.backspaces < 32 {
                    screen.removeLast(min(output.backspaces, screen.count))
                }
                screen.append(contentsOf: output.text)
                if output.resendKey { screen.append(contentsOf: typed.utf16) }
            }
        }
        return String(decoding: screen, as: UTF16.self)
    }

    static func parse(_ config: String) -> (EngineConfig, capsLock: Bool) {
        var c = EngineConfig()
        var capsLock = false
        for token in config.split(separator: ",") {
            switch token {
            case "telex": c.inputType = .telex
            case "vni": c.inputType = .vni
            case "st1": c.inputType = .simpleTelex1
            case "st2": c.inputType = .simpleTelex2
            case "modern": c.modernOrthography = true
            case "nospell": c.checkSpelling = false
            case "norestore": c.restoreIfWrong = false
            case "freemark": c.freeMark = true
            case "quicktelex": c.quickTelex = true
            case "qstart": c.quickStartConsonant = true
            case "qend": c.quickEndConsonant = true
            case "zfwj": c.allowConsonantZFWJ = true
            case "upperfirst": c.upperCaseFirstChar = true
            case "capslock": capsLock = true
            case "macro": c.useMacro = true
            case "autocaps": c.autoCapsMacro = true
            case "english": break
            default: fatalError("Unknown config: \(token)")
            }
        }
        return (c, capsLock)
    }
}

/// US keyboard layout used by the fixtures
enum FixtureKeys {
    /// Character → (key code, Shift). `<` is Delete, ⏎ Return, ⇥ Tab.
    static let table: [Character: (code: UInt16, shift: Bool)] = {
        var t: [Character: (code: UInt16, shift: Bool)] = [:]
        let lower = Array(#"asdfhgzxcvbqweryt123465=97-80]ou[ip lj'k;\,/nm.`"#)
        let codes: [UInt16] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
                               30, 31, 32, 33, 34, 35, 49, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 50]
        for (ch, code) in zip(lower, codes) { t[ch] = (code, false) }
        for ch in "abcdefghijklmnopqrstuvwxyz" { t[Character(ch.uppercased())] = (t[ch]!.code, true) }
        for (s, b) in zip(#"~!@#$%^&*()_+{}|:">?"#, #"`1234567890-=[]\;'./"#) { t[s] = (t[b]!.code, true) }
        t["<"] = (51, false)
        t["⏎"] = (36, false)
        t["⇥"] = (48, false)
        return t
    }()
}
