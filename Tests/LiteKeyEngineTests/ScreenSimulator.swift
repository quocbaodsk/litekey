import LiteKeyEngine

/// Screen simulator: types a key sequence through the engine and returns the displayed text.
/// `<` is the Delete key.
struct ScreenSimulator<Engine: TypingEngine> {
    var engine: Engine

    static var keyCodes: [Character: UInt16] {
        ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
         "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
         "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31,
         "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
         " ": 49, "<": 51, ".": 47, ",": 43]
    }

    mutating func type(_ keys: String) -> String {
        var screen: [UInt16] = []
        var output = EngineOutput()
        engine.newSession()
        for raw in keys {
            let upper = raw.isUppercase
            let key = Character(raw.lowercased())
            guard let code = Self.keyCodes[key] else { fatalError("No key code for \(raw)") }
            engine.handleKey(code: code, caps: upper ? .shift : .none, otherModifier: false, into: &output)
            if output.action == .pass {
                if raw == "<" {
                    if !screen.isEmpty { screen.removeLast() }
                } else {
                    screen.append(contentsOf: String(raw).utf16)
                }
            } else {
                if output.backspaces < 32 { screen.removeLast(min(output.backspaces, screen.count)) }
                screen.append(contentsOf: output.text)
                if output.resendKey { screen.append(contentsOf: String(raw).utf16) }
            }
        }
        return String(decoding: screen, as: UTF16.self)
    }
}
