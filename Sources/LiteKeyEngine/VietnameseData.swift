// Values are macOS key codes combined with the engine's bit masks (see EngineMasks).

/// Engine data tables. Keyed tables are arrays sorted by key, since lookups that scan them depend on
/// ascending key order.
enum VietnameseData {
    /// Vowel patterns (with allowed endings) per tone key (a, w, e, o). Sorted by key.
    static let vowel: [(key: UInt32, value: [[UInt32]])] = [
        (0, [[0, 45, 5], [0, 16389], [0, 45], [0, 46], [0, 32], [0, 16], [0, 17], [0, 35], [0], [0, 8]]),
        (13, [[31, 45], [32, 31, 45, 5], [32, 31, 16389], [32, 31, 45], [32, 31, 34], [32, 31, 8], [31, 34], [31, 35], [31, 46], [31, 0], [31, 17], [32, 45, 5], [32, 16389], [0, 45, 5], [0, 16389], [32, 45], [32, 46], [32, 8], [32, 0], [32, 34], [32, 17], [32], [0, 35], [0, 17], [0, 46], [0, 45], [0], [0, 8], [0, 8, 4], [0, 16424], [31], [32, 32]]),
        (14, [[14, 45, 4], [14, 16388], [14, 45, 5], [14, 16389], [14, 8, 4], [14, 16424], [14, 8], [14, 17], [14, 16], [14, 32], [14, 35], [14, 8], [14, 45], [14, 46], [14]]),
        (31, [[31, 45, 5], [31, 16389], [31, 45], [31, 46], [31, 34], [31, 8], [31, 17], [31, 35], [31]]),
    ]
    /// Valid vowel clusters by first vowel; element 0 is 1 if an end consonant may follow. Sorted by key.
    static let vowelCombine: [(key: UInt32, value: [[UInt32]])] = [
        (0, [[0, 0, 34], [0, 0, 31], [0, 0, 32], [0, 131072, 32], [0, 0, 16], [0, 131072, 16]]),
        (14, [[0, 14, 31], [0, 131086, 32]]),
        (16, [[0, 16, 131086, 32], [1, 16, 131086]]),
        (31, [[0, 31, 0, 34], [0, 31, 0, 31], [0, 31, 0, 16], [0, 31, 14, 31], [1, 31, 0], [1, 31, 262144], [1, 31, 14], [0, 31, 34], [0, 131103, 34], [0, 262175, 34], [1, 31, 31], [1, 131103, 131103]]),
        (32, [[0, 32, 16, 32], [1, 32, 16, 131086], [0, 32, 16, 0], [0, 262176, 262175, 32], [0, 262176, 262175, 34], [0, 32, 131103, 34], [0, 32, 131072, 16], [1, 32, 0, 31], [1, 32, 0], [1, 32, 262144], [1, 32, 131072], [0, 262176, 0], [1, 32, 131086], [0, 32, 34], [0, 262176, 34], [1, 32, 31], [1, 32, 131103], [0, 32, 262175], [1, 262176, 262175], [0, 262176, 32], [1, 32, 16]]),
        (34, [[1, 34, 131086, 32], [0, 34, 0], [1, 34, 131086], [0, 34, 32]]),
    ]
    /// Patterns checked when handling the d (đ) key.
    static let consonantD: [[UInt32]] = [
        [2, 14, 45, 4],
        [2, 14, 16388],
        [2, 14, 45, 5],
        [2, 14, 16389],
        [2, 14, 8, 4],
        [2, 14, 16424],
        [2, 14, 45],
        [2, 14, 8],
        [2, 14, 46],
        [2, 14],
        [2, 14, 17],
        [2, 14, 32],
        [2, 14, 31],
        [2, 14, 35],
        [2, 32, 45, 5],
        [2, 32, 16389],
        [2, 32, 45],
        [2, 32, 46],
        [2, 32, 8],
        [2, 32, 31],
        [2, 32, 0],
        [2, 32, 31, 34],
        [2, 32, 31, 8],
        [2, 32, 31, 45],
        [2, 32, 31, 45, 5],
        [2, 32, 31, 16389],
        [2, 32],
        [2, 32, 35],
        [2, 32, 17],
        [2, 32, 34],
        [2, 34, 8, 4],
        [2, 34, 16424],
        [2, 34, 8],
        [2, 34, 45, 4],
        [2, 34, 16388],
        [2, 34, 45],
        [2, 34],
        [2, 34, 0],
        [2, 34, 14],
        [2, 34, 14, 8],
        [2, 34, 14, 32],
        [2, 34, 14, 45],
        [2, 34, 14, 46],
        [2, 34, 14, 35],
        [2, 34, 17],
        [2, 31],
        [2, 31, 0],
        [2, 31, 0, 45],
        [2, 31, 0, 45, 5],
        [2, 31, 0, 16389],
        [2, 31, 0, 45, 4],
        [2, 31, 0, 16388],
        [2, 31, 0, 46],
        [2, 31, 14],
        [2, 31, 34],
        [2, 31, 35],
        [2, 31, 8],
        [2, 31, 45],
        [2, 31, 45, 5],
        [2, 31, 16389],
        [2, 31, 46],
        [2, 31, 17],
        [2, 0],
        [2, 0, 17],
        [2, 0, 16],
        [2, 0, 32],
        [2, 0, 34],
        [2, 0, 31],
        [2, 0, 35],
        [2, 0, 8],
        [2, 0, 8, 4],
        [2, 0, 16424],
        [2, 0, 45],
        [2, 0, 45, 4],
        [2, 0, 16388],
        [2, 0, 45, 5],
        [2, 0, 16389],
        [2, 0, 46],
        [2],
    ]
    /// Vowel patterns that can take a tone mark, by vowel. Sorted by key.
    static let vowelForMark: [(key: UInt32, value: [[UInt32]])] = [
        (0, [[0, 45, 5], [0, 16389], [0, 45], [0, 45, 4], [0, 16388], [0, 46], [0, 32], [0, 16], [0, 17], [0, 35], [0], [0, 8], [0, 34], [0, 31], [0, 8, 4], [0, 16424]]),
        (14, [[14, 45, 4], [14, 16388], [14, 45, 5], [14, 16389], [14, 8, 4], [14, 16424], [14, 8], [14, 17], [14, 16], [14, 32], [14, 35], [14, 8], [14, 45], [14, 46], [14]]),
        (16, [[16]]),
        (31, [[31, 31, 45, 5], [31, 31, 16389], [31, 45, 5], [31, 16389], [31, 31, 45], [31, 31, 8], [31, 31], [31, 45], [31, 46], [31, 34], [31, 8], [31, 17], [31, 35], [31]]),
        (32, [[32, 45, 5], [32, 16389], [32, 34], [32, 31], [32, 16], [32, 16, 45], [32, 16, 17], [32, 16, 35], [32, 16, 8, 4], [32, 16, 16424], [32, 16, 45, 4], [32, 16, 16388], [32, 17], [32, 32], [32, 0], [32, 34], [32, 8], [32, 45], [32, 46], [32, 35], [32]]),
        (34, [[34, 45, 4], [34, 16388], [34, 8, 4], [34, 16424], [34, 45], [34, 17], [34, 32], [34, 32, 35], [34, 45], [34, 46], [34, 35], [34, 0], [34, 8], [34]]),
    ]
    /// Valid initial consonants.
    static let consonantTable: [[UInt32]] = [
        [45, 5, 4],
        [35, 4],
        [17, 4],
        [17, 15],
        [5, 34],
        [8, 4],
        [45, 4],
        [45, 5],
        [40, 4],
        [5, 4],
        [5],
        [8],
        [12],
        [40],
        [17],
        [15],
        [4],
        [11],
        [46],
        [9],
        [45],
        [37],
        [7],
        [35],
        [1],
        [2],
        [32771],
        [32781],
        [32774],
        [32806],
        [16387],
        [16397],
        [16422],
    ]
    /// Valid end consonants.
    static let endConsonantTable: [[UInt32]] = [
        [17],
        [35],
        [8],
        [45],
        [46],
        [16389],
        [16424],
        [16388],
        [8, 4],
        [45, 4],
        [45, 5],
    ]
    /// Single letters after which a standalone "w" is not turned into "ư".
    static let standaloneWbad: [UInt32] = [
        13,
        14,
        16,
        3,
        38,
        40,
        6,
    ]
    /// Two-letter prefixes after which a standalone "w" may become "ư".
    static let doubleWAllowed: [[UInt32]] = [
        [17, 15],
        [17, 4],
        [8, 4],
        [45, 4],
        [45, 5],
        [40, 4],
        [5, 34],
        [35, 4],
        [5, 4],
    ]
    /// Quick start consonants: f→ph, j→gi, w→qu. Sorted by key.
    static let quickStartConsonant: [(key: UInt32, value: [UInt32])] = [
        (3, [35, 4]),
        (13, [12, 32]),
        (38, [5, 34]),
    ]
    /// Quick end consonants: g→ng, h→nh, k→ch. Sorted by key.
    static let quickEndConsonant: [(key: UInt32, value: [UInt32])] = [
        (4, [45, 4]),
        (5, [45, 5]),
        (40, [8, 4]),
    ]
    /// Quick Telex: a doubled key expands to a pair (cc→ch, nn→ng...). Sorted by key.
    static let quickTelex: [(key: UInt32, value: [UInt32])] = [
        (5, [5, 34]),
        (8, [8, 4]),
        (12, [12, 32]),
        (17, [17, 4]),
        (32, [32, 32]),
        (35, [35, 4]),
        (40, [40, 4]),
        (45, [45, 5]),
    ]
    /// Precomposed Unicode letters by base key, alternating upper/lower case.
    static let unicodeTable: [(key: UInt32, value: [UInt16])] = [
        (0, [0x00C2, 0x00E2, 0x0102, 0x0103, 0x00C1, 0x00E1, 0x00C0, 0x00E0, 0x1EA2, 0x1EA3, 0x00C3, 0x00E3, 0x1EA0, 0x1EA1]),
        (2, [0x0110, 0x0111]),
        (14, [0x00CA, 0x00EA, 0x0000, 0x0000, 0x00C9, 0x00E9, 0x00C8, 0x00E8, 0x1EBA, 0x1EBB, 0x1EBC, 0x1EBD, 0x1EB8, 0x1EB9]),
        (16, [0x00DD, 0x00FD, 0x1EF2, 0x1EF3, 0x1EF6, 0x1EF7, 0x1EF8, 0x1EF9, 0x1EF4, 0x1EF5]),
        (31, [0x00D4, 0x00F4, 0x01A0, 0x01A1, 0x00D3, 0x00F3, 0x00D2, 0x00F2, 0x1ECE, 0x1ECF, 0x00D5, 0x00F5, 0x1ECC, 0x1ECD]),
        (32, [0x0000, 0x0000, 0x01AF, 0x01B0, 0x00DA, 0x00FA, 0x00D9, 0x00F9, 0x1EE6, 0x1EE7, 0x0168, 0x0169, 0x1EE4, 0x1EE5]),
        (34, [0x00CD, 0x00ED, 0x00CC, 0x00EC, 0x1EC8, 0x1EC9, 0x0128, 0x0129, 0x1ECA, 0x1ECB]),
        (131072, [0x1EA4, 0x1EA5, 0x1EA6, 0x1EA7, 0x1EA8, 0x1EA9, 0x1EAA, 0x1EAB, 0x1EAC, 0x1EAD]),
        (131086, [0x1EBE, 0x1EBF, 0x1EC0, 0x1EC1, 0x1EC2, 0x1EC3, 0x1EC4, 0x1EC5, 0x1EC6, 0x1EC7]),
        (131103, [0x1ED0, 0x1ED1, 0x1ED2, 0x1ED3, 0x1ED4, 0x1ED5, 0x1ED6, 0x1ED7, 0x1ED8, 0x1ED9]),
        (262144, [0x1EAE, 0x1EAF, 0x1EB0, 0x1EB1, 0x1EB2, 0x1EB3, 0x1EB4, 0x1EB5, 0x1EB6, 0x1EB7]),
        (262175, [0x1EDA, 0x1EDB, 0x1EDC, 0x1EDD, 0x1EDE, 0x1EDF, 0x1EE0, 0x1EE1, 0x1EE2, 0x1EE3]),
        (262176, [0x1EE8, 0x1EE9, 0x1EEA, 0x1EEB, 0x1EEC, 0x1EED, 0x1EEE, 0x1EEF, 0x1EF0, 0x1EF1]),
    ]
    /// Character → key code (with the caps mask).
    static let characterMap: [(character: UInt16, keyCode: UInt32)] = [
        (97, 0),
        (65, 65536),
        (98, 11),
        (66, 65547),
        (99, 8),
        (67, 65544),
        (100, 2),
        (68, 65538),
        (101, 14),
        (69, 65550),
        (102, 3),
        (70, 65539),
        (103, 5),
        (71, 65541),
        (104, 4),
        (72, 65540),
        (105, 34),
        (73, 65570),
        (106, 38),
        (74, 65574),
        (107, 40),
        (75, 65576),
        (108, 37),
        (76, 65573),
        (109, 46),
        (77, 65582),
        (110, 45),
        (78, 65581),
        (111, 31),
        (79, 65567),
        (112, 35),
        (80, 65571),
        (113, 12),
        (81, 65548),
        (114, 15),
        (82, 65551),
        (115, 1),
        (83, 65537),
        (116, 17),
        (84, 65553),
        (117, 32),
        (85, 65568),
        (118, 9),
        (86, 65545),
        (119, 13),
        (87, 65549),
        (120, 7),
        (88, 65543),
        (121, 16),
        (89, 65552),
        (122, 6),
        (90, 65542),
        (49, 18),
        (33, 65554),
        (50, 19),
        (64, 65555),
        (51, 20),
        (35, 65556),
        (52, 21),
        (36, 65557),
        (53, 23),
        (37, 65559),
        (54, 22),
        (94, 65558),
        (55, 26),
        (38, 65562),
        (56, 28),
        (42, 65564),
        (57, 25),
        (40, 65561),
        (48, 29),
        (41, 65565),
        (96, 50),
        (126, 65586),
        (45, 27),
        (95, 65563),
        (61, 24),
        (43, 65560),
        (91, 33),
        (123, 65569),
        (93, 30),
        (125, 65566),
        (92, 42),
        (124, 65578),
        (59, 41),
        (58, 65577),
        (39, 39),
        (34, 65575),
        (44, 43),
        (60, 65579),
        (46, 47),
        (62, 65583),
        (47, 44),
        (63, 65580),
        (32, 49),
    ]

    // MARK: - Lookup dictionaries

    static let vowelByKey: [UInt32: [[UInt32]]] = Dictionary(uniqueKeysWithValues: vowel.map { ($0.key, $0.value) })
    static let vowelCombineByKey: [UInt32: [[UInt32]]] = Dictionary(uniqueKeysWithValues: vowelCombine.map { ($0.key, $0.value) })
    static let quickStartConsonantByKey: [UInt32: [UInt32]] = Dictionary(uniqueKeysWithValues: quickStartConsonant.map { ($0.key, $0.value) })
    static let quickEndConsonantByKey: [UInt32: [UInt32]] = Dictionary(uniqueKeysWithValues: quickEndConsonant.map { ($0.key, $0.value) })
    static let quickTelexByKey: [UInt32: [UInt32]] = Dictionary(uniqueKeysWithValues: quickTelex.map { ($0.key, $0.value) })
    static let unicodeByKey: [UInt32: [UInt16]] = Dictionary(uniqueKeysWithValues: unicodeTable.map { ($0.key, $0.value) })
    /// Key code → character (inverse of `characterMap`).
    static let keyCodeToChar: [UInt32: UInt16] = {
        var table: [UInt32: UInt16] = [:]
        for entry in characterMap { table[entry.keyCode] = entry.character }
        return table
    }()

    /// Character → key code.
    static let characterKeyCode: [UInt32: UInt32] = {
        var table: [UInt32: UInt32] = [:]
        for entry in characterMap { table[UInt32(entry.character)] = entry.keyCode }
        return table
    }()

    /// Character for a key code, or 0 if there is none.
    static func character(for keyCode: UInt32) -> UInt16 {
        keyCodeToChar[keyCode] ?? 0
    }
}
