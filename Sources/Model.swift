// Data model of nxnative's keyboard map (keymap.tsv) and gamepad map (padmap.tsv) for up to 8 players.
import AppKit
import Foundation

let kPlayers = 8

enum InputDeviceMode: String, CaseIterable, Identifiable {
    case gamepad = "Mando Xbox / Gamepad"
    case keyboard = "Teclado"
    var id: String { rawValue }
    var icon: String { self == .gamepad ? "gamecontroller.fill" : "keyboard.fill" }
}

enum Control: String, CaseIterable, Identifiable {
    case A, B, X, Y, L, R, ZL, ZR, PLUS, MINUS, LS, RS
    case UP, DOWN, LEFT, RIGHT
    case LUP, LDOWN, LLEFT, LRIGHT
    case RUP, RDOWN, RLEFT, RRIGHT
    case SHAKE
    var id: String { rawValue }

    var label: String {
        switch self {
        case .A: return "A"; case .B: return "B"; case .X: return "X"; case .Y: return "Y"
        case .L: return "L"; case .R: return "R"; case .ZL: return "ZL"; case .ZR: return "ZR"
        case .PLUS: return "+"; case .MINUS: return "−"
        case .LS: return "L3"; case .RS: return "R3"
        case .UP, .LUP, .RUP: return "↑"
        case .DOWN, .LDOWN, .RDOWN: return "↓"
        case .LEFT, .LLEFT, .RLEFT: return "←"
        case .RIGHT, .LRIGHT, .RRIGHT: return "→"
        case .SHAKE: return "≋"
        }
    }
    var shortBadge: String {
        switch self {
        case .A: return "Switch A"; case .B: return "Switch B"; case .X: return "Switch X"; case .Y: return "Switch Y"
        case .L: return "L"; case .R: return "R"; case .ZL: return "ZL"; case .ZR: return "ZR"
        case .PLUS: return "+ Start"; case .MINUS: return "− Select"
        case .LS: return "L3"; case .RS: return "R3"
        case .UP: return "D-Pad ↑"; case .DOWN: return "D-Pad ↓"; case .LEFT: return "D-Pad ←"; case .RIGHT: return "D-Pad →"
        case .LUP: return "L-Stick ↑"; case .LDOWN: return "L-Stick ↓"; case .LLEFT: return "L-Stick ←"; case .LRIGHT: return "L-Stick →"
        case .RUP: return "R-Stick ↑"; case .RDOWN: return "R-Stick ↓"; case .RLEFT: return "R-Stick ←"; case .RRIGHT: return "R-Stick →"
        case .SHAKE: return "Agitar ≋"
        }
    }
    var title: String {
        switch self {
        case .A: return "Botón A (Este)"; case .B: return "Botón B (Sur)"; case .X: return "Botón X (Norte)"; case .Y: return "Botón Y (Oeste)"
        case .L: return "Hombro L"; case .R: return "Hombro R"; case .ZL: return "Gatillo ZL"; case .ZR: return "Gatillo ZR"
        case .PLUS: return "+ (Start / Pausa)"; case .MINUS: return "− (Select)"
        case .LS: return "Pulsar stick izq. (L3)"; case .RS: return "Pulsar stick der. (R3)"
        case .UP: return "Cruceta arriba"; case .DOWN: return "Cruceta abajo"; case .LEFT: return "Cruceta izquierda"; case .RIGHT: return "Cruceta derecha"
        case .LUP: return "Stick Izq. Arriba"; case .LDOWN: return "Stick Izq. Abajo"; case .LLEFT: return "Stick Izq. Izquierda"; case .LRIGHT: return "Stick Izq. Derecha"
        case .RUP: return "Stick Der. Arriba"; case .RDOWN: return "Stick Der. Abajo"; case .RLEFT: return "Stick Der. Izquierda"; case .RRIGHT: return "Stick Der. Derecha"
        case .SHAKE: return "Agitar mando (Sensor)"
        }
    }
    var tint: NSColor {
        switch self {
        case .A: return .systemRed; case .B: return .systemYellow; case .X: return .systemBlue; case .Y: return .systemGreen
        case .L, .R, .ZL, .ZR: return .systemPurple
        case .LUP, .LDOWN, .LLEFT, .LRIGHT: return .systemTeal
        case .RUP, .RDOWN, .RLEFT, .RRIGHT: return .systemIndigo
        case .UP, .DOWN, .LEFT, .RIGHT: return .systemCyan
        default: return .systemOrange
        }
    }
}

/// Physical inputs on an Xbox / Extended Gamepad (matches pi_names in front_mac.m)
enum PadInput: String, CaseIterable, Identifiable {
    case A, B, X, Y
    case LB, RB, LT, RT
    case VIEW, MENU, LS, RS
    case DUP, DDOWN, DLEFT, DRIGHT
    case LUP, LDOWN, LLEFT, LRIGHT
    case RUP, RDOWN, RLEFT, RRIGHT
    var id: String { rawValue }

    var xboxLabel: String {
        switch self {
        case .A: return "A"; case .B: return "B"; case .X: return "X"; case .Y: return "Y"
        case .LB: return "LB"; case .RB: return "RB"; case .LT: return "LT"; case .RT: return "RT"
        case .VIEW: return "⧉ View"; case .MENU: return "≡ Menu"
        case .LS: return "L3"; case .RS: return "R3"
        case .DUP: return "D-Pad ↑"; case .DDOWN: return "D-Pad ↓"; case .DLEFT: return "D-Pad ←"; case .DRIGHT: return "D-Pad →"
        case .LUP: return "LS ↑"; case .LDOWN: return "LS ↓"; case .LLEFT: return "LS ←"; case .LRIGHT: return "LS →"
        case .RUP: return "RS ↑"; case .RDOWN: return "RS ↓"; case .RLEFT: return "RS ←"; case .RRIGHT: return "RS →"
        }
    }

    var xboxTitle: String {
        switch self {
        case .A: return "Botón A (Rojo · Este / Derecha)"
        case .B: return "Botón B (Amarillo · Sur / Abajo)"
        case .X: return "Botón X (Azul · Norte / Arriba)"
        case .Y: return "Botón Y (Verde · Oeste / Izquierda)"
        case .LB: return "LB / L (Bumper Izq.)"
        case .RB: return "RB / R (Bumper Der.)"
        case .LT: return "LT / ZL (Gatillo Izq.)"
        case .RT: return "RT / ZR (Gatillo Der.)"
        case .VIEW: return "View ⧉ / − (Select)"
        case .MENU: return "Menu ≡ / + (Start)"
        case .LS: return "Clic Stick Izq. (L3)"
        case .RS: return "Clic Stick Der. (R3)"
        case .DUP: return "Cruceta Arriba"
        case .DDOWN: return "Cruceta Abajo"
        case .DLEFT: return "Cruceta Izquierda"
        case .DRIGHT: return "Cruceta Derecha"
        case .LUP: return "Stick Izq. Arriba"
        case .LDOWN: return "Stick Izq. Abajo"
        case .LLEFT: return "Stick Izq. Izquierda"
        case .LRIGHT: return "Stick Izq. Derecha"
        case .RUP: return "Stick Der. Arriba"
        case .RDOWN: return "Stick Der. Abajo"
        case .RLEFT: return "Stick Der. Izquierda"
        case .RRIGHT: return "Stick Der. Derecha"
        }
    }

    var xboxColor: NSColor {
        switch self {
        case .A: return NSColor(calibratedRed: 0.92, green: 0.22, blue: 0.24, alpha: 1) // Switch A Red (East)
        case .B: return NSColor(calibratedRed: 0.96, green: 0.76, blue: 0.12, alpha: 1) // Switch B Yellow (South)
        case .X: return NSColor(calibratedRed: 0.16, green: 0.56, blue: 0.96, alpha: 1) // Switch X Blue (North)
        case .Y: return NSColor(calibratedRed: 0.18, green: 0.80, blue: 0.35, alpha: 1) // Switch Y Green (West)
        case .LB, .RB, .LT, .RT: return .systemPurple
        case .LUP, .LDOWN, .LLEFT, .LRIGHT, .LS: return .systemTeal
        case .RUP, .RDOWN, .RLEFT, .RRIGHT, .RS: return .systemIndigo
        case .DUP, .DDOWN, .DLEFT, .DRIGHT: return .systemCyan
        case .VIEW, .MENU: return .systemOrange
        }
    }
}

/// Device assignment per player
enum DeviceAssignment: Equatable, Hashable {
    case auto
    case none
    case controller(index: Int, name: String)

    var label: String {
        switch self {
        case .auto: return "Automático (Por orden de conexión)"
        case .none: return "Solo Teclado (Sin mando en este jugador)"
        case .controller(let idx, let name): return "Mando #\(idx + 1): \(name)"
        }
    }

    var shortLabel: String {
        switch self {
        case .auto: return "Auto"
        case .none: return "Solo Teclado"
        case .controller(let idx, _): return "Mando #\(idx + 1)"
        }
    }
}

struct ControlGroup: Identifiable {
    let id: String; let title: String; let symbol: String; let controls: [Control]
    static let all: [ControlGroup] = [
        .init(id: "face", title: "Botones frontales (Switch)", symbol: "circle.grid.cross", controls: [.A, .B, .X, .Y]),
        .init(id: "shoulder", title: "Hombros y Gatillos", symbol: "l.rectangle.roundedbottom", controls: [.L, .R, .ZL, .ZR]),
        .init(id: "lstick", title: "Stick izquierdo", symbol: "l.joystick", controls: [.LUP, .LDOWN, .LLEFT, .LRIGHT, .LS]),
        .init(id: "rstick", title: "Stick derecho", symbol: "r.joystick", controls: [.RUP, .RDOWN, .RLEFT, .RRIGHT, .RS]),
        .init(id: "dpad", title: "Cruceta (D-Pad)", symbol: "dpad", controls: [.UP, .DOWN, .LEFT, .RIGHT]),
        .init(id: "system", title: "Sistema y Sensor", symbol: "gearshape", controls: [.PLUS, .MINUS, .SHAKE]),
    ]
}

/// keys[player][control] = key codes
struct KeyMap: Equatable {
    var keys: [[Control: [UInt16]]] = Array(repeating: [:], count: kPlayers)

    static let builtIn: KeyMap = {   // front_mac.m kmap_defaults
        var m = KeyMap()
        let d: [(UInt16, Control)] = [(13, .LUP), (0, .LLEFT), (1, .LDOWN), (2, .LRIGHT), (123, .LEFT), (126, .UP), (124, .RIGHT), (125, .DOWN),
                                      (38, .A), (40, .B), (32, .X), (34, .Y), (3, .LS), (5, .RS), (12, .L), (14, .R), (6, .ZL), (8, .ZR),
                                      (36, .PLUS), (48, .MINUS), (49, .SHAKE)]
        for (k, c) in d { m.keys[0][c, default: []].append(k) }
        return m
    }()

    func usedPlayers() -> [Int] { (0..<kPlayers).filter { !keys[$0].values.allSatisfy { $0.isEmpty } } }
    func hasKeys(for player: Int) -> Bool {
        guard player >= 0 && player < kPlayers else { return false }
        return !keys[player].values.allSatisfy { $0.isEmpty }
    }

    static func player2ArrowsPreset() -> [Control: [UInt16]] {
        var d: [Control: [UInt16]] = [:]
        d[.LUP] = [126]; d[.LDOWN] = [125]; d[.LLEFT] = [123]; d[.LRIGHT] = [124] // Flechas
        d[.UP] = [126]; d[.DOWN] = [125]; d[.LEFT] = [123]; d[.RIGHT] = [124]
        d[.A] = [83]   // Num 1
        d[.B] = [84]   // Num 2
        d[.X] = [86]   // Num 4
        d[.Y] = [87]   // Num 5
        d[.L] = [89]   // Num 7
        d[.R] = [91]   // Num 8
        d[.ZL] = [92]  // Num 9
        d[.ZR] = [78]  // Num -
        d[.PLUS] = [76] // Num Enter
        d[.MINUS] = [69] // Num +
        return d
    }

    static func player2IJKLPreset() -> [Control: [UInt16]] {
        var d: [Control: [UInt16]] = [:]
        d[.LUP] = [34]; d[.LDOWN] = [40]; d[.LLEFT] = [38]; d[.LRIGHT] = [37] // I, K, J, L
        d[.A] = [45]   // N
        d[.B] = [46]   // M
        d[.X] = [35]   // P
        d[.Y] = [31]   // O
        d[.L] = [33]   // [
        d[.R] = [30]   // ]
        d[.ZL] = [41]  // ;
        d[.ZR] = [39]  // '
        d[.PLUS] = [36] // Return
        d[.MINUS] = [48] // Tab
        return d
    }

    static func parse(_ text: String) -> KeyMap {
        var m = KeyMap()
        for line in text.split(whereSeparator: \.isNewline) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            let f = t.split(whereSeparator: { $0 == "\t" || $0 == " " })
            guard f.count >= 3, let p = Int(f[0]), (1...kPlayers).contains(p), let c = Control(rawValue: f[1].uppercased()), let k = UInt16(f[2]), k < 256 else { continue }
            if !(m.keys[p - 1][c]?.contains(k) ?? false) { m.keys[p - 1][c, default: []].append(k) }
        }
        return m
    }

    func serialize(gameName: String) -> String {
        var s = "# nxnative keyboard map — \(gameName)\n# Written by NX Controles. Format: player <TAB> control <TAB> macOS key code\n"
        for p in 0..<kPlayers {
            for c in Control.allCases { for k in keys[p][c] ?? [] { s += "\(p + 1)\t\(c.rawValue)\t\(k)\t# \(KeyNames.name(k))\n" } }
        }
        return s
    }
}

/// inputs[player][control] = physical Xbox/gamepad inputs driving that Switch control
struct PadMap: Equatable {
    var inputs: [[Control: [PadInput]]] = Array(repeating: PadMap.defaultPlayerDict, count: kPlayers)
    var devices: [DeviceAssignment] = Array(repeating: .auto, count: kPlayers)

    static let defaultPairs: [(PadInput, Control)] = [
        (.A, .A), (.B, .B), (.X, .X), (.Y, .Y),
        (.LS, .LS), (.RS, .RS), (.LB, .L), (.RB, .R), (.LT, .ZL), (.RT, .ZR),
        (.MENU, .PLUS), (.VIEW, .MINUS),
        (.DLEFT, .LEFT), (.DUP, .UP), (.DRIGHT, .RIGHT), (.DDOWN, .DOWN),
        (.LUP, .LUP), (.LDOWN, .LDOWN), (.LLEFT, .LLEFT), (.LRIGHT, .LRIGHT),
        (.RUP, .RUP), (.RDOWN, .RDOWN), (.RLEFT, .RLEFT), (.RRIGHT, .RRIGHT),
    ]

    static let defaultPlayerDict: [Control: [PadInput]] = {
        var d: [Control: [PadInput]] = [:]
        for (pi, c) in defaultPairs { d[c, default: []].append(pi) }
        return d
    }()

    static let xboxLabelsPlayerDict: [Control: [PadInput]] = {
        var d = defaultPlayerDict
        d[.A] = [.B]; d[.B] = [.A]; d[.X] = [.Y]; d[.Y] = [.X]
        return d
    }()

    static let smashProPlayerDict: [Control: [PadInput]] = {
        var d = defaultPlayerDict
        d[.A] = [.B]           // Attack on B / Right
        d[.B] = [.A]           // Special on A / Bottom
        d[.X] = [.Y, .X]       // Jump on both Y and X
        d[.Y] = []
        d[.L] = [.LB, .RB]     // Grab on Bumpers
        d[.R] = []
        d[.ZL] = [.LT, .RT]    // Shield on Triggers
        d[.ZR] = []
        return d
    }()

    static let builtIn = PadMap()

    func isPlayerCustomized(_ p: Int) -> Bool {
        inputs[p] != PadMap.defaultPlayerDict || devices[p] != .auto
    }
    func customizedPlayers() -> [Int] { (0..<kPlayers).filter { isPlayerCustomized($0) } }

    /// Which Switch controls are triggered by a given Xbox physical input `pi` for `player`
    func controls(for pi: PadInput, player p: Int) -> [Control] {
        Control.allCases.filter { inputs[p][$0]?.contains(pi) ?? false }
    }

    /// Sets a single Xbox physical input `pi` to trigger the given `controls` (replacing previous bindings of `pi`)
    mutating func setControls(_ newControls: [Control], for pi: PadInput, player p: Int) {
        for c in Control.allCases {
            inputs[p][c]?.removeAll { $0 == pi }
        }
        for c in newControls {
            if !(inputs[p][c]?.contains(pi) ?? false) {
                inputs[p][c, default: []].append(pi)
            }
        }
    }

    static func parse(_ text: String) -> PadMap {
        var m = PadMap()
        var cleared: Set<Int> = []
        for line in text.split(whereSeparator: \.isNewline) {
            let noComment = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? Substring()
            let t = noComment.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            let f = t.split(maxSplits: 2, whereSeparator: { $0 == "\t" || $0 == " " })
            guard f.count >= 3, let p = Int(f[0]), (1...kPlayers).contains(p) else { continue }

            let col1 = f[1].uppercased()
            let rawCol2 = f[2].trimmingCharacters(in: .whitespaces)
            let col2 = rawCol2.uppercased()

            // Device assignment directive
            if col1 == "DEVICE" {
                if col2 == "AUTO" {
                    m.devices[p - 1] = .auto
                } else if col2 == "NONE" {
                    m.devices[p - 1] = .none
                } else if col2.hasPrefix("PAD:") {
                    let sub = rawCol2.split(separator: ":", maxSplits: 2)
                    let idx = sub.count > 1 ? (Int(sub[1]) ?? 0) : 0
                    let name = sub.count > 2 ? String(sub[2]).trimmingCharacters(in: .whitespaces) : "Mando \(idx + 1)"
                    m.devices[p - 1] = .controller(index: idx, name: name)
                }
                continue
            }

            if !cleared.contains(p - 1) {
                m.inputs[p - 1] = [:]
                cleared.insert(p - 1)
            }
            if col1 == "NONE" || col2 == "NONE" { continue }
            guard let c = Control(rawValue: col1), let pi = PadInput(rawValue: col2) else { continue }
            if !(m.inputs[p - 1][c]?.contains(pi) ?? false) {
                m.inputs[p - 1][c, default: []].append(pi)
            }
        }
        return m
    }

    func serialize(gameName: String) -> String {
        var s = "# nxnative gamepad map — \(gameName)\n# Written by NX Controles. Format: player <TAB> switch_control <TAB> xbox_input\n"
        // 1. Device assignments
        for p in 0..<kPlayers {
            switch devices[p] {
            case .auto:
                break // default, keep file concise
            case .none:
                s += "\(p + 1)\tDEVICE\tNONE\n"
            case .controller(let idx, let name):
                s += "\(p + 1)\tDEVICE\tPAD:\(idx):\(name)\n"
            }
        }
        // 2. Control mappings
        for p in 0..<kPlayers {
            var any = false
            for c in Control.allCases {
                for pi in inputs[p][c] ?? [] {
                    s += "\(p + 1)\t\(c.rawValue)\t\(pi.rawValue)\t# Xbox \(pi.xboxLabel) -> Switch \(c.shortBadge)\n"
                    any = true
                }
            }
            if !any { s += "\(p + 1)\tNONE\tNONE\n" }
        }
        return s
    }
}

enum KeyNames {
    static let table: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 10: "§", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
        32: "U", 33: "[", 34: "I", 35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        48: "Tab", 49: "Espacio", 50: "`", 51: "Borrar", 53: "Esc", 56: "⇧ izq", 58: "⌥ izq", 59: "⌃ izq", 60: "⇧ der", 61: "⌥ der", 62: "⌃ der",
        65: "Num .", 67: "Num *", 69: "Num+", 71: "NumClear", 75: "Num/", 76: "NumEnter", 78: "Num-", 81: "Num=",
        82: "Num0", 83: "Num1", 84: "Num2", 85: "Num3", 86: "Num4", 87: "Num5", 88: "Num6", 89: "Num7", 91: "Num8", 92: "Num9",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        114: "Help", 115: "Inicio", 116: "RePág", 117: "Supr", 118: "F4", 119: "Fin", 120: "F2", 121: "AvPág", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
    static func name(_ k: UInt16) -> String { table[k] ?? "Tecla\(k)" }
    static let unusable: Set<UInt16> = [54, 55, 57, 63, 179]
}

struct Game: Identifiable, Hashable {
    let id: String          // title ID, or "" for the global map
    var name: String
    var appURL: URL?
    var engine: String = "nxnative" // "nxnative" or "Astris"
    var romURL: URL? = nil
    var isGlobal: Bool { id.isEmpty }
    static let global = Game(id: "", name: "Todos los juegos", appURL: nil, engine: "Todos", romURL: nil)
}

enum GameFilter: String, CaseIterable, Identifiable {
    case all = "Todos"
    case native = "Nativos"
    case astris = "Astris"
    var id: String { rawValue }
}

enum Paths {
    static let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/nxnative")
    static let profilesJson = support.appendingPathComponent("profiles.json")
    static func keymap(_ g: Game) -> URL {
        let cleanId = g.id.components(separatedBy: " ").first ?? g.id
        return g.isGlobal ? support.appendingPathComponent("keymap.tsv") : support.appendingPathComponent(cleanId).appendingPathComponent("keymap.tsv")
    }
    static func padmap(_ g: Game) -> URL {
        let cleanId = g.id.components(separatedBy: " ").first ?? g.id
        return g.isGlobal ? support.appendingPathComponent("padmap.tsv") : support.appendingPathComponent(cleanId).appendingPathComponent("padmap.tsv")
    }
}

/// A user-saved profile for controller or keyboard with a customizable/editable name.
struct CustomProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var mode: String // "gamepad" or "keyboard"
    var dateCreated: Date = Date()
    var padInputs: [String: [String]]?
    var keyInputs: [String: [UInt16]]?

    var isGamepad: Bool { mode == "gamepad" }

    var buttonCount: Int {
        if isGamepad {
            return padInputs?.values.reduce(0) { $0 + $1.count } ?? 0
        } else {
            return keyInputs?.values.reduce(0) { $0 + $1.count } ?? 0
        }
    }
}
