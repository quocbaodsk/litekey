@testable import LiteKeyEngine

/// Fixture rows where the engine intentionally differs from the fixtures (which are never edited).
/// Each group says why; `FixtureTests` checks the new result for every row.
enum FixtureExceptions {
    /// Restore-if-wrong-spelling after backspacing over a space into the previous word and typing on.
    /// The fixtures delete the whole word but retype only the keys typed after the deletion, losing the
    /// word (e.g. "ừng", backspace, "s" gives "s"). The engine skips the restore when the word's keys are
    /// incomplete and keeps the text ("ừngs").
    static let restoreAfterDeletingIntoPreviousWord: [String: String] = [
        "editing.tsv:613": "ừngs ",
        "editing.tsv:615": "bượs ",
        "editing.tsv:631": "ciểus ",
        "editing.tsv:645": "chạs ",
        "editing.tsv:657": "gỏps ",
        "editing.tsv:673": "đễns ",
        "editing.tsv:675": "đáms ",
        "editing.tsv:681": "phòs ",
        "editing.tsv:683": "giườs ",
        "editing.tsv:685": "pệchs ",
        "editing.tsv:701": "lệs ",
        "editing.tsv:703": "hõs ",
        "editing.tsv:717": "khyểs ",
        "editing.tsv:723": "nghướs ",
        "editing.tsv:741": "ghuôs ",
        "editing.tsv:743": "mãs ",
        "editing.tsv:747": "koăs ",
        "editing.tsv:749": "pạns ",
        "editing.tsv:757": "lểus ",
        "editing.tsv:759": "poáchs ",
        "editing.tsv:761": "sửngs ",
        "editing.tsv:763": "quoảs ",
        "editing.tsv:764": "ngưus ",
        "editing.tsv:765": "xộns ",
        "editing.tsv:775": "tuýus ",
        "editing.tsv:783": "rõs ",
        "editing.tsv:789": "hũs ",
        "editing.tsv:795": "nhỏngs ",
        "editing.tsv:798": "trơs ",
        "editing.tsv:805": "khưs ",
        "editing.tsv:807": "phoàns ",
        "editing.tsv:811": "guẫns ",
        "editing.tsv:821": "sêus ",
        "editing.tsv:823": "quồs ",
        "editing.tsv:833": "đưs ",
        "editing.tsv:835": "moéns ",
        "editing.tsv:841": "khợps ",
        "editing.tsv:845": "nhoạcs ",
        "editing.tsv:847": "chuếnhs ",
        "editing.tsv:851": "soặs ",
        "editing.tsv:859": "thuềs ",
        "editing.tsv:863": "coãs ",
        "editing.tsv:865": "xís ",
        "editing.tsv:869": "thưs ",
        "editing.tsv:883": "bóps ",
        "editing.tsv:886": "ngêus ",
        "editing.tsv:891": "cãs ",
        "editing.tsv:898": "puôs ",
    ]

    /// The expected result for a row, if it is an exception
    static func expected(file: String, line: Int) -> String? {
        restoreAfterDeletingIntoPreviousWord["\(file):\(line)"]
    }
}
