import Foundation

public enum AstrisConfig {
    public static let plistPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Containers/V380-Ori.Astris/Data/Library/Preferences/V380-Ori.Astris.plist"
    }()

    public static func ryuKeyName(for code: UInt16) -> String {
        switch code {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "Number1"
        case 19: return "Number2"
        case 20: return "Number3"
        case 21: return "Number4"
        case 22: return "Number6"
        case 23: return "Number5"
        case 24: return "Plus"
        case 25: return "Number9"
        case 26: return "Number7"
        case 27: return "Minus"
        case 28: return "Number8"
        case 29: return "Number0"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 41: return "Semicolon"
        case 45: return "N"
        case 46: return "M"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "BackSpace"
        case 53: return "Escape"
        case 123: return "Left"
        case 124: return "Right"
        case 125: return "Down"
        case 126: return "Up"
        default: return "Unbound"
        }
    }

    static func keyForControl(_ ctrl: Control, player: Int, keyMap: KeyMap?) -> String {
        guard let map = keyMap, player < map.keys.count, let codes = map.keys[player][ctrl], let first = codes.first else {
            switch ctrl {
            case .A: return "J"
            case .B: return "K"
            case .X: return "U"
            case .Y: return "I"
            case .L: return "Q"
            case .R: return "E"
            case .ZL: return "Z"
            case .ZR: return "C"
            case .PLUS: return "Return"
            case .MINUS: return "Tab"
            case .UP: return "Up"
            case .DOWN: return "Down"
            case .LEFT: return "Left"
            case .RIGHT: return "Right"
            case .LUP: return "W"
            case .LDOWN: return "S"
            case .LLEFT: return "A"
            case .LRIGHT: return "D"
            case .LS: return "F"
            case .RS: return "G"
            default: return "Unbound"
            }
        }
        return ryuKeyName(for: first)
    }

    static func ensureConfigured(
        activeSlots: Set<Int> = [0],
        keyMap: KeyMap? = nil,
        playerModes: [InputDeviceMode] = Array(repeating: .keyboard, count: 8)
    ) {
        guard FileManager.default.fileExists(atPath: plistPath) else { return }

        guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
              var plist = (try? PropertyListSerialization.propertyList(from: plistData, options: .mutableContainersAndLeaves, format: nil)) as? [String: Any] else {
            return
        }

        guard let rawOptions = plist["RyujinxOptions"] as? Data,
              var ryu = (try? JSONSerialization.jsonObject(with: rawOptions, options: .mutableContainers)) as? [String: Any],
              var configs = ryu["playerInputConfig"] as? [[String: Any]] else {
            return
        }

        for i in 0..<configs.count {
            var cfg = configs[i]

            if !activeSlots.contains(i) {
                // Jugador inactivo -> Desactivar en Astris
                cfg["backend"] = "Invalid"
                cfg["controllerId"] = nil
                configs[i] = cfg
                continue
            }

            let mode = i < playerModes.count ? playerModes[i] : .keyboard

            if mode == .keyboard {
                // Modo Teclado Nativo (WindowKeyboard):
                // Cero permisos de macOS requeridos, latencia cero, configurado desde NX Controles
                cfg["playerIndex"] = "Player\(i + 1)"
                cfg["backend"] = "WindowKeyboard"
                cfg["controllerId"] = "\(i)"
                cfg["controllerType"] = "ProController"
                cfg["useNintendoLayout"] = false
                cfg["enableMotion"] = true
                cfg["enableCemuHookMotion"] = true
                cfg["dsuServerHost"] = "127.0.0.1"
                cfg["dsuServerPort"] = 26760
                cfg["dsuSlot"] = i
                cfg["dsuAltSlot"] = i
                cfg["dsuMirrorInput"] = true
                cfg["enableRumble"] = true
                cfg["enableLight"] = true
                cfg["enableSidewaysOrientation"] = false

                cfg["rightJoycon"] = [
                    "buttonA": keyForControl(.A, player: i, keyMap: keyMap),
                    "buttonB": keyForControl(.B, player: i, keyMap: keyMap),
                    "buttonX": keyForControl(.X, player: i, keyMap: keyMap),
                    "buttonY": keyForControl(.Y, player: i, keyMap: keyMap),
                    "buttonPlus": keyForControl(.PLUS, player: i, keyMap: keyMap),
                    "buttonR": keyForControl(.R, player: i, keyMap: keyMap),
                    "buttonZr": keyForControl(.ZR, player: i, keyMap: keyMap),
                    "buttonSl": "Unbound",
                    "buttonSr": "Unbound"
                ]

                cfg["leftJoycon"] = [
                    "buttonL": keyForControl(.L, player: i, keyMap: keyMap),
                    "buttonZl": keyForControl(.ZL, player: i, keyMap: keyMap),
                    "buttonMinus": keyForControl(.MINUS, player: i, keyMap: keyMap),
                    "dpadUp": keyForControl(.UP, player: i, keyMap: keyMap),
                    "dpadDown": keyForControl(.DOWN, player: i, keyMap: keyMap),
                    "dpadLeft": keyForControl(.LEFT, player: i, keyMap: keyMap),
                    "dpadRight": keyForControl(.RIGHT, player: i, keyMap: keyMap),
                    "buttonSl": "Unbound",
                    "buttonSr": "Unbound"
                ]

                cfg["leftJoyconStick"] = [
                    "stickUp": keyForControl(.LUP, player: i, keyMap: keyMap),
                    "stickDown": keyForControl(.LDOWN, player: i, keyMap: keyMap),
                    "stickLeft": keyForControl(.LLEFT, player: i, keyMap: keyMap),
                    "stickRight": keyForControl(.LRIGHT, player: i, keyMap: keyMap),
                    "stickButton": keyForControl(.LS, player: i, keyMap: keyMap)
                ]

                cfg["rightJoyconStick"] = [
                    "stickUp": "I",
                    "stickDown": "K",
                    "stickLeft": "J",
                    "stickRight": "L",
                    "stickButton": keyForControl(.RS, player: i, keyMap: keyMap)
                ]
            } else {
                // Modo Mando / Móvil (DSU):
                let expectedId = "DSU/127.0.0.1:26760/\(i)"
                cfg["playerIndex"] = "Player\(i + 1)"
                cfg["backend"] = "Dsu"
                cfg["controllerId"] = expectedId
                cfg["dsuSlot"] = i
                cfg["dsuAltSlot"] = i
                cfg["dsuServerHost"] = "127.0.0.1"
                cfg["dsuServerPort"] = 26760
                cfg["dsuMirrorInput"] = true
                cfg["enableCemuHookMotion"] = true
                cfg["enableMotion"] = true
                cfg["enableRumble"] = true
                cfg["useNintendoLayout"] = false
                cfg["controllerType"] = "ProController"
                cfg["enableSidewaysOrientation"] = false

                cfg["leftJoyconStick"] = [
                    "joystick": "Left",
                    "stickButton": "LeftStick",
                    "invertStickX": false,
                    "invertStickY": false,
                    "rotate90CW": false
                ]
                cfg["rightJoyconStick"] = [
                    "joystick": "Right",
                    "stickButton": "RightStick",
                    "invertStickX": false,
                    "invertStickY": false,
                    "rotate90CW": false
                ]
                cfg["leftJoycon"] = [
                    "dpadDown": "DpadDown", "buttonSr": "Unbound", "dpadUp": "DpadUp",
                    "buttonZl": "LeftTrigger", "dpadRight": "DpadRight", "dpadLeft": "DpadLeft",
                    "buttonMinus": "Minus", "buttonL": "LeftShoulder", "buttonSl": "Unbound"
                ]
                cfg["rightJoycon"] = [
                    "buttonPlus": "Plus", "buttonY": "Y", "buttonR": "RightShoulder",
                    "buttonX": "X", "buttonB": "B", "buttonZr": "RightTrigger",
                    "buttonSr": "Unbound", "buttonA": "A", "buttonSl": "Unbound"
                ]
            }

            configs[i] = cfg
        }

        plist["monitorBackgroundEvents"] = true
        ryu["playerInputConfig"] = configs

        if let newRaw = try? JSONSerialization.data(withJSONObject: ryu, options: []) {
            plist["RyujinxOptions"] = newRaw
            if let updatedPlistData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) {
                try? updatedPlistData.write(to: URL(fileURLWithPath: plistPath))
            }
        }
    }

    public static func ensureDSUConfigured(activeSlots: Set<Int> = [0]) {
        ensureConfigured(activeSlots: activeSlots)
    }
}
