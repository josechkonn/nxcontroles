import AppKit
import GameController
import SwiftUI

enum MapSource { case own, global, builtIn }

@MainActor
final class Store: ObservableObject {
    @Published var games: [Game] = []
    @Published var selectedID: String? = "" {
        didSet {
            if oldValue != selectedID && selectedID != RemoteStore.sidebarID {
                load()
            }
        }
    }
    var selection: Game? {
        guard let id = selectedID, id != RemoteStore.sidebarID else { return nil }
        return id.isEmpty ? .global : games.first { $0.id == id }
    }

    let remote = RemoteStore()
    @Published var showRemoteBanner: Bool = false {
        didSet {
            if showRemoteBanner {
                qrTargetPlayer = player
                syncCurrentPadMapToMobile()
            } else if qrTargetPlayer == player {
                qrTargetPlayer = nil
            }
        }
    }
    @Published var qrTargetPlayer: Int? = nil
    @Published var lastSyncMessage: String? = nil

    @Published var deviceMode: InputDeviceMode = .gamepad {
        didSet { capturing = nil; capturingPad = nil }
    }
    @Published var playerDeviceModes: [InputDeviceMode] = Array(repeating: .gamepad, count: kPlayers)
    @Published var map = KeyMap()
    @Published var keySource: MapSource = .builtIn
    @Published var padMap = PadMap()
    @Published var padSource: MapSource = .builtIn

    var activeSource: MapSource { deviceMode == .gamepad ? padSource : keySource }

    @Published var player = 0 {
        didSet {
            capturing = nil; capturingPad = nil
            // Reset live controller visual state when switching between J1, J2, etc.
            pressedPadInputs.removeAll()
            leftStick = .zero
            rightStick = .zero
            leftTrigger = 0
            rightTrigger = 0
            if player >= 0 && player < playerDeviceModes.count {
                deviceMode = playerDeviceModes[player]
            }
            if showRemoteBanner {
                qrTargetPlayer = player
            }
            syncCurrentPadMapToMobile()
        }
    }

    // Capture states (click and wait for key / controller button press)
    @Published var capturing: (player: Int, control: Control)? = nil
    @Published var capturingPad: (player: Int, control: Control)? = nil {
        didSet {
            if capturingPad != nil {
                pressedPadInputs.removeAll()
            }
        }
    }
    @Published var hoveredControl: Control? = nil

    // Live hardware telemetry
    @Published var pressed: Set<UInt16> = []
    @Published var pressedPadInputs: Set<PadInput> = []
    @Published var leftStick: CGPoint = .zero
    @Published var rightStick: CGPoint = .zero
    @Published var leftTrigger: Double = 0
    @Published var rightTrigger: Double = 0
    @Published var connectedPads: [String] = []
    @Published var identifyingPadForPlayer: Int? = nil
    @Published var isAccessibilityGranted: Bool = true

    @Published var lastError: String?
    @Published var gameFilter: GameFilter = .all
    @Published var scanFolders: [String] {
        didSet { UserDefaults.standard.set(scanFolders, forKey: "scanFolders"); scan() }
    }
    private var monitor: Any?
    private var globalMonitor: Any?
    private var globalEventTap: CFMachPort?
    private var globalRunLoopSource: CFRunLoopSource?

    var filteredGames: [Game] {
        switch gameFilter {
        case .all:
            return games
        case .native:
            return games.filter { $0.engine != "Astris" }
        case .astris:
            return games.filter { $0.engine == "Astris" }
        }
    }

    var nativeGamesCount: Int { games.filter { $0.engine != "Astris" }.count }
    var astrisGamesCount: Int { games.filter { $0.engine == "Astris" }.count }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        scanFolders = UserDefaults.standard.stringArray(forKey: "scanFolders") ?? ["/Volumes/Externo/Games", "/Applications", home + "/Applications", home + "/Games"]
        scan()
        load()
        loadCustomProfiles()
        installMonitor()
        installGamepadMonitor()
        _ = DSUServer.shared
        DSUServer.shared.setKeyMap(map)
        syncAstrisConfig()
    }

    func syncAstrisConfig() {
        var active: Set<Int> = [0] // Player 1 (J1) siempre activo
        for p in 1..<kPlayers {
            if isPlayerConnected(p) {
                active.insert(p)
            }
        }
        AstrisConfig.ensureConfigured(
            activeSlots: active,
            keyMap: self.map,
            playerModes: self.playerDeviceModes
        )
    }

    // MARK: - Games Discovery

    func scan() {
        var found: [String: Game] = [:]
        let fm = FileManager.default
        for folder in scanFolders {
            guard let items = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil) else { continue }
            for url in items where url.pathExtension == "app" {
                guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
                      let id = info["DMTitleID"] as? String, !id.isEmpty else { continue }
                let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
                found[id] = Game(id: id, name: name, appURL: url)
            }
        }
        if let dirs = try? fm.contentsOfDirectory(atPath: Paths.support.path) {
            for id in dirs where id.count == 16 && id.allSatisfy(\.isHexDigit) && found[id] == nil {
                found[id] = Game(id: id, name: profileName(id) ?? id, appURL: nil)
            }
        }

        // Scan Astris Games folder
        let astrisDir = URL(fileURLWithPath: "/Volumes/Externo/Games/Astris Games")
        if let astrisItems = try? fm.contentsOfDirectory(at: astrisDir, includingPropertiesForKeys: nil) {
            for item in astrisItems {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    let folderName = item.lastPathComponent
                    let lowerFolder = folderName.lowercased()
                    if folderName.hasPrefix(".") || ["bis", "games", "profiles", "sdcard", "system"].contains(lowerFolder) { continue }
                    if let files = try? fm.contentsOfDirectory(atPath: item.path) {
                        let romFiles = files.filter { f in
                            let lower = f.lowercased()
                            return lower.hasSuffix(".nsp") || lower.hasSuffix(".xci") || lower.hasSuffix(".nsz")
                        }

                        // Prioritize base games over updates/patches
                        let sortedFiles = romFiles.sorted { f1, f2 in
                            let isBase1 = f1.contains("000]") || f1.lowercased().contains("base") || (!f1.lowercased().contains("update") && !f1.lowercased().contains("up v"))
                            let isBase2 = f2.contains("000]") || f2.lowercased().contains("base") || (!f2.lowercased().contains("update") && !f2.lowercased().contains("up v"))
                            if isBase1 != isBase2 { return isBase1 && !isBase2 }
                            return f1 < f2
                        }

                        var bestTID: String? = nil
                        var bestName: String = folderName
                        var bestRomURL: URL? = nil

                        for f in sortedFiles {
                            if let startIdx = f.range(of: "[0100")?.lowerBound,
                               let endIdx = f[startIdx...].range(of: "]")?.lowerBound {
                                var tid = String(f[startIdx...endIdx].dropFirst().dropLast()).uppercased()
                                if tid.count == 16 && tid.allSatisfy(\.isHexDigit) {
                                    if tid.hasSuffix("800") {
                                        tid = String(tid.dropLast(3)) + "000"
                                    }
                                    bestTID = tid
                                    bestRomURL = item.appendingPathComponent(f)
                                    let candidateName = String(f[..<startIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !candidateName.isEmpty {
                                        bestName = candidateName
                                    }
                                    break // Only 1 game entry per folder!
                                }
                            }
                        }

                        if let tid = bestTID {
                            let astrisApp = URL(fileURLWithPath: "/Volumes/Externo/Games/Astris.app")
                            let appIconURL = fm.fileExists(atPath: astrisApp.path) ? astrisApp : item
                            if found[tid] == nil || (found[tid]?.appURL == nil && found[tid]?.romURL == nil) {
                                found[tid] = Game(id: tid, name: bestName, appURL: appIconURL, engine: "Astris", romURL: bestRomURL)
                            } else if found[tid]?.engine != "Astris" {
                                let astrisId = "\(tid) (Astris)"
                                found[astrisId] = Game(id: astrisId, name: "\(bestName) (Astris)", appURL: appIconURL, engine: "Astris", romURL: bestRomURL)
                            }
                        }
                    }
                }
            }
        }
        games = found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func profileName(_ id: String) -> String? {
        let p = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("nxnative/dm/games/\(id)/game.tsv")
        guard let first = (try? String(contentsOf: p, encoding: .utf8))?.split(separator: "\n").first,
              let r = first.range(of: "Game profile of ") else { return nil }
        let rest = first[r.upperBound...]
        return String(rest.split(separator: "(").first ?? rest).trimmingCharacters(in: .whitespaces)
    }

    func hasOwnKeyMap(_ g: Game) -> Bool { FileManager.default.fileExists(atPath: Paths.keymap(g).path) }
    func hasOwnPadMap(_ g: Game) -> Bool { FileManager.default.fileExists(atPath: Paths.padmap(g).path) }
    func hasOwnMap(_ g: Game) -> Bool { hasOwnKeyMap(g) || hasOwnPadMap(g) }

    // MARK: - Load & Save

    func readKeyMap(_ g: Game) -> KeyMap? {
        guard let t = try? String(contentsOf: Paths.keymap(g), encoding: .utf8) else { return nil }
        return KeyMap.parse(t)
    }

    func readPadMap(_ g: Game) -> PadMap? {
        guard let t = try? String(contentsOf: Paths.padmap(g), encoding: .utf8) else { return nil }
        return PadMap.parse(t)
    }

    func effectiveKey(_ g: Game) -> (KeyMap, MapSource) {
        if let m = readKeyMap(g) { return (m, .own) }
        if !g.isGlobal, let m = readKeyMap(.global) { return (m, .global) }
        return (KeyMap.builtIn, .builtIn)
    }

    func effectivePad(_ g: Game) -> (PadMap, MapSource) {
        if let m = readPadMap(g) { return (m, .own) }
        if !g.isGlobal, let m = readPadMap(.global) { return (m, .global) }
        return (PadMap.builtIn, .builtIn)
    }

    func load() {
        capturing = nil; capturingPad = nil
        guard let g = selection else { return }
        (map, keySource) = effectiveKey(g)
        (padMap, padSource) = effectivePad(g)
        DSUServer.shared.setKeyMap(map)

        // Clean up any stale "NONE" (Solo Teclado) on J2..J8 if that player has no keyboard keys configured
        var didCleanStale = false
        for p in 1..<kPlayers {
            if padMap.devices[p] == .none && !map.hasKeys(for: p) {
                padMap.devices[p] = .auto
                didCleanStale = true
            }
        }
        // Deduplicate explicit controller assignments so two players never point to the same controller index
        var seenIndices = Set<Int>()
        for p in 0..<kPlayers {
            if case .controller(let idx, _) = padMap.devices[p] {
                if seenIndices.contains(idx) {
                    padMap.devices[p] = .auto
                    didCleanStale = true
                } else {
                    seenIndices.insert(idx)
                }
            }
        }

        for p in 0..<kPlayers {
            if padMap.devices[p] == .none {
                playerDeviceModes[p] = .keyboard
            } else if map.hasKeys(for: p) && !padMap.isPlayerCustomized(p) {
                playerDeviceModes[p] = .keyboard
            } else {
                playerDeviceModes[p] = .gamepad
            }
        }
        if didCleanStale && padSource == .own {
            savePad()
        }
        syncConnectedPadIndices()
        // Automatically link player controls to matching custom profiles
        for p in 0..<kPlayers {
            for prof in customProfiles where prof.isGamepad {
                if let inputs = prof.padInputs {
                    var matches = true
                    for c in Control.allCases {
                        let curList = (padMap.inputs[p][c] ?? []).map(\.rawValue).sorted()
                        let pList = (inputs[c.rawValue] ?? []).sorted()
                        if curList != pList { matches = false; break }
                    }
                    if matches {
                        activePadProfileIDs[p] = prof.id
                        activePadProfileNames[p] = prof.name
                        break
                    }
                }
            }
            for prof in customProfiles where !prof.isGamepad {
                if let keys = prof.keyInputs {
                    var matches = true
                    for c in Control.allCases {
                        let curList = (map.keys[p][c] ?? []).sorted()
                        let pList = (keys[c.rawValue] ?? []).sorted()
                        if curList != pList { matches = false; break }
                    }
                    if matches {
                        activeKeyProfileIDs[p] = prof.id
                        activeKeyProfileNames[p] = prof.name
                        break
                    }
                }
            }
        }
        if player >= 0 && player < playerDeviceModes.count {
            deviceMode = playerDeviceModes[player]
        }
        syncAstrisConfig()
    }

    private func saveKey(player p: Int? = nil) {
        guard let g = selection else { return }
        let targetPlayer = p ?? player
        let url = Paths.keymap(g)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try map.serialize(gameName: g.name).write(to: url, atomically: true, encoding: .utf8)
            keySource = .own; lastError = nil
        } catch { lastError = "No se pudo guardar keymap: \(error.localizedDescription)" }
        syncCurrentToActiveProfile(player: targetPlayer, mode: .keyboard)
        DSUServer.shared.setKeyMap(map)
        syncAstrisConfig()
        objectWillChange.send()
    }

    private func savePad(player p: Int? = nil) {
        guard let g = selection else { return }
        let targetPlayer = p ?? player
        let url = Paths.padmap(g)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try padMap.serialize(gameName: g.name).write(to: url, atomically: true, encoding: .utf8)
            padSource = .own; lastError = nil
        } catch { lastError = "No se pudo guardar padmap: \(error.localizedDescription)" }
        syncCurrentToActiveProfile(player: targetPlayer, mode: .gamepad)
        syncCurrentPadMapToMobile()
        syncAstrisConfig()
        objectWillChange.send()
    }

    func syncCurrentPadMapToMobile() {
        let p = player
        var buttonMap: [String: String] = [:]
        for (c, pis) in padMap.inputs[p] {
            for pi in pis {
                buttonMap[pi.rawValue] = c.rawValue
            }
        }
        let isStickSwapped = (padMap.inputs[p][.LUP]?.contains(.DUP) == true)
        remote.sendRemapConfig(player: p, buttonMap: buttonMap, swapStickDpad: isStickSwapped)
    }

    // MARK: - Keyboard Editing

    func add(_ key: UInt16, player p: Int, control c: Control) {
        var list = map.keys[p][c] ?? []
        if !list.contains(key) { list.append(key) }
        map.keys[p][c] = list; saveKey()
    }
    func remove(_ key: UInt16, player p: Int, control c: Control) {
        map.keys[p][c]?.removeAll { $0 == key }; saveKey()
    }
    func clearPlayer(_ p: Int) {
        if deviceMode == .keyboard { map.keys[p] = [:]; saveKey() }
        else { padMap.inputs[p] = [:]; savePad() }
    }
    func resetPlayerPadToDefault(_ p: Int) {
        padMap.inputs[p] = PadMap.defaultPlayerDict; savePad()
    }
    func applyPadPreset(_ dict: [Control: [PadInput]], player p: Int) {
        padMap.inputs[p] = dict; savePad()
    }
    func swapPadDpadAndLeftStick(player p: Int) {
        let dUp = padMap.inputs[p][.UP] ?? [], dDown = padMap.inputs[p][.DOWN] ?? [], dLeft = padMap.inputs[p][.LEFT] ?? [], dRight = padMap.inputs[p][.RIGHT] ?? []
        padMap.inputs[p][.UP] = padMap.inputs[p][.LUP]; padMap.inputs[p][.DOWN] = padMap.inputs[p][.LDOWN]
        padMap.inputs[p][.LEFT] = padMap.inputs[p][.LLEFT]; padMap.inputs[p][.RIGHT] = padMap.inputs[p][.LRIGHT]
        padMap.inputs[p][.LUP] = dUp; padMap.inputs[p][.LDOWN] = dDown; padMap.inputs[p][.LLEFT] = dLeft; padMap.inputs[p][.LRIGHT] = dRight
        savePad()
    }
    func copy(from other: KeyMap) { map = other; saveKey() }
    func copyPad(from other: PadMap) { padMap = other; savePad() }
    func copyPlayer(_ from: Int, to: Int) {
        if deviceMode == .keyboard { map.keys[to] = map.keys[from]; saveKey() }
        else { padMap.inputs[to] = padMap.inputs[from]; savePad() }
    }
    func resetToInherited() {
        guard let g = selection else { return }
        if deviceMode == .keyboard {
            try? FileManager.default.removeItem(at: Paths.keymap(g))
        } else {
            try? FileManager.default.removeItem(at: Paths.padmap(g))
        }
        load()
        objectWillChange.send()
    }

    func uses(of key: UInt16) -> [(Int, Control)] {
        var r: [(Int, Control)] = []
        for p in 0..<kPlayers { for (c, ks) in map.keys[p] where ks.contains(key) { r.append((p, c)) } }
        return r
    }

    // MARK: - Custom Profiles (Gamepad & Keyboard)

    @Published var customProfiles: [CustomProfile] = []
    @Published var activePadProfileNames: [Int: String] = [:]
    @Published var activeKeyProfileNames: [Int: String] = [:]
    @Published var activePadProfileIDs: [Int: UUID] = [:]
    @Published var activeKeyProfileIDs: [Int: UUID] = [:]

    func currentProfileName(for player: Int, mode: InputDeviceMode) -> String {
        if mode == .gamepad {
            // 1. Check exact match with custom profiles
            for prof in customProfiles where prof.isGamepad {
                if let inputs = prof.padInputs {
                    var matches = true
                    for c in Control.allCases {
                        let curList = (padMap.inputs[player][c] ?? []).map(\.rawValue).sorted()
                        let pList = (inputs[c.rawValue] ?? []).sorted()
                        if curList != pList { matches = false; break }
                    }
                    if matches { return prof.name }
                }
            }
            // 2. Check factory presets
            if padMap.inputs[player] == PadMap.defaultPlayerDict { return "Switch Estándar" }
            if padMap.inputs[player] == PadMap.xboxLabelsPlayerDict { return "Invertido Xbox" }
            if padMap.inputs[player] == PadMap.smashProPlayerDict { return "Smash Bros Pro" }
            // 3. Fallback to remembered active profile with (editado)
            if let remembered = activePadProfileNames[player], !remembered.isEmpty {
                return "\(remembered) (editado)"
            }
            return "Personalizado"
        } else {
            // 1. Check exact match with custom profiles
            for prof in customProfiles where !prof.isGamepad {
                if let keys = prof.keyInputs {
                    var matches = true
                    for c in Control.allCases {
                        let curList = (map.keys[player][c] ?? []).sorted()
                        let pList = (keys[c.rawValue] ?? []).sorted()
                        if curList != pList { matches = false; break }
                    }
                    if matches { return prof.name }
                }
            }
            // 2. Check factory presets
            if map.keys[player] == KeyMap.builtIn.keys[0] { return "WASD estándar" }
            if map.keys[player] == KeyMap.player2ArrowsPreset() { return "Flechas + NumPad" }
            if map.keys[player] == KeyMap.player2IJKLPreset() { return "IJKL + Teclas" }
            if map.keys[player].isEmpty { return "Sin teclas" }
            // 3. Fallback to remembered active profile with (editado)
            if let remembered = activeKeyProfileNames[player], !remembered.isEmpty {
                return "\(remembered) (editado)"
            }
            return "Personalizado"
        }
    }

    func loadCustomProfiles() {
        let url = Paths.profilesJson
        if let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([CustomProfile].self, from: data) {
            customProfiles = list
            return
        }
        // Seed default profiles if none exist yet
        customProfiles = [
            CustomProfile(
                name: "Switch Estándar (Mando)",
                mode: "gamepad",
                padInputs: PadMap.defaultPlayerDict.reduce(into: [:]) { res, entry in
                    res[entry.key.rawValue] = entry.value.map(\.rawValue)
                }
            ),
            CustomProfile(
                name: "Smash Bros Pro (Mando)",
                mode: "gamepad",
                padInputs: PadMap.smashProPlayerDict.reduce(into: [:]) { res, entry in
                    res[entry.key.rawValue] = entry.value.map(\.rawValue)
                }
            ),
            CustomProfile(
                name: "WASD Clásico (Teclado)",
                mode: "keyboard",
                keyInputs: KeyMap.builtIn.keys[0].reduce(into: [:]) { res, entry in
                    res[entry.key.rawValue] = entry.value
                }
            ),
            CustomProfile(
                name: "Flechas + NumPad (Teclado)",
                mode: "keyboard",
                keyInputs: KeyMap.player2ArrowsPreset().reduce(into: [:]) { res, entry in
                    res[entry.key.rawValue] = entry.value
                }
            )
        ]
        saveCustomProfiles()
    }

    func saveCustomProfilesDisk() {
        let url = Paths.profilesJson
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(customProfiles) {
            try? data.write(to: url)
        }
    }

    func saveCustomProfiles() {
        saveCustomProfilesDisk()
        objectWillChange.send()
    }

    func syncCurrentToActiveProfile(player p: Int, mode: InputDeviceMode) {
        if mode == .gamepad {
            guard let id = activePadProfileIDs[p],
                  let idx = customProfiles.firstIndex(where: { $0.id == id }) else { return }
            var dict: [String: [String]] = [:]
            for (c, pis) in padMap.inputs[p] {
                dict[c.rawValue] = pis.map(\.rawValue)
            }
            customProfiles[idx].padInputs = dict
            saveCustomProfilesDisk()
        } else {
            guard let id = activeKeyProfileIDs[p],
                  let idx = customProfiles.firstIndex(where: { $0.id == id }) else { return }
            var dict: [String: [UInt16]] = [:]
            for (c, ks) in map.keys[p] {
                dict[c.rawValue] = ks
            }
            customProfiles[idx].keyInputs = dict
            saveCustomProfilesDisk()
        }
    }

    func createProfile(name: String, mode: InputDeviceMode, player: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var prof = CustomProfile(name: trimmed, mode: mode == .gamepad ? "gamepad" : "keyboard")
        if mode == .gamepad {
            var dict: [String: [String]] = [:]
            for (c, pis) in padMap.inputs[player] {
                dict[c.rawValue] = pis.map(\.rawValue)
            }
            prof.padInputs = dict
            activePadProfileIDs[player] = prof.id
            activePadProfileNames[player] = trimmed
        } else {
            var dict: [String: [UInt16]] = [:]
            for (c, ks) in map.keys[player] {
                dict[c.rawValue] = ks
            }
            prof.keyInputs = dict
            activeKeyProfileIDs[player] = prof.id
            activeKeyProfileNames[player] = trimmed
        }
        customProfiles.append(prof)
        saveCustomProfiles()
    }

    func renameProfile(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = customProfiles.firstIndex(where: { $0.id == id }) else { return }
        customProfiles[idx].name = trimmed
        saveCustomProfiles()
    }

    func updateProfileFromCurrent(id: UUID, player: Int) {
        guard let idx = customProfiles.firstIndex(where: { $0.id == id }) else { return }
        if customProfiles[idx].isGamepad {
            var dict: [String: [String]] = [:]
            for (c, pis) in padMap.inputs[player] {
                dict[c.rawValue] = pis.map(\.rawValue)
            }
            customProfiles[idx].padInputs = dict
        } else {
            var dict: [String: [UInt16]] = [:]
            for (c, ks) in map.keys[player] {
                dict[c.rawValue] = ks
            }
            customProfiles[idx].keyInputs = dict
        }
        saveCustomProfiles()
    }

    func duplicateProfile(id: UUID) {
        guard let prof = customProfiles.first(where: { $0.id == id }) else { return }
        var copy = prof
        copy.id = UUID()
        copy.name = "\(prof.name) (Copia)"
        copy.dateCreated = Date()
        customProfiles.append(copy)
        saveCustomProfiles()
    }

    func deleteProfile(id: UUID) {
        customProfiles.removeAll { $0.id == id }
        saveCustomProfiles()
    }

    func applyProfile(_ prof: CustomProfile, to player: Int) {
        if prof.isGamepad {
            activePadProfileIDs[player] = prof.id
            activePadProfileNames[player] = prof.name
            if let inputs = prof.padInputs {
                var dict: [Control: [PadInput]] = [:]
                for (cRaw, piRaws) in inputs {
                    if let c = Control(rawValue: cRaw) {
                        dict[c] = piRaws.compactMap { PadInput(rawValue: $0) }
                    }
                }
                applyPadPreset(dict, player: player)
            }
        } else {
            activeKeyProfileIDs[player] = prof.id
            activeKeyProfileNames[player] = prof.name
            if let keys = prof.keyInputs {
                var dict: [Control: [UInt16]] = [:]
                for (cRaw, ks) in keys {
                    if let c = Control(rawValue: cRaw) {
                        dict[c] = ks
                    }
                }
                applyKeyboardPreset(dict, player: player)
            }
        }
    }

    // MARK: - Gamepad Editing (Wait-for-press or Click-on-controller)

    /// Sets `pi` as the primary Xbox button for Switch control `c` (or adds it if Shift is held)
    func bindPadInput(_ pi: PadInput, player p: Int, control c: Control, replace: Bool = true) {
        if replace {
            padMap.inputs[p][c] = [pi]
        } else {
            var list = padMap.inputs[p][c] ?? []
            if !list.contains(pi) { list.append(pi) }
            padMap.inputs[p][c] = list
        }
        savePad(player: p)
    }

    func addPadInput(_ pi: PadInput, player p: Int, control c: Control) {
        bindPadInput(pi, player: p, control: c, replace: false)
    }

    func removePadInput(_ pi: PadInput, player p: Int, control c: Control) {
        padMap.inputs[p][c]?.removeAll { $0 == pi }
        savePad(player: p)
    }

    func clearPadControl(_ c: Control, player p: Int) {
        padMap.inputs[p][c] = []
        if capturingPad?.player == p && capturingPad?.control == c {
            capturingPad = nil
        }
        savePad(player: p)
    }

    func clearPadGroup(_ controls: [Control], player p: Int) {
        for c in controls {
            padMap.inputs[p][c] = []
            if capturingPad?.player == p && capturingPad?.control == c {
                capturingPad = nil
            }
        }
        savePad(player: p)
    }

    func resetPadGroup(_ controls: [Control], player p: Int) {
        for c in controls {
            padMap.inputs[p][c] = PadMap.defaultPlayerDict[c] ?? []
            if capturingPad?.player == p && capturingPad?.control == c {
                capturingPad = nil
            }
        }
        savePad(player: p)
    }

    /// Called when the user clicks a physical button on the Xbox controller diagram OR presses it on their real gamepad
    func handleXboxButtonPress(_ pi: PadInput) {
        if let cap = capturingPad {
            bindPadInput(pi, player: cap.player, control: cap.control, replace: true)
            capturingPad = nil
        }
    }

    // MARK: - Gamepad Device Assignment

    func setPlayerMode(_ newMode: InputDeviceMode, for p: Int) {
        guard p >= 0 && p < playerDeviceModes.count else { return }
        playerDeviceModes[p] = newMode
        if newMode == .keyboard {
            padMap.devices[p] = .none
            savePad()
        } else {
            if padMap.devices[p] == .none {
                padMap.devices[p] = .auto
                savePad()
            }
        }
        deviceMode = newMode
    }

    func applyKeyboardPreset(_ preset: [Control: [UInt16]], player p: Int) {
        map.keys[p] = preset
        saveKey()
    }

    func setDeviceAssignment(_ dev: DeviceAssignment, forPlayer p: Int) {
        if case .controller(let idx, let name) = dev {
            // Remove duplicate assignment from any other player slot
            for other in 0..<kPlayers where other != p {
                if case .controller(let oIdx, let oName) = padMap.devices[other] {
                    if oIdx == idx || oName.localizedCaseInsensitiveCompare(name) == .orderedSame {
                        padMap.devices[other] = .auto
                    }
                }
            }
        }
        padMap.devices[p] = dev
        if dev == .none {
            NxPadShared.clear(player: p)
            NxMotionShared.clear(player: p)
            playerDeviceModes[p] = .keyboard
            if p == player { deviceMode = .keyboard }
        } else {
            playerDeviceModes[p] = .gamepad
            if p == player { deviceMode = .gamepad }
        }
        savePad(player: p)
    }

    func assignConnectedPad(index: Int, toPlayer p: Int) {
        guard index >= 0 && index < connectedPads.count else { return }
        let name = connectedPads[index]
        setDeviceAssignment(.controller(index: index, name: name), forPlayer: p)
        lastSyncMessage = "✓ «\(name)» sincronizado con J\(p + 1)"
    }

    /// Returns a map [playerIndex: controllerIndexInConnectedPads] for each synced player.
    func resolvedPadIndexByPlayer() -> [Int: Int] {
        guard !connectedPads.isEmpty else { return [:] }
        var result: [Int: Int] = [:]
        var usedPadIndices = Set<Int>()

        // 1. First pass: Explicitly assigned controllers (.controller) that are currently connected
        for p in 0..<kPlayers {
            if case .controller(let explicitIdx, let savedName) = padMap.devices[p] {
                if !savedName.isEmpty {
                    if explicitIdx >= 0 && explicitIdx < connectedPads.count && !usedPadIndices.contains(explicitIdx) &&
                       connectedPads[explicitIdx].localizedCaseInsensitiveCompare(savedName) == .orderedSame {
                        result[p] = explicitIdx
                        usedPadIndices.insert(explicitIdx)
                    } else if let exactIdx = connectedPads.indices.first(where: { idx in
                        !usedPadIndices.contains(idx) && connectedPads[idx].localizedCaseInsensitiveCompare(savedName) == .orderedSame
                    }) {
                        result[p] = exactIdx
                        usedPadIndices.insert(exactIdx)
                    } else if let matchIdx = connectedPads.indices.first(where: { idx in
                        !usedPadIndices.contains(idx) && (
                            connectedPads[idx].localizedCaseInsensitiveContains(savedName) ||
                            savedName.localizedCaseInsensitiveContains(connectedPads[idx])
                        )
                    }) {
                        result[p] = matchIdx
                        usedPadIndices.insert(matchIdx)
                    }
                } else if explicitIdx >= 0 && explicitIdx < connectedPads.count && !usedPadIndices.contains(explicitIdx) {
                    result[p] = explicitIdx
                    usedPadIndices.insert(explicitIdx)
                }
            }
        }

        // 2. Second pass: Automatic players (.auto) receive remaining connected controllers in order
        for p in 0..<kPlayers {
            guard result[p] == nil, padMap.devices[p] == .auto else { continue }
            if let nextIdx = connectedPads.indices.first(where: { !usedPadIndices.contains($0) }) {
                result[p] = nextIdx
                usedPadIndices.insert(nextIdx)
            }
        }

        return result
    }

    /// Returns a map [playerIndex: controllerName] ONLY for players that currently have a real connected controller synced.
    func resolvedConnectedPadsByPlayer() -> [Int: String] {
        let indexMap = resolvedPadIndexByPlayer()
        var names: [Int: String] = [:]
        for (p, idx) in indexMap where idx >= 0 && idx < connectedPads.count {
            names[p] = connectedPads[idx]
        }
        return names
    }

    /// True ONLY if this player currently has a real connected & synced controller (or active keyboard keys in keyboard mode).
    func isPlayerConnected(_ p: Int) -> Bool {
        if playerDeviceModes[p] == .keyboard {
            return map.hasKeys(for: p)
        }
        return resolvedConnectedPadsByPlayer()[p] != nil
    }

    func connectedControllerName(forPlayer p: Int) -> String? {
        resolvedConnectedPadsByPlayer()[p]
    }

    /// Keeps saved PAD:index:name indices aligned with the current connectedPads order
    private func syncConnectedPadIndices() {
        guard !connectedPads.isEmpty else { return }
        var changed = false
        var usedIndices = Set<Int>()

        for p in 0..<kPlayers {
            if case .controller(let oldIdx, let savedName) = padMap.devices[p] {
                if oldIdx >= 0 && oldIdx < connectedPads.count && !usedIndices.contains(oldIdx) {
                    let liveName = connectedPads[oldIdx]
                    usedIndices.insert(oldIdx)
                    if savedName != liveName {
                        padMap.devices[p] = .controller(index: oldIdx, name: liveName)
                        changed = true
                    }
                } else if let liveIdx = connectedPads.indices.first(where: { idx in
                    !usedIndices.contains(idx) && (
                        connectedPads[idx].localizedCaseInsensitiveCompare(savedName) == .orderedSame ||
                        connectedPads[idx].localizedCaseInsensitiveContains(savedName) ||
                        savedName.localizedCaseInsensitiveContains(connectedPads[idx])
                    )
                }) {
                    usedIndices.insert(liveIdx)
                    let liveName = connectedPads[liveIdx]
                    padMap.devices[p] = .controller(index: liveIdx, name: liveName)
                    changed = true
                }
            }
        }
        if changed && padSource == .own {
            savePad()
        }
    }

    func startIdentifyingPad(forPlayer p: Int) {
        identifyingPadForPlayer = p
    }

    func cancelIdentifyingPad() {
        identifyingPadForPlayer = nil
    }

    // MARK: - Physical Keyboard Listener

    private static let modifierBits: [UInt16: UInt] = [56: 0x2, 60: 0x4, 59: 0x1, 62: 0x2000, 58: 0x20, 61: 0x40]

    private func installMonitor() {
        // Monitor local (para edición de controles o cuando la ventana está enfocada)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] e in
            guard let self else { return e }
            let code = e.keyCode
            var down: Bool
            switch e.type {
            case .flagsChanged:
                guard let bit = Store.modifierBits[code] else { return e }
                down = (e.modifierFlags.rawValue & bit) != 0
            case .keyDown: down = true
            default: down = false
            }

            self.handleKeyInput(code: code, down: down)

            // Also feed directly to DSU server
            DSUServer.shared.handleKeyEvent(code: code, down: down)

            if down, let capPad = self.capturingPad {
                if code == 53 {
                    self.capturingPad = nil
                    return nil
                }
                if code == 51 || code == 117 { // Backspace or Delete -> unassign control
                    self.clearPadControl(capPad.control, player: capPad.player)
                    return nil
                }
            }
            guard let cap = self.capturing else { return e }
            if e.type == .keyDown && e.modifierFlags.contains(.command) { return e }
            if down {
                if code == 53 { self.capturing = nil; return nil }
                if KeyNames.unusable.contains(code) { NSSound.beep(); return nil }
                self.add(code, player: cap.player, control: cap.control)
                self.capturing = nil
            }
            return e.type == .flagsChanged ? e : nil
        }

        // Monitor GLOBAL: captura teclas cuando OTRA app está en primer plano (ej: Astris)
        // Esto NO se llama cuando NX Controles está en primer plano (para eso está el local monitor)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] e in
            guard let self else { return }
            let code = e.keyCode
            var down: Bool
            switch e.type {
            case .flagsChanged:
                guard let bit = Store.modifierBits[code] else { return }
                down = (e.modifierFlags.rawValue & bit) != 0
            case .keyDown: down = true
            default: down = false
            }

            // Feed directly to DSU server (thread-safe)
            DSUServer.shared.handleKeyEvent(code: code, down: down)

            // Also update local UI state
            self.handleKeyInput(code: code, down: down)
        }
        dsuLog("[Store] NSEvent globalMonitor INSTALLED")

        // También instalar CGEvent tap como respaldo
        installGlobalKeyboardTap()
    }

    private func handleKeyInput(code: UInt16, down: Bool) {
        if self.capturing != nil || self.capturingPad != nil {
            return
        }

        if down {
            if self.pressed.contains(code) { return }
            self.pressed.insert(code)
            print("[Store-KEY] DOWN code=\(code)")
        } else {
            if !self.pressed.contains(code) { return }
            self.pressed.remove(code)
            print("[Store-KEY] UP code=\(code)")
        }
        self.updateKeyboardDSU()
    }

    private var accessibilityTimer: Timer?

    @discardableResult
    func checkAccessibilityPermissions(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.async {
            self.isAccessibilityGranted = trusted
        }
        dsuLog("[Store] AXIsProcessTrusted(prompt=\(prompt)) = \(trusted)")
        return trusted
    }

    func requestAccessibilityPermission() {
        _ = checkAccessibilityPermissions(prompt: true)
        startAccessibilityWatcher()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startAccessibilityWatcher() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            let trusted = AXIsProcessTrustedWithOptions(nil)
            if trusted {
                timer.invalidate()
                self.accessibilityTimer = nil
                self.isAccessibilityGranted = true
                dsuLog("[Store] 🎉 Accesibilidad concedida en caliente! Reinstalando tap global...")
                self.installGlobalKeyboardTap()
            }
        }
    }

    private func installGlobalKeyboardTap() {
        if let oldTap = self.globalEventTap {
            CGEvent.tapEnable(tap: oldTap, enable: false)
            self.globalEventTap = nil
        }
        if let oldSrc = self.globalRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), oldSrc, .commonModes)
            self.globalRunLoopSource = nil
        }

        let isTrusted = checkAccessibilityPermissions(prompt: true)
        if !isTrusted {
            dsuLog("[Store] ⚠️ Permiso de Accesibilidad NO otorgado. Iniciando observador en segundo plano...")
            startAccessibilityWatcher()
        } else {
            accessibilityTimer?.invalidate()
            accessibilityTimer = nil
        }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        // Intentar primero a nivel de sesión (.cgSessionEventTap) y si falla, a nivel HID (.cghidEventTap)
        var tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let store = Unmanaged<Store>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let port = store.globalEventTap {
                        CGEvent.tapEnable(tap: port, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                var down = false
                if type == .keyDown {
                    down = true
                } else if type == .keyUp {
                    down = false
                } else if type == .flagsChanged {
                    let flags = event.flags
                    guard let bit = Store.modifierBits[code] else { return Unmanaged.passUnretained(event) }
                    down = (flags.rawValue & UInt64(bit)) != 0
                }

                // Feed keyboard state directly to DSU on THIS thread (don't wait for main)
                // This avoids @MainActor dispatch delays
                let pressed = down
                let keyCode = code
                DSUServer.shared.handleKeyEvent(code: keyCode, down: pressed)

                DispatchQueue.main.async {
                    store.handleKeyInput(code: code, down: down)
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: observer
        )

        if tap == nil {
            dsuLog("[Store] cgSessionEventTap falló, intentando cghidEventTap...")
            tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: CGEventMask(mask),
                callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                    guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                    let store = Unmanaged<Store>.fromOpaque(refcon).takeUnretainedValue()

                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let port = store.globalEventTap {
                            CGEvent.tapEnable(tap: port, enable: true)
                        }
                        return Unmanaged.passUnretained(event)
                    }

                    let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                    var down = false
                    if type == .keyDown {
                        down = true
                    } else if type == .keyUp {
                        down = false
                    } else if type == .flagsChanged {
                        let flags = event.flags
                        guard let bit = Store.modifierBits[code] else { return Unmanaged.passUnretained(event) }
                        down = (flags.rawValue & UInt64(bit)) != 0
                    }

                    DSUServer.shared.handleKeyEvent(code: code, down: down)

                    DispatchQueue.main.async {
                        store.handleKeyInput(code: code, down: down)
                    }

                    return Unmanaged.passUnretained(event)
                },
                userInfo: observer
            )
        }

        guard let validTap = tap else {
            print("[Store] No se pudo crear CGEvent tap global (posible falta de permisos de accesibilidad)")
            dsuLog("[Store] CGEvent tap FAILED - no accessibility permissions?")
            return
        }

        self.globalEventTap = validTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, validTap, 0)
        self.globalRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: validTap, enable: true)
        print("[Store] CGEvent tap global de teclado instalado para DSU")
        dsuLog("[Store] CGEvent tap global INSTALLED OK")
    }

    func updateKeyboardDSU() {
        for p in 0..<kPlayers {
            // Solo procesar si el jugador tiene teclas configuradas o es Player 1 (índice 0)
            guard p == 0 || self.map.hasKeys(for: p) else { continue }

            var buttons = Set<String>()
            var lx: Double = 0.0
            var ly: Double = 0.0
            var rx: Double = 0.0
            var ry: Double = 0.0
            var isShaking = false

            for (control, keyCodes) in self.map.keys[p] {
                let isPressed = keyCodes.contains { self.pressed.contains($0) }
                guard isPressed else { continue }

                switch control {
                case .A: buttons.insert("A")
                case .B: buttons.insert("B")
                case .X: buttons.insert("X")
                case .Y: buttons.insert("Y")
                case .L: buttons.insert("L")
                case .R: buttons.insert("R")
                case .ZL: buttons.insert("ZL")
                case .ZR: buttons.insert("ZR")
                case .PLUS: buttons.insert("PLUS")
                case .MINUS: buttons.insert("MINUS")
                case .LS: buttons.insert("LS")
                case .RS: buttons.insert("RS")
                case .UP: buttons.insert("UP")
                case .DOWN: buttons.insert("DOWN")
                case .LEFT: buttons.insert("LEFT")
                case .RIGHT: buttons.insert("RIGHT")
                case .LUP: ly += 1.0
                case .LDOWN: ly -= 1.0
                case .LLEFT: lx -= 1.0
                case .LRIGHT: lx += 1.0
                case .RUP: ry += 1.0
                case .RDOWN: ry -= 1.0
                case .RLEFT: rx -= 1.0
                case .RRIGHT: rx += 1.0
                case .SHAKE: isShaking = true
                }
            }

            lx = max(-1.0, min(1.0, lx))
            ly = max(-1.0, min(1.0, ly))
            rx = max(-1.0, min(1.0, rx))
            ry = max(-1.0, min(1.0, ry))

            let joyState = JoyConState(
                player: p,
                pressedButtons: buttons,
                lx: lx,
                ly: ly,
                rx: rx,
                ry: ry,
                isShaking: isShaking
            )
            if !buttons.isEmpty || lx != 0 || ly != 0 || rx != 0 || ry != 0 {
                print("[Store-DSU] J\(p + 1) btns=\(buttons) lx=\(lx) ly=\(ly)")
            }
            DSUServer.shared.updateState(joyState, slot: UInt8(p))

            if p == self.player {
                self.leftStick = CGPoint(x: lx, y: ly)
                self.rightStick = CGPoint(x: rx, y: ry)
            }
        }
    }

    // MARK: - Physical GameController & HID Listener

    private var hidManager: HIDGamepadManager?
    private var hidIndexMap: [Int: Int] = [:] // Map from hid device index to connectedPads index
    private var previousConnectedPads: [String] = []

    private func installGamepadMonitor() {
        let nc = NotificationCenter.default
        for name in [NSNotification.Name.GCControllerDidConnect, NSNotification.Name.GCControllerDidDisconnect] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshControllers() }
            }
        }

        let hid = HIDGamepadManager()
        self.hidManager = hid
        hid.onDeviceListChanged = { [weak self] _ in
            Task { @MainActor in self?.refreshControllers() }
        }
        hid.onInput = { [weak self] devIdx, inputs, ls, rs, lt, rt in
            Task { @MainActor in
                self?.readPhysicalHIDGamepad(deviceIndex: devIdx, inputs: inputs, leftStick: ls, rightStick: rs, leftTrigger: lt, rightTrigger: rt)
            }
        }
        hid.onGetPlayerForDevice = { [weak self] devIdx in
            guard let self = self else { return nil }
            let controllerIndex = self.hidIndexMap[devIdx] ?? devIdx
            return self.resolvedPadIndexByPlayer().first(where: { $0.value == controllerIndex })?.key
        }

        remote.onResolvePlayerForName = { [weak self] devName in
            guard let self = self, !devName.isEmpty else { return nil }
            for p in 0..<kPlayers {
                if case .controller(_, let savedName) = self.padMap.devices[p], !savedName.isEmpty {
                    if savedName.localizedCaseInsensitiveCompare(devName) == .orderedSame ||
                       savedName.localizedCaseInsensitiveContains(devName) ||
                       devName.localizedCaseInsensitiveContains(savedName) {
                        return p
                    }
                }
            }
            return nil
        }

        remote.onQRClientConnected = { [weak self] _ in
            guard let self = self else { return }
            let targetP = self.qrTargetPlayer ?? self.player
            self.qrTargetPlayer = targetP
            if self.connectedPads.count == 1 {
                self.assignConnectedPad(index: 0, toPlayer: targetP)
                NSSound.beep()
            } else {
                self.lastSyncMessage = "QR leído — Pulsa un botón en ese móvil para asignarlo a J\(targetP + 1)"
            }
        }

        remote.onRemotePadInput = { [weak self] player, inputs, ls, rs in
            guard let self = self else { return }
            // STRICT ISOLATION PER PLAYER:
            // Only animate sticks/buttons if this packet is for the currently selected player tab (store.player)!
            guard player == self.player else { return }

            // If this player is explicitly assigned to a physical controller (.controller), ignore mobile for diagram
            if case .controller = self.padMap.devices[self.player] {
                return
            }

            self.leftStick = ls
            self.rightStick = rs
            let newlyPressed = inputs.subtracting(self.pressedPadInputs)
            self.pressedPadInputs = inputs
            if let firstNew = newlyPressed.first {
                self.handleXboxButtonPress(firstNew)
            }
        }

        refreshControllers()
    }

    func refreshControllers() {
        let controllers = GCController.controllers()
        var rawNames: [String] = []
        hidIndexMap.removeAll()

        for c in controllers {
            if c.extendedGamepad != nil {
                rawNames.append(c.vendorName ?? "Mando inalámbrico")
            }
        }
        let gcCount = rawNames.count

        if let hidDevices = hidManager?.devices {
            for (hIdx, dev) in hidDevices.enumerated() {
                let devName = dev.name
                let gcMatchCount = rawNames.prefix(gcCount).filter { $0 == devName }.count
                let hidMatchCount = rawNames.suffix(from: gcCount).filter { $0 == devName }.count
                let totalWithThisName = hidDevices.filter { $0.name == devName }.count
                if hidMatchCount < (totalWithThisName - gcMatchCount) {
                    let padIdx = rawNames.count
                    rawNames.append(devName)
                    hidIndexMap[hIdx] = padIdx
                }
            }
        }

        // Disambiguate identical controller names so users and players get unique controller targets
        var nameTotals: [String: Int] = [:]
        for n in rawNames { nameTotals[n, default: 0] += 1 }

        var nameCounters: [String: Int] = [:]
        var names: [String] = []
        for n in rawNames {
            if (nameTotals[n] ?? 0) > 1 {
                let count = (nameCounters[n] ?? 0) + 1
                nameCounters[n] = count
                names.append("\(n) #\(count)")
            } else {
                names.append(n)
            }
        }

        let oldSet = Set(previousConnectedPads)
        connectedPads = names
        syncConnectedPadIndices()

        // Only auto-assign if actively waiting for QR detection
        if let newIdx = names.indices.first(where: { !oldSet.contains(names[$0]) }) {
            if let targetP = qrTargetPlayer {
                assignConnectedPad(index: newIdx, toPlayer: targetP)
                qrTargetPlayer = nil
                NSSound.beep()
            }
        }
        previousConnectedPads = names

        for (idx, c) in controllers.enumerated() {
            guard let g = c.extendedGamepad else { continue }
            g.valueChangedHandler = { [weak self] gamepad, _ in
                Task { @MainActor in
                    self?.readPhysicalGamepad(gamepad, controllerIndex: idx)
                }
            }
        }
    }

    private func readPhysicalHIDGamepad(deviceIndex: Int, inputs: Set<PadInput>, leftStick ls: CGPoint, rightStick rs: CGPoint, leftTrigger lt: Double, rightTrigger rt: Double) {
        guard let controllerIndex = hidIndexMap[deviceIndex] else { return }

        // Allow "Detectar mando" or QR pairing to identify any pressed controller first
        if !inputs.isEmpty {
            if let targetP = identifyingPadForPlayer {
                assignConnectedPad(index: controllerIndex, toPlayer: targetP)
                identifyingPadForPlayer = nil
                NSSound.beep()
                return
            }
            if let qrP = qrTargetPlayer, capturingPad == nil {
                assignConnectedPad(index: controllerIndex, toPlayer: qrP)
                qrTargetPlayer = nil
                NSSound.beep()
                return
            }
        }

        // Forward to Astris via DSU and non-Astris apps via keyboard injection
        let frontApp = NSWorkspace.shared.frontmostApplication
        let frontBundle = frontApp?.bundleIdentifier ?? ""
        let isAstris = frontBundle == "V380-Ori.Astris"
        let isNxNative = frontBundle.hasPrefix("org.nxnative") || frontBundle.contains("Jamboree") || frontApp?.executableURL?.lastPathComponent == "dmhost"
        let assignedPlayer = resolvedPadIndexByPlayer().first(where: { $0.value == controllerIndex })?.key ?? 0
        let joyState = JoyConState.from(padInputs: inputs, ls: ls, rs: rs, player: assignedPlayer)
        DSUServer.shared.updateState(joyState, slot: UInt8(assignedPlayer))

        if isNxNative {
            remote.injector.releaseAll()
        } else if !isAstris {
            remote.injector.updateFromPadInputs(inputs, ls: ls, rs: rs, player: assignedPlayer, isAstris: false)
        }

        // STRICT ISOLATION PER PLAYER:
        // Only animate sticks/buttons and capture inputs if this controller belongs to the currently selected player (store.player)!
        if selectedID != RemoteStore.sidebarID {
            let activePadIdxForCurrentPlayer = resolvedPadIndexByPlayer()[player]
            guard controllerIndex == activePadIdxForCurrentPlayer else { return }
        }

        leftStick = ls
        rightStick = rs
        leftTrigger = lt
        rightTrigger = rt

        let newlyPressed = inputs.subtracting(pressedPadInputs)
        pressedPadInputs = inputs

        if let firstNew = newlyPressed.first {
            handleXboxButtonPress(firstNew)
        }
    }

    private func readPhysicalGamepad(_ g: GCExtendedGamepad, controllerIndex: Int) {
        let lx = Double(g.leftThumbstick.xAxis.value)
        let ly = Double(g.leftThumbstick.yAxis.value)
        let rx = Double(g.rightThumbstick.xAxis.value)
        let ry = Double(g.rightThumbstick.yAxis.value)

        var now = Set<PadInput>()
        if g.buttonA.isPressed { now.insert(.A) }
        if g.buttonB.isPressed { now.insert(.B) }
        if g.buttonX.isPressed { now.insert(.X) }
        if g.buttonY.isPressed { now.insert(.Y) }
        if g.leftShoulder.isPressed { now.insert(.LB) }
        if g.rightShoulder.isPressed { now.insert(.RB) }
        if g.leftTrigger.isPressed || g.leftTrigger.value > 0.45 { now.insert(.LT) }
        if g.rightTrigger.isPressed || g.rightTrigger.value > 0.45 { now.insert(.RT) }
        if g.buttonOptions?.isPressed == true { now.insert(.VIEW) }
        if g.buttonMenu.isPressed { now.insert(.MENU) }
        if g.leftThumbstickButton?.isPressed == true { now.insert(.LS) }
        if g.rightThumbstickButton?.isPressed == true { now.insert(.RS) }
        if g.dpad.up.isPressed { now.insert(.DUP) }
        if g.dpad.down.isPressed { now.insert(.DDOWN) }
        if g.dpad.left.isPressed { now.insert(.DLEFT) }
        if g.dpad.right.isPressed { now.insert(.DRIGHT) }
        if ly > 0.60 { now.insert(.LUP) }
        if ly < -0.60 { now.insert(.LDOWN) }
        if lx < -0.60 { now.insert(.LLEFT) }
        if lx > 0.60 { now.insert(.LRIGHT) }
        if ry > 0.60 { now.insert(.RUP) }
        if ry < -0.60 { now.insert(.RDOWN) }
        if rx < -0.60 { now.insert(.RLEFT) }
        if rx > 0.60 { now.insert(.RRIGHT) }

        if !now.isEmpty {
            if let targetP = identifyingPadForPlayer {
                assignConnectedPad(index: controllerIndex, toPlayer: targetP)
                identifyingPadForPlayer = nil
                NSSound.beep()
                return
            }
            if let qrP = qrTargetPlayer, capturingPad == nil {
                assignConnectedPad(index: controllerIndex, toPlayer: qrP)
                qrTargetPlayer = nil
                NSSound.beep()
                return
            }
        }

        // Forward to Astris via DSU and non-Astris apps via keyboard injection
        let frontApp = NSWorkspace.shared.frontmostApplication
        let frontBundle = frontApp?.bundleIdentifier ?? ""
        let isAstris = frontBundle == "V380-Ori.Astris"
        let isNxNative = frontBundle.hasPrefix("org.nxnative") || frontBundle.contains("Jamboree") || frontApp?.executableURL?.lastPathComponent == "dmhost"
        let assignedPlayer = resolvedPadIndexByPlayer().first(where: { $0.value == controllerIndex })?.key ?? 0
        let joyState = JoyConState.from(padInputs: now, ls: CGPoint(x: lx, y: ly), rs: CGPoint(x: rx, y: ry), player: assignedPlayer)
        DSUServer.shared.updateState(joyState, slot: UInt8(assignedPlayer))

        if isNxNative {
            remote.injector.releaseAll()
        } else if !isAstris {
            remote.injector.updateFromPadInputs(now, ls: CGPoint(x: lx, y: ly), rs: CGPoint(x: rx, y: ry), player: assignedPlayer, isAstris: false)
        }

        // STRICT ISOLATION PER PLAYER:
        // Only animate sticks/buttons and capture inputs if this controller belongs to the currently selected player (store.player)!
        if selectedID != RemoteStore.sidebarID {
            let activePadIdxForCurrentPlayer = resolvedPadIndexByPlayer()[player]
            guard controllerIndex == activePadIdxForCurrentPlayer else { return }
        }

        leftStick = CGPoint(x: lx, y: ly)
        rightStick = CGPoint(x: rx, y: ry)
        leftTrigger = Double(g.leftTrigger.value)
        rightTrigger = Double(g.rightTrigger.value)

        let newlyPressed = now.subtracting(pressedPadInputs)
        pressedPadInputs = now

        if let firstNew = newlyPressed.first {
            handleXboxButtonPress(firstNew)
        }
    }
}
